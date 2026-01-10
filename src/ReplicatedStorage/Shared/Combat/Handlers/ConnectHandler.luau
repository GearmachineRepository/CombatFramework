--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)

local ConnectHandler = {}

function ConnectHandler.Execute(Block: any, Context: any): any?
    local Signal = Block.Signal
    local Time = Block.Time or 0
    local Range = Block.Range or math.huge

    if not Signal then
        warn("[ConnectHandler] Missing Signal")
        return nil
    end

    local Character = Context.Entity.Character
    local Position = Character:GetPivot().Position

    Context.EventBus:Publish(Enums.Combat.Connect.SignalSent, {
        Signal = Signal,
        Position = Position,
        Range = Range,
        Duration = Time,
        Entity = Context.Entity,
    })

    if Time > 0 then
        task.wait(Time)
    end

    return nil
end

return ConnectHandler