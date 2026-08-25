local ElementDatabase = {
	Materials = {
		Iron = {
			Color = Color3.fromRGB(120, 120, 120),
			Tags = { "Absorbable", "Conductor", "Meltable" },
			BaseDamage = 15,
		},
		Water = {
			Color = Color3.fromRGB(0, 100, 255),
			Tags = { "Absorbable", "Conductor" },
			BaseDamage = 5,
		},
		Magma = {
			Color = Color3.fromRGB(255, 50, 0),
			Tags = { "Absorbable", "Damaging" },
			BaseDamage = 25,
		},
		Shadow = {
			Color = Color3.fromRGB(10, 10, 10),
			Tags = { "Absorbable", "Ethereal" },
			BaseDamage = 10,
		},
	},
	Modifiers = {
		Spread = {
			Cooldown = 3,
			Behavior = "DeployWall",
			ManaCost = 20,
		},
		Bounce = {
			Cooldown = 4,
			Behavior = "Ricochet",
			ManaCost = 15,
		},
		GravityInvert = {
			Cooldown = 8,
			Behavior = "LiftTarget",
			ManaCost = 30,
		},
	},
	Combinations = {
		Water_GravityInvert = {
			Name = "窒息水牢",
			DamageMultiplier = 1.5,
			Prefab = "Water_Sphere",
			Effect = "Stun",
		},
		Iron_Spread = {
			Name = "鐵幕迷宮",
			DamageMultiplier = 0,
			Prefab = "Shield_Wall",
			Effect = "Block",
		},
	},
}

return ElementDatabase
