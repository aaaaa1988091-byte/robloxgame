local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local sendNotificationEvent = ReplicatedStorage:WaitForChild("SendNotification")
local teleportEvent = ReplicatedStorage:WaitForChild("TeleportToShop")
local shopActionEvent = ReplicatedStorage:WaitForChild("ShopAction")
local miningEvent = ReplicatedStorage:WaitForChild("MiningEvent")
local shopCatalogFunction = ReplicatedStorage:WaitForChild("GetShopCatalog")

local gui = Instance.new("ScreenGui")
gui.Name = "MiningHud"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

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
	return button
end

local homeButton = makeButton("TeleportHomeButton", "一鍵回城", UDim2.fromOffset(120, 42), UDim2.fromOffset(16, 160), gui)
homeButton.MouseButton1Click:Connect(function()
	teleportEvent:FireServer()
end)

local shopFrame = Instance.new("Frame")
shopFrame.Name = "ShopFrame"
shopFrame.Size = UDim2.fromOffset(380, 240)
shopFrame.Position = UDim2.new(0.5, -190, 1, -260)
shopFrame.BackgroundColor3 = Color3.fromRGB(64, 42, 24)
shopFrame.Visible = false
shopFrame.Parent = gui

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
local previousCameraType = nil
local previousCameraSubject = nil
local previousCameraCFrame = nil

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
	local shopWorld = getShopWorld()
	local previewFolder = shopWorld and shopWorld:FindFirstChild("ShopPreviewModels")
	if not previewFolder then
		return
	end
	for _, descendant in ipairs(previewFolder:GetDescendants()) do
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
	if not camera or not anchor then
		return
	end
	previousCameraType = camera.CameraType
	previousCameraSubject = camera.CameraSubject
	previousCameraCFrame = camera.CFrame
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = anchor.CFrame
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

local progressBar = Instance.new("Frame")
progressBar.Name = "Bar"
progressBar.Size = UDim2.fromScale(1, 1)
progressBar.BackgroundColor3 = Color3.fromRGB(252, 203, 96)
progressBar.Parent = progressFrame

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

local function hookShopPrompt(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end
	if prompt.Name == "OpenShopPrompt" then
		prompt.Triggered:Connect(function(triggeringPlayer)
			if triggeringPlayer == player then
				openShop()
			end
		end)
	end
end

for _, descendant in ipairs(Workspace:GetDescendants()) do
	hookShopPrompt(descendant)
end
Workspace.DescendantAdded:Connect(hookShopPrompt)

mouse.Move:Connect(function()
	updateHighlight(getMineableTarget())
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isMining = true
		task.spawn(function()
			while isMining do
				local target = getMineableTarget()
				updateHighlight(target)
				if target then
					miningEvent:FireServer(target)
				end
				task.wait(0.2)
			end
		end)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		isMining = false
	end
end)

miningEvent.OnClientEvent:Connect(function(_targetPart, currentHealth, maxHealth)
	if currentHealth <= 0 or maxHealth <= 0 then
		progressFrame.Visible = false
		return
	end
	local percentRemaining = math.clamp(currentHealth / maxHealth, 0, 1)
	progressBar.Size = UDim2.fromScale(percentRemaining, 1)
	progressFrame.Visible = true
end)
