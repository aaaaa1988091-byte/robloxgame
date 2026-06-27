local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")

-- ==================== 參數設定 ====================
local BLOCK_SIZE = 4
local CHUNK_RADIUS_XZ = 14
local CHUNK_RADIUS_Y = 8
local MAX_DEPTH_BLOCKS = 4000
local CHEST_CHANCE = 0.02
local STEEL_FLOOR_SIZE = Vector3.new(10, 1, 10)
local NOISE_SCALE = 0.075
local HILL_HEIGHT_BLOCKS = 5
local CACTUS_CHANCE = 0.025
local CACTUS_HEIGHT_SCALE = 2.2
local MINING_DEBRIS_COUNT = 18
local MAX_BACKPACK_CAPPED = 20
local BACKPACK_UPGRADE_AMOUNT = 20
local WORLD_REFRESH_SECONDS = 10 * 60
local PLAYER_DATA_STORE = DataStoreService:GetDataStore("DynamicMiningWorldPlayerDataV2")

local SHOP_POSITION = Vector3.new(0, 0, -25)
local SHOP_PREVIEW_POSITION = Vector3.new(0, 10000, 0)
local BOMB_THROW_FLIGHT_TIME = 0.42

-- 寶箱可維護設定：新增等級只要複製一列，調整 id / minDepth / weight / color / health / reward。
-- 視覺模型共用 ServerStorage.BOX，只依等級套用不同顏色。
local CHEST_LEVELS = {
	{ id = "common", minDepth = 0, weight = 70, color = Color3.fromRGB(180, 130, 65), health = 18, reward = { 50, 180 }, emoji = "🪙" },
	{ id = "rare", minDepth = 35, weight = 24, color = Color3.fromRGB(70, 150, 255), health = 42, reward = { 180, 520 }, emoji = "💎" },
	{ id = "epic", minDepth = 120, weight = 6, color = Color3.fromRGB(190, 80, 255), health = 90, reward = { 520, 1400 }, emoji = "👑" },
}

local function getSteelFloor()
	local shopModel = Workspace:FindFirstChild("MiningShopWorld")
	local steelFloor = shopModel and shopModel:FindFirstChild("SecureFloor", true)
	return steelFloor or Workspace:FindFirstChild("SecureFloor", true)
end

local function getWorldOrigin()
	local steelFloor = getSteelFloor()
	if steelFloor then
		return Vector3.new(steelFloor.Position.X, steelFloor.Position.Y + steelFloor.Size.Y / 2, steelFloor.Position.Z)
	end
	return SHOP_POSITION
end

local function worldFromBlock(bx, by, bz)
	-- by = 0 的方塊頂面剛好貼齊鋼體平台頂面。
	return getWorldOrigin() + Vector3.new(bx * BLOCK_SIZE, by * BLOCK_SIZE - BLOCK_SIZE / 2, bz * BLOCK_SIZE)
end

local function blockFromWorld(position)
	local relative = position - getWorldOrigin()
	return math.floor((relative.X + BLOCK_SIZE / 2) / BLOCK_SIZE), math.floor((relative.Y + BLOCK_SIZE) / BLOCK_SIZE), math.floor((relative.Z + BLOCK_SIZE / 2) / BLOCK_SIZE)
end

local folder = Workspace:FindFirstChild("DynamicMiningWorld") or Instance.new("Folder")
folder.Name = "DynamicMiningWorld"
folder.Parent = Workspace

local worldData = {}
local spawnedParts = {}
local blockHealthData = {}

-- 建立與獲取網路事件 (確保在最前端正確註冊)
local function getRemote(className, name)
	local remote = ReplicatedStorage:FindFirstChild(name)
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

local sendNotificationEvent = getRemote("RemoteEvent", "SendNotification")
local teleportEvent = getRemote("RemoteEvent", "TeleportToShop")
local shopActionEvent = getRemote("RemoteEvent", "ShopAction")
local miningEvent = getRemote("RemoteEvent", "MiningEvent")
local rewardEmojiEvent = getRemote("RemoteEvent", "RewardEmojiEvent")
local shopCatalogFunction = getRemote("RemoteFunction", "GetShopCatalog")

local nextWorldRefreshTimeValue = ReplicatedStorage:FindFirstChild("NextWorldRefreshTime") or Instance.new("IntValue")
nextWorldRefreshTimeValue.Name = "NextWorldRefreshTime"
nextWorldRefreshTimeValue.Value = os.time() + WORLD_REFRESH_SECONDS
nextWorldRefreshTimeValue.Parent = ReplicatedStorage

local function sendNotification(player, title, text)
	sendNotificationEvent:FireClient(player, title, text)
end

-- ==================== 1. 玩家數據與工具系統 ====================
local TOOL_EFFICIENCY = {
	["拳頭"] = 5,
	["木鎬"] = 20,
	["鐵鎬"] = 50,
	["鑽石鎬"] = 100,
	["鐵鑽頭"] = 35,
	["鑽石鑽頭"] = 80,
}

local TOOL_AUTO_MINE = {
	["鐵鑽頭"] = true,
	["鑽石鑽頭"] = true,
}


local PICKAXE_NAMES = { "木鎬", "鐵鎬", "鑽石鎬", "鐵鑽頭", "鑽石鑽頭" }
local BOMB_TOOL_NAME = "💣 炸彈"
local CLUSTER_BOMB_TOOL_NAME = "💥 集束炸彈"
local playerMiningState = {}

local function teleportPlayerToSteel(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(getWorldOrigin() + Vector3.new(0, 7, 0))
	end
end

local function getOwnedToolsFolder(player)
	local folderValue = player:FindFirstChild("OwnedTools")
	if not folderValue then
		folderValue = Instance.new("Folder")
		folderValue.Name = "OwnedTools"
		folderValue.Parent = player
	end
	return folderValue
end

local function rememberTool(player, toolName)
	local ownedTools = getOwnedToolsFolder(player)
	if not ownedTools:FindFirstChild(toolName) then
		local value = Instance.new("BoolValue")
		value.Name = toolName
		value.Value = true
		value.Parent = ownedTools
	end
end

local ITEM_STORAGE_FOLDER_NAME = "MiningItemModels"
local DEFAULT_CATALOG_IDS = {
	sell_sand = true,
	wood_pickaxe = true,
	iron_pickaxe = true,
	diamond_pickaxe = true,
	iron_drill = true,
	diamond_drill = true,
	bomb = true,
	cluster_bomb = true,
	backpack_upgrade = true,
}

local function getItemStorageFolder()
	local folder = ServerStorage:FindFirstChild(ITEM_STORAGE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ITEM_STORAGE_FOLDER_NAME
		folder.Parent = ServerStorage
	end
	return folder
end

local function readCatalogItemFromStorage(child)
	if child:GetAttribute("ShopItem") == false or (DEFAULT_CATALOG_IDS[child.Name] and not child:GetAttribute("ShopItem")) then
		return nil
	end
	local itemId = child:GetAttribute("Id") or child.Name
	return {
		id = itemId,
		name = child:GetAttribute("DisplayName") or child.Name,
		description = child:GetAttribute("Description") or "ServerStorage.MiningItemModels 內新增的商品。",
		action = child:GetAttribute("Action") or "BuyTool",
		item = child:GetAttribute("Item") or child.Name,
		price = child:GetAttribute("Price") or 0,
		model = {
			kind = child:GetAttribute("PreviewKind") or "block",
			color = child:GetAttribute("PreviewColor") or Color3.fromRGB(235, 205, 130),
			material = Enum.Material[child:GetAttribute("PreviewMaterial") or "Sand"],
		},
	}
end

local SHOP_CATALOG = {
	{
		id = "sell_sand",
		name = "出售沙子",
		description = "把背包裡的沙子全部換成金幣，每顆 +5。",
		action = "Sell",
		item = "",
		price = 0,
		model = { kind = "block", size = Vector3.new(2.5, 2.5, 2.5), color = Color3.fromRGB(235, 205, 130), material = Enum.Material.Sand },
	},
	{
		id = "wood_pickaxe",
		name = "木鎬",
		description = "工具強度 20 / 秒，適合開始挖深一點。",
		action = "BuyTool",
		item = "木鎬",
		price = 150,
		model = { kind = "pickaxe", color = Color3.fromRGB(126, 78, 36), material = Enum.Material.Wood },
	},
	{
		id = "iron_pickaxe",
		name = "鐵鎬",
		description = "工具強度 50 / 秒，更快打穿中層沙子。",
		action = "BuyTool",
		item = "鐵鎬",
		price = 500,
		model = { kind = "pickaxe", color = Color3.fromRGB(180, 185, 190), material = Enum.Material.Metal },
	},
	{
		id = "diamond_pickaxe",
		name = "鑽石鎬",
		description = "工具強度 100 / 秒，深層挖礦核心裝備。",
		action = "BuyTool",
		item = "鑽石鎬",
		price = 1500,
		model = { kind = "pickaxe", color = Color3.fromRGB(45, 210, 235), material = Enum.Material.Neon },
	},
	{
		id = "iron_drill",
		name = "鐵鑽頭",
		description = "自動工具：按住即可連續挖掘，工具強度 35 / 秒。",
		action = "BuyTool",
		item = "鐵鑽頭",
		price = 3000,
		model = { kind = "pickaxe", color = Color3.fromRGB(140, 150, 160), material = Enum.Material.Metal },
	},
	{
		id = "diamond_drill",
		name = "鑽石鑽頭",
		description = "高級自動工具：按住即可連續挖掘，工具強度 80 / 秒。",
		action = "BuyTool",
		item = "鑽石鑽頭",
		price = 9000,
		model = { kind = "pickaxe", color = Color3.fromRGB(65, 240, 255), material = Enum.Material.Neon },
	},
	{
		id = "bomb",
		name = "炸彈",
		description = "可無限重複購買。投擲後以拋物線飛出並爆炸。",
		action = "BuyBomb",
		item = "",
		price = 50,
		model = { kind = "bomb", color = Color3.fromRGB(25, 25, 25), material = Enum.Material.Slate },
	},
	{
		id = "cluster_bomb",
		name = "集束炸彈",
		description = "高級炸彈：價格為普通炸彈 3 倍，可堆疊，爆炸範圍更大。",
		action = "BuyBomb",
		item = "ClusterBombCount",
		price = 150,
		model = { kind = "bomb", color = Color3.fromRGB(120, 30, 30), material = Enum.Material.Metal },
	},
	{
		id = "backpack_upgrade",
		name = "背包升級",
		description = "背包容量 +20。只要在這個表新增商品與模型，就會自動進商店輪播。",
		action = "BuyBackpackUpgrade",
		item = "20",
		price = 300,
		model = { kind = "backpack", color = Color3.fromRGB(85, 135, 210), material = Enum.Material.Fabric },
	},
}

local TOOL_PRICES = {}
for _, catalogItem in ipairs(SHOP_CATALOG) do
	if catalogItem.action == "BuyTool" then
		TOOL_PRICES[catalogItem.item] = catalogItem.price
	end
end

local getRuntimeShopCatalog

local function getCatalogItemById(itemId)
	for _, catalogItem in ipairs(getRuntimeShopCatalog()) do
		if catalogItem.id == itemId then
			return catalogItem
		end
	end
	return nil
end

function getRuntimeShopCatalog()
	local catalog = table.clone(SHOP_CATALOG)
	for _, child in ipairs(getItemStorageFolder():GetChildren()) do
		local storageItem = readCatalogItemFromStorage(child)
		if storageItem then
			table.insert(catalog, storageItem)
		end
	end
	return catalog
end

shopCatalogFunction.OnServerInvoke = function()
	local serializableCatalog = {}
	for _, catalogItem in ipairs(getRuntimeShopCatalog()) do
		table.insert(serializableCatalog, {
			id = catalogItem.id,
			name = catalogItem.name,
			description = catalogItem.description,
			price = catalogItem.price,
			action = catalogItem.action,
			item = catalogItem.item,
			model = catalogItem.model,
		})
	end
	return serializableCatalog
end

local function giveTool(player, toolName)
	local backpack = player:WaitForChild("Backpack")
	local starterGear = player:WaitForChild("StarterGear")
	if backpack:FindFirstChild(toolName) or starterGear:FindFirstChild(toolName) then
		return false
	end

	local tool = Instance.new("Tool")
	tool.Name = toolName
	tool:SetAttribute("Strength", TOOL_EFFICIENCY[toolName] or 1)
	tool:SetAttribute("AutoMine", TOOL_AUTO_MINE[toolName] == true)

	if toolName == "拳頭" then
		tool.RequiresHandle = false
	else
		tool.RequiresHandle = true
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.4, 3, 0.4)
		handle.Material = Enum.Material.Wood
		handle.Color = Color3.fromRGB(125, 78, 38)
		handle.Parent = tool

		local head = Instance.new("Part")
		head.Name = "ToolHead"
		head.Size = TOOL_AUTO_MINE[toolName] and Vector3.new(1.2, 1.2, 1.2) or Vector3.new(2, 0.35, 0.35)
		head.Material = (toolName == "鐵鎬" or toolName == "鐵鑽頭") and Enum.Material.Metal or ((toolName == "鑽石鎬" or toolName == "鑽石鑽頭") and Enum.Material.Neon or Enum.Material.Wood)
		head.Color = (toolName == "鐵鎬" or toolName == "鐵鑽頭") and Color3.fromRGB(180, 185, 190) or ((toolName == "鑽石鎬" or toolName == "鑽石鑽頭") and Color3.fromRGB(45, 210, 235) or Color3.fromRGB(126, 78, 36))
		head.Shape = TOOL_AUTO_MINE[toolName] and Enum.PartType.Ball or Enum.PartType.Block
		head.CFrame = handle.CFrame * CFrame.new(0, 1.35, 0)
		head.Parent = tool

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = handle
		weld.Part1 = head
		weld.Parent = handle
	end

	tool.Parent = backpack
	local clone = tool:Clone()
	clone.Parent = starterGear
	rememberTool(player, toolName)
	return true
end

local function getBombCountValue(player, countName)
	local value = player:FindFirstChild(countName)
	if not value then
		value = Instance.new("IntValue")
		value.Name = countName
		value.Value = 0
		value.Parent = player
	end
	return value
end

local function updateBombTool(player, countName, toolBaseName, radius)
	local backpack = player:WaitForChild("Backpack")
	local character = player.Character
	local countValue = getBombCountValue(player, countName)
	local tool = nil
	for _, container in ipairs({ backpack, character }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and child:GetAttribute("BombCountName") == countName then
					tool = child
					break
				end
			end
		end
		if tool then
			break
		end
	end
	if countValue.Value <= 0 then
		if tool then
			tool:Destroy()
		end
		return nil
	end
	if not tool then
		tool = Instance.new("Tool")
		tool.Name = toolBaseName
		tool.RequiresHandle = true
		tool:SetAttribute("BombCountName", countName)
		tool:SetAttribute("BombBaseName", toolBaseName)
		tool:SetAttribute("BombRadius", radius)
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Shape = Enum.PartType.Ball
		handle.Size = Vector3.new(1.6, 1.6, 1.6)
		handle.Material = (radius > 1) and Enum.Material.Metal or Enum.Material.Slate
		handle.Color = (radius > 1) and Color3.fromRGB(120, 30, 30) or Color3.fromRGB(25, 25, 25)
		handle.Parent = tool
		tool.Parent = backpack
	end
	tool.Name = toolBaseName .. " *" .. countValue.Value
	return tool
end

local function refreshBombTools(player)
	updateBombTool(player, "BombCount", BOMB_TOOL_NAME, 1)
	updateBombTool(player, "ClusterBombCount", CLUSTER_BOMB_TOOL_NAME, 2)
end

local function giveStoredWeapons(player)
	giveTool(player, "拳頭")
	local ownedTools = getOwnedToolsFolder(player)
	for _, toolName in ipairs(PICKAXE_NAMES) do
		if ownedTools:FindFirstChild(toolName) then
			giveTool(player, toolName)
		end
	end
	refreshBombTools(player)
end

Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player

	local money = Instance.new("IntValue")
	money.Name = "Coins"
	money.Value = 0
	money.Parent = leaderstats

	local sandCount = Instance.new("IntValue")
	sandCount.Name = "Sand"
	sandCount.Value = 0
	sandCount.Parent = leaderstats

	local maxSand = Instance.new("IntValue")
	maxSand.Name = "MaxSand"
	maxSand.Value = MAX_BACKPACK_CAPPED
	maxSand.Parent = player

	local currentPickaxe = Instance.new("StringValue")
	currentPickaxe.Name = "CurrentPickaxe"
	currentPickaxe.Value = "拳頭"
	currentPickaxe.Parent = player

	local bombCount = Instance.new("IntValue")
	bombCount.Name = "BombCount"
	bombCount.Value = 0
	bombCount.Parent = player

	local clusterBombCount = Instance.new("IntValue")
	clusterBombCount.Name = "ClusterBombCount"
	clusterBombCount.Value = 0
	clusterBombCount.Parent = player

	local ownedTools = getOwnedToolsFolder(player)
	local success, savedData = pcall(function()
		return PLAYER_DATA_STORE:GetAsync(player.UserId)
	end)
	if success and type(savedData) == "table" then
		money.Value = tonumber(savedData.Coins) or 0
		currentPickaxe.Value = savedData.CurrentPickaxe or "拳頭"
		bombCount.Value = tonumber(savedData.BombCount) or 0
		clusterBombCount.Value = tonumber(savedData.ClusterBombCount) or 0
		maxSand.Value = tonumber(savedData.MaxSand) or MAX_BACKPACK_CAPPED
		for _, toolName in ipairs(savedData.OwnedTools or {}) do
			rememberTool(player, toolName)
		end
	elseif not success then
		sendNotification(player, "資料讀取失敗", "暫時使用本局資料，離線前會再嘗試保存。")
	end

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		giveStoredWeapons(player)
		teleportPlayerToSteel(player)
	end)
end)

local function savePlayerData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local currentPickaxe = player:FindFirstChild("CurrentPickaxe")
	local bombCount = player:FindFirstChild("BombCount")
	local clusterBombCount = player:FindFirstChild("ClusterBombCount")
	local ownedTools = player:FindFirstChild("OwnedTools")
	local maxSand = player:FindFirstChild("MaxSand")
	if not leaderstats or not currentPickaxe or not bombCount or not clusterBombCount or not ownedTools or not maxSand then
		return
	end
	local toolList = {}
	for _, value in ipairs(ownedTools:GetChildren()) do
		table.insert(toolList, value.Name)
	end
	pcall(function()
		PLAYER_DATA_STORE:SetAsync(player.UserId, {
			Coins = leaderstats.Coins.Value,
			CurrentPickaxe = currentPickaxe.Value,
			BombCount = bombCount.Value,
			ClusterBombCount = clusterBombCount.Value,
			MaxSand = maxSand.Value,
			OwnedTools = toolList,
		})
	end)
end

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
	playerMiningState[player] = nil
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerData(player)
	end
end)


local function createCatalogModel(parent, itemData, pivotCFrame)
	local model = Instance.new("Model")
	model.Name = itemData.id .. "_Preview"
	model.Parent = parent

	local visual = itemData.model
	local mainPart
	if visual.kind == "pickaxe" then
		mainPart = Instance.new("Part")
		mainPart.Name = "Handle"
		mainPart.Size = Vector3.new(0.35, 3.2, 0.35)
		mainPart.Material = Enum.Material.Wood
		mainPart.Color = Color3.fromRGB(125, 78, 38)
		mainPart.Anchored = true
		mainPart.CFrame = pivotCFrame * CFrame.Angles(0, 0, math.rad(25))
		mainPart.Parent = model

		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(2.4, 0.35, 0.35)
		head.Material = visual.material
		head.Color = visual.color
		head.Anchored = true
		head.CFrame = mainPart.CFrame * CFrame.new(0, 1.35, 0)
		head.Parent = model
	elseif visual.kind == "bomb" then
		mainPart = Instance.new("Part")
		mainPart.Name = "BombBody"
		mainPart.Shape = Enum.PartType.Ball
		mainPart.Size = Vector3.new(2.2, 2.2, 2.2)
		mainPart.Material = visual.material
		mainPart.Color = visual.color
		mainPart.Anchored = true
		mainPart.CFrame = pivotCFrame
		mainPart.Parent = model
	elseif visual.kind == "backpack" then
		mainPart = Instance.new("Part")
		mainPart.Name = "BackpackBody"
		mainPart.Size = Vector3.new(2.2, 2.8, 1.2)
		mainPart.Material = visual.material
		mainPart.Color = visual.color
		mainPart.Anchored = true
		mainPart.CFrame = pivotCFrame
		mainPart.Parent = model
	else
		mainPart = Instance.new("Part")
		mainPart.Name = "DisplayBlock"
		mainPart.Size = visual.size or Vector3.new(2, 2, 2)
		mainPart.Material = visual.material
		mainPart.Color = visual.color
		mainPart.Anchored = true
		mainPart.CFrame = pivotCFrame
		mainPart.Parent = model
	end

	model.PrimaryPart = mainPart
	return model
end


local function getOrCreateChild(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing, false
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created, true
end

local function configureGuiButton(parent, name, text, size, position)
	local button, created = getOrCreateChild(parent, "TextButton", name)
	if created then
		button.Text = text
		button.Size = size
		button.Position = position
		button.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
		button.TextColor3 = Color3.fromRGB(255, 255, 255)
		button.TextScaled = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = button
	end
	return button, created
end

local function ensureStarterGuiTemplate()
	local gui, guiCreated = getOrCreateChild(StarterGui, "ScreenGui", "MiningHud")
	if guiCreated then
		gui.ResetOnSpawn = false
	end

	local infoLabel, infoCreated = getOrCreateChild(gui, "TextLabel", "WorldInfo")
	if infoCreated then
		infoLabel.Size = UDim2.fromOffset(260, 58)
		infoLabel.Position = UDim2.fromOffset(16, 16)
		infoLabel.BackgroundTransparency = 0.25
		infoLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		infoLabel.TextColor3 = Color3.fromRGB(255, 245, 210)
		infoLabel.TextWrapped = true
		infoLabel.TextScaled = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = infoLabel
	end

	configureGuiButton(gui, "TeleportHomeButton", "一鍵回城", UDim2.fromOffset(120, 42), UDim2.fromOffset(16, 160))
	local fullButton, fullButtonCreated = configureGuiButton(gui, "FullBackpackReturnButton", "背包已滿！返回商城", UDim2.fromOffset(260, 58), UDim2.new(0.5, -130, 0.52, 0))
	if fullButton and fullButtonCreated then
		fullButton.BackgroundColor3 = Color3.fromRGB(170, 80, 35)
		fullButton.Visible = false
	end

	local shopFrame, shopCreated = getOrCreateChild(gui, "Frame", "ShopFrame")
	if shopCreated then
		shopFrame.Size = UDim2.fromOffset(380, 240)
		shopFrame.Position = UDim2.new(0.5, -190, 1, -260)
		shopFrame.BackgroundColor3 = Color3.fromRGB(64, 42, 24)
		shopFrame.Visible = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 16)
		corner.Parent = shopFrame
	end
	configureGuiButton(shopFrame, "CloseButton", "X", UDim2.fromOffset(36, 36), UDim2.new(1, -44, 0, 8))
	configureGuiButton(shopFrame, "PreviousItem", "◀ 上一個", UDim2.fromOffset(110, 42), UDim2.fromOffset(16, 150))
	configureGuiButton(shopFrame, "BuySelected", "購買", UDim2.fromOffset(120, 42), UDim2.fromOffset(130, 150))
	configureGuiButton(shopFrame, "NextItem", "下一個 ▶", UDim2.fromOffset(110, 42), UDim2.fromOffset(254, 150))

	local title, titleCreated = getOrCreateChild(shopFrame, "TextLabel", "Title")
	if titleCreated then
		title.Text = "礦工棚子商店"
		title.Size = UDim2.new(1, -48, 0, 44)
		title.Position = UDim2.fromOffset(8, 8)
		title.BackgroundTransparency = 1
		title.TextColor3 = Color3.fromRGB(255, 235, 190)
		title.TextScaled = true
	end

	local description, descriptionCreated = getOrCreateChild(shopFrame, "TextLabel", "Description")
	if descriptionCreated then
		description.Size = UDim2.new(1, -32, 0, 76)
		description.Position = UDim2.fromOffset(16, 56)
		description.BackgroundTransparency = 0.25
		description.BackgroundColor3 = Color3.fromRGB(45, 30, 18)
		description.TextColor3 = Color3.fromRGB(255, 235, 190)
		description.TextWrapped = true
		description.TextScaled = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 12)
		corner.Parent = description
	end

	local oldProgress = gui:FindFirstChild("MiningProgress")
	if oldProgress then
		oldProgress:Destroy()
	end
end
ensureStarterGuiTemplate()

-- ==================== 2. 建立齊平場地與實體商店 ====================
local function createShopWorld()
	local shopModel = Workspace:FindFirstChild("MiningShopWorld")
	if not shopModel then
		shopModel = Instance.new("Model")
		shopModel.Name = "MiningShopWorld"
		shopModel.Parent = Workspace
	end

	local function createPartIfMissing(name, configure)
		local part = shopModel:FindFirstChild(name, true) or Workspace:FindFirstChild(name, true)
		if not part then
			part = Instance.new("Part")
			part.Name = name
			part.Parent = shopModel
			configure(part)
		end
		return part
	end

	createPartIfMissing("SecureFloor", function(secureFloor)
		secureFloor.Size = STEEL_FLOOR_SIZE
		secureFloor.Position = Vector3.new(0, -STEEL_FLOOR_SIZE.Y / 2, -25)
		secureFloor.Material = Enum.Material.Metal
		secureFloor.Color = Color3.fromRGB(125, 135, 145)
		secureFloor.Anchored = true
		secureFloor.CanCollide = true
	end)

	createPartIfMissing("WoodDeck", function(deck)
		deck.Size = Vector3.new(18, 0.4, 16)
		deck.Position = SHOP_POSITION + Vector3.new(0, 0.2, -2)
		deck.Material = Enum.Material.WoodPlanks
		deck.Color = Color3.fromRGB(139, 92, 50)
		deck.Anchored = true
	end)

	createPartIfMissing("CanvasCanopy", function(roof)
		roof.Size = Vector3.new(22, 0.6, 18)
		roof.Position = SHOP_POSITION + Vector3.new(0, 8, -2)
		roof.Material = Enum.Material.Fabric
		roof.Color = Color3.fromRGB(205, 60, 45)
		roof.Anchored = true
	end)

	local postOffsets = {
		Vector3.new(-8, 4, -9),
		Vector3.new(8, 4, -9),
		Vector3.new(-8, 4, 5),
		Vector3.new(8, 4, 5),
	}
	for index, offset in ipairs(postOffsets) do
		createPartIfMissing("ShedPost" .. index, function(post)
			post.Size = Vector3.new(1, 8, 1)
			post.Position = SHOP_POSITION + offset
			post.Material = Enum.Material.Wood
			post.Color = Color3.fromRGB(105, 68, 36)
			post.Anchored = true
		end)
	end

	createPartIfMissing("ShopOpenZone", function(shopZone)
		shopZone.Shape = Enum.PartType.Cylinder
		shopZone.Size = Vector3.new(0.25, 18, 18)
		shopZone.CFrame = CFrame.new(SHOP_POSITION + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
		shopZone.Material = Enum.Material.Neon
		shopZone.Color = Color3.fromRGB(80, 210, 255)
		shopZone.Transparency = 0.55
		shopZone.Anchored = true
		shopZone.CanCollide = false
	end)

	createPartIfMissing("ShopCounter", function(shopCounter)
		shopCounter.Size = Vector3.new(8, 3, 2)
		shopCounter.Position = SHOP_POSITION + Vector3.new(0, 1.5, -7)
		shopCounter.Material = Enum.Material.WoodPlanks
		shopCounter.Color = Color3.fromRGB(157, 107, 63)
		shopCounter.Anchored = true
	end)

	createPartIfMissing("ShopSign", function(sign)
		sign.Size = Vector3.new(10, 2, 0.4)
		sign.Position = SHOP_POSITION + Vector3.new(0, 6, -7.3)
		sign.Material = Enum.Material.WoodPlanks
		sign.Color = Color3.fromRGB(118, 74, 34)
		sign.Anchored = true
	end)

	createPartIfMissing("ShopPreviewBase", function(previewBase)
		previewBase.Size = Vector3.new(10, 0.5, 10)
		previewBase.Position = SHOP_PREVIEW_POSITION + Vector3.new(0, 0.25, 0)
		previewBase.Material = Enum.Material.WoodPlanks
		previewBase.Color = Color3.fromRGB(120, 75, 35)
		previewBase.Anchored = true
	end)

	createPartIfMissing("ShopCameraAnchor", function(cameraAnchor)
		cameraAnchor.Size = Vector3.new(1, 1, 1)
		cameraAnchor.Transparency = 1
		cameraAnchor.CanCollide = false
		cameraAnchor.Anchored = true
		cameraAnchor.CFrame = CFrame.lookAt(SHOP_PREVIEW_POSITION + Vector3.new(0, 5, 11), SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0))
	end)

	local previewFolder = shopModel:FindFirstChild("ShopPreviewModels") or Instance.new("Folder")
	previewFolder.Name = "ShopPreviewModels"
	previewFolder.Parent = shopModel

	local itemModelsFolder = ServerStorage:FindFirstChild("MiningItemModels") or Instance.new("Folder")
	itemModelsFolder.Name = "MiningItemModels"
	itemModelsFolder.Parent = ServerStorage
	for _, catalogItem in ipairs(SHOP_CATALOG) do
		if not itemModelsFolder:FindFirstChild(catalogItem.id) then
			local itemFolder = Instance.new("Folder")
			itemFolder.Name = catalogItem.id
			itemFolder:SetAttribute("ShopItem", false)
			itemFolder.Parent = itemModelsFolder
			createCatalogModel(itemFolder, catalogItem, CFrame.new())
		end
	end

	local miningAssets = ServerStorage:FindFirstChild("MiningAssets") or Instance.new("Folder")
	miningAssets.Name = "MiningAssets"
	miningAssets.Parent = ServerStorage
	local effectsFolder = miningAssets:FindFirstChild("MiningEffects") or Instance.new("Folder")
	effectsFolder.Name = "MiningEffects"
	effectsFolder.Parent = miningAssets
	local debrisConfig = effectsFolder:FindFirstChild("MiningDebrisConfig") or Instance.new("Folder")
	debrisConfig.Name = "MiningDebrisConfig"
	debrisConfig.Parent = effectsFolder
	local debrisCount = debrisConfig:FindFirstChild("DebrisCount") or Instance.new("IntValue")
	debrisCount.Name = "DebrisCount"
	debrisCount.Value = MINING_DEBRIS_COUNT
	debrisCount.Parent = debrisConfig
	local debrisLifetime = debrisConfig:FindFirstChild("DebrisLifetime") or Instance.new("NumberValue")
	debrisLifetime.Name = "DebrisLifetime"
	debrisLifetime.Value = 0.8
	debrisLifetime.Parent = debrisConfig
	local debrisSpeed = debrisConfig:FindFirstChild("DebrisSpeed") or Instance.new("NumberValue")
	debrisSpeed.Name = "DebrisSpeed"
	debrisSpeed.Value = 24
	debrisSpeed.Parent = debrisConfig
	if not effectsFolder:FindFirstChild("MiningImpactSound") then
		local sound = Instance.new("Sound")
		sound.Name = "MiningImpactSound"
		sound.SoundId = "rbxassetid://12221976"
		sound.Volume = 0.35
		sound.RollOffMaxDistance = 45
		sound.Parent = effectsFolder
	end

	-- 商品模型由每位玩家的 LocalScript 依目錄載入到高空預覽區，避免多人同時切換商品時互相影響。
end
createShopWorld()

-- 一鍵回城
teleportEvent.OnServerEvent:Connect(function(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(getWorldOrigin() + Vector3.new(0, 7, 0))
	end
end)

local function isChestBlock(blockType)
	return type(blockType) == "table" and blockType.kind == "Chest"
end

local function getChestLevel(levelId)
	for _, level in ipairs(CHEST_LEVELS) do
		if level.id == levelId then
			return level
		end
	end
	return CHEST_LEVELS[1]
end

local releaseCactus

-- 炸彈爆炸邏輯
local function triggerExplosion(player, centerPos, radius)
	radius = radius or 1
	local lstats = player:FindFirstChild("leaderstats")
	local maxSandVal = player:FindFirstChild("MaxSand")
	if not lstats or not maxSandVal then
		return
	end

	local cx, cy, cz = blockFromWorld(centerPos)

	local earnedSand = 0
	local earnedCoins = 0

	for x = -radius, radius do
		for y = -radius, radius do
			for z = -radius, radius do
				local bx, by, bz = cx + x, cy + y, cz + z
				local key = bx .. "_" .. by .. "_" .. bz
				local blockType = worldData[key]

				if blockType then
					worldData[key] = false
					if spawnedParts[key] then
						releaseCactus(spawnedParts[key])
						spawnedParts[key]:Destroy()
						spawnedParts[key] = nil
					end
					blockHealthData[key] = nil
					if isChestBlock(blockType) then
						local level = getChestLevel(blockType.level)
						earnedCoins += math.random(level.reward[1], level.reward[2])
					elseif lstats.Sand.Value + earnedSand < maxSandVal.Value then
						earnedSand += 1
					end
				end
			end
		end
	end

	lstats.Sand.Value = math.clamp(lstats.Sand.Value + earnedSand, 0, maxSandVal.Value)
	if earnedCoins > 0 then
		lstats.Coins.Value += earnedCoins
		rewardEmojiEvent:FireClient(player, "💥", earnedCoins)
	end
	if earnedSand > 0 then
		sendNotification(player, "炸彈爆炸", "成功轟炸！收集了 " .. earnedSand .. " 顆沙子。")
	end
end

-- 商店交易後端
shopActionEvent.OnServerEvent:Connect(function(player, action, item)
	local catalogItem = getCatalogItemById(action)
	local catalogPrice = nil
	if catalogItem then
		action = catalogItem.action
		item = catalogItem.item
		catalogPrice = catalogItem.price
	end

	local lstats = player:FindFirstChild("leaderstats")
	local currentPickaxe = player:FindFirstChild("CurrentPickaxe")
	if not lstats or not currentPickaxe then
		return
	end

	local coins = lstats:FindFirstChild("Coins")
	local sand = lstats:FindFirstChild("Sand")
	if not coins or not sand then
		return
	end

	if action == "Sell" then
		local amount = sand.Value
		if amount > 0 then
			coins.Value += amount * 5
			sand.Value = 0
			sendNotification(player, "成功出售", "出售全部沙子，賺取了 " .. (amount * 5) .. " 金幣！")
		else
			sendNotification(player, "提示", "身上沒有沙子可以賣。")
		end
	elseif action == "BuyTool" then
		local price = catalogPrice or TOOL_PRICES[item]
		if price and coins.Value >= price and giveTool(player, item) then
			coins.Value -= price
			currentPickaxe.Value = item
			sendNotification(player, "購買成功", "獲得 " .. item .. "！")
		else
			sendNotification(player, "交易失敗", "金幣不足，或已擁有該等級工具。")
		end
	elseif action == "BuyBomb" then
		local countName = (item ~= "" and item) or "BombCount"
		local bombCount = getBombCountValue(player, countName)
		local price = catalogPrice or 50
		if coins.Value >= price and bombCount then
			coins.Value -= price
			bombCount.Value += 1
			refreshBombTools(player)
			sendNotification(player, "購買成功", "炸彈已堆疊到背包：" .. bombCount.Value)
		else
			sendNotification(player, "交易失敗", "金幣不足。")
		end
	elseif action == "BuyBackpackUpgrade" then
		local price = catalogPrice or 300
		local upgradeAmount = tonumber(item) or BACKPACK_UPGRADE_AMOUNT
		if coins.Value >= price then
			coins.Value -= price
			local maxSand = player:FindFirstChild("MaxSand")
			if maxSand then
				maxSand.Value += upgradeAmount
			end
			sendNotification(player, "背包升級", "背包容量增加 " .. upgradeAmount .. "！")
		else
			sendNotification(player, "交易失敗", "金幣不足。")
		end
	end
end)

-- ==================== 3. 核心大世界生成機制 ====================
local function getSurfaceHeight(bx, bz)
	local broad = math.noise(bx * NOISE_SCALE, bz * NOISE_SCALE, 0) * HILL_HEIGHT_BLOCKS
	local detail = math.noise(bx * NOISE_SCALE * 2.7, bz * NOISE_SCALE * 2.7, 31) * 1.5
	return math.max(0, math.floor(broad + detail))
end

local function getChestLevelForDepth(depth)
	local available = {}
	local totalWeight = 0
	for _, level in ipairs(CHEST_LEVELS) do
		if depth >= level.minDepth then
			table.insert(available, level)
			totalWeight += level.weight
		end
	end
	local roll = math.random() * totalWeight
	for _, level in ipairs(available) do
		roll -= level.weight
		if roll <= 0 then
			return level
		end
	end
	return available[1] or CHEST_LEVELS[1]
end

local function isInShopSafeZone(bx, by, bz)
	local steelFloor = getSteelFloor()
	local halfX = math.max(0, ((steelFloor and steelFloor.Size.X) or STEEL_FLOOR_SIZE.X) / 2 - BLOCK_SIZE / 2)
	local halfZ = math.max(0, ((steelFloor and steelFloor.Size.Z) or STEEL_FLOOR_SIZE.Z) / 2 - BLOCK_SIZE / 2)
	local relativeToSteel = Vector3.new(bx * BLOCK_SIZE, by * BLOCK_SIZE, bz * BLOCK_SIZE)
	return relativeToSteel.X >= -halfX and relativeToSteel.X <= halfX and relativeToSteel.Z >= -halfZ and relativeToSteel.Z <= halfZ and by >= -2
end

local function getBlockData(bx, by, bz)
	if by < -MAX_DEPTH_BLOCKS then
		return false
	end

	if isInShopSafeZone(bx, by, bz) then
		return false
	end

	local surfaceHeight = getSurfaceHeight(bx, bz)
	if by > surfaceHeight then
		return false
	end

	local key = bx .. "_" .. by .. "_" .. bz
	if worldData[key] == nil then
		local depth = math.max(0, -by)
		if by <= 0 and math.random() < CHEST_CHANCE then
			local level = getChestLevelForDepth(depth)
			worldData[key] = { kind = "Chest", level = level.id }
		else
			worldData[key] = true
		end
	end
	return worldData[key]
end

local function shouldSpawnCactus(bx, bz)
	local cactusNoise = math.noise(bx * 0.19, bz * 0.19, 83)
	return cactusNoise > 0.38 and math.random() < CACTUS_CHANCE
end

local function isBlockExposed(bx, by, bz)
	local neighbors = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
	for _, offset in ipairs(neighbors) do
		if not getBlockData(bx + offset[1], by + offset[2], bz + offset[3]) then
			return true
		end
	end
	return false
end

local function instanceBlock(bx, by, bz)
	local key = bx .. "_" .. by .. "_" .. bz
	if spawnedParts[key] then
		return
	end

	local blockType = getBlockData(bx, by, bz)
	if not blockType then
		return
	end

	local chest = isChestBlock(blockType)
	local chestLevel = chest and getChestLevel(blockType.level) or nil
	local blockModel = Instance.new("Model")
	blockModel.Name = chest and "ChestBlock" or "SandBlock"
	blockModel.Parent = folder

	local part
	if chest and ServerStorage:FindFirstChild("BOX") then
		local boxTemplate = ServerStorage:FindFirstChild("BOX")
		local boxClone = boxTemplate:Clone()
		boxClone.Name = "Block"
		boxClone.Parent = blockModel
		if boxClone:IsA("Model") then
			part = boxClone.PrimaryPart or boxClone:FindFirstChildWhichIsA("BasePart", true)
			if part then
				boxClone.PrimaryPart = part
				boxClone:PivotTo(CFrame.new(worldFromBlock(bx, by, bz)))
			end
		elseif boxClone:IsA("BasePart") then
			part = boxClone
			part.Position = worldFromBlock(bx, by, bz)
		end
	else
		part = Instance.new("Part")
		part.Name = "Block"
		part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
		part.Position = worldFromBlock(bx, by, bz)
		part.Material = chest and Enum.Material.WoodPlanks or Enum.Material.Sand
		part.Parent = blockModel
	end

	if not part then
		blockModel:Destroy()
		return
	end
	for _, descendant in ipairs(blockModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = true
			descendant:SetAttribute("BlockKey", key)
			if chest and chestLevel then
				descendant.Color = chestLevel.color
			end
		end
	end
	blockModel.PrimaryPart = part
	part:SetAttribute("BlockKey", key)

	local depthPercent = math.clamp(math.abs(by) / MAX_DEPTH_BLOCKS, 0, 1)
	if not chest then
		part.Color = Color3.fromRGB(240, 200, 140):Lerp(Color3.fromRGB(40, 30, 20), depthPercent)
	end

	if by == getSurfaceHeight(bx, bz) and shouldSpawnCactus(bx, bz) then
		local cactus = Instance.new("Part")
		cactus.Name = "Cactus"
		cactus.Size = Vector3.new(1.6, math.random(4, 7) * CACTUS_HEIGHT_SCALE, 1.6)
		cactus.Position = part.Position + Vector3.new(0, BLOCK_SIZE / 2 + cactus.Size.Y / 2, 0)
		cactus.Material = Enum.Material.Grass
		cactus.Color = Color3.fromRGB(35, 135, 55)
		cactus.Anchored = true
		cactus.Parent = blockModel
	end

	spawnedParts[key] = blockModel
end

local function revealNeighbors(bx, by, bz)
	local neighbors = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
	for _, offset in ipairs(neighbors) do
		local nx, ny, nz = bx + offset[1], by + offset[2], bz + offset[3]
		if getBlockData(nx, ny, nz) and isBlockExposed(nx, ny, nz) then
			instanceBlock(nx, ny, nz)
		end
	end
end

function releaseCactus(blockModel)
	local cactus = blockModel and blockModel:FindFirstChild("Cactus")
	if not cactus then
		return
	end
	local fallingCactus = cactus:Clone()
	fallingCactus.Parent = Workspace
	fallingCactus.Anchored = false
	fallingCactus.CanCollide = true
	fallingCactus.AssemblyLinearVelocity = Vector3.new(math.random(-8, 8), 14, math.random(-8, 8))
	fallingCactus.AssemblyAngularVelocity = Vector3.new(math.random(-5, 5), math.random(-5, 5), math.random(-5, 5))
	TweenService:Create(fallingCactus, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
	Debris:AddItem(fallingCactus, 1.55)
end

-- ==================== 4. 統一處理挖掘事件 (不透過 ClickDetector) ====================
miningEvent.OnServerEvent:Connect(function(player, targetPart)
	if not targetPart or not targetPart:IsDescendantOf(folder) then
		return
	end

	local currentTool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	local bombCountName = currentTool and currentTool:GetAttribute("BombCountName")
	if currentTool and bombCountName then
		local bombCount = getBombCountValue(player, bombCountName)
		bombCount.Value = math.max(0, bombCount.Value - 1)
		local bombRadius = currentTool:GetAttribute("BombRadius") or 1
		local bombBaseName = currentTool:GetAttribute("BombBaseName") or BOMB_TOOL_NAME
		if bombCount.Value <= 0 then
			currentTool:Destroy()
		else
			currentTool.Name = bombBaseName .. " *" .. bombCount.Value
		end

		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local startPosition = root and (root.Position + Vector3.new(0, 2, 0)) or (targetPart.Position + Vector3.new(0, 5, 0))
		local targetPosition = targetPart.Position
		local projectile = Instance.new("Part")
		projectile.Name = "ThrownBomb"
		projectile.Shape = Enum.PartType.Ball
		projectile.Size = Vector3.new(1.8, 1.8, 1.8)
		projectile.Material = Enum.Material.Slate
		projectile.Color = Color3.fromRGB(20, 20, 20)
		projectile.Anchored = true
		projectile.CanCollide = false
		projectile.Position = startPosition
		projectile.Parent = Workspace

		local flightTime = BOMB_THROW_FLIGHT_TIME
		local apexLift = math.clamp((targetPosition - startPosition).Magnitude * 0.12, 3, 9)
		task.spawn(function()
			local steps = 18
			for step = 1, steps do
				local alpha = step / steps
				local flatPosition = startPosition:Lerp(targetPosition, alpha)
				local arcOffset = math.sin(math.pi * alpha) * apexLift
				projectile.Position = flatPosition + Vector3.new(0, arcOffset, 0)
				task.wait(flightTime / steps)
			end
			triggerExplosion(player, targetPosition, bombRadius)
			projectile:Destroy()
		end)
		return
	end

	local lstats = player:FindFirstChild("leaderstats")
	local maxSand = player:FindFirstChild("MaxSand")
	if not lstats or not maxSand then
		return
	end

	local bx, by, bz = blockFromWorld(targetPart.Position)
	local key = targetPart:GetAttribute("BlockKey") or (bx .. "_" .. by .. "_" .. bz)
	if targetPart:GetAttribute("BlockKey") then
		local parsedX, parsedY, parsedZ = string.match(key, "^(-?%d+)_(-?%d+)_(-?%d+)$")
		bx, by, bz = tonumber(parsedX) or bx, tonumber(parsedY) or by, tonumber(parsedZ) or bz
	end

	local blockType = worldData[key]
	if not blockType then
		return
	end

	if lstats.Sand.Value >= maxSand.Value and not isChestBlock(blockType) then
		sendNotification(player, "背包已滿", "請使用左側【一鍵回城】清空背包！")
		return
	end

	local chestLevel = isChestBlock(blockType) and getChestLevel(blockType.level) or nil
	local maxHealth = chestLevel and chestLevel.health or (math.abs(by) + 10)
	blockHealthData[key] = blockHealthData[key] or maxHealth

	local stateKey = player.UserId .. ":" .. key
	local now = os.clock()
	local previousTime = playerMiningState[stateKey] or (now - 0.2)
	local elapsed = math.clamp(now - previousTime, 0.05, 0.35)
	playerMiningState[stateKey] = now
	local equippedTool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	local power = (equippedTool and equippedTool:GetAttribute("Strength")) or 1
	blockHealthData[key] -= power * elapsed

	local miningAssets = ServerStorage:FindFirstChild("MiningAssets")
	local miningEffects = miningAssets and miningAssets:FindFirstChild("MiningEffects")
	local debrisConfig = miningEffects and miningEffects:FindFirstChild("MiningDebrisConfig")
	local debrisCount = (debrisConfig and debrisConfig:FindFirstChild("DebrisCount") and debrisConfig.DebrisCount.Value) or MINING_DEBRIS_COUNT
	local debrisLifetime = (debrisConfig and debrisConfig:FindFirstChild("DebrisLifetime") and debrisConfig.DebrisLifetime.Value) or 0.8
	local debrisSpeed = (debrisConfig and debrisConfig:FindFirstChild("DebrisSpeed") and debrisConfig.DebrisSpeed.Value) or 24
	local hitNormal = (targetPart.Position - ((player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position) or targetPart.Position)).Unit
	if hitNormal.Magnitude ~= hitNormal.Magnitude then
		hitNormal = Vector3.new(0, 1, 0)
	end
	for _ = 1, debrisCount do
		local chip = Instance.new("Part")
		chip.Name = "MiningDebrisChip"
		chip.Size = Vector3.new(0.22, 0.22, 0.22) * math.random(60, 130) / 100
		chip.Material = targetPart.Material
		chip.Color = targetPart.Color
		chip.CFrame = CFrame.new(targetPart.Position + hitNormal * (targetPart.Size.Magnitude / 8))
		chip.CanCollide = true
		chip.Parent = Workspace
		chip.AssemblyLinearVelocity = (hitNormal * debrisSpeed) + Vector3.new(math.random(-8, 8), math.random(8, 18), math.random(-8, 8))
		chip.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
		TweenService:Create(chip, TweenInfo.new(debrisLifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
		Debris:AddItem(chip, debrisLifetime + 0.1)
	end
	local soundTemplate = miningEffects and miningEffects:FindFirstChild("MiningImpactSound")
	if soundTemplate then
		local sound = soundTemplate:Clone()
		sound.Parent = targetPart
		sound:Play()
		sound.Ended:Connect(function()
			sound:Destroy()
		end)
	end

	miningEvent:FireClient(player, targetPart, blockHealthData[key], maxHealth)

	if blockHealthData[key] <= 0 then
		worldData[key] = false
		blockHealthData[key] = nil
		if spawnedParts[key] then
			releaseCactus(spawnedParts[key])
			spawnedParts[key]:Destroy()
			spawnedParts[key] = nil
		end
		miningEvent:FireClient(player, targetPart, 0, maxHealth)

		if isChestBlock(blockType) then
			local level = getChestLevel(blockType.level)
			local reward = math.random(level.reward[1], level.reward[2])
			lstats.Coins.Value += reward
			rewardEmojiEvent:FireClient(player, level.emoji or "🪙", reward)
		else
			lstats.Sand.Value = math.clamp(lstats.Sand.Value + 1, 0, maxSand.Value)
		end

		revealNeighbors(bx, by, bz)
	end
end)

local function refreshWorld()
	for _, blockModel in ipairs(folder:GetChildren()) do
		blockModel:Destroy()
	end
	table.clear(worldData)
	table.clear(spawnedParts)
	table.clear(blockHealthData)
	table.clear(playerMiningState)
	for _, player in ipairs(Players:GetPlayers()) do
		local sand = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Sand")
		if sand then
			sand.Value = 0
		end
		teleportPlayerToSteel(player)
		sendNotification(player, "世界刷新", "礦區已重置，所有玩家已回到鋼體平台。")
	end
end

task.spawn(function()
	while true do
		nextWorldRefreshTimeValue.Value = os.time() + WORLD_REFRESH_SECONDS
		task.wait(math.max(0, WORLD_REFRESH_SECONDS - 5))
		for _, player in ipairs(Players:GetPlayers()) do
			sendNotification(player, "世界即將刷新", "5 秒後重置礦區，請注意安全！")
		end
		task.wait(5)
		refreshWorld()
	end
end)

-- 大世界裁剪循環：支援所有玩家，而不是只更新第一位玩家。
local function updateWorldForPlayer(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	if root.Position.Y < getWorldOrigin().Y - 180 then
		root.CFrame = CFrame.new(getWorldOrigin() + Vector3.new(0, 8, 0))
		return
	end

	local pBx, pBy, pBz = blockFromWorld(root.Position)

	for x = -CHUNK_RADIUS_XZ, CHUNK_RADIUS_XZ do
		for y = -CHUNK_RADIUS_Y, CHUNK_RADIUS_Y do
			for z = -CHUNK_RADIUS_XZ, CHUNK_RADIUS_XZ do
				local bx, by, bz = pBx + x, pBy + y, pBz + z
				if getBlockData(bx, by, bz) and isBlockExposed(bx, by, bz) then
					instanceBlock(bx, by, bz)
				end
			end
		end
	end
end

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			updateWorldForPlayer(player)
		end
		task.wait(0.3)
	end
end)
