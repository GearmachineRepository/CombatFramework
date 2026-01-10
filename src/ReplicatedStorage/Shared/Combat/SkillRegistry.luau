--!strict

local SkillRegistry = {}

local Skills: { [string]: any } = {}

function SkillRegistry.Register(SkillDefinition: any)
    if not SkillDefinition.SkillId then
        warn("[SkillRegistry] Missing SkillId")
        return
    end
    Skills[SkillDefinition.SkillId] = SkillDefinition
end

function SkillRegistry.Get(SkillId: string): any?
    return Skills[SkillId]
end

function SkillRegistry.Has(SkillId: string): boolean
    return Skills[SkillId] ~= nil
end

function SkillRegistry.LoadFolder(Folder: Folder)
    for _, Module in Folder:GetDescendants() do
        if not Module:IsA("ModuleScript") then
            continue
        end

        local Success, Definition = pcall(require, Module)
        if not Success then
            warn(string.format("[SkillRegistry] Failed to load %s: %s", Module.Name, tostring(Definition)))
            continue
        end

        if type(Definition) == "table" and Definition.SkillId then
            SkillRegistry.Register(Definition)
        end
    end
end

function SkillRegistry.GetAll(): { [string]: any }
    return table.clone(Skills)
end

return SkillRegistry