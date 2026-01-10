--!strict

local Handlers = {}

local LoadedHandlers: { [string]: any } = {}

function Handlers.Configure()
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
        LoadedHandlers[BlockType] = Handler
    end
end

function Handlers.Get(BlockType: string): any?
    return LoadedHandlers[BlockType]
end

function Handlers.Has(BlockType: string): boolean
    return LoadedHandlers[BlockType] ~= nil
end

Handlers.Configure()

return Handlers