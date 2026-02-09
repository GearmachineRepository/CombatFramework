--!strict

--[=[
	@class Ensemble

	The top-level API for the Ensemble entity-component system.

	Manages initialization, entity creation/destruction, and exposes
	the shared EventBus for lifecycle events.

	```lua
	Ensemble.Init({
		Components = Server.Components,
		Archetypes = {
			Player = { "Stats", "States", "Modifiers", "Hotbar" },
			Enemy = { "Stats", "States", "Modifiers" },
		},
	})

	local Entity = Ensemble.CreateEntity(Character, Context)
		:WithArchetype("Player")
		:Build()
	```
]=]

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

--[=[
	Initializes the Ensemble ECS with the given configuration.

	Must be called once before creating any entities. Loads all components,
	sets up archetypes, and starts the update system.

	@param Config InitConfig -- Configuration containing Components folder and optional Archetypes
]=]
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
end

--[=[
	Creates a new EntityBuilder for the given Character.

	@param Character Model -- The character model for the entity
	@param Context EntityContext? -- Optional context data
	@return EntityBuilder -- A fluent builder for constructing the entity
]=]
function Ensemble.CreateEntity(Character: Model, Context: Types.EntityContext?): Types.EntityBuilder
	if not Initialized then
		error(Types.EngineName .. " Not initialized")
	end

	return EntityBuilder.Create(Character, Context)
end

--[=[
	Returns the entity bound to the given Character, or nil.

	@param Character Model -- The character to look up
	@return Entity? -- The entity, or nil
]=]
function Ensemble.GetEntity(Character: Model): Types.Entity?
	return Entity.Get(Character)
end

--[=[
	Returns all currently registered entities.

	@return { Entity } -- Array of all active entities
]=]
function Ensemble.GetAllEntities(): { Types.Entity }
	return Entity.GetAll()
end

--[=[
	Destroys the entity associated with the given Character.

	Publishes an `Entity.Destroyed` event before cleanup.

	@param Character Model -- The character whose entity should be destroyed
]=]
function Ensemble.DestroyEntity(Character: Model)
	local EntityInstance = Entity.Get(Character)
	if EntityInstance then
		Events:Publish(Enums.Entity.Destroyed, {
			Entity = EntityInstance,
			Character = Character,
		})
		EntityInstance:Destroy()
	end
end

Ensemble.Events = Events
Ensemble.Types = Types

return Ensemble