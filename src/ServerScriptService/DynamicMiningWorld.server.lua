local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

-- ==================== 參數設定 ====================
local BLOCK_SIZE = 4
local CHUNK_RADIUS_XZ = 6
local CHUNK_RADIUS_Y = 4
local MAX_DEPTH_BLOCKS = 4000
local CHEST_CHANCE = 0.02
local MAX_BACKPACK_CAPPED = 20
local WORLD_REFRESH_SECONDS = 10 * 60
local PLAYER_DATA_STORE = DataStoreService:GetDataStore("DynamicMiningWorldPlayerDataV2")

local SHOP_POSITION = Vector3.new(0, 0, -25)

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

local function sendNotification(player, title, text)
	sendNotificationEvent:FireClient(player, title, text)
end

-- ==================== 1. 玩家數據與工具系統 ====================
local TOOL_EFFICIENCY = {
	["拳頭"] = 5,
	["木鎬"] = 20,
	["鐵鎬"] = 50,
	["鑽石鎬"] = 100,
}


local PICKAXE_NAMES = { "木鎬", "鐵鎬", "鑽石鎬" }
local BOMB_TOOL_NAME = "💣 炸彈"
local playerMiningState = {}

local function teleportPlayerToSteel(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(SHOP_POSITION + Vector3.new(0, 7, 0))
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

local TOOL_PRICES = {
	["木鎬"] = 150,
	["鐵鎬"] = 500,
	["鑽石鎬"] = 1500,
}

local function giveTool(player, toolName)
	local backpack = player:WaitForChild("Backpack")
	local starterGear = player:WaitForChild("StarterGear")
	if backpack:FindFirstChild(toolName) or starterGear:FindFirstChild(toolName) then
		return false
	end

	local tool = Instance.new("Tool")
	tool.Name = toolName
	tool.RequiresHandle = false
	tool.Parent = backpack

	local clone = tool:Clone()
	clone.Parent = starterGear
	rememberTool(player, toolName)
	return true
end

local function giveBombTool(player)
	local backpack = player:WaitForChild("Backpack")
	local tool = Instance.new("Tool")
	tool.Name = BOMB_TOOL_NAME
	tool.RequiresHandle = false
	tool.Parent = backpack
	return tool
end

local function giveStoredWeapons(player)
	giveTool(player, "拳頭")
	local ownedTools = getOwnedToolsFolder(player)
	for _, toolName in ipairs(PICKAXE_NAMES) do
		if ownedTools:FindFirstChild(toolName) then
			giveTool(player, toolName)
		end
	end
	local bombCount = player:FindFirstChild("BombCount")
	if bombCount then
		for _ = 1, bombCount.Value do
			giveBombTool(player)
		end
	end
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

	local ownedTools = getOwnedToolsFolder(player)
	local success, savedData = pcall(function()
		return PLAYER_DATA_STORE:GetAsync(player.UserId)
	end)
	if success and type(savedData) == "table" then
		money.Value = tonumber(savedData.Coins) or 0
		currentPickaxe.Value = savedData.CurrentPickaxe or "拳頭"
		bombCount.Value = tonumber(savedData.BombCount) or 0
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
	local ownedTools = player:FindFirstChild("OwnedTools")
	if not leaderstats or not currentPickaxe or not bombCount or not ownedTools then
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

-- ==================== 2. 建立齊平場地與實體商店 ====================
local function createShopWorld()
	local shopModel = Workspace:FindFirstChild("MiningShopWorld") or Instance.new("Model")
	shopModel.Name = "MiningShopWorld"
	shopModel.Parent = Workspace

	-- 與 4x4x4 方塊高度貼合：地板中心在 -2，表面正好是 Y = 0。
	local secureFloor = shopModel:FindFirstChild("SecureFloor") or Instance.new("Part")
	secureFloor.Name = "SecureFloor"
	secureFloor.Size = Vector3.new(44, BLOCK_SIZE, 44)
	secureFloor.Position = Vector3.new(0, -BLOCK_SIZE / 2, -25)
	secureFloor.Material = Enum.Material.Metal
	secureFloor.Color = Color3.fromRGB(125, 135, 145)
	secureFloor.Anchored = true
	secureFloor.CanCollide = true
	secureFloor.Parent = shopModel

	local deck = shopModel:FindFirstChild("WoodDeck") or Instance.new("Part")
	deck.Name = "WoodDeck"
	deck.Size = Vector3.new(18, 0.4, 16)
	deck.Position = SHOP_POSITION + Vector3.new(0, 0.2, -2)
	deck.Material = Enum.Material.WoodPlanks
	deck.Color = Color3.fromRGB(139, 92, 50)
	deck.Anchored = true
	deck.Parent = shopModel

	local roof = shopModel:FindFirstChild("CanvasCanopy") or Instance.new("Part")
	roof.Name = "CanvasCanopy"
	roof.Size = Vector3.new(22, 0.6, 18)
	roof.Position = SHOP_POSITION + Vector3.new(0, 8, -2)
	roof.Material = Enum.Material.Fabric
	roof.Color = Color3.fromRGB(205, 60, 45)
	roof.Anchored = true
	roof.Parent = shopModel

	local postOffsets = {
		Vector3.new(-8, 4, -9),
		Vector3.new(8, 4, -9),
		Vector3.new(-8, 4, 5),
		Vector3.new(8, 4, 5),
	}
	for index, offset in ipairs(postOffsets) do
		local post = shopModel:FindFirstChild("ShedPost" .. index) or Instance.new("Part")
		post.Name = "ShedPost" .. index
		post.Size = Vector3.new(1, 8, 1)
		post.Position = SHOP_POSITION + offset
		post.Material = Enum.Material.Wood
		post.Color = Color3.fromRGB(105, 68, 36)
		post.Anchored = true
		post.Parent = shopModel
	end

	-- 商店櫃台（可互動）
	local shopCounter = shopModel:FindFirstChild("ShopCounter") or Instance.new("Part")
	shopCounter.Name = "ShopCounter"
	shopCounter.Size = Vector3.new(8, 3, 2)
	shopCounter.Position = SHOP_POSITION + Vector3.new(0, 1.5, -7)
	shopCounter.Material = Enum.Material.WoodPlanks
	shopCounter.Color = Color3.fromRGB(157, 107, 63)
	shopCounter.Anchored = true
	shopCounter.Parent = shopModel

	local sign = shopModel:FindFirstChild("ShopSign") or Instance.new("Part")
	sign.Name = "ShopSign"
	sign.Size = Vector3.new(10, 2, 0.4)
	sign.Position = SHOP_POSITION + Vector3.new(0, 6, -7.3)
	sign.Material = Enum.Material.WoodPlanks
	sign.Color = Color3.fromRGB(118, 74, 34)
	sign.Anchored = true
	sign.Parent = shopModel

	local prompt = shopCounter:FindFirstChild("OpenShopPrompt") or Instance.new("ProximityPrompt")
	prompt.Name = "OpenShopPrompt"
	prompt.ActionText = "打開商店"
	prompt.ObjectText = "礦工棚子"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = shopCounter

	local shopItems = {
		{ name = "SellSandDisplay", label = "出售沙子", action = "Sell", item = "", offset = Vector3.new(-8, 2.2, -2), color = Color3.fromRGB(235, 205, 130), size = Vector3.new(2.5, 2.5, 2.5), material = Enum.Material.Sand },
		{ name = "WoodPickaxeDisplay", label = "木鎬 $150", action = "BuyTool", item = "木鎬", offset = Vector3.new(-4, 2.2, -2), color = Color3.fromRGB(126, 78, 36), size = Vector3.new(0.7, 4, 0.7), material = Enum.Material.Wood },
		{ name = "IronPickaxeDisplay", label = "鐵鎬 $500", action = "BuyTool", item = "鐵鎬", offset = Vector3.new(0, 2.2, -2), color = Color3.fromRGB(180, 185, 190), size = Vector3.new(0.7, 4, 0.7), material = Enum.Material.Metal },
		{ name = "DiamondPickaxeDisplay", label = "鑽石鎬 $1500", action = "BuyTool", item = "鑽石鎬", offset = Vector3.new(4, 2.2, -2), color = Color3.fromRGB(45, 210, 235), size = Vector3.new(0.7, 4, 0.7), material = Enum.Material.Neon },
		{ name = "BombDisplay", label = "炸彈 $50", action = "BuyBomb", item = "", offset = Vector3.new(8, 2.2, -2), color = Color3.fromRGB(25, 25, 25), size = Vector3.new(2.2, 2.2, 2.2), material = Enum.Material.Slate },
	}

	for _, itemData in ipairs(shopItems) do
		local display = shopModel:FindFirstChild(itemData.name) or Instance.new("Part")
		display.Name = itemData.name
		display.Size = itemData.size
		display.Position = SHOP_POSITION + itemData.offset
		display.Material = itemData.material
		display.Color = itemData.color
		display.Anchored = true
		display.Shape = (itemData.name == "BombDisplay") and Enum.PartType.Ball or Enum.PartType.Block
		display:SetAttribute("ShopAction", itemData.action)
		display:SetAttribute("ShopItem", itemData.item)
		display.Parent = shopModel

		local displayPrompt = display:FindFirstChild("ShopItemPrompt") or Instance.new("ProximityPrompt")
		displayPrompt.Name = "ShopItemPrompt"
		displayPrompt.ActionText = itemData.label
		displayPrompt.ObjectText = "3D 商品展示"
		displayPrompt.KeyboardKeyCode = Enum.KeyCode.E
		displayPrompt.HoldDuration = 0
		displayPrompt.MaxActivationDistance = 10
		displayPrompt.RequiresLineOfSight = false
		displayPrompt.Parent = display

		local priceTag = display:FindFirstChild("PriceTag") or Instance.new("BillboardGui")
		priceTag.Name = "PriceTag"
		priceTag.Size = UDim2.fromOffset(120, 36)
		priceTag.StudsOffset = Vector3.new(0, 2.5, 0)
		priceTag.AlwaysOnTop = true
		priceTag.Parent = display

		local label = priceTag:FindFirstChild("Label") or Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 0.25
		label.BackgroundColor3 = Color3.fromRGB(45, 30, 18)
		label.TextColor3 = Color3.fromRGB(255, 235, 190)
		label.TextScaled = true
		label.Text = itemData.label
		label.Parent = priceTag
	end
end
createShopWorld()

-- 一鍵回城
teleportEvent.OnServerEvent:Connect(function(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(SHOP_POSITION + Vector3.new(0, 7, 0))
	end
end)

-- 炸彈爆炸邏輯
local function triggerExplosion(player, centerPos)
	local lstats = player:FindFirstChild("leaderstats")
	local maxSandVal = player:FindFirstChild("MaxSand")
	if not lstats or not maxSandVal then
		return
	end

	local cx = math.floor((centerPos.X + BLOCK_SIZE / 2) / BLOCK_SIZE)
	local cy = math.floor((centerPos.Y + BLOCK_SIZE / 2) / BLOCK_SIZE)
	local cz = math.floor((centerPos.Z + BLOCK_SIZE / 2) / BLOCK_SIZE)

	local earnedSand = 0
	local earnedCoins = 0

	for x = -1, 1 do
		for y = -1, 1 do
			for z = -1, 1 do
				local bx, by, bz = cx + x, cy + y, cz + z
				local key = bx .. "_" .. by .. "_" .. bz
				local blockType = worldData[key]

				if blockType then
					worldData[key] = false
					if spawnedParts[key] then
						spawnedParts[key]:Destroy()
						spawnedParts[key] = nil
					end
					blockHealthData[key] = nil
					if blockType == 1 then
						earnedCoins += math.random(50, 200)
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
	end
	sendNotification(player, "炸彈爆炸", "成功轟炸！收集了 " .. earnedSand .. " 顆沙子。")
end

-- 商店交易後端
shopActionEvent.OnServerEvent:Connect(function(player, action, item)
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
		local price = TOOL_PRICES[item]
		if price and coins.Value >= price and giveTool(player, item) then
			coins.Value -= price
			currentPickaxe.Value = item
			sendNotification(player, "購買成功", "獲得 " .. item .. "！")
		else
			sendNotification(player, "交易失敗", "金幣不足，或已擁有該等級工具。")
		end
	elseif action == "BuyBomb" then
		local bombCount = player:FindFirstChild("BombCount")
		if coins.Value >= 50 and bombCount then
			coins.Value -= 50
			bombCount.Value += 1
			giveBombTool(player)
			sendNotification(player, "購買成功", "獲得一枚隨身炸彈！炸彈可重複購買。")
		else
			sendNotification(player, "交易失敗", "金幣不足。")
		end
	end
end)

-- ==================== 3. 核心大世界生成機制 ====================
local function getBlockData(bx, by, bz)
	if by > 0 or by < -MAX_DEPTH_BLOCKS then
		return false
	end

	-- 精準控制安全區，不生成方塊避免卡住商店。
	local realX = bx * BLOCK_SIZE
	local realZ = bz * BLOCK_SIZE
	if realX >= -20 and realX <= 20 and realZ >= -40 and realZ <= -10 and by >= -2 then
		return false
	end

	local key = bx .. "_" .. by .. "_" .. bz
	if worldData[key] == nil then
		worldData[key] = (math.random() < CHEST_CHANCE) and 1 or true
	end
	return worldData[key]
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

	local blockModel = Instance.new("Model")
	blockModel.Name = (blockType == 1) and "ChestBlock" or "SandBlock"
	blockModel.Parent = folder

	local part = Instance.new("Part")
	part.Name = "Block"
	part.Size = Vector3.new(BLOCK_SIZE, BLOCK_SIZE, BLOCK_SIZE)
	part.Position = Vector3.new(bx * BLOCK_SIZE, by * BLOCK_SIZE, bz * BLOCK_SIZE)
	part.Anchored = true
	part.Material = (blockType == 1) and Enum.Material.WoodPlanks or Enum.Material.Sand
	part.Parent = blockModel
	blockModel.PrimaryPart = part

	local depthPercent = math.clamp(math.abs(by) / MAX_DEPTH_BLOCKS, 0, 1)
	part.Color = (blockType == 1) and Color3.fromRGB(150, 100, 50)
		or Color3.fromRGB(240, 200, 140):Lerp(Color3.fromRGB(40, 30, 20), depthPercent)

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

-- ==================== 4. 統一處理挖掘事件 (不透過 ClickDetector) ====================
miningEvent.OnServerEvent:Connect(function(player, targetPart)
	if not targetPart or not targetPart:IsDescendantOf(folder) then
		return
	end

	local currentTool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	if currentTool and currentTool.Name == BOMB_TOOL_NAME then
		local bombCount = player:FindFirstChild("BombCount")
		if bombCount then
			bombCount.Value = math.max(0, bombCount.Value - 1)
		end
		currentTool:Destroy()
		local bVisual = Instance.new("Part")
		bVisual.Size = Vector3.new(2, 2, 2)
		bVisual.Position = targetPart.Position + Vector3.new(0, BLOCK_SIZE, 0)
		bVisual.Color = Color3.fromRGB(20, 20, 20)
		bVisual.Anchored = true
		bVisual.Parent = Workspace
		task.spawn(function()
			for _ = 1, 3 do
				bVisual.Transparency = 0.5
				task.wait(0.15)
				bVisual.Transparency = 0
				task.wait(0.15)
			end
			triggerExplosion(player, bVisual.Position)
			bVisual:Destroy()
		end)
		return
	end

	local lstats = player:FindFirstChild("leaderstats")
	local maxSand = player:FindFirstChild("MaxSand")
	local currentPickaxe = player:FindFirstChild("CurrentPickaxe")
	if not lstats or not maxSand or not currentPickaxe then
		return
	end

	if lstats.Sand.Value >= maxSand.Value and targetPart.Parent.Name ~= "ChestBlock" then
		sendNotification(player, "背包已滿", "請使用左側【一鍵回城】清空背包！")
		return
	end

	local bx = math.floor((targetPart.Position.X + BLOCK_SIZE / 2) / BLOCK_SIZE)
	local by = math.floor((targetPart.Position.Y + BLOCK_SIZE / 2) / BLOCK_SIZE)
	local bz = math.floor((targetPart.Position.Z + BLOCK_SIZE / 2) / BLOCK_SIZE)
	local key = bx .. "_" .. by .. "_" .. bz

	local blockType = worldData[key]
	if not blockType then
		return
	end

	local maxHealth = math.abs(by) + 10
	blockHealthData[key] = blockHealthData[key] or maxHealth

	local stateKey = player.UserId .. ":" .. key
	local now = os.clock()
	local previousTime = playerMiningState[stateKey] or (now - 0.2)
	local elapsed = math.clamp(now - previousTime, 0.05, 0.35)
	playerMiningState[stateKey] = now
	local power = TOOL_EFFICIENCY[currentPickaxe.Value] or TOOL_EFFICIENCY["拳頭"]
	blockHealthData[key] -= power * elapsed

	miningEvent:FireClient(player, targetPart, blockHealthData[key], maxHealth)

	if blockHealthData[key] <= 0 then
		worldData[key] = false
		blockHealthData[key] = nil
		if spawnedParts[key] then
			spawnedParts[key]:Destroy()
			spawnedParts[key] = nil
		end
		miningEvent:FireClient(player, targetPart, 0, maxHealth)

		if blockType == 1 then
			lstats.Coins.Value += math.random(50, 200)
			sendNotification(player, "發現寶藏", "砸開寶箱，獲得金幣！")
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
		task.wait(WORLD_REFRESH_SECONDS)
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

	local pBx = math.floor((root.Position.X + BLOCK_SIZE / 2) / BLOCK_SIZE)
	local pBy = math.floor((root.Position.Y + BLOCK_SIZE / 2) / BLOCK_SIZE)
	local pBz = math.floor((root.Position.Z + BLOCK_SIZE / 2) / BLOCK_SIZE)

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
