--!strict

local ToolRegistry = {}

local Tools: { [string]: any } = {}
local ActionToTool: { [string]: any } = {}

function ToolRegistry.Register(ToolDefinition: any)
    if not ToolDefinition.ToolId then
        warn("[ToolRegistry] Missing ToolId")
        return
    end
    Tools[ToolDefinition.ToolId] = ToolDefinition

    if ToolDefinition.ActionId then
        ActionToTool[ToolDefinition.ActionId] = ToolDefinition
    end
end

function ToolRegistry.Get(ToolId: string): any?
    return Tools[ToolId]
end

function ToolRegistry.GetByActionId(ActionId: string): any?
    return ActionToTool[ActionId]
end

function ToolRegistry.Has(ToolId: string): boolean
    return Tools[ToolId] ~= nil
end

function ToolRegistry.LoadFolder(Folder: Folder)
    for _, Module in Folder:GetDescendants() do
        if not Module:IsA("ModuleScript") then
            continue
        end

        local Success, Definition = pcall(require, Module)
        if not Success then
            warn(string.format("[ToolRegistry] Failed to load %s: %s", Module.Name, tostring(Definition)))
            continue
        end

        if type(Definition) == "table" and Definition.ToolId then
            ToolRegistry.Register(Definition)
        end
    end
end

function ToolRegistry.GetAll(): { [string]: any }
    return table.clone(Tools)
end

return ToolRegistry