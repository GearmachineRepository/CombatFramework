--!strict

--[=[
	@class ModifierComponent

	A priority-sorted modifier stack for transforming numeric values.

	Modifiers are registered under a named type (e.g. "DamageTaken", "MoveSpeed")
	with a priority that controls evaluation order. Lower priorities run first.
	Useful for buffs, debuffs, and any layered value transformation.

	```lua
	local Modifiers = ModifierComponent.From(Entity)
	if Modifiers then
		local Unsub = Modifiers:Register("DamageTaken", 10, function(Base, Data)
			return Base * 0.5
		end)
		local Final = Modifiers:Apply("DamageTaken", 100)
	end
	```
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Server.Ensemble.Types)
local Packages = require(Shared.Packages)

local Trove = Packages.Trove

type Entity = Types.Entity
type EntityContext = Types.EntityContext

type ModifierFunction = (BaseValue: number, Data: { [string]: any }?) -> number

type Modifier = {
	Priority: number,
	Func: ModifierFunction,
}

local ModifierComponent = {}
ModifierComponent.ComponentName = "Modifiers"
ModifierComponent.Dependencies = {}

local ModifierInstance = {}
ModifierInstance.__index = ModifierInstance

type ModifierStorage = {
	_ModifiersByType: { [string]: { Modifier } },
	_Trove: typeof(Trove.new()),
}

type ModifierInstanceInternal = typeof(setmetatable({} :: ModifierStorage, {} :: typeof(ModifierInstance)))

--[=[
	Returns the ModifierComponent attached to the given entity, or nil.

	@param EntityInstance Entity -- The entity to look up
	@return ModifierInstance? -- The modifier instance, or nil
]=]
function ModifierComponent.From(EntityInstance: Entity): ModifierInstanceInternal?
	return EntityInstance:GetComponent("Modifiers")
end

--[=[
	Creates a new ModifierComponent for the given entity.

	@param _Entity Entity -- The owning entity (unused, kept for interface conformance)
	@param _Context EntityContext -- The entity context (unused)
	@return ModifierInstance -- The new modifier instance
]=]
function ModifierComponent.Create(_Entity: Entity, _Context: EntityContext): ModifierInstanceInternal
	local Storage: ModifierStorage = {
		_ModifiersByType = {},
		_Trove = Trove.new(),
	}

	return setmetatable(Storage, ModifierInstance)
end

--[=[
	Registers a modifier function under a type with a given priority.
	Lower priority values run first. Returns an unsubscribe function.

	@param self ModifierInstance
	@param Type string -- The modifier category (e.g. "DamageTaken")
	@param Priority number -- Sort order, lower runs first
	@param Func (BaseValue: number, Data: { [string]: any }?) -> number -- The transform function
	@return () -> () -- Call to unregister this modifier
]=]
function ModifierInstance:Register(Type: string, Priority: number, Func: ModifierFunction): () -> ()
	local Modifiers = self._ModifiersByType[Type]
	if not Modifiers then
		Modifiers = {}
		self._ModifiersByType[Type] = Modifiers
	end

	local NewModifier: Modifier = {
		Priority = Priority,
		Func = Func,
	}

	table.insert(Modifiers, NewModifier)

	table.sort(Modifiers, function(FirstModifier: Modifier, SecondModifier: Modifier): boolean
		return FirstModifier.Priority < SecondModifier.Priority
	end)

	return function()
		local CurrentModifiers = self._ModifiersByType[Type]
		if not CurrentModifiers then
			return
		end

		for Index, ExistingModifier in CurrentModifiers do
			if ExistingModifier.Func == Func then
				table.remove(CurrentModifiers, Index)
				break
			end
		end
	end
end

--[=[
	Removes a specific modifier function from a type.

	@param self ModifierInstance
	@param Type string -- The modifier category
	@param Func (BaseValue: number, Data: { [string]: any }?) -> number -- The function to remove
]=]
function ModifierInstance:Unregister(Type: string, Func: ModifierFunction)
	local Modifiers = self._ModifiersByType[Type]
	if not Modifiers then
		return
	end

	for Index, ExistingModifier in Modifiers do
		if ExistingModifier.Func == Func then
			table.remove(Modifiers, Index)
			break
		end
	end
end

--[=[
	Runs all modifiers for a type against a base value in priority order.

	@param self ModifierInstance
	@param Type string -- The modifier category
	@param BaseValue number -- The starting value
	@param Data { [string]: any }? -- Optional context passed to each modifier
	@return number -- The final transformed value
]=]
function ModifierInstance:Apply(Type: string, BaseValue: number, Data: { [string]: any }?): number
	local Modifiers = self._ModifiersByType[Type]
	if not Modifiers or #Modifiers == 0 then
		return BaseValue
	end

	local CurrentValue = BaseValue

	for _, ExistingModifier in Modifiers do
		CurrentValue = ExistingModifier.Func(CurrentValue, Data)
	end

	return CurrentValue
end

--[=[
	Returns the number of active modifiers for a type.

	@param self ModifierInstance
	@param Type string -- The modifier category
	@return number -- The count
]=]
function ModifierInstance:GetCount(Type: string): number
	local Modifiers = self._ModifiersByType[Type]
	return if Modifiers then #Modifiers else 0
end

--[=[
	Clears modifiers. If a type is provided, only that type is cleared.
	If nil, all modifiers are cleared.

	@param self ModifierInstance
	@param Type string? -- Optional type to clear, or nil for all
]=]
function ModifierInstance:Clear(Type: string?)
	if Type then
		self._ModifiersByType[Type] = nil
	else
		table.clear(self._ModifiersByType)
	end
end

--[=[
	Destroys the component and cleans up all modifiers.

	@param self ModifierInstance
]=]
function ModifierInstance:Destroy()
	self._Trove:Destroy()
	table.clear(self._ModifiersByType)
end

export type Type = typeof(setmetatable({} :: ModifierStorage, ModifierInstance))

return ModifierComponent