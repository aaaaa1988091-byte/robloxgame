local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local DataStoreService = game:GetService("DataStoreService")

local MiningShared = ReplicatedStorage:WaitForChild("MiningShared")
local MiningConfig = require(MiningShared:WaitForChild("Config"))
local MiningRemotes = require(MiningShared:WaitForChild("Remotes"))
local MiningCatalog = require(MiningShared:WaitForChild("Catalog"))
local MiningVisuals = require(MiningShared:WaitForChild("Visuals"))
local ModelFactory = require(MiningShared:WaitForChild("ModelFactory"))
local PlayerSchema = require(script.Parent:WaitForChild("MiningServer"):WaitForChild("PlayerSchema"))

-- ==================== 參數設定 ====================
local BLOCK_SIZE = MiningConfig.BlockSize
local CHUNK_RADIUS_XZ = MiningConfig.ChunkRadiusXZ
local CHUNK_RADIUS_Y = MiningConfig.ChunkRadiusY
local MAX_DEPTH_BLOCKS = MiningConfig.MaxDepthBlocks
local CHEST_CHANCE = MiningConfig.ChestChance
local PYRAMID_CHANCE = MiningConfig.PyramidChance
local STEEL_FLOOR_SIZE = MiningConfig.SteelFloorSize
local NOISE_SCALE = MiningConfig.NoiseScale
local HILL_HEIGHT_BLOCKS = MiningConfig.HillHeightBlocks
local CACTUS_CHANCE = MiningConfig.CactusChance
local DEADWOOD_CHANCE = MiningConfig.DeadwoodChance
local OASIS_CHANCE = MiningConfig.OasisChance
local TREE_CHANCE = MiningConfig.TreeChance
local CACTUS_HEIGHT_SCALE = MiningConfig.CactusHeightScale
local MINING_DEBRIS_COUNT = MiningConfig.MiningDebrisCount
local MAX_BACKPACK_CAPPED = MiningConfig.MaxBackpackCapped
local BACKPACK_UPGRADE_AMOUNT = MiningConfig.BackpackUpgradeAmount
local PET_MINE_RADIUS_BLOCKS = MiningConfig.PetMineRadiusBlocks
local PET_MINE_INTERVAL = MiningConfig.PetMineInterval
local WORLD_REFRESH_SECONDS = MiningConfig.WorldRefreshSeconds
local PLAYER_DATA_STORE = DataStoreService:GetDataStore("DynamicMiningWorldPlayerDataV2")

local SHOP_POSITION = MiningConfig.ShopPosition
local SHOP_PREVIEW_POSITION = MiningConfig.ShopPreviewPosition -- 高空本地預覽
local WORLD_SEED = math.random(1, 1000000)
local lastShopTeleportAt = {}
local activeBackpackModels = {}
local playerAbilityState = {}
local pendingAbilityDrafts = {}
local currentWeather = "Clear"
local BOMB_THROW_FLIGHT_TIME = MiningConfig.BombThrowFlightTime

-- 寶箱可維護設定：新增等級只要複製一列，調整 id / minDepth / weight / color / health / reward。
-- 視覺模型共用 ServerStorage.BOX，只依等級套用不同顏色。
local CHEST_LEVELS = MiningConfig.ChestLevels

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

-- 建立與獲取網路事件：所有 Remote 名稱集中在 ReplicatedStorage.MiningShared.Remotes。
local miningRemotes = MiningRemotes.ensureAll()
local sendNotificationEvent = miningRemotes.SendNotification
local teleportEvent = miningRemotes.TeleportToShop
local shopActionEvent = miningRemotes.ShopAction
local miningEvent = miningRemotes.MiningEvent
local rewardEmojiEvent = miningRemotes.RewardEmojiEvent
local abilityDraftEvent = miningRemotes.AbilityDraftEvent
local weatherEvent = miningRemotes.WeatherEvent
local potionActionEvent = miningRemotes.PotionActionEvent
local questActionEvent = miningRemotes.QuestActionEvent
local questStateFunction = miningRemotes.GetQuestState
local shopCatalogFunction = miningRemotes.GetShopCatalog
local shopStateFunction = miningRemotes.GetShopState

local nextWorldRefreshTimeValue = ReplicatedStorage:FindFirstChild("NextWorldRefreshTime") or Instance.new("IntValue")
nextWorldRefreshTimeValue.Name = "NextWorldRefreshTime"
nextWorldRefreshTimeValue.Value = os.time() + WORLD_REFRESH_SECONDS
nextWorldRefreshTimeValue.Parent = ReplicatedStorage

local function sendNotification(player, title, text)
	sendNotificationEvent:FireClient(player, title, text)
end

local DAILY_QUEST_DEFINITIONS = {
	Cactus = { displayName = "挖掘仙人掌", targetMin = 10, targetMax = 20, rewardPotion = "Strength", rewardName = "力量藥水" },
	Tree = { displayName = "挖掘樹木", targetMin = 10, targetMax = 20, rewardPotion = "Speed", rewardName = "速度藥水" },
}

local function getOrCreateDailyQuests(player)
	local quests = player:FindFirstChild("DailyQuests") or Instance.new("Folder")
	quests.Name = "DailyQuests"
	quests.Parent = player
	for questId, definition in pairs(DAILY_QUEST_DEFINITIONS) do
		local questFolder = quests:FindFirstChild(questId) or Instance.new("Folder")
		questFolder.Name = questId
		questFolder.Parent = quests
		local progress = questFolder:FindFirstChild("Progress") or Instance.new("IntValue")
		progress.Name = "Progress"
		progress.Parent = questFolder
		local target = questFolder:FindFirstChild("Target") or Instance.new("IntValue")
		target.Name = "Target"
		target.Parent = questFolder
		if target.Value <= 0 then target.Value = math.random(definition.targetMin, definition.targetMax) end
		local claimed = questFolder:FindFirstChild("Claimed") or Instance.new("BoolValue")
		claimed.Name = "Claimed"
		claimed.Parent = questFolder
	end
	return quests
end

local function serializeQuestState(player)
	local quests = getOrCreateDailyQuests(player)
	local result = {}
	for questId, definition in pairs(DAILY_QUEST_DEFINITIONS) do
		local questFolder = quests:FindFirstChild(questId)
		local progress = questFolder and questFolder:FindFirstChild("Progress")
		local target = questFolder and questFolder:FindFirstChild("Target")
		local claimed = questFolder and questFolder:FindFirstChild("Claimed")
		table.insert(result, {
			id = questId,
			displayName = definition.displayName,
			progress = progress and progress.Value or 0,
			target = target and target.Value or definition.targetMax,
			claimed = claimed and claimed.Value or false,
			rewardPotion = definition.rewardPotion,
			rewardName = definition.rewardName,
		})
	end
	return result
end

local function addPotionCount(player, potionName, amount)
	local potions = player:FindFirstChild("Potions")
	local count = potions and potions:FindFirstChild(potionName)
	if count then count.Value += amount end
end

local function recordQuestProgress(player, questId, amount)
	local definition = DAILY_QUEST_DEFINITIONS[questId]
	if not definition then return end
	local quests = getOrCreateDailyQuests(player)
	local questFolder = quests:FindFirstChild(questId)
	local progress = questFolder and questFolder:FindFirstChild("Progress")
	local target = questFolder and questFolder:FindFirstChild("Target")
	local claimed = questFolder and questFolder:FindFirstChild("Claimed")
	if progress and target and claimed and not claimed.Value then
		progress.Value = math.clamp(progress.Value + (amount or 1), 0, target.Value)
		if progress.Value >= target.Value then
			sendNotification(player, "任務完成", definition.displayName .. " 可領取 " .. definition.rewardName .. "。")
		end
	end
end

local function recordPropQuestProgress(player, blockModel)
	if not blockModel then return end
	if blockModel:FindFirstChild("Cactus", true) then
		recordQuestProgress(player, "Cactus", 1)
	end
	if blockModel:FindFirstChild("Tree", true) or blockModel:FindFirstChild("Leaves", true) then
		recordQuestProgress(player, "Tree", 1)
	end
end

-- ==================== 1. 玩家數據與工具系統 ====================
local TOOL_EFFICIENCY = MiningConfig.ToolEfficiency
local TOOL_AUTO_MINE = MiningConfig.ToolAutoMine

local PICKAXE_NAMES = MiningConfig.PickaxeNames
local BOMB_TOOL_NAME = MiningConfig.BombToolName
local CLUSTER_BOMB_TOOL_NAME = MiningConfig.ClusterBombToolName

local playerMiningState = {}
local activePetModels = {}
local activePetLoops = {}
local ensureSandPet = function() end
local offerAbilityDraft = function() end

local function teleportPlayerToSteel(player)
	local now = os.clock()
	if lastShopTeleportAt[player] and now - lastShopTeleportAt[player] < 2.5 then
		return
	end
	lastShopTeleportAt[player] = now
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		local deck = Workspace:FindFirstChild("WoodDeck", true)
		root.CFrame = CFrame.new((deck and deck.Position or getWorldOrigin()) + Vector3.new(0, 3, 0))
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
local WORLD_ASSET_FOLDER_NAME = "MiningWorldEditableModels"
local SOUND_FOLDER_NAME = "MiningConfigurableSounds"
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


local ORE_LEVELS = MiningConfig.OreLevels

local function getWorldAssetFolder()
	local assets = ServerStorage:FindFirstChild(WORLD_ASSET_FOLDER_NAME) or Instance.new("Folder")
	assets.Name = WORLD_ASSET_FOLDER_NAME
	assets.Parent = ServerStorage
	for _, name in ipairs({ "Tree", "Cactus", "Deadwood", "Pyramid", "Backpack" }) do
		if not assets:FindFirstChild(name) then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = assets
		end
	end
	return assets
end

local function getSoundFolder()
	local folder = ServerStorage:FindFirstChild(SOUND_FOLDER_NAME) or Instance.new("Folder")
	folder.Name = SOUND_FOLDER_NAME
	folder.Parent = ServerStorage
	local defaults = {
		MiningImpactSound = "rbxassetid://12221976", MoneySound = "rbxassetid://12222124", ChestMineSound = "rbxassetid://12221967",
		LightningSound = "rbxassetid://9113420775", BombSound = "rbxassetid://138186576", PurchaseSound = "rbxassetid://12222253", ClaimSound = "rbxassetid://12222253",
	}
	for name, soundId in pairs(defaults) do
		if not folder:FindFirstChild(name) then
			local sound = Instance.new("Sound")
			sound.Name = name
			sound.SoundId = soundId
			sound.Volume = 0.35
			sound.RollOffMaxDistance = 60
			sound.Parent = folder
		end
	end
	return folder
end

local function playConfiguredSound(name, parent)
	local template = getSoundFolder():FindFirstChild(name)
	if template and template:IsA("Sound") and parent then
		local sound = template:Clone()
		sound.Parent = parent
		sound:Play()
		sound.Ended:Connect(function() sound:Destroy() end)
	end
end

local function getItemStorageFolder()
	local folder = ServerStorage:FindFirstChild(ITEM_STORAGE_FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = ITEM_STORAGE_FOLDER_NAME
		folder.Parent = ServerStorage
	end
	return folder
end

local function getConfigValue(container, name, fallback)
	local child = container:FindFirstChild(name)
	if child and child:IsA("ValueBase") then
		return child.Value
	end
	local attribute = container:GetAttribute(name)
	if attribute ~= nil then
		return attribute
	end
	return fallback
end

local function readCatalogItemFromStorage(child)
	if child:GetAttribute("ShopItem") == false or (DEFAULT_CATALOG_IDS[child.Name] and not child:GetAttribute("ShopItem")) then
		return nil
	end
	local itemId = getConfigValue(child, "Id", child.Name)
	local previewMaterialName = getConfigValue(child, "PreviewMaterial", "Sand")
	return {
		id = itemId,
		name = getConfigValue(child, "DisplayName", child.Name),
		description = getConfigValue(child, "Description", "在 LocalShopPreviewModels 或 ServerStorage.MiningItemModels 依格式新增的商品。"),
		action = getConfigValue(child, "Action", "BuyTool"),
		item = getConfigValue(child, "Item", child.Name),
		price = getConfigValue(child, "Price", 0),
		sourceName = child.Name,
		model = {
			kind = getConfigValue(child, "PreviewKind", "stored"),
			color = getConfigValue(child, "PreviewColor", Color3.fromRGB(235, 205, 130)),
			material = Enum.Material[previewMaterialName] or Enum.Material.Sand,
		},
	}
end

local SHOP_CATALOG = MiningCatalog.getShopCatalog()
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

local function findCatalogSourceModel(catalogItem)
	if not catalogItem or not catalogItem.sourceName then
		return nil
	end
	local localFolder = Workspace:FindFirstChild("LocalShopPreviewModels")
	return getItemStorageFolder():FindFirstChild(catalogItem.sourceName) or (localFolder and localFolder:FindFirstChild(catalogItem.sourceName))
end

function getRuntimeShopCatalog()
	local catalog = table.clone(SHOP_CATALOG)
	for _, sourceFolder in ipairs({ getItemStorageFolder(), Workspace:FindFirstChild("LocalShopPreviewModels") }) do
		if sourceFolder then
			for _, child in ipairs(sourceFolder:GetChildren()) do
				local storageItem = readCatalogItemFromStorage(child)
				if storageItem then
					table.insert(catalog, storageItem)
				end
			end
		end
	end
	return catalog
end


shopStateFunction.OnServerInvoke = function(player)
	local owned = {}
	local ownedTools = getOwnedToolsFolder(player)
	for _, child in ipairs(ownedTools:GetChildren()) do
		owned[child.Name] = true
	end
	return {
		ownedTools = owned,
		currentPickaxe = (player:FindFirstChild("CurrentPickaxe") and player.CurrentPickaxe.Value) or "拳頭",
		maxSand = (player:FindFirstChild("MaxSand") and player.MaxSand.Value) or MAX_BACKPACK_CAPPED,
	}
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
			sourceName = catalogItem.sourceName,
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
	local catalogItem = nil
	for _, candidate in ipairs(getRuntimeShopCatalog()) do
		if candidate.item == toolName then
			catalogItem = candidate
			break
		end
	end
	tool:SetAttribute("Strength", TOOL_EFFICIENCY[toolName] or (catalogItem and tonumber(catalogItem.price) and math.max(1, math.floor(catalogItem.price / 20))) or 1)
	tool:SetAttribute("AutoMine", TOOL_AUTO_MINE[toolName] == true)

	local sourceModel = findCatalogSourceModel(catalogItem)
	local sourcePart = sourceModel and (sourceModel:IsA("BasePart") and sourceModel or sourceModel:FindFirstChildWhichIsA("BasePart", true))
	if toolName == "拳頭" then
		tool.RequiresHandle = false
	elseif sourcePart then
		tool.RequiresHandle = true
		local handle = sourcePart:Clone()
		handle.Name = "Handle"
		handle.Anchored = false
		handle.CanCollide = false
		handle.Parent = tool
	else
		tool.RequiresHandle = true
		local handle = ModelFactory.createToolFallback(toolName, TOOL_AUTO_MINE[toolName] == true)
		handle.Parent = tool
	end

	tool.Parent = backpack
	local clone = tool:Clone()
	clone.Parent = starterGear
	rememberTool(player, toolName)
	return true
end

local function removePickaxeTools(player)
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character, player:FindFirstChild("StarterGear") }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and (child.Name == "拳頭" or table.find(PICKAXE_NAMES, child.Name)) then
					child:Destroy()
				end
			end
		end
	end
end

local function equipMiningTool(player, toolName)
	local ownedTools = getOwnedToolsFolder(player)
	if toolName ~= "拳頭" and not ownedTools:FindFirstChild(toolName) then
		return false
	end
	removePickaxeTools(player)
	giveTool(player, toolName)
	local currentPickaxe = player:FindFirstChild("CurrentPickaxe")
	if currentPickaxe then
		currentPickaxe.Value = toolName
	end
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
		local handle = ModelFactory.createBombHandle(radius)
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
	local currentPickaxe = player:FindFirstChild("CurrentPickaxe")
	local wantedTool = currentPickaxe and currentPickaxe.Value or "拳頭"
	if wantedTool ~= "拳頭" and not getOwnedToolsFolder(player):FindFirstChild(wantedTool) then
		wantedTool = "拳頭"
	end
	equipMiningTool(player, wantedTool)
	refreshBombTools(player)
end

local updateBackpackModel = function() end

Players.PlayerAdded:Connect(function(player)
	local playerValues = PlayerSchema.ensure(player, { MaxSand = MAX_BACKPACK_CAPPED })
	local leaderstats = playerValues.leaderstats
	local money = playerValues.Coins
	local totalBlocks = playerValues.TotalBlocks
	local sandCount = playerValues.Sand
	local maxSand = playerValues.MaxSand
	local currentPickaxe = playerValues.CurrentPickaxe
	local bombCount = playerValues.BombCount
	local clusterBombCount = playerValues.ClusterBombCount
	local hasSandPet = playerValues.HasSandPet
	local potions = playerValues.Potions
	local dailyQuests = getOrCreateDailyQuests(player)

	local ownedTools = getOwnedToolsFolder(player)
	local success, savedData = pcall(function()
		return PLAYER_DATA_STORE:GetAsync(player.UserId)
	end)
	if success and type(savedData) == "table" then
		money.Value = tonumber(savedData.Coins) or 0
		totalBlocks.Value = tonumber(savedData.TotalBlocks) or 0
		currentPickaxe.Value = savedData.CurrentPickaxe or "拳頭"
		bombCount.Value = tonumber(savedData.BombCount) or 0
		clusterBombCount.Value = tonumber(savedData.ClusterBombCount) or 0
		maxSand.Value = tonumber(savedData.MaxSand) or MAX_BACKPACK_CAPPED
		hasSandPet.Value = savedData.HasSandPet == true
		if type(savedData.Potions) == "table" then
			for potionName, count in pairs(savedData.Potions) do
				if potions:FindFirstChild(potionName) then potions[potionName].Value = tonumber(count) or 0 end
			end
		end
		if type(savedData.DailyQuests) == "table" then
			for questId, data in pairs(savedData.DailyQuests) do
				local questFolder = dailyQuests:FindFirstChild(questId)
				if questFolder then
					questFolder.Progress.Value = tonumber(data.Progress) or 0
					questFolder.Target.Value = tonumber(data.Target) or questFolder.Target.Value
					questFolder.Claimed.Value = data.Claimed == true
				end
			end
		end
		for _, toolName in ipairs(savedData.OwnedTools or {}) do
			rememberTool(player, toolName)
		end
	elseif not success then
		sendNotification(player, "資料讀取失敗", "暫時使用本局資料，離線前會再嘗試保存。")
	end

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		giveStoredWeapons(player)
		ensureSandPet(player)
		teleportPlayerToSteel(player)
		updateBackpackModel(player)
	end)
	hasSandPet.Changed:Connect(function()
		ensureSandPet(player)
	end)
	task.delay(8, function()
		offerAbilityDraft(player, "Join")
	end)
end)


function updateBackpackModel(player)
	local character = player.Character
	local torso = character and (character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso"))
	if not character or not torso then
		return
	end
	if activeBackpackModels[player] then
		activeBackpackModels[player]:Destroy()
		activeBackpackModels[player] = nil
	end
	local maxSand = player:FindFirstChild("MaxSand")
	local capacity = maxSand and maxSand.Value or MAX_BACKPACK_CAPPED
	local templateFolder = getWorldAssetFolder():FindFirstChild("Backpack")
	local template = templateFolder and templateFolder:FindFirstChild(tostring(capacity)) or (templateFolder and templateFolder:FindFirstChild("Default"))
	local model = template and template:Clone() or Instance.new("Model")
	model.Name = player.Name .. "_EquippedBackpack"
	local mainPart = model:IsA("BasePart") and model or model:FindFirstChildWhichIsA("BasePart", true)
	if model:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		model.Parent = wrapper
		model = wrapper
	end
	if not mainPart then
		mainPart = Instance.new("Part")
		mainPart.Name = "BackpackBody"
		mainPart.Size = Vector3.new(1.8, 2.4, 0.75)
		mainPart.Material = Enum.Material.Fabric
		mainPart.Color = Color3.fromRGB(70 + capacity % 120, 120, 200)
		mainPart.Parent = model
	end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
		end
	end
	model.PrimaryPart = mainPart
	model.Parent = character
	mainPart.CFrame = torso.CFrame * CFrame.new(0, 0, 0.85)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = mainPart
	weld.Parent = mainPart
	activeBackpackModels[player] = model
end

local function savePlayerData(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	local currentPickaxe = player:FindFirstChild("CurrentPickaxe")
	local bombCount = player:FindFirstChild("BombCount")
	local clusterBombCount = player:FindFirstChild("ClusterBombCount")
	local ownedTools = player:FindFirstChild("OwnedTools")
	local maxSand = player:FindFirstChild("MaxSand")
	local hasSandPet = player:FindFirstChild("HasSandPet")
	local potions = player:FindFirstChild("Potions")
	local dailyQuests = player:FindFirstChild("DailyQuests")
	if not leaderstats or not currentPickaxe or not bombCount or not clusterBombCount or not ownedTools or not maxSand or not hasSandPet then
		return
	end
	local toolList = {}
	for _, value in ipairs(ownedTools:GetChildren()) do
		table.insert(toolList, value.Name)
	end
	local questSave = {}
	if dailyQuests then
		for _, questFolder in ipairs(dailyQuests:GetChildren()) do
			questSave[questFolder.Name] = {
				Progress = questFolder:FindFirstChild("Progress") and questFolder.Progress.Value or 0,
				Target = questFolder:FindFirstChild("Target") and questFolder.Target.Value or 0,
				Claimed = questFolder:FindFirstChild("Claimed") and questFolder.Claimed.Value or false,
			}
		end
	end
	pcall(function()
		PLAYER_DATA_STORE:SetAsync(player.UserId, {
			Coins = leaderstats.Coins.Value,
			TotalBlocks = (leaderstats:FindFirstChild("TotalBlocks") and leaderstats.TotalBlocks.Value) or 0,
			CurrentPickaxe = currentPickaxe.Value,
			BombCount = bombCount.Value,
			ClusterBombCount = clusterBombCount.Value,
			MaxSand = maxSand.Value,
			HasSandPet = hasSandPet.Value,
			Potions = potions and { Strength = potions.Strength.Value, Luck = potions.Luck.Value, Speed = potions.Speed.Value } or nil,
			DailyQuests = questSave,
			OwnedTools = toolList,
		})
	end)
end

Players.PlayerRemoving:Connect(function(player)
	savePlayerData(player)
	playerMiningState[player] = nil
	playerAbilityState[player] = nil
	pendingAbilityDrafts[player] = nil
	lastShopTeleportAt[player] = nil
	activePetLoops[player] = nil
	if activeBackpackModels[player] then
		activeBackpackModels[player]:Destroy()
		activeBackpackModels[player] = nil
	end
	if activePetModels[player] then
		activePetModels[player]:Destroy()
		activePetModels[player] = nil
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		savePlayerData(player)
	end
end)


local function createCatalogModel(parent, itemData, pivotCFrame)
	return ModelFactory.createCatalogModel(parent, itemData, pivotCFrame, {
		sourceInstance = findCatalogSourceModel(itemData),
	})
end


-- GUI 現在由 StarterGui.MiningHud 底下的 LocalScript 自行維護；
-- 伺服器不再每次啟動重建介面，方便直接複製 MiningHud 後獨立使用。

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
		ModelFactory.applyStyle(secureFloor, MiningVisuals.Shop.SecureFloor)
		secureFloor.Anchored = true
		secureFloor.CanCollide = true
	end)

	createPartIfMissing("WoodDeck", function(deck)
		deck.Size = Vector3.new(18, 0.4, 16)
		deck.Position = SHOP_POSITION + Vector3.new(0, 0.2, -2)
		ModelFactory.applyStyle(deck, MiningVisuals.Shop.WoodDeck)
		deck.Anchored = true
	end)

	createPartIfMissing("CanvasCanopy", function(roof)
		roof.Size = Vector3.new(22, 0.6, 18)
		roof.Position = SHOP_POSITION + Vector3.new(0, 8, -2)
		ModelFactory.applyStyle(roof, MiningVisuals.Shop.CanvasCanopy)
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
			ModelFactory.applyStyle(post, MiningVisuals.Shop.ShedPost)
			post.Anchored = true
		end)
	end

	createPartIfMissing("ShopOpenZone", function(shopZone)
		shopZone.Shape = Enum.PartType.Cylinder
		shopZone.Size = Vector3.new(0.25, 18, 18)
		shopZone.CFrame = CFrame.new(SHOP_POSITION + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ModelFactory.applyStyle(shopZone, MiningVisuals.Shop.ShopOpenZone)
		shopZone.Transparency = 0.55
		shopZone.Anchored = true
		shopZone.CanCollide = false
		shopZone.CanTouch = true
	end)

	createPartIfMissing("ShopCounter", function(shopCounter)
		shopCounter.Size = Vector3.new(8, 3, 2)
		shopCounter.Position = SHOP_POSITION + Vector3.new(0, 1.5, -7)
		ModelFactory.applyStyle(shopCounter, MiningVisuals.Shop.ShopCounter)
		shopCounter.Anchored = true
	end)

	createPartIfMissing("ShopSign", function(sign)
		sign.Size = Vector3.new(10, 2, 0.4)
		sign.Position = SHOP_POSITION + Vector3.new(0, 6, -7.3)
		ModelFactory.applyStyle(sign, MiningVisuals.Shop.ShopSign)
		sign.Anchored = true
	end)

	createPartIfMissing("ShopPreviewBase", function(previewBase)
		previewBase.Size = Vector3.new(10, 0.5, 10)
		previewBase.Position = SHOP_PREVIEW_POSITION + Vector3.new(0, 0.25, 0)
		ModelFactory.applyStyle(previewBase, MiningVisuals.Shop.ShopPreviewBase)
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

	for _, child in ipairs(previewFolder:GetChildren()) do
		if child:GetAttribute("GeneratedShopPreview") then
			child:Destroy()
		end
	end
	for index, catalogItem in ipairs(getRuntimeShopCatalog()) do
		local itemStand = Instance.new("Model")
		itemStand.Name = string.format("%02d_%s_PhysicalShopItem", index, catalogItem.id)
		itemStand:SetAttribute("GeneratedShopPreview", true)
		itemStand.Parent = previewFolder
		local offsetX = (index - 1) * 5.5 - 10
		local base = Instance.new("Part")
		base.Name = "ItemBackground"
		base.Size = Vector3.new(4.8, 0.35, 3.8)
		base.Position = SHOP_POSITION + Vector3.new(offsetX, 1.15, -11.5)
		ModelFactory.applyStyle(base, MiningVisuals.Shop.ItemStand)
		base.Anchored = true
		base.Parent = itemStand
		createCatalogModel(itemStand, catalogItem, CFrame.new(base.Position + Vector3.new(0, 2.2, 0)))
	end

	getWorldAssetFolder()
	getSoundFolder()

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
task.spawn(function()
	while true do
		task.wait(5)
		createShopWorld()
	end
end)

-- 一鍵回城
teleportEvent.OnServerEvent:Connect(function(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		local deck = Workspace:FindFirstChild("WoodDeck", true)
		root.CFrame = CFrame.new((deck and deck.Position or getWorldOrigin()) + Vector3.new(0, 3, 0))
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

local function makeSandPetModel(player)
	local model = Instance.new("Model")
	model.Name = player.Name .. "_SandPet"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(1.4, 0.9, 1.8)
	body.Material = Enum.Material.SmoothPlastic
	body.Color = Color3.fromRGB(210, 170, 75)
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model
	model.PrimaryPart = body

	local eye = Instance.new("Part")
	eye.Name = "Eye"
	eye.Shape = Enum.PartType.Ball
	eye.Size = Vector3.new(0.18, 0.18, 0.18)
	eye.Material = Enum.Material.Neon
	eye.Color = Color3.fromRGB(30, 25, 15)
	eye.Anchored = true
	eye.CanCollide = false
	eye.Parent = model

	model.Parent = Workspace
	return model
end

local function petEatNearbySand(player)
	local hasSandPet = player:FindFirstChild("HasSandPet")
	local leaderstats = player:FindFirstChild("leaderstats")
	local maxSand = player:FindFirstChild("MaxSand")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not hasSandPet or not hasSandPet.Value or not leaderstats or not maxSand or not root then
		return
	end
	local sand = leaderstats:FindFirstChild("Sand")
	if not sand or sand.Value >= maxSand.Value then
		return
	end

	local centerX, centerY, centerZ = blockFromWorld(root.Position)
	for radius = 0, PET_MINE_RADIUS_BLOCKS do
		for x = -radius, radius do
			for y = -1, 1 do
				for z = -radius, radius do
					local bx, by, bz = centerX + x, centerY + y, centerZ + z
					local key = bx .. "_" .. by .. "_" .. bz
					local blockType = worldData[key]
					if blockType and not isChestBlock(blockType) then
						worldData[key] = false
						blockHealthData[key] = nil
						if spawnedParts[key] then
							releaseCactus(spawnedParts[key])
							spawnedParts[key]:Destroy()
							spawnedParts[key] = nil
						end
						sand.Value = math.clamp(sand.Value + 1, 0, maxSand.Value)
						if revealNeighbors then
							revealNeighbors(bx, by, bz)
						end
						return
					end
				end
			end
		end
	end
end

function ensureSandPet(player)
	local hasSandPet = player:FindFirstChild("HasSandPet")
	if not hasSandPet or not hasSandPet.Value then
		if activePetModels[player] then
			activePetModels[player]:Destroy()
			activePetModels[player] = nil
		end
		return
	end
	if not activePetModels[player] or not activePetModels[player].Parent then
		activePetModels[player] = makeSandPetModel(player)
	end
	if activePetLoops[player] then
		return
	end
	activePetLoops[player] = true
	task.spawn(function()
		while player.Parent and activePetLoops[player] do
			local model = activePetModels[player]
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if model and model.PrimaryPart and root then
				local target = root.CFrame * CFrame.new(2.8, -1.6, 2.4)
				model:PivotTo(model:GetPivot():Lerp(target, 0.18))
				local eye = model:FindFirstChild("Eye")
				if eye then
					eye.CFrame = model.PrimaryPart.CFrame * CFrame.new(0, 0.18, -0.72)
				end
			end
			task.wait(0.15)
		end
	end)
	task.spawn(function()
		while player.Parent and activePetLoops[player] do
			task.wait(PET_MINE_INTERVAL)
			petEatNearbySand(player)
		end
	end)
end

local releaseCactus
local revealNeighbors

-- 炸彈爆炸邏輯
local function triggerExplosion(player, centerPos, radius)
	radius = radius or 1
	local lstats = player:FindFirstChild("leaderstats")
	local maxSandVal = player:FindFirstChild("MaxSand")
	if not lstats or not maxSandVal then
		return
	end
	if lstats.Sand.Value >= maxSandVal.Value then
		sendNotification(player, "背包已滿", "背包滿後不能再丟炸彈，請先回商店出售。")
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
						recordPropQuestProgress(player, spawnedParts[key])
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
		if lstats:FindFirstChild("TotalBlocks") then lstats.TotalBlocks.Value += earnedSand end
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
		local ownedTools = getOwnedToolsFolder(player)
		local ownsTool = item == "拳頭" or ownedTools:FindFirstChild(item) ~= nil
		local price = catalogPrice or TOOL_PRICES[item]
		if ownsTool then
			if equipMiningTool(player, item) then
				sendNotification(player, "裝備成功", "已裝備 " .. item .. "。")
			end
		elseif price and coins.Value >= price then
			coins.Value -= price
			rememberTool(player, item)
			equipMiningTool(player, item)
			sendNotification(player, "購買成功", "已購買並裝備 " .. item .. "！")
		else
			sendNotification(player, "交易失敗", "金幣不足。")
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
	elseif action == "BuyBackpack" or action == "BuyBackpackUpgrade" then
		local price = catalogPrice or 300
		local capacity = (action == "BuyBackpack") and (tonumber(item) or MAX_BACKPACK_CAPPED) or ((player:FindFirstChild("MaxSand") and player.MaxSand.Value or MAX_BACKPACK_CAPPED) + (tonumber(item) or BACKPACK_UPGRADE_AMOUNT))
		local maxSand = player:FindFirstChild("MaxSand")
		if not maxSand then
			return
		end
		if maxSand.Value >= capacity then
			sendNotification(player, "已擁有背包", "目前背包容量已經不小於這個背包。")
		elseif coins.Value >= price then
			coins.Value -= price
			maxSand.Value = capacity
			updateBackpackModel(player)
			sendNotification(player, "購買成功", "背包容量變為 " .. capacity .. "！")
		else
			sendNotification(player, "交易失敗", "金幣不足。")
		end
	elseif action == "BuyPet" then
		local price = catalogPrice or 2500
		local hasSandPet = player:FindFirstChild("HasSandPet")
		if not hasSandPet then
			return
		end
		if hasSandPet.Value then
			sendNotification(player, "已擁有寵物", "沙漠小蜥蜴已經跟著你了。")
		elseif coins.Value >= price then
			coins.Value -= price
			hasSandPet.Value = true
			ensureSandPet(player)
			sendNotification(player, "購買成功", "沙漠小蜥蜴會慢慢吃掉附近沙子。")
		else
			sendNotification(player, "交易失敗", "金幣不足。")
		end
	end
end)

-- ==================== 3. 核心大世界生成機制 ====================
local function getSurfaceHeight(bx, bz)
	local broad = math.noise(bx * NOISE_SCALE, bz * NOISE_SCALE, WORLD_SEED) * HILL_HEIGHT_BLOCKS
	local detail = math.noise(bx * NOISE_SCALE * 2.7, bz * NOISE_SCALE * 2.7, WORLD_SEED + 31) * 1.5
	return math.max(0, math.floor(broad + detail))
end

local function getDistanceDifficulty(bx, bz)
	return math.clamp(Vector2.new(bx, bz).Magnitude / 120, 0, 1)
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

local getSurfaceBiome
local shouldSpawnTree

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
		local distanceDifficulty = getDistanceDifficulty(bx, bz)
		local surfaceHeight = getSurfaceHeight(bx, bz)
		if by == surfaceHeight and math.random() < PYRAMID_CHANCE * (0.35 + distanceDifficulty) then
			worldData[key] = { kind = "Pyramid", guardian = true }
		elseif by <= 0 and math.random() < CHEST_CHANCE * (1 + distanceDifficulty * 2.2) then
			local level = getChestLevelForDepth(depth + math.floor(distanceDifficulty * 160))
			worldData[key] = { kind = "Chest", level = level.id }
		else
			local underGrassTree = by == surfaceHeight - 1 and getSurfaceBiome(bx, bz) == "grass" and shouldSpawnTree(bx, bz)
			if underGrassTree and math.random() < 0.14 then
				local level = getChestLevelForDepth(depth + 180)
				worldData[key] = { kind = "Chest", level = level.id }
				return worldData[key]
			end
			local oreData = nil
			for oreId, ore in pairs(ORE_LEVELS) do
				if depth >= ore.minDepth and math.random() < ore.chance then
					oreData = { kind = "Ore", ore = oreId }
					break
				end
			end
			worldData[key] = oreData or true
		end
	end
	return worldData[key]
end

getSurfaceBiome = function(bx, bz)
	local n = math.noise(bx * 0.055, bz * 0.055, WORLD_SEED + 117)
	local biomeName = "grass"
	if n < -0.42 then
		biomeName = "white_sand"
	elseif n < -0.08 then
		biomeName = "clay"
	elseif n < 0.32 then
		biomeName = "mud"
	elseif n < 0.58 then
		biomeName = "red_sand"
	end
	local biome = MiningVisuals.Biomes[biomeName] or MiningVisuals.Biomes.grass
	return biomeName, biome.color, biome.material
end


local function shouldSpawnCactus(bx, bz)
	local cactusNoise = math.noise(bx * 0.19, bz * 0.19, WORLD_SEED + 83)
	return cactusNoise > 0.38 and math.random() < CACTUS_CHANCE
end

local function shouldSpawnDeadwood(bx, bz)
	return math.noise(bx * 0.13, bz * 0.13, WORLD_SEED + 211) > 0.2 and math.random() < DEADWOOD_CHANCE
end

local function shouldSpawnOasis(bx, bz)
	return math.noise(bx * 0.045, bz * 0.045, WORLD_SEED + 377) > 0.55 and math.random() < OASIS_CHANCE
end

shouldSpawnTree = function(bx, bz)
	return math.noise(bx * 0.07, bz * 0.07, WORLD_SEED + 503) > 0.34 and math.random() < TREE_CHANCE
end

local function cloneEditableWorldModel(folderName, parent, pivotCFrame)
	local modelFolder = getWorldAssetFolder():FindFirstChild(folderName)
	local template = modelFolder and modelFolder:FindFirstChildWhichIsA("Model") or (modelFolder and modelFolder:FindFirstChildWhichIsA("BasePart"))
	if template then
		local clone = template:Clone()
		clone.Parent = parent
		if clone:IsA("Model") then
			local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
			if primary then clone.PrimaryPart = primary clone:PivotTo(pivotCFrame) end
		elseif clone:IsA("BasePart") then
			clone.CFrame = pivotCFrame
		end
		return clone
	end
	return nil
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
	local pyramid = type(blockType) == "table" and blockType.kind == "Pyramid"
	local ore = type(blockType) == "table" and blockType.kind == "Ore" and ORE_LEVELS[blockType.ore]
	local chestLevel = chest and getChestLevel(blockType.level) or nil
	local blockModel = Instance.new("Model")
	blockModel.Name = pyramid and "PyramidBlock" or (chest and "ChestBlock" or (ore and "OreBlock" or "SandBlock"))
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
		part.Material = (chest or pyramid) and Enum.Material.WoodPlanks or Enum.Material.Sand
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
	local isSurface = by == getSurfaceHeight(bx, bz)
	local biomeName = nil
	if pyramid then
		ModelFactory.applyStyle(part, MiningVisuals.Defaults.PyramidBlock)
	elseif ore then
		part.Material = ore.material
		part.Color = ore.color
	elseif not chest then
		local biomeColor, biomeMaterial
		biomeName, biomeColor, biomeMaterial = getSurfaceBiome(bx, bz)
		part.Material = isSurface and biomeMaterial or Enum.Material.Sand
		part.Color = biomeColor:Lerp(Color3.fromRGB(40, 30, 20), depthPercent)
	end

	if isSurface and shouldSpawnOasis(bx, bz) then
		local water = Instance.new("Part")
		water.Name = "OasisWater"
		water.Size = Vector3.new(BLOCK_SIZE * 0.9, 0.16, BLOCK_SIZE * 0.9)
		water.Position = part.Position + Vector3.new(0, BLOCK_SIZE / 2 + 0.09, 0)
		ModelFactory.applyStyle(water, MiningVisuals.Defaults.Water)
		water.Transparency = 0.25
		water.Anchored = true
		water.CanCollide = false
		water.Parent = blockModel
	end

	if isSurface and biomeName == "grass" and shouldSpawnTree(bx, bz) then
		local tree = cloneEditableWorldModel("Tree", blockModel, CFrame.new(part.Position + Vector3.new(0, BLOCK_SIZE / 2, 0)))
		if not tree then
			ModelFactory.createFallbackTree(blockModel, part.Position, BLOCK_SIZE)
		end
	end

	if isSurface and shouldSpawnDeadwood(bx, bz) then
		local editableDeadwood = cloneEditableWorldModel("Deadwood", blockModel, CFrame.new(part.Position + Vector3.new(0, BLOCK_SIZE / 2 + 0.3, 0)))
		if not editableDeadwood then
			ModelFactory.createFallbackDeadwood(blockModel, part.Position, BLOCK_SIZE)
		end
	end

	if isSurface and shouldSpawnCactus(bx, bz) then
		local editableCactus = cloneEditableWorldModel("Cactus", blockModel, CFrame.new(part.Position + Vector3.new(0, BLOCK_SIZE / 2, 0)))
		if editableCactus then
			spawnedParts[key] = blockModel
			return
		end
		local height = math.random(4, 7) * CACTUS_HEIGHT_SCALE
		ModelFactory.createFallbackCactus(blockModel, part.Position, BLOCK_SIZE, height)
	end

	spawnedParts[key] = blockModel
end

function revealNeighbors(bx, by, bz)
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
		local preStats = player:FindFirstChild("leaderstats")
		local preMaxSand = player:FindFirstChild("MaxSand")
		if preStats and preMaxSand and preStats.Sand.Value >= preMaxSand.Value then
			sendNotification(player, "背包已滿", "背包滿後不能再丟炸彈，請先回商店出售。")
			return
		end
		local bombCount = getBombCountValue(player, bombCountName)
		bombCount.Value = math.max(0, bombCount.Value - 1)
		local ability = playerAbilityState[player] or {}
		local bombRadius = (currentTool:GetAttribute("BombRadius") or 1) * (ability.BombMultiplier or 1)
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
			local casts = ability.NukeBombs or (ability.ScatterBomb and 3) or 1
			for cast = 1, casts do
				local offset = casts == 1 and Vector3.zero or Vector3.new(math.random(-12, 12), 0, math.random(-12, 12))
				triggerExplosion(player, targetPosition + offset, bombRadius)
			end
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
	local isScorched = type(blockType) == "table" and blockType.scorched == true
	local depthHardness = math.floor((math.abs(by) + 10) * (1 + getDistanceDifficulty(bx, bz) * 2.5))
	local maxHealth = isScorched and 1 or (chestLevel and chestLevel.health or ((type(blockType) == "table" and blockType.kind == "Pyramid") and 280 or depthHardness))
	blockHealthData[key] = blockHealthData[key] or maxHealth

	local stateKey = player.UserId .. ":" .. key
	local now = os.clock()
	local previousTime = playerMiningState[stateKey] or (now - 0.2)
	local elapsed = math.clamp(now - previousTime, 0.05, 0.35)
	playerMiningState[stateKey] = now
	local equippedTool = player.Character and player.Character:FindFirstChildOfClass("Tool")
	local ability = playerAbilityState[player] or {}
	local power = (equippedTool and equippedTool:GetAttribute("Strength")) or 1
	if ability.StrengthMultiplier then power *= ability.StrengthMultiplier end
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
	local soundTemplate = getSoundFolder():FindFirstChild(isChestBlock(blockType) and "ChestMineSound" or "MiningImpactSound")
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
			recordPropQuestProgress(player, spawnedParts[key])
			releaseCactus(spawnedParts[key])
			spawnedParts[key]:Destroy()
			spawnedParts[key] = nil
		end
		miningEvent:FireClient(player, targetPart, 0, maxHealth)

		if isChestBlock(blockType) then
			local level = getChestLevel(blockType.level)
			local reward = math.random(level.reward[1], level.reward[2])
			if blockType.rewardBoost then reward = math.floor(reward * blockType.rewardBoost) end
			if ability.LuckMoneyMultiplier then reward = math.floor(reward * ability.LuckMoneyMultiplier) end
			lstats.Coins.Value += reward
			rewardEmojiEvent:FireClient(player, level.emoji or "🪙", reward)
		elseif type(blockType) == "table" and blockType.kind == "Pyramid" then
			local reward = math.random(2500, 6500)
			lstats.Coins.Value += reward
			rewardEmojiEvent:FireClient(player, "🏺", reward)
		else
			local ore = type(blockType) == "table" and blockType.kind == "Ore" and ORE_LEVELS[blockType.ore]
			local gain = ore and ore.blocks or math.max(1, math.floor(depthHardness / 45) + 1)
			if ability.HardnessCoins then
				lstats.Coins.Value += depthHardness
				rewardEmojiEvent:FireClient(player, "🍀", depthHardness)
			end
			lstats.Sand.Value = math.clamp(lstats.Sand.Value + gain, 0, maxSand.Value)
			if lstats:FindFirstChild("TotalBlocks") then lstats.TotalBlocks.Value += gain end
		end

		revealNeighbors(bx, by, bz)
		if ability.RainbowBeam and math.random() < 0.18 then
			triggerExplosion(player, worldFromBlock(bx + math.random(-1,1), by, bz + math.random(-1,1)), 1)
		end
	end
end)

questStateFunction.OnServerInvoke = function(player)
	return serializeQuestState(player)
end

questActionEvent.OnServerEvent:Connect(function(player, action, questId)
	if action ~= "Claim" then return end
	local definition = DAILY_QUEST_DEFINITIONS[questId]
	local quests = getOrCreateDailyQuests(player)
	local questFolder = quests:FindFirstChild(questId)
	local progress = questFolder and questFolder:FindFirstChild("Progress")
	local target = questFolder and questFolder:FindFirstChild("Target")
	local claimed = questFolder and questFolder:FindFirstChild("Claimed")
	if not definition or not progress or not target or not claimed then return end
	if claimed.Value then
		sendNotification(player, "已領取", "這個每日任務獎勵已領取。")
	elseif progress.Value >= target.Value then
		claimed.Value = true
		addPotionCount(player, definition.rewardPotion, 1)
		sendNotification(player, "任務獎勵", "獲得 " .. definition.rewardName .. " * 1。")
	else
		sendNotification(player, "任務未完成", "進度不足，繼續探索礦區吧。")
	end
end)

local POTION_EFFECTS = {
	Strength = { displayName = "力量藥水", duration = 90, stat = "StrengthMultiplier", multiplier = 1.35 },
	Luck = { displayName = "幸運藥水", duration = 90, stat = "LuckMoneyMultiplier", multiplier = 1.5 },
	Speed = { displayName = "速度藥水", duration = 90, stat = "SpeedMultiplier", multiplier = 1.25 },
}

potionActionEvent.OnServerEvent:Connect(function(player, potionName)
	local effect = POTION_EFFECTS[potionName]
	local potions = player:FindFirstChild("Potions")
	local count = potions and potions:FindFirstChild(potionName)
	if not effect or not count or count.Value <= 0 then
		sendNotification(player, "藥水不足", "目前沒有可使用的藥水。")
		return
	end
	count.Value -= 1
	local state = playerAbilityState[player] or {}
	state[effect.stat] = (state[effect.stat] or 1) * effect.multiplier
	playerAbilityState[player] = state
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and state.SpeedMultiplier then humanoid.WalkSpeed = 16 * state.SpeedMultiplier end
	sendNotification(player, "藥水啟用", effect.displayName .. " 已生效 " .. effect.duration .. " 秒。")
	task.delay(effect.duration, function()
		if player.Parent then
			local currentState = playerAbilityState[player] or {}
			if type(currentState[effect.stat]) == "number" then
				currentState[effect.stat] = math.max(1, currentState[effect.stat] / effect.multiplier)
			end
			playerAbilityState[player] = currentState
			local resetHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if resetHumanoid and effect.stat == "SpeedMultiplier" then resetHumanoid.WalkSpeed = 16 * (currentState.SpeedMultiplier or 1) end
			sendNotification(player, "藥水結束", effect.displayName .. " 效果已結束。")
		end
	end)
end)

local ABILITY_EFFECTS = {
	["炸彈威力 +20%"] = { BombMultiplier = 1.2 }, ["力量 +20%"] = { StrengthMultiplier = 1.2 },
	["挖掘範圍 +15%"] = { RangeMultiplier = 1.15 }, ["走路速度 +10%"] = { SpeedMultiplier = 1.1 },
	["七彩霞光"] = { RainbowBeam = true }, ["散彈"] = { ScatterBomb = true }, ["雙手"] = { StrengthMultiplier = 2, RangeMultiplier = 2 },
	["運氣佳"] = { LuckMoneyMultiplier = 1.6, HardnessCoins = true }, ["專注"] = { Focus = true, StrengthMultiplier = 1.35 },
	["核彈"] = { BombMultiplier = 15, NukeBombs = 10 }, ["雷射"] = { Laser = true },
}

local ABILITY_CARD_POOL = {
	{ name = "炸彈威力 +20%", rarity = "green", weight = 46, description = "本輪炸彈爆炸範圍提高 20%。" },
	{ name = "力量 +20%", rarity = "green", weight = 46, description = "本輪挖掘力量提高 20%。" },
	{ name = "挖掘範圍 +15%", rarity = "blue", weight = 28, description = "提升範圍型效果，與炸彈/特殊能力相容。" },
	{ name = "走路速度 +10%", rarity = "blue", weight = 28, description = "本輪移動速度提高 10%。" },
	{ name = "七彩霞光", rarity = "purple", weight = 10, description = "破壞方塊時有機率觸發周圍小爆破。" },
	{ name = "散彈", rarity = "purple", weight = 10, description = "投擲炸彈後分裂為 3 次落點爆破。" },
	{ name = "雙手", rarity = "purple", weight = 10, description = "挖掘力量與範圍大幅提升。" },
	{ name = "運氣佳", rarity = "gold", weight = 3, description = "寶箱金錢提升，並可依硬度額外取得金幣。" },
	{ name = "專注", rarity = "gold", weight = 3, description = "提供穩定挖掘力量加成，適合長時間連挖。" },
	{ name = "核彈", rarity = "orange", weight = 1, description = "炸彈變成多次超大範圍爆破。" },
	{ name = "雷射", rarity = "orange", weight = 1, description = "保留為直線挖掘能力相容旗標。" },
}

local function rollAbilityCard(excluded)
	local totalWeight = 0
	for _, card in ipairs(ABILITY_CARD_POOL) do
		if not excluded[card.name] then totalWeight += card.weight end
	end
	local roll = math.random() * totalWeight
	for _, card in ipairs(ABILITY_CARD_POOL) do
		if not excluded[card.name] then
			roll -= card.weight
			if roll <= 0 then
				return card
			end
		end
	end
	return ABILITY_CARD_POOL[1]
end

function offerAbilityDraft(player, reason)
	if not player.Parent then return end
	local excluded = {}
	local choices = {}
	for _ = 1, 3 do
		local rolled = rollAbilityCard(excluded)
		excluded[rolled.name] = true
		table.insert(choices, { name = rolled.name, rarity = rolled.rarity, description = rolled.description })
	end
	pendingAbilityDrafts[player] = excluded
	abilityDraftEvent:FireClient(player, "Offer", choices, reason or "Timer")
end

abilityDraftEvent.OnServerEvent:Connect(function(player, action, abilityName)
	if action ~= "Select" then return end
	local pending = pendingAbilityDrafts[player]
	if not pending or not pending[abilityName] then
		sendNotification(player, "抽卡失效", "請等待下一次能力抽選。")
		return
	end
	pendingAbilityDrafts[player] = nil
	local effect = ABILITY_EFFECTS[abilityName]
	if not effect then return end
	local state = playerAbilityState[player] or {}
	for key, value in pairs(effect) do
		if type(value) == "number" and type(state[key]) == "number" then state[key] *= value else state[key] = value end
	end
	playerAbilityState[player] = state
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid and state.SpeedMultiplier then humanoid.WalkSpeed = 16 * state.SpeedMultiplier end
	sendNotification(player, "能力啟用", abilityName .. " 已加入本輪能力。")
end)

task.spawn(function()
	while true do
		task.wait(60)
		for _, player in ipairs(Players:GetPlayers()) do
			offerAbilityDraft(player, "Timer")
		end
	end
end)

local function scorchBlockAt(position)
	local bx, by, bz = blockFromWorld(position)
	for x=-1,1 do for z=-1,1 do
		local key = (bx+x).."_"..by.."_"..(bz+z)
		local data = getBlockData(bx+x, by, bz+z)
		if data then
			if type(data) == "table" then data.scorched = true; if data.kind == "Chest" then data.rewardBoost = 2 end else worldData[key] = { kind = "ScorchedSand", scorched = true } end
			if spawnedParts[key] and spawnedParts[key].PrimaryPart then spawnedParts[key].PrimaryPart.Color = Color3.fromRGB(18,18,18); spawnedParts[key].PrimaryPart.Material = Enum.Material.Slate end
		end
	end end
end

task.spawn(function()
	while true do
		task.wait(math.random(90, 180))
		currentWeather = "Thunderstorm"
		weatherEvent:FireAllClients(currentWeather)
		for _=1, math.random(6, 12) do
			task.wait(math.random(2, 5))
			local origin = getWorldOrigin() + Vector3.new(math.random(-220,220), 80, math.random(-220,220))
			scorchBlockAt(origin - Vector3.new(0,80,0))
			playConfiguredSound("LightningSound", Workspace)
			-- 隕石雨事件保留為地形焦黑效果，避免把獎勵歸給任一玩家。
		end
		currentWeather = "Clear"
		weatherEvent:FireAllClients(currentWeather)
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
	WORLD_SEED = math.random(1, 1000000)
	for _, player in ipairs(Players:GetPlayers()) do
		local sand = player:FindFirstChild("leaderstats") and player.leaderstats:FindFirstChild("Sand")
		if sand then
			sand.Value = 0
		end
		teleportPlayerToSteel(player)
		playerAbilityState[player] = {}
		pendingAbilityDrafts[player] = nil
		offerAbilityDraft(player, "WorldRefresh")
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


local function isPlayerInSteelSafeArea(player)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local steelFloor = getSteelFloor()
	if not root or not steelFloor then
		return false
	end
	local relative = steelFloor.CFrame:PointToObjectSpace(root.Position)
	return math.abs(relative.X) <= steelFloor.Size.X / 2 + 2
		and math.abs(relative.Z) <= steelFloor.Size.Z / 2 + 2
		and root.Position.Y >= steelFloor.Position.Y - 2
		and root.Position.Y <= steelFloor.Position.Y + 18
end

task.spawn(function()
	while true do
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if character then
				local forceField = character:FindFirstChild("SteelSafeZoneForceField")
				if isPlayerInSteelSafeArea(player) then
					if not forceField then
						forceField = Instance.new("ForceField")
						forceField.Name = "SteelSafeZoneForceField"
						forceField.Visible = false
						forceField.Parent = character
					end
				else
					if forceField then
						forceField:Destroy()
					end
				end
			end
		end
		task.wait(0.25)
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
