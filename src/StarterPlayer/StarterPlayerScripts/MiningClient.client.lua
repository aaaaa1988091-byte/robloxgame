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
shopFrame.Size = UDim2.fromOffset(320, 300)
shopFrame.Position = UDim2.new(0.5, -160, 0.5, -150)
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

local closeButton = makeButton("CloseButton", "X", UDim2.fromOffset(36, 36), UDim2.new(1, -44, 0, 8), shopFrame)
closeButton.BackgroundColor3 = Color3.fromRGB(120, 45, 45)
closeButton.MouseButton1Click:Connect(function()
	shopFrame.Visible = false
end)

local actions = {
	{ "SellSand", "出售沙子 (+5/顆)", "Sell" },
	{ "BuyWoodPickaxe", "購買木鎬 $150", "BuyTool", "木鎬" },
	{ "BuyIronPickaxe", "購買鐵鎬 $500", "BuyTool", "鐵鎬" },
	{ "BuyDiamondPickaxe", "購買鑽石鎬 $1500", "BuyTool", "鑽石鎬" },
	{ "BuyBomb", "購買炸彈 $50", "BuyBomb" },
}

for index, action in ipairs(actions) do
	local button = makeButton(action[1], action[2], UDim2.new(1, -32, 0, 38), UDim2.fromOffset(16, 56 + (index - 1) * 44), shopFrame)
	button.BackgroundColor3 = Color3.fromRGB(92, 62, 34)
	button.MouseButton1Click:Connect(function()
		shopActionEvent:FireServer(action[3], action[4])
	end)
end

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
				shopFrame.Visible = true
			end
		end)
	elseif prompt.Name == "ShopItemPrompt" then
		prompt.Triggered:Connect(function(triggeringPlayer)
			if triggeringPlayer ~= player then
				return
			end
			local display = prompt.Parent
			shopActionEvent:FireServer(display:GetAttribute("ShopAction"), display:GetAttribute("ShopItem"))
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
