local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
if player:GetAttribute("MiningClientInitialized") then
	script:Destroy()
	return
end
player:SetAttribute("MiningClientInitialized", true)

local mouse = player:GetMouse()
local SHOP_PREVIEW_POSITION = Vector3.new(0, 10000, 0)
local SHOP_SLOT_TWEEN = 0.32

local sendNotificationEvent = ReplicatedStorage:WaitForChild("SendNotification")
local teleportEvent = ReplicatedStorage:WaitForChild("TeleportToShop")
local shopActionEvent = ReplicatedStorage:WaitForChild("ShopAction")
local miningEvent = ReplicatedStorage:WaitForChild("MiningEvent")
local rewardEmojiEvent = ReplicatedStorage:WaitForChild("RewardEmojiEvent")
local shopCatalogFunction = ReplicatedStorage:WaitForChild("GetShopCatalog")
local nextWorldRefreshTimeValue = ReplicatedStorage:WaitForChild("NextWorldRefreshTime")

local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:FindFirstChild("MiningHud")
if not gui then
	local starterTemplate = StarterGui:FindFirstChild("MiningHud")
	if starterTemplate then
		-- StarterGui normally clones MiningHud into PlayerGui; wait for that clone instead of creating a second copy.
		gui = playerGui:WaitForChild("MiningHud", 10)
		if not gui then
			gui = starterTemplate:Clone()
			gui.Parent = playerGui
		end
	else
		gui = Instance.new("ScreenGui")
		gui.Name = "MiningHud"
		gui.ResetOnSpawn = false
		gui.Parent = playerGui
	end
end

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 10)
	corner.Parent = instance
	return corner
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

local function makeButton(name, text, size, position, parent)
	local button, created = getOrCreateChild(parent, "TextButton", name)
	button.Text = text
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.TextScaled = true
	button.Parent = parent
	if created then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = button
	end
	return button
end

local homeButton = makeButton("TeleportHomeButton", "一鍵回城", UDim2.fromOffset(120, 42), UDim2.fromOffset(16, 160), gui)
homeButton.MouseButton1Click:Connect(function()
	teleportEvent:FireServer()
end)

local infoLabel, infoCreated = getOrCreateChild(gui, "TextLabel", "WorldInfo")
if infoCreated then
infoLabel.Size = UDim2.fromOffset(260, 58)
infoLabel.Position = UDim2.fromOffset(16, 16)
infoLabel.BackgroundTransparency = 0.25
infoLabel.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
infoLabel.TextColor3 = Color3.fromRGB(255, 245, 210)
infoLabel.TextWrapped = true
infoLabel.TextScaled = true
infoLabel.Parent = gui
addCorner(infoLabel, 12)
end

local fullBackpackButton = makeButton("FullBackpackReturnButton", "背包已滿！返回商城", UDim2.fromOffset(260, 58), UDim2.new(0.5, -130, 0.52, 0), gui)
fullBackpackButton.BackgroundColor3 = Color3.fromRGB(170, 80, 35)
fullBackpackButton.Visible = false
fullBackpackButton.MouseButton1Click:Connect(function()
	teleportEvent:FireServer()
end)

local shopFrame, shopFrameCreated = getOrCreateChild(gui, "Frame", "ShopFrame")
if shopFrameCreated then
	addCorner(shopFrame, 16)
end
shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
shopFrame.Size = UDim2.fromOffset(620, 180)
shopFrame.Position = UDim2.new(0.5, 0, 1, -110)
shopFrame.BackgroundColor3 = Color3.fromRGB(64, 42, 24)
shopFrame.Visible = false
shopFrame.Parent = gui

local title, titleCreated = getOrCreateChild(shopFrame, "TextLabel", "Title")
title.Text = "礦工棚子商店"
title.Size = UDim2.new(1, -64, 0, 36)
title.Position = UDim2.fromOffset(16, 8)
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
local shopIsOpen = false

local localPreviewFolder = Workspace:FindFirstChild("LocalShopPreviewModels")
if not localPreviewFolder then
	localPreviewFolder = Instance.new("Folder")
	localPreviewFolder.Name = "LocalShopPreviewModels"
	localPreviewFolder.Parent = Workspace
end

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

	local source = item.sourceName and localPreviewFolder:FindFirstChild(item.sourceName)
	if source then
		local clone = source:Clone()
		clone.Name = "DisplayModel"
		clone.Parent = model
		mainPart = clone:IsA("BasePart") and clone or clone:FindFirstChildWhichIsA("BasePart", true)
		if mainPart then
			model.PrimaryPart = mainPart
			model:PivotTo(CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new((index - 1) * 5, 3, 0)))
		end
	end
	if mainPart then
		for _, descendant in ipairs(model:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant:SetAttribute("ShopIndex", index)
			end
		end
	elseif modelData.kind == "pickaxe" then
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


local function refreshCatalogAndPreviews()
	shopCatalog = shopCatalogFunction:InvokeServer()
	for _, child in ipairs(localPreviewFolder:GetChildren()) do
		if child.Name:match("^LocalPreview_") then
			child:Destroy()
		end
	end
	for index, item in ipairs(shopCatalog) do
		createLocalPreviewModel(item, index)
	end
	selectedShopIndex = math.clamp(selectedShopIndex, 1, math.max(1, #shopCatalog))
end

refreshCatalogAndPreviews()

local descriptionLabel, descriptionCreated = getOrCreateChild(shopFrame, "TextLabel", "Description")
if descriptionCreated then
	addCorner(descriptionLabel, 12)
end
descriptionLabel.Size = UDim2.new(1, -40, 0, 56)
descriptionLabel.Position = UDim2.fromOffset(20, 48)
descriptionLabel.BackgroundTransparency = 0.25
descriptionLabel.BackgroundColor3 = Color3.fromRGB(45, 30, 18)
descriptionLabel.TextColor3 = Color3.fromRGB(255, 235, 190)
descriptionLabel.TextWrapped = true
descriptionLabel.TextScaled = true
descriptionLabel.Parent = shopFrame

local previousButton = makeButton("PreviousItem", "◀ 上一個", UDim2.fromOffset(120, 46), UDim2.fromOffset(20, 118), shopFrame)
previousButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local buyButton = makeButton("BuySelected", "購買 / 使用", UDim2.fromOffset(320, 46), UDim2.fromOffset(150, 118), shopFrame)
buyButton.BackgroundColor3 = Color3.fromRGB(35, 95, 55)

local nextButton = makeButton("NextItem", "下一個 ▶", UDim2.fromOffset(120, 46), UDim2.fromOffset(480, 118), shopFrame)
nextButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local function getShopWorld()
	return Workspace:FindFirstChild("MiningShopWorld")
end

local shopOpenCount = 0
local shopPreviewScene = Workspace:FindFirstChild("LocalShop3DPurchaseScene")
if not shopPreviewScene then
	shopPreviewScene = Instance.new("Folder")
	shopPreviewScene.Name = "LocalShop3DPurchaseScene"
	shopPreviewScene.Parent = Workspace
end

local slotLayout = {
	previous = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(-7.5, 1.2, 0)), scale = 0.72, platform = Vector3.new(4.8, 0.45, 3.4), transparency = 0.22 },
	current = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(0, 1.45, 0)), scale = 1.12, platform = Vector3.new(6.4, 0.55, 4.4), transparency = 0 },
	next = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(7.5, 1.2, 0)), scale = 0.72, platform = Vector3.new(4.8, 0.45, 3.4), transparency = 0.22 },
	leftOut = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(-15, 0.9, 0)), scale = 0.55, platform = Vector3.new(3.8, 0.35, 2.8), transparency = 1 },
	rightOut = { cframe = CFrame.new(SHOP_PREVIEW_POSITION + Vector3.new(15, 0.9, 0)), scale = 0.55, platform = Vector3.new(3.8, 0.35, 2.8), transparency = 1 },
}
local activeDisplays = {}

local function wrapIndex(index)
	if #shopCatalog == 0 then
		return 1
	end
	return ((index - 1) % #shopCatalog) + 1
end

local function clear3DDisplays()
	for _, display in ipairs(activeDisplays) do
		if display.model and display.model.Parent then
			display.model:Destroy()
		end
	end
	table.clear(activeDisplays)
end

local function clonePreviewModel(item)
	local source = localPreviewFolder:FindFirstChild("LocalPreview_" .. item.id)
	local clone = source and source:Clone()
	if not clone then
		return nil
	end
	clone.Name = "3DItem_" .. item.id
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.Transparency = 0
		end
	end
	return clone
end

local function pivotItemAbovePlatform(itemModel, platform)
	if not itemModel then
		return
	end
	local _, size = itemModel:GetBoundingBox()
	itemModel:PivotTo(platform.CFrame * CFrame.new(0, platform.Size.Y / 2 + math.max(size.Y / 2, 0.8) + 0.2, 0) * CFrame.Angles(0, math.rad(25), 0))
end

local function create3DDisplay(index, layoutKey)
	local item = shopCatalog[wrapIndex(index)]
	if not item then
		return nil
	end
	local layout = slotLayout[layoutKey]
	local displayModel = Instance.new("Model")
	displayModel.Name = "Shop3DDisplay_" .. layoutKey .. "_" .. item.id
	displayModel.Parent = shopPreviewScene

	local platform = Instance.new("Part")
	platform.Name = "WoodDisplayPlatform"
	platform.Size = layout.platform
	platform.Material = Enum.Material.WoodPlanks
	platform.Color = Color3.fromRGB(118, 74, 34)
	platform.Anchored = true
	platform.CanCollide = false
	platform.Transparency = layout.transparency
	platform.CFrame = layout.cframe
	platform.Parent = displayModel
	displayModel.PrimaryPart = platform

	local itemModel = clonePreviewModel(item)
	if itemModel then
		itemModel.Parent = displayModel
		pcall(function() itemModel:ScaleTo(layout.scale) end)
		pivotItemAbovePlatform(itemModel, platform)
		for _, descendant in ipairs(itemModel:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Transparency = layout.transparency
			end
		end
	end

	local display = { model = displayModel, platform = platform, itemModel = itemModel, layoutKey = layoutKey }
	table.insert(activeDisplays, display)
	return display
end

local function tween3DDisplay(display, layoutKey)
	if not display then
		return nil
	end
	local layout = slotLayout[layoutKey]
	local startPivot = display.model:GetPivot()
	local pivotValue = Instance.new("CFrameValue")
	pivotValue.Value = startPivot
	pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
		display.model:PivotTo(pivotValue.Value)
	end)
	local pivotTween = TweenService:Create(pivotValue, TweenInfo.new(SHOP_SLOT_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = layout.cframe })
	local sizeTween = TweenService:Create(display.platform, TweenInfo.new(SHOP_SLOT_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = layout.platform, Transparency = layout.transparency })
	for _, descendant in ipairs(display.model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant ~= display.platform then
			TweenService:Create(descendant, TweenInfo.new(SHOP_SLOT_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = layout.transparency }):Play()
		end
	end
	pivotTween:Play()
	sizeTween:Play()
	pivotTween.Completed:Connect(function()
		pivotValue:Destroy()
		if display.itemModel then
			pcall(function() display.itemModel:ScaleTo(layout.scale) end)
			pivotItemAbovePlatform(display.itemModel, display.platform)
		end
	end)
	return pivotTween
end

local function render3DShop(direction)
	if #shopCatalog == 0 then
		clear3DDisplays()
		return
	end
	if not direction then
		clear3DDisplays()
		create3DDisplay(selectedShopIndex - 1, "previous")
		create3DDisplay(selectedShopIndex, "current")
		create3DDisplay(selectedShopIndex + 1, "next")
		return
	end

	local oldSelected = direction == "next" and wrapIndex(selectedShopIndex - 1) or wrapIndex(selectedShopIndex + 1)
	clear3DDisplays()
	if direction == "next" then
		local leaving = create3DDisplay(oldSelected - 1, "previous")
		local oldCurrent = create3DDisplay(oldSelected, "current")
		local newCurrent = create3DDisplay(selectedShopIndex, "next")
		local entering = create3DDisplay(selectedShopIndex + 1, "rightOut")
		tween3DDisplay(leaving, "leftOut")
		tween3DDisplay(oldCurrent, "previous")
		tween3DDisplay(newCurrent, "current")
		local tween = tween3DDisplay(entering, "next")
		if tween then
			local connection
			connection = tween.Completed:Connect(function()
				if connection then connection:Disconnect() end
				render3DShop(nil)
			end)
		end
	else
		local entering = create3DDisplay(selectedShopIndex - 1, "leftOut")
		local newCurrent = create3DDisplay(selectedShopIndex, "previous")
		local oldCurrent = create3DDisplay(oldSelected, "current")
		local leaving = create3DDisplay(oldSelected + 1, "next")
		tween3DDisplay(entering, "previous")
		tween3DDisplay(newCurrent, "current")
		tween3DDisplay(oldCurrent, "next")
		local tween = tween3DDisplay(leaving, "rightOut")
		if tween then
			local connection
			connection = tween.Completed:Connect(function()
				if connection then connection:Disconnect() end
				render3DShop(nil)
			end)
		end
	end
end

local function setPreviewVisible(index)
	for _, descendant in ipairs(localPreviewFolder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("ShopIndex") then
			descendant.Transparency = 1
		end
	end
end

local function updateShopSelection(direction)
	local item = shopCatalog[selectedShopIndex]
	if not item then
		return
	end
	title.Text = item.name .. ((item.price and item.price > 0) and ("  $" .. item.price) or "")
	descriptionLabel.Text = item.description
	buyButton.Text = (item.action == "Sell") and "出售沙子" or "購買 / 使用"
	setPreviewVisible(selectedShopIndex)
	render3DShop(direction)
end

local function focusShopCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	if not shopIsOpen then
		previousCameraType = camera.CameraType
		previousCameraSubject = camera.CameraSubject
		previousCameraCFrame = camera.CFrame
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(SHOP_PREVIEW_POSITION + Vector3.new(0, 6, 18), SHOP_PREVIEW_POSITION + Vector3.new(0, 2.4, 0))
end

local function restoreCamera()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end
	camera.CameraType = previousCameraType or Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraSubject = previousCameraSubject or humanoid
	if humanoid and (not previousCameraSubject or previousCameraSubject.Parent == nil) then
		camera.CameraSubject = humanoid
	end
	if previousCameraCFrame then
		camera.CFrame = previousCameraCFrame
	end
end

local function openShop()
	if os.clock() < suppressShopOpenUntil or shopIsOpen then
		return
	end
	shopOpenCount += 1
	refreshCatalogAndPreviews()
	shopFrame.Visible = true
	shopFrame.Position = UDim2.new(0.5, 0, 1, 80)
	TweenService:Create(shopFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 1, -110) }):Play()
	focusShopCamera()
	shopIsOpen = true
	selectedShopIndex = 1
	updateShopSelection(nil)
end

closeShop = function()
	if not shopIsOpen and not shopFrame.Visible then
		return
	end
	shopIsOpen = false
	shopFrame.Visible = false
	clear3DDisplays()
	restoreCamera()
end

previousButton.MouseButton1Click:Connect(function()
	selectedShopIndex = ((selectedShopIndex - 2) % #shopCatalog) + 1
	updateShopSelection("previous")
end)

nextButton.MouseButton1Click:Connect(function()
	selectedShopIndex = (selectedShopIndex % #shopCatalog) + 1
	updateShopSelection("next")
end)

buyButton.MouseButton1Click:Connect(function()
	local item = shopCatalog[selectedShopIndex]
	if item then
		shopActionEvent:FireServer(item.id)
	end
end)

updateShopSelection(nil)

local oldPlayerProgress = gui:FindFirstChild("MiningProgress")
if oldPlayerProgress then
	oldPlayerProgress:Destroy()
end

local activeSurfaceProgress = nil

local function clearSurfaceProgress()
	if activeSurfaceProgress then
		activeSurfaceProgress:Destroy()
		activeSurfaceProgress = nil
	end
end

local function darkenColor(color, amount)
	return color:Lerp(Color3.new(0, 0, 0), amount or 0.45)
end

local function lightenColor(color, amount)
	return color:Lerp(Color3.new(1, 1, 1), amount or 0.18)
end

local function showSurfaceProgress(targetPart, percentRemaining)
	clearSurfaceProgress()
	if not targetPart then
		return
	end
	local surfaceGui = Instance.new("SurfaceGui")
	surfaceGui.Name = "MiningProgressSurface"
	surfaceGui.Face = Enum.NormalId.Top
	surfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surfaceGui.PixelsPerStud = 40
	surfaceGui.LightInfluence = 0
	surfaceGui.Adornee = targetPart
	surfaceGui.Parent = targetPart

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 0.5)
	back.Position = UDim2.fromScale(0.5, 0.5)
	back.Size = UDim2.fromScale(0.72, 0.16)
	back.BackgroundColor3 = darkenColor(targetPart.Color, 0.58)
	back.BackgroundTransparency = 0.15
	back.Parent = surfaceGui
	addCorner(back, 6)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(percentRemaining, 1)
	bar.BackgroundColor3 = lightenColor(targetPart.Color, 0.16)
	bar.Parent = back
	addCorner(bar, 6)
	activeSurfaceProgress = surfaceGui
end

local selectionBox = Instance.new("SelectionBox")
selectionBox.Name = "TargetBlockHighlight"
selectionBox.Color3 = Color3.fromRGB(90, 60, 30)
selectionBox.LineThickness = 0.05
selectionBox.SurfaceTransparency = 1
selectionBox.Parent = gui

local isMining = false
local pendingBombInput = nil
local bombTrajectoryParts = {}
local LONG_PRESS_SECONDS = 0.25
local THROW_ARC_STEPS = 18

local function equippedBombTool()
	local character = player.Character
	local tool = character and character:FindFirstChildOfClass("Tool")
	if tool and tool:GetAttribute("BombCountName") then
		return tool
	end
	return nil
end

local function clearBombTrajectory()
	for _, part in ipairs(bombTrajectoryParts) do
		part:Destroy()
	end
	table.clear(bombTrajectoryParts)
end

local function drawBombTrajectory(targetPart)
	clearBombTrajectory()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not targetPart then
		return
	end
	local startPosition = root.Position + Vector3.new(0, 2, 0)
	local targetPosition = targetPart.Position
	local apexLift = math.clamp((targetPosition - startPosition).Magnitude * 0.12, 3, 9)
	for step = 1, THROW_ARC_STEPS do
		local alpha = step / THROW_ARC_STEPS
		local marker = Instance.new("Part")
		marker.Name = "BombTrajectoryMarker"
		marker.Shape = Enum.PartType.Ball
		marker.Size = Vector3.new(0.22, 0.22, 0.22)
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.fromRGB(255, 255, 255)
		marker.Transparency = 0.05 + alpha * 0.35
		marker.Anchored = true
		marker.CanCollide = false
		marker.Position = startPosition:Lerp(targetPosition, alpha) + Vector3.new(0, math.sin(math.pi * alpha) * apexLift, 0)
		marker.Parent = Workspace
		table.insert(bombTrajectoryParts, marker)
	end
end

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
	if target then
		selectionBox.Color3 = darkenColor(target.Color, 0.5)
	end
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

Lighting.FogColor = Color3.fromRGB(225, 202, 158)
Lighting.FogStart = 240
Lighting.FogEnd = 820
Lighting.Ambient = Color3.fromRGB(128, 104, 82)
Lighting.OutdoorAmbient = Color3.fromRGB(165, 132, 96)
Lighting.Brightness = 2.15
Lighting.ClockTime = 16.25
Lighting.ExposureCompensation = -0.08

local shopTouchConnections = {}
local touchingShopZone = false

local function disconnectShopTouchConnections()
	for _, connection in ipairs(shopTouchConnections) do
		connection:Disconnect()
	end
	table.clear(shopTouchConnections)
end

local function connectShopOpenZone()
	disconnectShopTouchConnections()
	local shopWorld = getShopWorld()
	local zone = shopWorld and shopWorld:FindFirstChild("ShopOpenZone")
	if not zone then
		return
	end

	table.insert(shopTouchConnections, zone.Touched:Connect(function(hit)
		local character = player.Character
		if character and hit and hit:IsDescendantOf(character) then
			touchingShopZone = true
			openShop()
		end
	end))

	table.insert(shopTouchConnections, zone.TouchEnded:Connect(function(hit)
		local character = player.Character
		if character and hit and hit:IsDescendantOf(character) then
			task.delay(0.15, function()
				local root = character:FindFirstChild("HumanoidRootPart")
				if not root then
					return
				end
				local flatDistance = Vector3.new(root.Position.X - zone.Position.X, 0, root.Position.Z - zone.Position.Z).Magnitude
				local stillInside = flatDistance <= math.max(zone.Size.Y, zone.Size.Z) / 2 + 1
				if not stillInside then
					touchingShopZone = false
					closeShop()
				end
			end)
		end
	end))
end

connectShopOpenZone()
task.spawn(function()
	while true do
		local shopWorld = getShopWorld()
		local zone = shopWorld and shopWorld:FindFirstChild("ShopOpenZone")
		if not zone then
			connectShopOpenZone()
		elseif shopIsOpen then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local flatDistance = root and Vector3.new(root.Position.X - zone.Position.X, 0, root.Position.Z - zone.Position.Z).Magnitude or math.huge
			if flatDistance > math.max(zone.Size.Y, zone.Size.Z) / 2 + 2 then
				touchingShopZone = false
				closeShop()
			end
		end
		task.wait(0.25)
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
		if tool and tool:GetAttribute("BombCountName") then
			pendingBombInput = input
			task.spawn(function()
				task.wait(LONG_PRESS_SECONDS)
				while pendingBombInput == input and equippedBombTool() do
					drawBombTrajectory(getMineableTarget())
					task.wait(0.08)
				end
			end)
		elseif target then
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
		if pendingBombInput then
			local target = getMineableTarget()
			if equippedBombTool() and target then
				miningEvent:FireServer(target)
			end
			pendingBombInput = nil
			clearBombTrajectory()
		end
	end
end)

rewardEmojiEvent.OnClientEvent:Connect(function(emoji, amount)
	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardEmojiFly"
	rewardLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	rewardLabel.Position = UDim2.fromScale(0.5, 0.55)
	rewardLabel.Size = UDim2.fromOffset(150, 52)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = string.format("%s +%s", emoji or "🪙", amount or 0)
	rewardLabel.TextScaled = true
	rewardLabel.TextColor3 = Color3.fromRGB(255, 230, 90)
	rewardLabel.TextStrokeTransparency = 0.25
	rewardLabel.Parent = gui

	local targetX = infoLabel.AbsolutePosition.X + infoLabel.AbsoluteSize.X * 0.45
	local targetY = infoLabel.AbsolutePosition.Y + infoLabel.AbsoluteSize.Y * 0.35
	local tween = game:GetService("TweenService"):Create(rewardLabel, TweenInfo.new(0.75, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.fromOffset(targetX, targetY),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		rewardLabel:Destroy()
	end)
end)

miningEvent.OnClientEvent:Connect(function(targetPart, currentHealth, maxHealth)
	if currentHealth <= 0 or maxHealth <= 0 then
		clearSurfaceProgress()
		return
	end
	local percentRemaining = math.clamp(currentHealth / maxHealth, 0, 1)
	showSurfaceProgress(targetPart, percentRemaining)
end)
