--!strict

local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type EntityContext = Types.EntityContext
type Component = Types.Component

local Entity = {}

local EntityRegistry: { [Model]: Entity } = {}

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

function Entity.Get(Character: Model): Entity?
	return EntityRegistry[Character]
end

function Entity.GetAll(): { Entity }
	local Entities = {}
	for _, EntityInstance in EntityRegistry do
		table.insert(Entities, EntityInstance)
	end
	return Entities
end

function Entity.Destroy(Character: Model)
	local EntityInstance = EntityRegistry[Character]
	if EntityInstance then
		EntityInstance:Destroy()
	end
end

return Entity