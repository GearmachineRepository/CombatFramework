--!strict

--[=[
	@class Entity

	Manages entity instances in the Ensemble ECS.

	Each entity is tied to a Character Model and tracks its components,
	player association, and context. Entities are registered globally
	and can be looked up by their Character reference.
]=]

local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type EntityContext = Types.EntityContext
type Component = Types.Component

local Entity = {}

local EntityRegistry: { [Model]: Entity } = {}

--[=[
	Creates a new Entity bound to the given Character.

	Sets a `HasEntity` attribute on the Character for external visibility.

	@param Character Model -- The character model to bind the entity to
	@param Context EntityContext -- Contextual data for the entity
	@return Entity -- The newly created entity
]=]
function Entity.Create(Character: Model, Context: EntityContext): Entity
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		error(string.format("%s Character '%s' has no Humanoid", Types.EngineName, Character.Name))
	end

	if EntityRegistry[Character] then
		error(string.format("%s Entity already exists for '%s'", Types.EngineName, Character.Name))
	end

	local Components: { [string]: Component } = {}
	local Destroyed = false

	local NewEntity = {} :: Entity

	NewEntity.Character = Character
	NewEntity.Humanoid = Humanoid
	NewEntity.IsPlayer = Context.Player ~= nil
	NewEntity.Player = Context.Player
	NewEntity.Context = Context

	function NewEntity:GetComponent(ComponentName: string): any?
		return Components[ComponentName]
	end

	function NewEntity:HasComponent(ComponentName: string): boolean
		return Components[ComponentName] ~= nil
	end

	function NewEntity:AddComponent(ComponentName: string, ComponentInstance: Component)
		if Components[ComponentName] then
			warn(string.format("%s Component '%s' already exists", Types.EngineName, ComponentName))
			return
		end
		Components[ComponentName] = ComponentInstance
	end

	function NewEntity:RemoveComponent(ComponentName: string)
		local ComponentInstance = Components[ComponentName]
		if not ComponentInstance then
			return
		end
		Components[ComponentName] = nil
		if ComponentInstance.Destroy then
			ComponentInstance.Destroy()
		end
	end

	function NewEntity:Destroy()
		if Destroyed then
			return
		end
		Destroyed = true

		for ComponentName, ComponentInstance in Components do
			if ComponentName and ComponentInstance.Destroy then
				ComponentInstance.Destroy()
			end
		end
		table.clear(Components)

		Character:SetAttribute("HasEntity", nil)
		EntityRegistry[Character] = nil
	end

	Character:SetAttribute("HasEntity", true)
	EntityRegistry[Character] = NewEntity

	return NewEntity
end

--[=[
	Returns the entity bound to the given Character, or nil if none exists.

	@param Character Model -- The character to look up
	@return Entity? -- The entity, or nil
]=]
function Entity.Get(Character: Model): Entity?
	return EntityRegistry[Character]
end

--[=[
	Returns an array of all currently registered entities.

	@return { Entity } -- All active entities
]=]
function Entity.GetAll(): { Entity }
	local Entities = {}
	for _, EntityInstance in EntityRegistry do
		table.insert(Entities, EntityInstance)
	end
	return Entities
end

--[=[
	Destroys the entity bound to the given Character, if one exists.

	@param Character Model -- The character whose entity should be destroyed
]=]
function Entity.Destroy(Character: Model)
	local EntityInstance = EntityRegistry[Character]
	if EntityInstance then
		EntityInstance:Destroy()
	end
end

return Entity