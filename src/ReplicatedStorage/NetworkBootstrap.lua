local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NETWORK_FOLDER_NAME = "Network_Events"
local PREFAB_FOLDER_NAME = "Projectiles_Prefab"
local REQUIRED_REMOTES = {
	TryAbsorb = "RemoteFunction",
	FireWeave = "RemoteEvent",
	MatchStateUpdate = "RemoteEvent",
}

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if folder then
		return folder
	end

	if not RunService:IsServer() then
		return parent:WaitForChild(name)
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function getOrCreateRemote(parent, className, name)
	local remote = parent:FindFirstChild(name)
	if remote then
		assert(remote:IsA(className), string.format("%s must be a %s", name, className))
		return remote
	end

	if not RunService:IsServer() then
		remote = parent:WaitForChild(name)
		assert(remote:IsA(className), string.format("%s must be a %s", name, className))
		return remote
	end

	remote = Instance.new(className)
	remote.Name = name
	remote.Parent = parent
	return remote
end

local networkFolder = getOrCreateFolder(ReplicatedStorage, NETWORK_FOLDER_NAME)
local prefabFolder = getOrCreateFolder(ReplicatedStorage, PREFAB_FOLDER_NAME)

local remotes = {
	NetworkFolder = networkFolder,
	PrefabFolder = prefabFolder,
}

for remoteName, className in pairs(REQUIRED_REMOTES) do
	remotes[remoteName] = getOrCreateRemote(networkFolder, className, remoteName)
end

return remotes
