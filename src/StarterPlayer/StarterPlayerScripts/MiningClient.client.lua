local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local SHOP_PREVIEW_POSITION = Vector3.new(0, 10000, 0)

local sendNotificationEvent = ReplicatedStorage:WaitForChild("SendNotification")
local teleportEvent = ReplicatedStorage:WaitForChild("TeleportToShop")
local shopActionEvent = ReplicatedStorage:WaitForChild("ShopAction")
local miningEvent = ReplicatedStorage:WaitForChild("MiningEvent")
local shopCatalogFunction = ReplicatedStorage:WaitForChild("GetShopCatalog")
local nextWorldRefreshTimeValue = ReplicatedStorage:WaitForChild("NextWorldRefreshTime")

local gui = Instance.new("ScreenGui")
gui.Name = "MiningHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = instance
	return corner
end

local function makeButton(name, text, size, position, parent)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button
	return button
end

local homeButton = makeButton("TeleportHomeButton", "一鍵回城", UDim2.fromOffset(120, 42), UDim2.fromOffset(16, 160), gui)
homeButton.MouseButton1Click:Connect(function()
	teleportEvent:FireServer()
end)

local infoLabel = Instance.new("TextLabel")
infoLabel.Name = "WorldInfo"
infoLabel.Size = UDim2.fromOffset(260, 58)
infoLabel.Position = UDim2.fromOffset(16, 16)
infoLabel.BackgroundTransparency = 0.25
infoLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
infoLabel.TextColor3 = Color3.fromRGB(255, 245, 210)
infoLabel.TextWrapped = true
infoLabel.TextScaled = true
infoLabel.Parent = gui
addCorner(infoLabel, 12)

local fullBackpackButton = makeButton("FullBackpackReturnButton", "背包已滿！返回商城", UDim2.fromOffset(260, 58), UDim2.new(0.5, -130, 0.52, 0), gui)
fullBackpackButton.BackgroundColor3 = Color3.fromRGB(170, 80, 35)
fullBackpackButton.Visible = false
fullBackpackButton.MouseButton1Click:Connect(function()
	teleportEvent:FireServer()
end)

local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
shopFrame.Size = UDim2.fromOffset(380, 240)
shopFrame.Position = UDim2.new(0.5, -190, 1, -260)
shopFrame.BackgroundColor3 = Color3.fromRGB(64, 42, 24)
shopFrame.Visible = false
shopFrame.Parent = gui
addCorner(shopFrame, 16)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Text = "礦工棚子商店"
title.Size = UDim2.new(1, -48, 0, 44)
title.Position = UDim2.fromOffset(8, 8)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(255, 235, 190)
title.TextScaled = true
title.Parent = shopFrame

local closeShop

local closeButton = makeButton("CloseButton", "X", UDim2.fromOffset(36, 36), UDim2.new(1, -44, 0, 8), shopFrame)
closeButton.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
closeButton.MouseButton1Click:Connect(function()
	if closeShop then
		closeShop()
	end
end)

local shopCatalog = shopCatalogFunction:InvokeServer()
local selectedShopIndex = 1
local suppressShopOpenUntil = os.clock() + 5
local previousCameraType = nil
local previousCameraSubject = nil
local previousCameraCFrame = nil

local localPreviewFolder = Instance.new("Folder")
localPreviewFolder.Name = "LocalShopPreviewModels"
localPreviewFolder.Parent = Workspace

local function createLocalPreviewModel(item, index)
	local modelData = item.model or {}
	local model = Instance.new("Model")
	model.Name = "LocalPreview_" .. item.id
	model.Parent = localPreviewFolder

	local mainPart
	local function setupPart(part)
		part.Anchored = true
		part.CanCollide = false
		part:SetAttribute("ShopIndex", index)
		part.Parent = model
		return part
	end

	if modelData.kind == "pickaxe" then
		mainPart = setupPart(Instance.new("Part"))
		mainPart.Name = "Handle"
		mainPart.Size = Vector3.new(0.35, 3.2, 0.35)
		mainPart.Material = Enum.Material.Wood
		mainPart.Color = Color3.fromRGB(125, 78, 38)
		mainPart.CFrame = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0)) * CFrame.Angles(0, 0, math.rad(25))

		local head = setupPart(Instance.new("Part"))
		head.Name = "Head"
		head.Size = Vector3.new(2.4, 0.35, 0.35)
		head.Material = modelData.material or Enum.Material.Wood
		head.Color = modelData.color or Color3.fromRGB(150, 100, 50)
		head.CFrame = mainPart.CFrame * CFrame.new(0, 1.35, 0)
	elseif modelData.kind == "bomb" then
		mainPart = setupPart(Instance.new("Part"))
		mainPart.Name = "BombBody"
		mainPart.Shape = Enum.PartType.Ball
		mainPart.Size = Vector3.new(2.2, 2.2, 2.2)
		mainPart.Material = modelData.material or Enum.Material.Slate
		mainPart.Color = modelData.color or Color3.fromRGB(25, 25, 25)
		mainPart.CFrame = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0))
	elseif modelData.kind == "backpack" then
		mainPart = setupPart(Instance.new("Part"))
		mainPart.Name = "BackpackBody"
		mainPart.Size = Vector3.new(2.2, 2.8, 1.2)
		mainPart.Material = modelData.material or Enum.Material.Fabric
		mainPart.Color = modelData.color or Color3.fromRGB(85, 135, 210)
		mainPart.CFrame = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0))
	else
		mainPart = setupPart(Instance.new("Part"))
		mainPart.Name = "DisplayBlock"
		mainPart.Size = modelData.size or Vector3.new(2, 2, 2)
		mainPart.Material = modelData.material or Enum.Material.Sand
		mainPart.Color = modelData.color or Color3.fromRGB(235, 205, 130)
		mainPart.CFrame = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0))
	end

	model.PrimaryPart = mainPart
	return model
end

for index, item in ipairs(shopCatalog) do
	createLocalPreviewModel(item, index)
end

local descriptionLabel = Instance.new("TextLabel")
descriptionLabel.Name = "Description"
descriptionLabel.Size = UDim2.new(1, -32, 0, 76)
descriptionLabel.Position = UDim2.fromOffset(16, 56)
descriptionLabel.BackgroundTransparency = 0.25
descriptionLabel.BackgroundColor3 = Color3.fromRGB(45, 30, 18)
descriptionLabel.TextColor3 = Color3.fromRGB(255, 235, 190)
descriptionLabel.TextWrapped = true
descriptionLabel.TextScaled = true
descriptionLabel.Parent = shopFrame
addCorner(descriptionLabel, 12)

local previousButton = makeButton("PreviousItem", "◀ 上一個", UDim2.fromOffset(110, 42), UDim2.fromOffset(16, 150), shopFrame)
previousButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local buyButton = makeButton("BuySelected", "購買", UDim2.fromOffset(120, 42), UDim2.fromOffset(130, 150), shopFrame)
buyButton.BackgroundColor3 = Color3.fromRGB(35, 95, 55)

local nextButton = makeButton("NextItem", "下一個 ▶", UDim2.fromOffset(110, 42), UDim2.fromOffset(254, 150), shopFrame)
nextButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local function getShopWorld()
	return Workspace:FindFirstChild("MiningShopWorld")
end

local function setPreviewVisible(index)
	for _, descendant in ipairs(localPreviewFolder:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Transparency = (descendant:GetAttribute("ShopIndex") == index) and 0 or 1
		end
	end
end

local function updateShopSelection()
	local item = shopCatalog[selectedShopIndex]
	if not item then
		return
	end
	title.Text = item.name .. ((item.price and item.price > 0) and ("  $" .. item.price) or "")
	descriptionLabel.Text = item.description
	buyButton.Text = (item.action == "Sell") and "出售" or "購買 / 使用"
	setPreviewVisible(selectedShopIndex)
end

local function focusShopCamera()
	local camera = Workspace.CurrentCamera
	local shopWorld = getShopWorld()
	local anchor = shopWorld and shopWorld:FindFirstChild("ShopCameraAnchor")
	if not camera then
		return
	end
	previousCameraType = camera.CameraType
	previousCameraSubject = camera.CameraSubject
	previousCameraCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = anchor and anchor.CFrame or CFrame.lookAt(SHOP_PREVIEW_POSITION + Vector3.new(0, 5, 11), SHOP_PREVIEW_POSITION + Vector3.new(0, 3, 0))
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = previousCameraType or Enum.CameraType.Custom
	camera.CameraSubject = previousCameraSubject
	if previousCameraCFrame then
		camera.CFrame = previousCameraCFrame
	end
end

local function openShop()
	if os.clock() < suppressShopOpenUntil then
		return
	end
	shopFrame.Visible = true
	focusShopCamera()
	updateShopSelection()
end

closeShop = function()
	shopFrame.Visible = false
	restoreCamera()
end

previousButton.MouseButton1Click:Connect(function()
	selectedShopIndex = ((selectedShopIndex - 2) % #shopCatalog) + 1
	updateShopSelection()
end)

nextButton.MouseButton1Click:Connect(function()
	selectedShopIndex = (selectedShopIndex % #shopCatalog) + 1
	updateShopSelection()
end)

buyButton.MouseButton1Click:Connect(function()
	local item = shopCatalog[selectedShopIndex]
	if item then
		shopActionEvent:FireServer(item.id)
	end
end)

updateShopSelection()

local progressFrame = Instance.new("Frame")
progressFrame.Name = "MiningProgress"
progressFrame.Size = UDim2.fromOffset(220, 20)
progressFrame.Position = UDim2.new(0.5, -110, 0.72, 0)
progressFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
progressFrame.Visible = false
progressFrame.Parent = gui
addCorner(progressFrame, 8)

local progressBar = Instance.new("Frame")
progressBar.Name = "Bar"
progressBar.Size = UDim2.fromScale(1, 1)
progressBar.BackgroundColor3 = Color3.fromRGB(252, 203, 96)
progressBar.Parent = progressFrame
addCorner(progressBar, 8)

local blockProgressBillboard = Instance.new("BillboardGui")
blockProgressBillboard.Name = "BlockMiningProgress"
blockProgressBillboard.Size = UDim2.fromOffset(120, 14)
blockProgressBillboard.StudsOffset = Vector3.new(0, 3, 0)
blockProgressBillboard.AlwaysOnTop = true
blockProgressBillboard.Enabled = false
blockProgressBillboard.Parent = gui

local blockProgressBack = Instance.new("Frame")
blockProgressBack.Name = "Back"
blockProgressBack.Size = UDim2.fromScale(1, 1)
blockProgressBack.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
blockProgressBack.Parent = blockProgressBillboard
addCorner(blockProgressBack, 6)

local blockProgressBar = Instance.new("Frame")
blockProgressBar.Name = "Bar"
blockProgressBar.Size = UDim2.fromScale(1, 1)
blockProgressBar.BackgroundColor3 = Color3.fromRGB(255, 210, 90)
blockProgressBar.Parent = blockProgressBack
addCorner(blockProgressBar, 6)

local selectionBox = Instance.new("SelectionBox")
selectionBox.Name = "TargetBlockHighlight"
selectionBox.Color3 = Color3.fromRGB(255, 245, 120)
selectionBox.LineThickness = 0.05
selectionBox.SurfaceTransparency = 1
selectionBox.Parent = gui

local isMining = false

local function getMineableTarget()
	local target = mouse.Target
	local miningFolder = Workspace:FindFirstChild("DynamicMiningWorld")
	if target and miningFolder and target:IsDescendantOf(miningFolder) then
		return target
	end
	return nil
end

local function updateHighlight(target)
	selectionBox.Adornee = target
end

sendNotificationEvent.OnClientEvent:Connect(function(titleText, message)
	StarterGui:SetCore("SendNotification", {
		Title = titleText,
		Text = message,
		Duration = 3,
	})
end)

player.CharacterAdded:Connect(function()
	suppressShopOpenUntil = os.clock() + 5
	closeShop()
end)

nextWorldRefreshTimeValue.Changed:Connect(function()
	suppressShopOpenUntil = os.clock() + 6
	closeShop()
end)

local function isInsideShopZone()
	local shopWorld = getShopWorld()
	local zone = shopWorld and shopWorld:FindFirstChild("ShopOpenZone")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not zone or not root then
		return false
	end
	local flatDistance = Vector3.new(root.Position.X - zone.Position.X, 0, root.Position.Z - zone.Position.Z).Magnitude
	return flatDistance <= 9
end

task.spawn(function()
	local wasInsideShop = false
	while true do
		local insideShop = isInsideShopZone()
		if insideShop and not wasInsideShop then
			openShop()
		elseif not insideShop and wasInsideShop then
			closeShop()
		end
		wasInsideShop = insideShop
		task.wait(0.2)
	end
end)

local function updateInfoPanel()
	local leaderstats = player:FindFirstChild("leaderstats")
	local sand = leaderstats and leaderstats:FindFirstChild("Sand")
	local coins = leaderstats and leaderstats:FindFirstChild("Coins")
	local maxSand = player:FindFirstChild("MaxSand")
	local remaining = math.max(0, nextWorldRefreshTimeValue.Value - os.time())
	local minutes = math.floor(remaining / 60)
	local seconds = remaining % 60
	local sandText = sand and maxSand and (sand.Value .. "/" .. maxSand.Value) or "載入中"
	local coinText = coins and coins.Value or 0
	infoLabel.Text = string.format("金錢：$%s  背包：%s\n世界刷新：%02d:%02d", coinText, sandText, minutes, seconds)
	fullBackpackButton.Visible = sand and maxSand and sand.Value >= maxSand.Value
end

task.spawn(function()
	while true do
		updateInfoPanel()
		task.wait(0.5)
	end
end)

local function playMiningSwing()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if not tool then
		return
	end
	local originalGrip = tool.Grip
	for step = 1, 6 do
		local angle = math.sin(step / 6 * math.pi) * math.rad(45)
		tool.Grip = originalGrip * CFrame.Angles(-angle, 0, 0)
		task.wait(0.03)
	end
	if tool.Parent == character then
		tool.Grip = originalGrip
	end
end

mouse.Move:Connect(function()
	updateHighlight(getMineableTarget())
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local character = player.Character
		local tool = character and character:FindFirstChildOfClass("Tool")
		local target = getMineableTarget()
		updateHighlight(target)
		if target then
			miningEvent:FireServer(target)
			task.spawn(playMiningSwing)
		end
		if tool and tool:GetAttribute("AutoMine") then
			isMining = true
			task.spawn(function()
				while isMining do
					local autoTarget = getMineableTarget()
					updateHighlight(autoTarget)
					if autoTarget then
						miningEvent:FireServer(autoTarget)
						task.spawn(playMiningSwing)
					end
					task.wait(0.2)
				end
			end)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isMining = false
	end
end)

miningEvent.OnClientEvent:Connect(function(targetPart, currentHealth, maxHealth)
	if currentHealth <= 0 or maxHealth <= 0 then
		progressFrame.Visible = false
		blockProgressBillboard.Enabled = false
		return
	end
	local percentRemaining = math.clamp(currentHealth / maxHealth, 0, 1)
	progressBar.Size = UDim2.fromScale(percentRemaining, 1)
	progressFrame.Visible = true
	blockProgressBillboard.Adornee = targetPart
	blockProgressBar.Size = UDim2.fromScale(percentRemaining, 1)
	blockProgressBillboard.Enabled = true
end)
