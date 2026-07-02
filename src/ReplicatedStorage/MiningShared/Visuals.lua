local Visuals = {}

Visuals.Defaults = {
	ToolHandle = { material = Enum.Material.Wood, color = Color3.fromRGB(125, 78, 38), size = Vector3.new(0.35, 3.2, 0.35) },
	SandBlock = { material = Enum.Material.Sand, color = Color3.fromRGB(235, 205, 130) },
	PyramidBlock = { material = Enum.Material.Sandstone, color = Color3.fromRGB(214, 174, 94) },
	Water = { material = Enum.Material.Water, color = Color3.fromRGB(55, 170, 185) },
	Scorched = { material = Enum.Material.Slate, color = Color3.fromRGB(18, 18, 18) },
}

Visuals.Biomes = {
	white_sand = { color = Color3.fromRGB(238, 226, 196), material = Enum.Material.Sand },
	clay = { color = Color3.fromRGB(150, 86, 58), material = Enum.Material.Ground },
	mud = { color = Color3.fromRGB(104, 75, 49), material = Enum.Material.Mud },
	red_sand = { color = Color3.fromRGB(198, 94, 58), material = Enum.Material.Sand },
	grass = { color = Color3.fromRGB(75, 150, 70), material = Enum.Material.Grass },
}

Visuals.Decorations = {
	Tree = {
		trunk = { name = "Tree", size = Vector3.new(1.1, 5, 1.1), material = Enum.Material.Wood, color = Color3.fromRGB(95, 60, 32), yOffset = 2.5 },
		leaves = { name = "Leaves", size = Vector3.new(4.4, 3.2, 4.4), material = Enum.Material.Grass, color = Color3.fromRGB(55, 135, 55), yOffset = 5.4 },
	},
	Deadwood = { name = "Deadwood", size = Vector3.new(5, 0.6, 0.6), material = Enum.Material.Wood, color = Color3.fromRGB(92, 63, 39), yOffset = 0.3 },
	Cactus = { name = "Cactus", size = Vector3.new(1, 1, 1), material = Enum.Material.Grass, color = Color3.fromRGB(35, 135, 55) },
	Backpack = { name = "BackpackBody", size = Vector3.new(2, 2.4, 0.8), material = Enum.Material.Fabric },
	Pet = { bodyColor = Color3.fromRGB(210, 170, 75), eyeColor = Color3.fromRGB(30, 25, 15) },
}

Visuals.Shop = {
	SecureFloor = { material = Enum.Material.Metal, color = Color3.fromRGB(125, 135, 145) },
	WoodDeck = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(139, 92, 50) },
	CanvasCanopy = { material = Enum.Material.Fabric, color = Color3.fromRGB(205, 60, 45) },
	ShedPost = { material = Enum.Material.Wood, color = Color3.fromRGB(105, 68, 36) },
	ShopOpenZone = { material = Enum.Material.Neon, color = Color3.fromRGB(80, 210, 255) },
	ShopCounter = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(157, 107, 63) },
	ShopSign = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(118, 74, 34) },
	ShopPreviewBase = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(120, 75, 35) },
	ItemStand = { material = Enum.Material.WoodPlanks, color = Color3.fromRGB(91, 58, 31) },
}

return Visuals
