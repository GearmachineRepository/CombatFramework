--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local EventBus = require(Shared.Utils.EventBus)
local Enums = require(Shared.Enums)

local Types = require(script.Types)
local Entity = require(script.Core.Entity)
local EntityBuilder = require(script.Core.EntityBuilder)
local ComponentLoader = require(script.Core.ComponentLoader)
local UpdateSystem = require(script.Systems.UpdateSystem)

type InitConfig = {
    Components: Instance,
    Archetypes: { [string]: { string } }?,
}

local Ensemble = {}

local Initialized = false
local Events: Types.EventBus = EventBus.new()

function Ensemble.Init(Config: InitConfig)
    if Initialized then
        error(Types.EngineName .. " Already initialized")
    end

    if not Config.Components then
        error(Types.EngineName .. " Config.Components is required")
    end

    ComponentLoader.Configure(Config.Components)
    EntityBuilder.SetEventBus(Events)

    if Config.Archetypes then
        EntityBuilder.SetArchetypes(Config.Archetypes)
    end

    UpdateSystem.Configure(ComponentLoader, Events)
    UpdateSystem.Start()

    Initialized = true

    print(Types.EngineName .. " Initialized")
    print(string.format("%s  Components: %d", Types.EngineName, #ComponentLoader.GetAllNames()))
end

function Ensemble.CreateEntity(Character: Model, Context: Types.EntityContext?): Types.EntityBuilder
    if not Initialized then
        error(Types.EngineName .. " Not initialized")
    end

    return EntityBuilder.Create(Character, Context)
end

function Ensemble.GetEntity(Character: Model): Types.Entity?
    return Entity.Get(Character)
end

function Ensemble.GetAllEntities(): { Types.Entity }
    return Entity.GetAll()
end

function Ensemble.DestroyEntity(Character: Model)
    local EntityInstance = Entity.Get(Character)
    if EntityInstance then
        Events:Publish(Enums.Entity.Destroyed, {
            Entity = EntityInstance,
            Character = Character,
        })
        EntityInstance:Destroy()

        print(string.format("%s Entity Cleared for %s", Types.EngineName, Character.Name))
    end
end

Ensemble.Events = Events
Ensemble.Types = Types

return Ensemble