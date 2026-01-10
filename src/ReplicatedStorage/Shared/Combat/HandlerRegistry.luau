--!strict

local HandlerRegistry = {}

local Handlers: { [string]: any } = {}

function HandlerRegistry.Configure(HandlersFolder: Folder)
    table.clear(Handlers)

    for _, Module in HandlersFolder:GetChildren() do
        if not Module:IsA("ModuleScript") then
            continue
        end

        local Success, Handler = pcall(require, Module)
        if not Success then
            warn(string.format("[HandlerRegistry] Failed to load handler '%s': %s", Module.Name, tostring(Handler)))
            continue
        end

        local BlockType = string.gsub(Module.Name, "Handler", "")
        Handlers[BlockType] = Handler
    end
end

function HandlerRegistry.Get(BlockType: string): any?
    return Handlers[BlockType]
end

function HandlerRegistry.Has(BlockType: string): boolean
    return Handlers[BlockType] ~= nil
end

function HandlerRegistry.GetAll(): { [string]: any }
    return table.clone(Handlers)
end

return HandlerRegistry