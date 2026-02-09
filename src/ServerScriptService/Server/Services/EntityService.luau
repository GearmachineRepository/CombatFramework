--!strict

--[=[
	@class EntityService

	A thin service layer over Ensemble for entity CRUD operations.

	Provides convenience methods for creating entities with archetypes
	or component lists, and exposes filtered queries for player vs
	non-player entities. Publishes `EntityCreated` and `EntityDestroyed`
	signals for service-level consumers.
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local Enums = require(Shared.Enums)

local Signal = Packages.Signal
local Ensemble = require(Server.Ensemble)
local EnsembleTypes = require(Server.Ensemble.Types)

type Entity = EnsembleTypes.Entity
type EntityContext = EnsembleTypes.EntityContext
type Connection = EnsembleTypes.Connection

local EntityService = {}

EntityService.EntityCreated = Signal.new()
EntityService.EntityDestroyed = Signal.new()

local CreatedConnection: Connection? = nil
local DestroyedConnection: Connection? = nil

--[=[
	Subscribes to Ensemble entity lifecycle events.
]=]
function EntityService.Init()
	CreatedConnection = Ensemble.Events:Subscribe(Enums.Entity.Created, function(Data: any)
		EntityService.EntityCreated:Fire(Data.Entity)
	end)

	DestroyedConnection = Ensemble.Events:Subscribe(Enums.Entity.Destroyed, function(Data: any)
		EntityService.EntityDestroyed:Fire(Data.Entity)
	end)
end

function EntityService.Start()
end

--[=[
	Disconnects event subscriptions and cleans up signals.
]=]
function EntityService.Stop()
	if CreatedConnection then
		CreatedConnection:Disconnect()
		CreatedConnection = nil
	end

	if DestroyedConnection then
		DestroyedConnection:Disconnect()
		DestroyedConnection = nil
	end
end

--[=[
	Creates an entity for the given Character with default context.

	@param Character Model -- The character model
	@param Context EntityContext? -- Optional entity context
	@return Entity -- The newly created entity
]=]
function EntityService.CreateEntity(Character: Model, Context: EntityContext?): Entity
	return Ensemble.CreateEntity(Character, Context or {}):Build()
end

--[=[
	Creates an entity using a named archetype.

	@param Character Model -- The character model
	@param Archetype string -- The archetype name to apply
	@param Context EntityContext? -- Optional entity context
	@return Entity -- The newly created entity
]=]
function EntityService.CreateEntityWithArchetype(Character: Model, Archetype: string, Context: EntityContext?): Entity
	return Ensemble.CreateEntity(Character, Context or {}):WithArchetype(Archetype):Build()
end

--[=[
	Creates an entity with a specific set of components.

	@param Character Model -- The character model
	@param Components { string } -- Array of component names to add
	@param Context EntityContext? -- Optional entity context
	@return Entity -- The newly created entity
]=]
function EntityService.CreateEntityWithComponents(Character: Model, Components: { string }, Context: EntityContext?): Entity
	local Builder = Ensemble.CreateEntity(Character, Context or {})
	for _, ComponentName in Components do
		Builder:WithComponent(ComponentName)
	end
	return Builder:Build()
end

--[=[
	Destroys the entity associated with the given Character.

	@param Character Model -- The character whose entity should be destroyed
]=]
function EntityService.DestroyEntity(Character: Model)
	Ensemble.DestroyEntity(Character)
end

--[=[
	Returns the entity bound to the given Character, or nil.

	@param Character Model -- The character to look up
	@return Entity? -- The entity, or nil
]=]
function EntityService.GetEntity(Character: Model): Entity?
	return Ensemble.GetEntity(Character)
end

--[=[
	Returns all currently registered entities.

	@return { Entity } -- Array of all active entities
]=]
function EntityService.GetAllEntities(): { Entity }
	return Ensemble.GetAllEntities()
end

--[=[
	Returns all entities that are associated with a Player.

	@return { Entity } -- Array of player entities
]=]
function EntityService.GetPlayerEntities(): { Entity }
	local Result = {}
	for _, EntityInstance in Ensemble.GetAllEntities() do
		if EntityInstance.IsPlayer then
			table.insert(Result, EntityInstance)
		end
	end
	return Result
end

--[=[
	Returns all entities that are not associated with a Player.

	@return { Entity } -- Array of non-player entities
]=]
function EntityService.GetNonPlayerEntities(): { Entity }
	local Result = {}
	for _, EntityInstance in Ensemble.GetAllEntities() do
		if not EntityInstance.IsPlayer then
			table.insert(Result, EntityInstance)
		end
	end
	return Result
end

--[=[
	Returns the entity for a Player based on their current Character.

	@param Player Player -- The player to look up
	@return Entity? -- The entity, or nil if no character or entity exists
]=]
function EntityService.GetEntityByPlayer(Player: Player): Entity?
	if not Player.Character then
		return nil
	end
	return Ensemble.GetEntity(Player.Character)
end

--[=[
	Returns whether an entity exists for the given Character.

	@param Character Model -- The character to check
	@return boolean -- True if an entity is registered
]=]
function EntityService.HasEntity(Character: Model): boolean
	return Ensemble.GetEntity(Character) ~= nil
end

return EntityService