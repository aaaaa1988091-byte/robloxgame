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
	if not created then
		return button
	end
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
shopFrame.Size = UDim2.fromOffset(760, 520)
shopFrame.Position = UDim2.fromScale(0.5, 0.5)
shopFrame.BackgroundColor3 = Color3.fromRGB(64, 42, 24)
shopFrame.Visible = false
shopFrame.Parent = gui

local title, titleCreated = getOrCreateChild(shopFrame, "TextLabel", "Title")
title.Text = "礦工棚子商店"
title.Size = UDim2.new(1, -64, 0, 46)
title.Position = UDim2.fromOffset(16, 10)
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
descriptionLabel.Size = UDim2.new(1, -40, 0, 70)
descriptionLabel.Position = UDim2.fromOffset(20, 350)
descriptionLabel.BackgroundTransparency = 0.25
descriptionLabel.BackgroundColor3 = Color3.fromRGB(45, 30, 18)
descriptionLabel.TextColor3 = Color3.fromRGB(255, 235, 190)
descriptionLabel.TextWrapped = true
descriptionLabel.TextScaled = true
descriptionLabel.Parent = shopFrame

local carousel, carouselCreated = getOrCreateChild(shopFrame, "Frame", "ItemCarousel")
carousel.Size = UDim2.new(1, -40, 0, 260)
carousel.Position = UDim2.fromOffset(20, 78)
carousel.BackgroundColor3 = Color3.fromRGB(38, 25, 15)
carousel.BackgroundTransparency = 0.05
carousel.ClipsDescendants = true
if carouselCreated then
	addCorner(carousel, 18)
end

local previousButton = makeButton("PreviousItem", "◀", UDim2.fromOffset(58, 48), UDim2.fromOffset(24, 438), shopFrame)
previousButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local buyButton = makeButton("BuySelected", "購買 / 使用", UDim2.fromOffset(560, 48), UDim2.fromOffset(100, 438), shopFrame)
buyButton.BackgroundColor3 = Color3.fromRGB(35, 95, 55)

local nextButton = makeButton("NextItem", "▶", UDim2.fromOffset(58, 48), UDim2.fromOffset(678, 438), shopFrame)
nextButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local function getShopWorld()
	return Workspace:FindFirstChild("MiningShopWorld")
end

local shopOpenCount = 0
local carouselCards = {}
local slotLayout = {
	previous = { position = UDim2.fromScale(0.18, 0.54), size = UDim2.fromOffset(190, 185), transparency = 0.18 },
	current = { position = UDim2.fromScale(0.5, 0.5), size = UDim2.fromOffset(270, 235), transparency = 0 },
	next = { position = UDim2.fromScale(0.82, 0.54), size = UDim2.fromOffset(190, 185), transparency = 0.18 },
	leftOut = { position = UDim2.fromScale(-0.18, 0.58), size = UDim2.fromOffset(160, 155), transparency = 1 },
	rightOut = { position = UDim2.fromScale(1.18, 0.58), size = UDim2.fromOffset(160, 155), transparency = 1 },
}

local function wrapIndex(index)
	if #shopCatalog == 0 then
		return 1
	end
	return ((index - 1) % #shopCatalog) + 1
end

local function clearCarouselCards()
	for _, card in ipairs(carouselCards) do
		if card and card.Parent then
			card:Destroy()
		end
	end
	table.clear(carouselCards)
end

local function fitViewportModel(model)
	local _, size = model:GetBoundingBox()
	local maxSize = math.max(size.X, size.Y, size.Z, 1)
	model:PivotTo(CFrame.new(0, math.max(1.4, size.Y / 2 + 0.35), 0) * CFrame.Angles(0, math.rad(25), 0))
	return maxSize
end

local function clonePreviewForViewport(item)
	local source = localPreviewFolder:FindFirstChild("LocalPreview_" .. item.id)
	local clone = source and source:Clone()
	if not clone then
		return nil
	end
	clone.Name = "ViewportItem"
	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.Transparency = 0
		end
	end
	return clone
end

local function createDisplayCard(index, layoutKey)
	local item = shopCatalog[wrapIndex(index)]
	if not item then
		return nil
	end
	local layout = slotLayout[layoutKey]
	local card = Instance.new("Frame")
	card.Name = "ShopDisplay_" .. layoutKey
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = layout.position
	card.Size = layout.size
	card.BackgroundTransparency = 1
	card.Parent = carousel

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "ModelViewport"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.ImageTransparency = layout.transparency
	viewport.Ambient = Color3.fromRGB(210, 185, 145)
	viewport.LightColor = Color3.fromRGB(255, 236, 190)
	viewport.LightDirection = Vector3.new(-0.35, -1, -0.55)
	viewport.Parent = card

	local world = Instance.new("WorldModel")
	world.Parent = viewport

	local platform = Instance.new("Part")
	platform.Name = "WoodDisplayPlatform"
	platform.Size = Vector3.new(5.5, 0.45, 3.8)
	platform.Position = Vector3.new(0, 0.2, 0)
	platform.Material = Enum.Material.WoodPlanks
	platform.Color = Color3.fromRGB(118, 74, 34)
	platform.Anchored = true
	platform.Parent = world

	local itemModel = clonePreviewForViewport(item)
	local maxSize = 4
	if itemModel then
		itemModel.Parent = world
		maxSize = fitViewportModel(itemModel)
	end

	local camera = Instance.new("Camera")
	camera.CFrame = CFrame.lookAt(Vector3.new(0, math.max(3.2, maxSize * 0.7), math.max(7, maxSize * 2.2)), Vector3.new(0, math.max(1.6, maxSize * 0.35), 0))
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local label = Instance.new("TextLabel")
	label.Name = "ItemName"
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.fromScale(0.5, 1)
	label.Size = UDim2.new(1, -12, 0, 34)
	label.BackgroundTransparency = 0.25
	label.BackgroundColor3 = Color3.fromRGB(55, 34, 18)
	label.TextColor3 = Color3.fromRGB(255, 236, 196)
	label.TextScaled = true
	label.Text = item.name
	label.Parent = card
	addCorner(label, 10)

	table.insert(carouselCards, card)
	return card
end

local function tweenCard(card, layoutKey)
	if not card then
		return nil
	end
	local layout = slotLayout[layoutKey]
	local viewport = card:FindFirstChild("ModelViewport")
	if viewport then
		TweenService:Create(viewport, TweenInfo.new(SHOP_SLOT_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { ImageTransparency = layout.transparency }):Play()
	end
	local tween = TweenService:Create(card, TweenInfo.new(SHOP_SLOT_TWEEN, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = layout.position,
		Size = layout.size,
	})
	tween:Play()
	return tween
end

local function renderCarousel(direction)
	if #shopCatalog == 0 then
		clearCarouselCards()
		return
	end
	if not direction then
		clearCarouselCards()
		createDisplayCard(selectedShopIndex - 1, "previous")
		createDisplayCard(selectedShopIndex, "current")
		createDisplayCard(selectedShopIndex + 1, "next")
		return
	end

	local oldSelected = direction == "next" and wrapIndex(selectedShopIndex - 1) or wrapIndex(selectedShopIndex + 1)
	clearCarouselCards()
	if direction == "next" then
		local leaving = createDisplayCard(oldSelected - 1, "previous")
		local oldCurrent = createDisplayCard(oldSelected, "current")
		local newCurrent = createDisplayCard(selectedShopIndex, "next")
		local entering = createDisplayCard(selectedShopIndex + 1, "rightOut")
		tweenCard(leaving, "leftOut")
		tweenCard(oldCurrent, "previous")
		tweenCard(newCurrent, "current")
		local tween = tweenCard(entering, "next")
		if tween then
			local connection
			connection = tween.Completed:Connect(function()
				if connection then connection:Disconnect() end
				renderCarousel(nil)
			end)
		end
	else
		local entering = createDisplayCard(selectedShopIndex - 1, "leftOut")
		local newCurrent = createDisplayCard(selectedShopIndex, "previous")
		local oldCurrent = createDisplayCard(oldSelected, "current")
		local leaving = createDisplayCard(oldSelected + 1, "next")
		tweenCard(entering, "previous")
		tweenCard(newCurrent, "current")
		tweenCard(oldCurrent, "next")
		local tween = tweenCard(leaving, "rightOut")
		if tween then
			local connection
			connection = tween.Completed:Connect(function()
				if connection then connection:Disconnect() end
				renderCarousel(nil)
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
	renderCarousel(direction)
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
	shopOpenCount += 1
	refreshCatalogAndPreviews()
	shopFrame.Visible = true
	shopFrame.Position = UDim2.fromScale(1.25, 0.5)
	TweenService:Create(shopFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
	focusShopCamera()
	selectedShopIndex = 1
	updateShopSelection(nil)
end

closeShop = function()
	shopFrame.Visible = false
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
				local localPosition = zone.CFrame:PointToObjectSpace(root.Position)
				local halfSize = zone.Size * 0.5
				local stillInside = math.abs(localPosition.X) <= halfSize.X + 1 and math.abs(localPosition.Y) <= halfSize.Y + 3 and math.abs(localPosition.Z) <= halfSize.Z + 1
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
		if not getShopWorld() or not (getShopWorld() and getShopWorld():FindFirstChild("ShopOpenZone")) then
			connectShopOpenZone()
		end
		task.wait(2)
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
