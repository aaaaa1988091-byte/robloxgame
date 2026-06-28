local Visuals = require(script.Parent:WaitForChild("Visuals"))

local ModelFactory = {}

local function setupPart(part, model, anchored)
	part.Anchored = anchored ~= false
	part.CanCollide = false
	part.Parent = model
	return part
end

function ModelFactory.createCatalogModel(parent, itemData, pivotCFrame, options)
	options = options or {}
	local visual = itemData.model or {}
	local model = Instance.new("Model")
	model.Name = options.name or (itemData.id .. "Model")
	model.Parent = parent

	local mainPart
	local source = options.sourceInstance
	if not source and itemData.sourceName and options.sourceFolder then
		source = options.sourceFolder:FindFirstChild(itemData.sourceName)
	end
	if source then
		local clone = source:Clone()
		clone.Name = "DisplayModel"
		clone.Parent = model
		mainPart = clone:IsA("BasePart") and clone or clone:FindFirstChildWhichIsA("BasePart", true)
		if mainPart then
			model.PrimaryPart = mainPart
			model:PivotTo(pivotCFrame)
		end
	elseif visual.kind == "pickaxe" then
		local handleStyle = Visuals.Defaults.ToolHandle
		mainPart = setupPart(Instance.new("Part"), model, true)
		mainPart.Name = "Handle"
		mainPart.Size = handleStyle.size
		mainPart.Material = handleStyle.material
		mainPart.Color = handleStyle.color
		mainPart.CFrame = pivotCFrame * CFrame.Angles(0, 0, math.rad(25))

		local head = setupPart(Instance.new("Part"), model, true)
		head.Name = "Head"
		head.Size = Vector3.new(2.4, 0.35, 0.35)
		head.Material = visual.material or Enum.Material.Wood
		head.Color = visual.color or Color3.fromRGB(150, 100, 50)
		head.CFrame = mainPart.CFrame * CFrame.new(0, 1.35, 0)
	elseif visual.kind == "bomb" then
		mainPart = setupPart(Instance.new("Part"), model, true)
		mainPart.Name = "BombBody"
		mainPart.Shape = Enum.PartType.Ball
		mainPart.Size = Vector3.new(2.2, 2.2, 2.2)
		mainPart.Material = visual.material or Enum.Material.Slate
		mainPart.Color = visual.color or Color3.fromRGB(25, 25, 25)
		mainPart.CFrame = pivotCFrame
	elseif visual.kind == "backpack" then
		mainPart = setupPart(Instance.new("Part"), model, true)
		mainPart.Name = "BackpackBody"
		mainPart.Size = Vector3.new(2.2, 2.8, 1.2)
		mainPart.Material = visual.material or Enum.Material.Fabric
		mainPart.Color = visual.color or Color3.fromRGB(85, 135, 210)
		mainPart.CFrame = pivotCFrame
	else
		mainPart = setupPart(Instance.new("Part"), model, true)
		mainPart.Name = "DisplayBlock"
		mainPart.Size = visual.size or Vector3.new(2, 2, 2)
		mainPart.Material = visual.material or Visuals.Defaults.SandBlock.material
		mainPart.Color = visual.color or Visuals.Defaults.SandBlock.color
		mainPart.CFrame = pivotCFrame
	end

	model.PrimaryPart = mainPart
	return model
end

function ModelFactory.createToolFallback(toolName, autoMine)
	local handleStyle = Visuals.Defaults.ToolHandle
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 3, 0.4)
	handle.Material = handleStyle.material
	handle.Color = handleStyle.color

	local head = Instance.new("Part")
	head.Name = "ToolHead"
	head.Size = autoMine and Vector3.new(1.2, 1.2, 1.2) or Vector3.new(2, 0.35, 0.35)
	head.Material = (toolName == "鐵鎬" or toolName == "鐵鑽頭") and Enum.Material.Metal or ((toolName == "鑽石鎬" or toolName == "鑽石鑽頭") and Enum.Material.Neon or Enum.Material.Wood)
	head.Color = (toolName == "鐵鎬" or toolName == "鐵鑽頭") and Color3.fromRGB(180, 185, 190) or ((toolName == "鑽石鎬" or toolName == "鑽石鑽頭") and Color3.fromRGB(45, 210, 235) or Color3.fromRGB(126, 78, 36))
	head.Shape = autoMine and Enum.PartType.Ball or Enum.PartType.Block
	head.CFrame = handle.CFrame * CFrame.new(0, 1.35, 0)
	head.Parent = handle

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = head
	weld.Parent = handle
	return handle
end

function ModelFactory.createBombHandle(radius)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Shape = Enum.PartType.Ball
	handle.Size = Vector3.new(1.6, 1.6, 1.6)
	handle.Material = (radius > 1) and Enum.Material.Metal or Enum.Material.Slate
	handle.Color = (radius > 1) and Color3.fromRGB(120, 30, 30) or Color3.fromRGB(25, 25, 25)
	return handle
end

function ModelFactory.createFallbackTree(parent, basePosition, blockSize)
	local style = Visuals.Decorations.Tree
	local trunk = Instance.new("Part")
	trunk.Name = style.trunk.name
	trunk.Size = style.trunk.size
	trunk.Position = basePosition + Vector3.new(0, blockSize / 2 + style.trunk.yOffset, 0)
	trunk.Anchored = true
	trunk.Material = style.trunk.material
	trunk.Color = style.trunk.color
	trunk.Parent = parent

	local leaves = Instance.new("Part")
	leaves.Name = style.leaves.name
	leaves.Shape = Enum.PartType.Ball
	leaves.Size = style.leaves.size
	leaves.Position = basePosition + Vector3.new(0, blockSize / 2 + style.leaves.yOffset, 0)
	leaves.Anchored = true
	leaves.Material = style.leaves.material
	leaves.Color = style.leaves.color
	leaves.Parent = parent
	return trunk, leaves
end

function ModelFactory.createFallbackDeadwood(parent, basePosition, blockSize)
	local style = Visuals.Decorations.Deadwood
	local log = Instance.new("Part")
	log.Name = style.name
	log.Size = style.size
	log.CFrame = CFrame.new(basePosition + Vector3.new(0, blockSize / 2 + style.yOffset, 0)) * CFrame.Angles(math.rad(math.random(-8, 8)), math.rad(math.random(0, 180)), math.rad(math.random(-8, 8)))
	log.Anchored = true
	log.Material = style.material
	log.Color = style.color
	log.Parent = parent
	return log
end

function ModelFactory.createFallbackCactus(parent, basePosition, blockSize, height)
	local style = Visuals.Decorations.Cactus
	local cactus = Instance.new("Part")
	cactus.Name = style.name
	cactus.Size = Vector3.new(style.size.X, height, style.size.Z)
	cactus.Position = basePosition + Vector3.new(0, blockSize / 2 + cactus.Size.Y / 2, 0)
	cactus.Anchored = true
	cactus.Material = style.material
	cactus.Color = style.color
	cactus.Parent = parent
	return cactus
end

function ModelFactory.applyStyle(part, style)
	if not part or not style then return end
	part.Material = style.material or part.Material
	part.Color = style.color or part.Color
end

return ModelFactory
