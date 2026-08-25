local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ElementDatabase = require(ReplicatedStorage:WaitForChild("ElementDatabase"))
local Network = require(ReplicatedStorage:WaitForChild("NetworkBootstrap"))

local PROJECTILE_LIFETIME_SECONDS = 8
local DEFAULT_PROJECTILE_SPEED = 120
local FIZZLE_KNOCKBACK = 12

local lastCastAtByPlayer = {}

local function getRootPart(player)
	local character = player.Character
	if not character then
		return nil
	end

	return character:FindFirstChild("HumanoidRootPart")
end

local function getModifier(player, requestedModifier)
	local equippedModifier = player:GetAttribute("RightHandModifier")
	local modifier = requestedModifier or equippedModifier
	if typeof(modifier) ~= "string" or not ElementDatabase.Modifiers[modifier] then
		return nil
	end

	return modifier
end

local function isOnCooldown(player, modifier)
	local cooldown = ElementDatabase.Modifiers[modifier].Cooldown
	local now = os.clock()
	local lastCastAt = lastCastAtByPlayer[player.UserId] or 0
	if now - lastCastAt < cooldown then
		return true
	end

	lastCastAtByPlayer[player.UserId] = now
	return false
end

local function createFallbackProjectile(material, origin, direction)
	local projectile = Instance.new("Part")
	projectile.Name = material .. "_Projectile"
	projectile.Shape = Enum.PartType.Ball
	projectile.Size = Vector3.new(2, 2, 2)
	projectile.Color = ElementDatabase.Materials[material].Color
	projectile.Material = Enum.Material.Neon
	projectile.CanCollide = false
	projectile.CFrame = CFrame.new(origin)
	projectile.AssemblyLinearVelocity = direction.Unit * DEFAULT_PROJECTILE_SPEED
	return projectile
end

local function spawnCombination(player, material, modifier, combination, origin, direction)
	local prefab = Network.PrefabFolder:FindFirstChild(combination.Prefab)
	local projectile = prefab and prefab:Clone() or createFallbackProjectile(material, origin, direction)

	projectile.Name = combination.Prefab
	projectile:SetAttribute("OwnerUserId", player.UserId)
	projectile:SetAttribute("ElementType", material)
	projectile:SetAttribute("Modifier", modifier)
	projectile:SetAttribute("CombinationName", combination.Name)
	projectile:SetAttribute("Effect", combination.Effect)
	projectile:SetAttribute("Damage", ElementDatabase.Materials[material].BaseDamage * combination.DamageMultiplier)

	if projectile:IsA("BasePart") then
		projectile.CFrame = CFrame.new(origin)
		projectile.AssemblyLinearVelocity = direction.Unit * DEFAULT_PROJECTILE_SPEED
	elseif projectile:IsA("Model") then
		projectile:PivotTo(CFrame.new(origin, origin + direction))
	end

	projectile.Parent = workspace
	Debris:AddItem(projectile, PROJECTILE_LIFETIME_SECONDS)
end

local function spawnFizzle(player, origin, direction)
	local rootPart = getRootPart(player)
	if rootPart then
		rootPart.AssemblyLinearVelocity += -direction.Unit * FIZZLE_KNOCKBACK
	end

	local fizzle = Instance.new("Part")
	fizzle.Name = "Fizzle_BlackSmoke"
	fizzle.Anchored = true
	fizzle.CanCollide = false
	fizzle.Transparency = 1
	fizzle.CFrame = CFrame.new(origin)
	fizzle.Parent = workspace

	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "ComedicBlackSmoke"
	smoke.Color = ColorSequence.new(Color3.new(0, 0, 0))
	smoke.Lifetime = NumberRange.new(0.5, 1.2)
	smoke.Rate = 120
	smoke.Speed = NumberRange.new(8, 14)
	smoke.Parent = fizzle

	local sound = Instance.new("Sound")
	sound.Name = "ScreamingChickenFizzle"
	-- Replace this placeholder with an approved Roblox audio asset before production publishing.
	sound.SoundId = "rbxassetid://0"
	sound.Volume = 0.8
	sound.Parent = fizzle
	sound:Play()

	Debris:AddItem(fizzle, 2)
end

Network.FireWeave.OnServerEvent:Connect(function(player, requestedModifier, aimDirection)
	local material = player:GetAttribute("LeftHandElement")
	local modifier = getModifier(player, requestedModifier)
	local rootPart = getRootPart(player)
	if typeof(material) ~= "string" or not ElementDatabase.Materials[material] or not modifier or not rootPart then
		return
	end

	if typeof(aimDirection) ~= "Vector3" or aimDirection.Magnitude < 0.1 then
		aimDirection = rootPart.CFrame.LookVector
	end

	if isOnCooldown(player, modifier) then
		return
	end

	local origin = rootPart.Position + aimDirection.Unit * 4
	local key = material .. "_" .. modifier
	local combination = ElementDatabase.Combinations[key]
	if combination then
		spawnCombination(player, material, modifier, combination, origin, aimDirection)
	else
		spawnFizzle(player, origin, aimDirection)
	end
end)
