local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Network = require(ReplicatedStorage:WaitForChild("NetworkBootstrap"))

local gui = Instance.new("ScreenGui")
gui.Name = "HUD_ScreenGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

local topBar = Instance.new("TextLabel")
topBar.Name = "MatchScoreBar"
topBar.AnchorPoint = Vector2.new(0.5, 0)
topBar.Position = UDim2.fromScale(0.5, 0.02)
topBar.Size = UDim2.fromScale(0.72, 0.06)
topBar.BackgroundTransparency = 0.25
topBar.TextScaled = true
topBar.TextColor3 = Color3.new(1, 1, 1)
topBar.Text = "Blue: 0% ===== (05:00) ===== Red: 0%"
topBar.Parent = gui

local weavePanel = Instance.new("TextLabel")
weavePanel.Name = "WeavePreviewPanel"
weavePanel.AnchorPoint = Vector2.new(1, 1)
weavePanel.Position = UDim2.fromScale(0.98, 0.96)
weavePanel.Size = UDim2.fromScale(0.42, 0.14)
weavePanel.BackgroundTransparency = 0.2
weavePanel.TextScaled = true
weavePanel.TextColor3 = Color3.new(1, 1, 1)
weavePanel.Text = "【左手/環境】 --  ===> 【編織預覽】 <=== -- 【右手/術式】"
weavePanel.Parent = gui

local function formatTime(seconds)
	local minutes = math.floor(seconds / 60)
	local remainder = seconds % 60
	return string.format("%02d:%02d", minutes, remainder)
end

Network.MatchStateUpdate.OnClientEvent:Connect(function(state)
	local blueScore = state.Scores and state.Scores.Blue or 0
	local redScore = state.Scores and state.Scores.Red or 0
	topBar.Text = string.format("Blue: %d%% ===== (%s) ===== Red: %d%%", blueScore, formatTime(state.RemainingSeconds or 0), redScore)
end)

player:GetAttributeChangedSignal("LeftHandElement"):Connect(function()
	local material = player:GetAttribute("LeftHandElement") or "--"
	local modifier = player:GetAttribute("RightHandModifier") or "--"
	weavePanel.Text = string.format("【左手/環境】 %s ===> 【編織預覽】 %s + %s <=== %s 【右手/術式】", material, material, modifier, modifier)
end)
