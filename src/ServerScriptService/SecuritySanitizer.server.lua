local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ElementDatabase = require(ReplicatedStorage:WaitForChild("ElementDatabase"))
local Network = require(ReplicatedStorage:WaitForChild("NetworkBootstrap"))

local ABSORB_RANGE_STUDS = 20
local DEFAULT_MODIFIER = "Spread"

local function getRootPart(player)
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function isKnownMaterial(elementType)
	return typeof(elementType) == "string" and ElementDatabase.Materials[elementType] ~= nil
end

local function ensurePlayerDefaults(player)
	if player:GetAttribute("RightHandModifier") == nil then
		player:SetAttribute("RightHandModifier", DEFAULT_MODIFIER)
	end
end

local function canAbsorb(player, target)
	if typeof(target) ~= "Instance" or not target:IsA("BasePart") then
		return false, "Target must be a BasePart"
	end

	if not target:IsDescendantOf(workspace) then
		return false, "Target is not in the workspace"
	end

	if not CollectionService:HasTag(target, "Absorbable") then
		return false, "Target is not absorbable"
	end

	local elementType = target:GetAttribute("ElementType")
	if not isKnownMaterial(elementType) then
		return false, "Unknown element type"
	end

	local rootPart = getRootPart(player)
	if not rootPart then
		return false, "Character is not ready"
	end

	local distance = (rootPart.Position - target.Position).Magnitude
	if distance >= ABSORB_RANGE_STUDS then
		return false, "Target is out of range"
	end

	return true, elementType
end

Players.PlayerAdded:Connect(ensurePlayerDefaults)
for _, player in ipairs(Players:GetPlayers()) do
	ensurePlayerDefaults(player)
end

Network.TryAbsorb.OnServerInvoke = function(player, target)
	local success, result = canAbsorb(player, target)
	if not success then
		return {
			Success = false,
			Reason = result,
		}
	end

	player:SetAttribute("LeftHandElement", result)
	return {
		Success = true,
		ElementType = result,
		Material = ElementDatabase.Materials[result],
	}
end
