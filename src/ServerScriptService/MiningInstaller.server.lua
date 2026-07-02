local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local MiningShared = ReplicatedStorage:WaitForChild("MiningShared")
local Remotes = require(MiningShared:WaitForChild("Remotes"))
local Config = require(MiningShared:WaitForChild("Config"))

local INSTALLER_TAG = "MiningInstallerManaged"

local function getOrCreate(parent, className, name)
	local instance = parent:FindFirstChild(name)
	if instance and instance.ClassName ~= className then
		instance:Destroy()
		instance = nil
	end
	if not instance then
		instance = Instance.new(className)
		instance.Name = name
		instance:SetAttribute(INSTALLER_TAG, true)
		instance.Parent = parent
	end
	return instance
end

local function ensureServerStoragePackage()
	local editableModels = getOrCreate(ServerStorage, "Folder", "MiningWorldEditableModels")
	for _, name in ipairs({ "Tree", "Cactus", "Deadwood", "Pyramid", "Backpack" }) do
		getOrCreate(editableModels, "Folder", name)
	end
	getOrCreate(ServerStorage, "Folder", "MiningItemModels")
	local sounds = getOrCreate(ServerStorage, "Folder", "MiningConfigurableSounds")
	local defaults = {
		MiningImpactSound = "rbxassetid://12221976",
		MoneySound = "rbxassetid://12222124",
		ChestMineSound = "rbxassetid://12221967",
		LightningSound = "rbxassetid://9113420775",
		BombSound = "rbxassetid://138186576",
		PurchaseSound = "rbxassetid://12222253",
		ClaimSound = "rbxassetid://12222253",
	}
	for name, soundId in pairs(defaults) do
		local sound = getOrCreate(sounds, "Sound", name)
		sound.SoundId = soundId
		sound.Volume = 0.35
		sound.RollOffMaxDistance = 60
	end
	local assets = getOrCreate(ServerStorage, "Folder", "MiningAssets")
	local effects = getOrCreate(assets, "Folder", "MiningEffects")
	local debrisConfig = getOrCreate(effects, "Folder", "MiningDebrisConfig")
	local debrisCount = getOrCreate(debrisConfig, "IntValue", "DebrisCount")
	debrisCount.Value = Config.MiningDebrisCount
end

local function ensureRuntimeFolders()
	getOrCreate(Workspace, "Folder", "DynamicMiningWorld")
	getOrCreate(Workspace, "Folder", "LocalShopPreviewModels")
	getOrCreate(ServerScriptService, "Folder", "MiningServer")
	local hud = getOrCreate(StarterGui, "ScreenGui", "MiningHud")
	hud.ResetOnSpawn = false
end

Remotes.ensureAll()
ensureServerStoragePackage()
ensureRuntimeFolders()

local nextRefresh = getOrCreate(ReplicatedStorage, "IntValue", "NextWorldRefreshTime")
nextRefresh.Value = os.time() + Config.WorldRefreshSeconds

script:SetAttribute("InstallComplete", true)
warn("MiningInstaller finished. You can copy ReplicatedStorage.MiningShared, ServerScriptService.MiningServer, StarterGui.MiningHud, ServerStorage mining folders, and Workspace.MiningShopWorld after Play starts. Runtime continues from MiningServer/Main.server.lua.")
