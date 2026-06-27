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
local SHOP_CARD_SPACING = 250

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
		gui = starterTemplate:Clone()
	else
		gui = Instance.new("ScreenGui")
		gui.Name = "MiningHud"
		gui.ResetOnSpawn = false
	end
	gui.Parent = playerGui
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
shopFrame.Size = UDim2.fromOffset(620, 300)
shopFrame.Position = UDim2.new(0.5, -310, 1, -324)
shopFrame.BackgroundColor3 = Color3.fromRGB(64, 42, 24)
shopFrame.Visible = false
shopFrame.Parent = gui
addCorner(shopFrame, 16)
end

local title, titleCreated = getOrCreateChild(shopFrame, "TextLabel", "Title")
if titleCreated then
title.Text = "礦工棚子商店"
title.Size = UDim2.new(1, -48, 0, 44)
title.Position = UDim2.fromOffset(8, 8)
title.BackgroundTransparency = 1
title.TextColor3 = Color3.fromRGB(255, 235, 190)
title.TextScaled = true
title.Parent = shopFrame
end

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
descriptionLabel.Size = UDim2.new(1, -32, 0, 72)
descriptionLabel.Position = UDim2.fromOffset(16, 60)
descriptionLabel.BackgroundTransparency = 0.25
descriptionLabel.BackgroundColor3 = Color3.fromRGB(45, 30, 18)
descriptionLabel.TextColor3 = Color3.fromRGB(255, 235, 190)
descriptionLabel.TextWrapped = true
descriptionLabel.TextScaled = true
descriptionLabel.Parent = shopFrame
addCorner(descriptionLabel, 12)
end

local carousel, carouselCreated = getOrCreateChild(shopFrame, "Frame", "ItemCarousel")
if carouselCreated then
	carousel.Size = UDim2.new(1, -32, 0, 80)
	carousel.Position = UDim2.fromOffset(16, 142)
	carousel.BackgroundColor3 = Color3.fromRGB(38, 25, 15)
	carousel.BackgroundTransparency = 0.08
	carousel.ClipsDescendants = true
	addCorner(carousel, 14)
end

local previousButton = makeButton("PreviousItem", "◀", UDim2.fromOffset(48, 42), UDim2.fromOffset(16, 238), shopFrame)
previousButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local buyButton = makeButton("BuySelected", "購買", UDim2.fromOffset(420, 42), UDim2.fromOffset(100, 238), shopFrame)
buyButton.BackgroundColor3 = Color3.fromRGB(35, 95, 55)

local nextButton = makeButton("NextItem", "▶", UDim2.fromOffset(48, 42), UDim2.fromOffset(556, 238), shopFrame)
nextButton.BackgroundColor3 = Color3.fromRGB(92, 62, 34)

local function getShopWorld()
	return Workspace:FindFirstChild("MiningShopWorld")
end

local itemCards = {}
local shopOpenCount = 0

local function buildCarouselCards()
	for _, child in ipairs(carousel:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	table.clear(itemCards)
	for index, item in ipairs(shopCatalog) do
		local card = Instance.new("TextLabel")
		card.Name = "ItemCard_" .. item.id
		card.AnchorPoint = Vector2.new(0.5, 0.5)
		card.Size = UDim2.fromOffset(210, 58)
		card.Position = UDim2.fromOffset(carousel.AbsoluteSize.X + index * SHOP_CARD_SPACING, 40)
		card.BackgroundColor3 = Color3.fromRGB(75, 50, 28)
		card.TextColor3 = Color3.fromRGB(255, 235, 190)
		card.TextScaled = true
		card.Text = item.name .. ((item.price and item.price > 0) and ("\n$" .. item.price) or "")
		card.Parent = carousel
		addCorner(card, 12)
		table.insert(itemCards, card)
	end
end

local function setPreviewVisible(index)
	for _, descendant in ipairs(localPreviewFolder:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("ShopIndex") then
			descendant.Transparency = (descendant:GetAttribute("ShopIndex") == index) and 0 or 0.65
		end
	end
end

local function updateCarousel(animated)
	local centerX = math.max(160, carousel.AbsoluteSize.X / 2)
	for index, card in ipairs(itemCards) do
		local offset = (index - selectedShopIndex) * SHOP_CARD_SPACING
		local props = {
			Position = UDim2.fromOffset(centerX + offset, 40),
			BackgroundColor3 = (index == selectedShopIndex) and Color3.fromRGB(130, 82, 38) or Color3.fromRGB(55, 36, 22),
			TextTransparency = math.abs(index - selectedShopIndex) > 2 and 0.55 or 0,
		}
		if animated then
			TweenService:Create(card, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
		else
			for prop, value in pairs(props) do card[prop] = value end
		end
	end
end

local function updateShopSelection(animated)
	local item = shopCatalog[selectedShopIndex]
	if not item then
		return
	end
	title.Text = item.name .. ((item.price and item.price > 0) and ("  $" .. item.price) or "")
	descriptionLabel.Text = item.description
	buyButton.Text = (item.action == "Sell") and "出售沙子" or "購買 / 使用"
	setPreviewVisible(selectedShopIndex)
	updateCarousel(animated)
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
	shopFrame.Position = UDim2.new(1, 24, 1, -324)
	TweenService:Create(shopFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, -310, 1, -324) }):Play()
	focusShopCamera()
	buildCarouselCards()
	selectedShopIndex = 1
	updateShopSelection(false)
	task.defer(function() updateCarousel(true) end)
end

closeShop = function()
	shopFrame.Visible = false
	restoreCamera()
end

previousButton.MouseButton1Click:Connect(function()
	selectedShopIndex = ((selectedShopIndex - 2) % #shopCatalog) + 1
	updateShopSelection(true)
end)

nextButton.MouseButton1Click:Connect(function()
	selectedShopIndex = (selectedShopIndex % #shopCatalog) + 1
	updateShopSelection(true)
end)

buyButton.MouseButton1Click:Connect(function()
	local item = shopCatalog[selectedShopIndex]
	if item then
		shopActionEvent:FireServer(item.id)
	end
end)

updateShopSelection(true)

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
	back.BackgroundColor3 = Color3.fromRGB(25, 20, 15)
	back.BackgroundTransparency = 0.15
	back.Parent = surfaceGui
	addCorner(back, 6)

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(percentRemaining, 1)
	bar.BackgroundColor3 = Color3.fromRGB(255, 210, 90)
	bar.Parent = back
	addCorner(bar, 6)
	activeSurfaceProgress = surfaceGui
end

local selectionBox = Instance.new("SelectionBox")
selectionBox.Name = "TargetBlockHighlight"
selectionBox.Color3 = Color3.fromRGB(255, 245, 120)
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
		marker.Color = Color3.fromRGB(255, 185, 60)
		marker.Transparency = 0.15 + alpha * 0.45
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

Lighting.FogColor = Color3.fromRGB(230, 210, 170)
Lighting.FogStart = 180
Lighting.FogEnd = 650

local function isInsideShopZone()
	local shopWorld = getShopWorld()
	local zone = shopWorld and shopWorld:FindFirstChild("ShopOpenZone")
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not zone or not root then
		return false
	end
	local flatDistance = Vector3.new(root.Position.X - zone.Position.X, 0, root.Position.Z - zone.Position.Z).Magnitude
	return flatDistance <= 18
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
