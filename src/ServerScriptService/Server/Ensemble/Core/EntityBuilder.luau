--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)

local Entity = require(script.Parent.Entity)
local ComponentLoader = require(script.Parent.ComponentLoader)
local Types = require(script.Parent.Parent.Types)

type EntityContext = Types.EntityContext
type EntityBuilder = Types.EntityBuilder
type EventBus = Types.EventBus
type Component = Types.Component

local EntityBuilder = {}

local ActiveArchetypes: { [string]: { string } }? = nil
local EventBusRef: EventBus? = nil

function EntityBuilder.SetArchetypes(Archetypes: { [string]: { string } }?)
    ActiveArchetypes = Archetypes
end

function EntityBuilder.SetEventBus(EventBus: EventBus)
    EventBusRef = EventBus
end

function EntityBuilder.Create(Character: Model, Context: EntityContext?): EntityBuilder
    local BuilderContext = Context or {} :: EntityContext
    local ComponentsToAdd: { [string]: { any } } = {}
    local ComponentsToExclude: { [string]: boolean } = {}

    local Builder = {} :: EntityBuilder

    function Builder:WithComponent(ComponentName: string, ...: any): EntityBuilder
        if not ComponentLoader.Has(ComponentName) then
            error(string.format("%s Unknown component: '%s'", Types.EngineName, ComponentName))
        end

        ComponentsToAdd[ComponentName] = { ... }
        return self
    end

    function Builder:WithComponents(...: string): EntityBuilder
        for Index = 1, select("#", ...) do
            local ComponentName = select(Index, ...)
            self:WithComponent(ComponentName)
        end
        return self
    end

    function Builder:WithArchetype(ArchetypeName: string): EntityBuilder
        if not ActiveArchetypes then
            error(Types.EngineName .. " No archetypes configured")
        end

        local ArchetypeComponents = ActiveArchetypes[ArchetypeName]
        if not ArchetypeComponents then
            error(string.format("%s Unknown archetype: '%s'", Types.EngineName, ArchetypeName))
        end

        for _, ComponentName in ArchetypeComponents do
            if ComponentLoader.Has(ComponentName) then
                ComponentsToAdd[ComponentName] = {}
            end
        end

        return self
    end

    function Builder:WithoutComponent(ComponentName: string): EntityBuilder
        ComponentsToExclude[ComponentName] = true
        ComponentsToAdd[ComponentName] = nil
        return self
    end

    function Builder:Build(): Types.Entity
        local NewEntity = Entity.Create(Character, BuilderContext)

        local ComponentNames = {}
        for ComponentName in ComponentsToAdd do
            if not ComponentsToExclude[ComponentName] then
                table.insert(ComponentNames, ComponentName)
            end
        end

        local OrderedComponents = ComponentLoader.ResolveDependencyOrder(ComponentNames)
        local CreatedComponents: { Component } = {}

        for _, ComponentName in OrderedComponents do
            local Loaded = ComponentLoader.Get(ComponentName)
            if not Loaded then
                continue
            end

            local ComponentInstance = Loaded.Definition.Create(NewEntity, BuilderContext)
            NewEntity:AddComponent(ComponentName, ComponentInstance)
            table.insert(CreatedComponents, ComponentInstance)
        end

        for _, ComponentInstance in CreatedComponents do
            if ComponentInstance.Init then
                local Success, ErrorMessage = pcall(function()
                    ComponentInstance.Init()
                    return nil
                end)

                if not Success then
                    warn(string.format("%s Component Init failed: %s", Types.EngineName, tostring(ErrorMessage)))
                end
            end
        end

        for _, ComponentInstance in CreatedComponents do
            if ComponentInstance.Start then
                task.spawn(function()
                    local Success, ErrorMessage = pcall(function()
                        ComponentInstance.Start()
                        return nil
                    end)

                    if not Success then
                        warn(string.format("%s Component Start failed: %s", Types.EngineName, tostring(ErrorMessage)))
                    end
                end)
            end
        end

        if EventBusRef then
            EventBusRef:Publish(Enums.Entity.Created, {
                Entity = NewEntity,
                Character = NewEntity.Character,
                IsPlayer = NewEntity.IsPlayer,
                Player = NewEntity.Player,
            })
        end

        return NewEntity
    end

    return Builder
end

return EntityBuilder