--!strict

--[=[
	@class EntityController

	Client-side entity state tracking.

	Listens for server replication packets to maintain a local cache of
	entity stats and states. Fires signals when entities are added,
	removed, or when their stats/states change.
]=]

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

--[=[
	Creates the controller Trove for connection cleanup.
]=]
function EntityController.Init()
    ControllerTrove = Trove.new()
end

--[=[
	Subscribes to entity replication packets from the server and tracks
	local player character removal.
]=]
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

--[=[
	Destroys the controller Trove and clears the entity cache.
]=]
function EntityController.Stop()
    ControllerTrove:Destroy()
    table.clear(Entities)
end

--[=[
	Returns the cached entity data for a given Character instance, or nil.

	@param Character Instance -- The character to look up
	@return EntityData? -- The entity's stats and states, or nil
]=]
function EntityController.GetEntity(Character: Instance): EntityData?
    return Entities[Character]
end

--[=[
	Returns the cached entity data for the local player's current character, or nil.

	@return EntityData? -- The local entity data, or nil
]=]
function EntityController.GetLocalEntity(): EntityData?
    local Character = LocalPlayer.Character
    if not Character then
        return nil
    end
    return Entities[Character]
end

--[=[
	Returns the current value of a stat on the local player's entity.

	@param StatName string -- The stat to look up
	@return number -- The stat value, or 0 if not found
]=]
function EntityController.GetLocalStat(StatName: string): number
    local EntityData = EntityController.GetLocalEntity()
    if not EntityData then
        return 0
    end
    return EntityData.Stats[StatName] or 0
end

--[=[
	Returns the current value of a state on the local player's entity.

	@param StateName string -- The state to look up
	@return boolean -- The state value, or false if not found
]=]
function EntityController.GetLocalState(StateName: string): boolean
    local EntityData = EntityController.GetLocalEntity()
    if not EntityData then
        return false
    end
    return EntityData.States[StateName] or false
end

return EntityController