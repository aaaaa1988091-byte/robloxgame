local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

Remotes.Definitions = {
	SendNotification = "RemoteEvent",
	TeleportToShop = "RemoteEvent",
	ShopAction = "RemoteEvent",
	MiningEvent = "RemoteEvent",
	RewardEmojiEvent = "RemoteEvent",
	AbilityDraftEvent = "RemoteEvent",
	WeatherEvent = "RemoteEvent",
	PotionActionEvent = "RemoteEvent",
	QuestActionEvent = "RemoteEvent",
	GetQuestState = "RemoteFunction",
	GetShopCatalog = "RemoteFunction",
	GetShopState = "RemoteFunction",
}

function Remotes.get(name)
	local className = Remotes.Definitions[name]
	assert(className, "Unknown mining remote: " .. tostring(name))
	local remote = ReplicatedStorage:FindFirstChild(name)
	if remote and remote.ClassName ~= className then
		remote:Destroy()
		remote = nil
	end
	if not remote then
		remote = Instance.new(className)
		remote.Name = name
		remote.Parent = ReplicatedStorage
	end
	return remote
end

function Remotes.wait(name)
	local className = Remotes.Definitions[name]
	assert(className, "Unknown mining remote: " .. tostring(name))
	local remote = ReplicatedStorage:WaitForChild(name)
	assert(remote.ClassName == className, name .. " must be a " .. className)
	return remote
end

function Remotes.ensureAll()
	local result = {}
	for name in pairs(Remotes.Definitions) do
		result[name] = Remotes.get(name)
	end
	return result
end

return Remotes
