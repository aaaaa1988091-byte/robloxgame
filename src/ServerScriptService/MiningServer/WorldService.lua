local WorldService = {}

local context = {}

function WorldService.configure(newContext)
	context = newContext or {}
end

function WorldService.ensureEditableAssetFolders()
	local serverStorage = context.serverStorage or game:GetService("ServerStorage")
	local assets = serverStorage:FindFirstChild("MiningWorldEditableModels") or Instance.new("Folder")
	assets.Name = "MiningWorldEditableModels"
	assets.Parent = serverStorage
	for _, name in ipairs({ "Tree", "Cactus", "Deadwood", "Pyramid", "Backpack" }) do
		local folder = assets:FindFirstChild(name) or Instance.new("Folder")
		folder.Name = name
		folder.Parent = assets
	end
	return assets
end

function WorldService.getBiomeStyle(biomeName)
	local visuals = context.visuals
	return visuals and visuals.Biomes and visuals.Biomes[biomeName]
end

function WorldService.applyStyle(part, style)
	local factory = context.modelFactory
	if factory then
		factory.applyStyle(part, style)
	end
end

return WorldService
