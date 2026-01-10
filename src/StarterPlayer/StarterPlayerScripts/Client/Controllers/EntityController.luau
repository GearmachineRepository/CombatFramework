--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)

local Trove = Packages.Trove
local Signal = Packages.Signal

local EntityController = {}

type Stats = { [string]: number }
type States = { [string]: boolean }

type EntityData = {
    Stats: Stats,
    States: States,
}

type EntityMap = { [Instance]: EntityData }

local LocalPlayer = Players.LocalPlayer :: Player
local Entities: EntityMap = {}
local ControllerTrove: typeof(Trove.new()) = nil :: any

EntityController.EntityAdded = Signal.new()
EntityController.EntityRemoved = Signal.new()
EntityController.StatChanged = Signal.new()
EntityController.StateChanged = Signal.new()

function EntityController.Init()
    ControllerTrove = Trove.new()
end

function EntityController.Start()
    ControllerTrove:Connect(Packets.EntitySpawned.OnClientEvent :: any, function(Character: Instance, Data: { Stats: Stats?, States: States? })
        local EntityData: EntityData = {
            Stats = Data.Stats or {},
            States = Data.States or {},
        }
        Entities[Character] = EntityData
        EntityController.EntityAdded:Fire(Character, EntityData)
    end)

    ControllerTrove:Connect(Packets.EntityDespawned.OnClientEvent :: any, function(Character: Instance)
        local EntityData = Entities[Character]
        if EntityData then
            Entities[Character] = nil
            EntityController.EntityRemoved:Fire(Character, EntityData)
        end
    end)

    ControllerTrove:Connect(Packets.StatChanged.OnClientEvent :: any, function(StatName: string, NewValue: number, OldValue: number)
        local Character = LocalPlayer.Character
        if Character and Entities[Character] then
            Entities[Character].Stats[StatName] = NewValue
            EntityController.StatChanged:Fire(StatName, NewValue, OldValue)
        end
    end)

    ControllerTrove:Connect(Packets.StateChanged.OnClientEvent :: any, function(StateName: string, Value: boolean)
        local Character = LocalPlayer.Character
        if Character and Entities[Character] then
            Entities[Character].States[StateName] = Value
            EntityController.StateChanged:Fire(StateName, Value)
        end
    end)

    ControllerTrove:Connect(LocalPlayer.CharacterRemoving, function(Character: Model)
        local EntityData = Entities[Character]
        if EntityData then
            Entities[Character] = nil
            EntityController.EntityRemoved:Fire(Character, EntityData)
        end
    end)
end

function EntityController.Stop()
    ControllerTrove:Destroy()
    table.clear(Entities)
end

function EntityController.GetEntity(Character: Instance): EntityData?
    return Entities[Character]
end

function EntityController.GetLocalEntity(): EntityData?
    local Character = LocalPlayer.Character
    if not Character then
        return nil
    end
    return Entities[Character]
end

function EntityController.GetStat(StatName: string): number?
    local EntityData = EntityController.GetLocalEntity()
    if not EntityData then
        return nil
    end
    return EntityData.Stats[StatName]
end

function EntityController.GetState(StateName: string): boolean?
    local EntityData = EntityController.GetLocalEntity()
    if not EntityData then
        return nil
    end
    return EntityData.States[StateName]
end

return EntityController