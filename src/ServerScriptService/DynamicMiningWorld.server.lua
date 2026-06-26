local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ==================== 參數設定 ====================
local BLOCK_SIZE = 4
local CHUNK_RADIUS_XZ = 6
local CHUNK_RADIUS_Y = 4
local MAX_DEPTH_BLOCKS = 4000
local CHEST_CHANCE = 0.02
local MAX_BACKPACK_CAPPED = 20

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
	["拳頭"] = 1,
	["木鎬"] = 2,
	["鐵鎬"] = 4,
	["鑽石鎬"] = 8,
}

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
	return true
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

	player.CharacterAdded:Connect(function()
		task.wait(0.5)
		giveTool(player, "拳頭")
	end)
end)

-- ==================== 2. 建立齊平場地與實體商店 ====================
local function createShopWorld()
	local shopModel = Workspace:FindFirstChild("MiningShopWorld") or Instance.new("Model")
	shopModel.Name = "MiningShopWorld"
	shopModel.Parent = Workspace

	-- 剛體固體地面精準齊平 Y = 0
	local secureFloor = shopModel:FindFirstChild("SecureFloor") or Instance.new("Part")
	secureFloor.Name = "SecureFloor"
	secureFloor.Size = Vector3.new(40, 4, 40)
	secureFloor.Position = Vector3.new(0, -2, -25)
	secureFloor.Material = Enum.Material.Concrete
	secureFloor.Color = Color3.fromRGB(80, 85, 90)
	secureFloor.Anchored = true
	secureFloor.CanCollide = true
	secureFloor.Parent = shopModel

	-- 藍色地墊
	local pad = shopModel:FindFirstChild("ShopPad") or Instance.new("Part")
	pad.Name = "ShopPad"
	pad.Size = Vector3.new(12, 0.2, 12)
	pad.Position = SHOP_POSITION + Vector3.new(0, 0.1, 0)
	pad.BrickColor = BrickColor.new("Bright blue")
	pad.Anchored = true
	pad.Parent = shopModel

	-- 商店實體（自動販賣機）
	local shopVending = shopModel:FindFirstChild("ShopVendingMachine") or Instance.new("Part")
	shopVending.Name = "ShopVendingMachine"
	shopVending.Size = Vector3.new(4, 7, 3)
	shopVending.Position = SHOP_POSITION + Vector3.new(0, 3.5, -4)
	shopVending.Material = Enum.Material.SmoothPlastic
	shopVending.Color = Color3.fromRGB(40, 40, 45)
	shopVending.Anchored = true
	shopVending.Parent = shopModel

	local neonPanel = shopModel:FindFirstChild("NeonPanel") or Instance.new("Part")
	neonPanel.Name = "NeonPanel"
	neonPanel.Size = Vector3.new(3, 5, 0.2)
	neonPanel.Position = shopVending.Position + Vector3.new(0, 0, 1.4)
	neonPanel.Material = Enum.Material.Neon
	neonPanel.Color = Color3.fromRGB(0, 255, 128)
	neonPanel.Anchored = true
	neonPanel.CanCollide = false
	neonPanel.Parent = shopModel
end
createShopWorld()

-- 一鍵回城
teleportEvent.OnServerEvent:Connect(function(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(SHOP_POSITION + Vector3.new(0, 3, 0))
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
		if coins.Value >= 50 and giveTool(player, "💣 炸彈") then
			coins.Value -= 50
			sendNotification(player, "購買成功", "獲得一枚隨身炸彈！")
		else
			sendNotification(player, "交易失敗", "金幣不足，或已擁有炸彈。")
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
	if currentTool and currentTool.Name == "💣 炸彈" then
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

	local depthPercent = math.clamp(math.abs(by) / MAX_DEPTH_BLOCKS, 0, 1)
	local maxHealth = math.floor(1 + (depthPercent * 19))
	blockHealthData[key] = blockHealthData[key] or maxHealth

	local power = TOOL_EFFICIENCY[currentPickaxe.Value] or 1
	blockHealthData[key] -= power

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
