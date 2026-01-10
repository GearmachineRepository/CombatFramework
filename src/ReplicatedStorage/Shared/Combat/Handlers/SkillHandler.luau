--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local SkillHandler = {}

local SkillRegistry: any = nil

local function GetSkillRegistry(): any
    if not SkillRegistry then
        SkillRegistry = require(Shared.Combat.SkillRegistry)
    end
    return SkillRegistry
end

function SkillHandler.Execute(Block: any, Context: any): any?
    local SkillId = Block.SkillId
    local _Speed = Block.Speed or 1
    local _CancelLast = Block.CancelLast or false
    local _HoldFor = Block.HoldFor or 0

    if not SkillId or SkillId == "Cancel" then
        return nil
    end

    local Registry = GetSkillRegistry()
    local SkillDef = Registry.Get(SkillId)

    if not SkillDef then
        warn(string.format("[SkillHandler] Unknown skill: %s", SkillId))
        return nil
    end

    local SkillExecutor = require(script.Parent.Parent.SkillExecutor)
    local SubContext = SkillExecutor.Execute(Context.Entity, SkillDef, Context.EventBus)

    for _, Record in SubContext.HitRecords do
        Context.RecordHit(Record.Target, Record.Damage)
    end

    return nil
end

return SkillHandler