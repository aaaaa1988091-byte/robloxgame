local PlayerDataService = {}

local context = {}

function PlayerDataService.configure(newContext)
	context = newContext or {}
end

function PlayerDataService.ensurePlayerValues(player, overrides)
	local schema = context.playerSchema or require(script.Parent:WaitForChild("PlayerSchema"))
	return schema.ensure(player, overrides)
end

function PlayerDataService.serializePotions(potionsFolder)
	local result = {}
	if not potionsFolder then
		return result
	end
	for _, child in ipairs(potionsFolder:GetChildren()) do
		if child:IsA("IntValue") then
			result[child.Name] = child.Value
		end
	end
	return result
end

function PlayerDataService.serializeOwnedTools(ownedToolsFolder)
	local result = {}
	if not ownedToolsFolder then
		return result
	end
	for _, child in ipairs(ownedToolsFolder:GetChildren()) do
		if child:IsA("BoolValue") and child.Value then
			table.insert(result, child.Name)
		end
	end
	return result
end

return PlayerDataService
