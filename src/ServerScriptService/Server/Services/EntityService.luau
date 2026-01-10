--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)

local Signal = Packages.Signal
local Ensemble = require(Server.Ensemble)
local EnsembleTypes = require(Server.Ensemble.Types)

type Entity = EnsembleTypes.Entity
type EntityContext = EnsembleTypes.EntityContext

local EntityService = {}

EntityService.EntityCreated = Signal.new()
EntityService.EntityDestroyed = Signal.new()

function EntityService.Init()
    Ensemble.Events:Subscribe("EntityCreated", function(Data: any)
        EntityService.EntityCreated:Fire(Data.Entity)
    end)

    Ensemble.Events:Subscribe("EntityDestroyed", function(Data: any)
        EntityService.EntityDestroyed:Fire(Data.Entity)
    end)
end

function EntityService.Start()
end

function EntityService.Stop()
end

function EntityService.CreateEntity(Character: Model, Context: EntityContext?): Entity
    return Ensemble.CreateEntity(Character, Context or {}):Build()
end

function EntityService.CreateEntityWithArchetype(Character: Model, Archetype: string, Context: EntityContext?): Entity
    return Ensemble.CreateEntity(Character, Context or {}):WithArchetype(Archetype):Build()
end

function EntityService.CreateEntityWithComponents(Character: Model, Components: { string }, Context: EntityContext?): Entity
    local Builder = Ensemble.CreateEntity(Character, Context or {})
    for _, ComponentName in Components do
        Builder:WithComponent(ComponentName)
    end
    return Builder:Build()
end

function EntityService.DestroyEntity(Character: Model)
    Ensemble.DestroyEntity(Character)
end

function EntityService.GetEntity(Character: Model): Entity?
    return Ensemble.GetEntity(Character)
end

function EntityService.GetAllEntities(): { Entity }
    return Ensemble.GetAllEntities()
end

function EntityService.GetPlayerEntities(): { Entity }
    local Result = {}
    for _, EntityInstance in Ensemble.GetAllEntities() do
        if EntityInstance.IsPlayer then
            table.insert(Result, EntityInstance)
        end
    end
    return Result
end

function EntityService.GetNonPlayerEntities(): { Entity }
    local Result = {}
    for _, EntityInstance in Ensemble.GetAllEntities() do
        if not EntityInstance.IsPlayer then
            table.insert(Result, EntityInstance)
        end
    end
    return Result
end

function EntityService.GetEntityByPlayer(Player: Player): Entity?
    if not Player.Character then
        return nil
    end
    return Ensemble.GetEntity(Player.Character)
end

function EntityService.HasEntity(Character: Model): boolean
    return Ensemble.GetEntity(Character) ~= nil
end

return EntityService