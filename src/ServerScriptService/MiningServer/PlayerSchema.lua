local PlayerSchema = {}

PlayerSchema.Leaderstats = {
	{ name = "Coins", className = "IntValue", default = 0 },
	{ name = "TotalBlocks", className = "IntValue", default = 0 },
	{ name = "Sand", className = "IntValue", default = 0 },
}

PlayerSchema.PlayerValues = {
	{ name = "MaxSand", className = "IntValue", default = 20 },
	{ name = "CurrentPickaxe", className = "StringValue", default = "拳頭" },
	{ name = "BombCount", className = "IntValue", default = 0 },
	{ name = "ClusterBombCount", className = "IntValue", default = 0 },
	{ name = "HasSandPet", className = "BoolValue", default = false },
}

PlayerSchema.Potions = { "Strength", "Luck", "Speed" }

local function getOrCreateValue(parent, spec)
	local value = parent:FindFirstChild(spec.name)
	if value and value.ClassName ~= spec.className then
		value:Destroy()
		value = nil
	end
	if not value then
		value = Instance.new(spec.className)
		value.Name = spec.name
		value.Value = spec.default
		value.Parent = parent
	end
	return value
end

function PlayerSchema.ensure(player, overrides)
	overrides = overrides or {}
	local result = {}
	local leaderstats = player:FindFirstChild("leaderstats") or Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	result.leaderstats = leaderstats
	for _, spec in ipairs(PlayerSchema.Leaderstats) do
		result[spec.name] = getOrCreateValue(leaderstats, spec)
	end
	for _, spec in ipairs(PlayerSchema.PlayerValues) do
		local withOverride = table.clone(spec)
		if overrides[spec.name] ~= nil then
			withOverride.default = overrides[spec.name]
		end
		result[spec.name] = getOrCreateValue(player, withOverride)
	end
	local potions = player:FindFirstChild("Potions") or Instance.new("Folder")
	potions.Name = "Potions"
	potions.Parent = player
	result.Potions = potions
	for _, potionName in ipairs(PlayerSchema.Potions) do
		result[potionName] = getOrCreateValue(potions, { name = potionName, className = "IntValue", default = 1 })
	end
	return result
end

return PlayerSchema
