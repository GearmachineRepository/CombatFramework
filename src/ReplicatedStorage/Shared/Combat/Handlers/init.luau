--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type BlockHandler = CombatTypes.BlockHandler

local Handlers = {}

local LoadedHandlers: { [string]: BlockHandler } = {}

local function Configure()
	for _, Module in script:GetChildren() do
		if not Module:IsA("ModuleScript") then
			continue
		end

		local Success, Handler = pcall(require, Module)
		if not Success then
			warn(string.format("[Handlers] Failed to load %s: %s", Module.Name, tostring(Handler)))
			continue
		end

		local BlockType = string.gsub(Module.Name, "Handler", "")
		LoadedHandlers[BlockType] = Handler :: BlockHandler
	end
end

function Handlers.Get(BlockType: string): BlockHandler?
	return LoadedHandlers[BlockType]
end

function Handlers.Has(BlockType: string): boolean
	return LoadedHandlers[BlockType] ~= nil
end

function Handlers.GetAll(): { [string]: BlockHandler }
	return table.clone(LoadedHandlers)
end

Configure()

return Handlers