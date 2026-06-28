local ToolService = {}

local context = {}

function ToolService.configure(newContext)
	context = newContext or {}
end

function ToolService.createFallbackHandle(toolName, autoMine)
	local factory = context.modelFactory
	if not factory then
		factory = require(game:GetService("ReplicatedStorage"):WaitForChild("MiningShared"):WaitForChild("ModelFactory"))
	end
	return factory.createToolFallback(toolName, autoMine)
end

function ToolService.createBombHandle(radius)
	local factory = context.modelFactory
	if not factory then
		factory = require(game:GetService("ReplicatedStorage"):WaitForChild("MiningShared"):WaitForChild("ModelFactory"))
	end
	return factory.createBombHandle(radius)
end

function ToolService.removeNamedTools(player, names)
	local lookup = {}
	for _, name in ipairs(names or {}) do
		lookup[name] = true
	end
	for _, container in ipairs({ player:FindFirstChild("Backpack"), player.Character, player:FindFirstChild("StarterGear") }) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and lookup[child.Name] then
					child:Destroy()
				end
			end
		end
	end
end

return ToolService
