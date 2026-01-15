--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ActionHandler = {}

local ActionRegistry: any = nil

local function GetActionRegistry(): any
    if not ActionRegistry then
        ActionRegistry = require(Shared.Combat.ActionRegistry)
    end
    return ActionRegistry
end

function ActionHandler.Execute(Block: any, Context: any): any?
    local ActionId = Block.ActionId
    local _Speed = Block.Speed or 1
    local _CancelLast = Block.CancelLast or false
    local _HoldFor = Block.HoldFor or 0

    if not ActionId or ActionId == "Cancel" then
        return nil
    end

    local Registry = GetActionRegistry()
    local ActionDef = Registry.Get(ActionId)

    if not ActionDef then
        warn(string.format("[ActionHandler] Unknown Action: %s", ActionId))
        return nil
    end

    local ActionExecutor = require(script.Parent.Parent.ActionExecutor)
    local SubContext = ActionExecutor.Execute(Context.Entity, ActionDef, Context.EventBus)

    for _, Record in SubContext.HitRecords do
        Context.RecordHit(Record.Target, Record.Damage)
    end

    return nil
end

return ActionHandler