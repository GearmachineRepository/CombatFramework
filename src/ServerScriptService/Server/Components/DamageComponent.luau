--!strict

--[=[
	@class DamageComponent

	Handles damage application for an entity, integrating with States (invulnerability),
	Modifiers (damage reduction/amplification), and Stats (health tracking).

	Publishes an `OnDamaged` signal with details about each damage event.

	```lua
	local Damage = DamageComponent.From(Entity)
	if Damage then
		Damage:TakeDamage(25, SourcePlayer, HitDirection)
	end
	```
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Server.Ensemble.Types)
local Packages = require(Shared.Packages)
local StateComponent = require(script.Parent.StateComponent)
local StatComponent = require(script.Parent.StatComponent)
local ModifierComponent = require(script.Parent.ModifierComponent)

local Trove = Packages.Trove
local Signal = Packages.Signal

type Entity = Types.Entity
type EntityContext = Types.EntityContext

local DamageComponent = {}
DamageComponent.ComponentName = "Damage"
DamageComponent.Dependencies = { "States", "Stats", "Modifiers" }

local DamageInstance = {}
DamageInstance.__index = DamageInstance

type DamageStorage = {
	_States: StateComponent.Type?,
	_Stats: StatComponent.Type?,
	_Modifiers: ModifierComponent.Type?,
	_Humanoid: Humanoid,
	_Trove: typeof(Trove.new()),
	OnDamaged: typeof(Signal.new()),
}

type DamageInstanceInternal = typeof(setmetatable({} :: DamageStorage, {} :: typeof(DamageInstance)))

--[=[
	Returns the DamageComponent attached to the given entity, or nil.

	@param EntityInstance Entity -- The entity to look up
	@return DamageInstance? -- The damage instance, or nil
]=]
function DamageComponent.From(EntityInstance: Entity): DamageInstanceInternal?
	return EntityInstance:GetComponent("Damage")
end

--[=[
	Creates a new DamageComponent for the given entity.

	Grabs references to the entity's States, Stats, and Modifiers components
	at construction time. Missing dependencies are handled gracefully.

	@param EntityInstance Entity -- The owning entity
	@param _Context EntityContext -- The entity context (unused)
	@return DamageInstance -- The new damage instance
]=]
function DamageComponent.Create(EntityInstance: Entity, _Context: EntityContext): DamageInstanceInternal
	local ComponentTrove = Trove.new()

	local Storage: DamageStorage = {
		_States = StateComponent.From(EntityInstance),
		_Stats = StatComponent.From(EntityInstance),
		_Modifiers = ModifierComponent.From(EntityInstance),
		_Humanoid = EntityInstance.Humanoid,
		_Trove = ComponentTrove,
		OnDamaged = ComponentTrove:Construct(Signal),
	}

	return setmetatable(Storage, DamageInstance)
end

--[=[
	Returns whether the entity is currently invulnerable.

	@param self DamageInstance
	@return boolean -- True if the entity has the Invulnerable state active
]=]
function DamageInstance:IsInvulnerable(): boolean
	if not self._States then
		return false
	end
	return self._States:GetState("Invulnerable")
end

--[=[
	Applies damage to the entity. Checks invulnerability first, then runs
	the damage value through the modifier stack, updates the Humanoid health,
	syncs the Stats component, and fires the OnDamaged signal.

	@param self DamageInstance
	@param Amount number -- Raw damage amount before modifiers
	@param Source Player? -- The player who dealt the damage, if any
	@param Direction Vector3? -- The direction the damage came from, if any
]=]
function DamageInstance:TakeDamage(Amount: number, Source: Player?, Direction: Vector3?)
	if self:IsInvulnerable() then
		return
	end

	local ModifiedDamage = Amount

	if self._Modifiers then
		ModifiedDamage = self._Modifiers:Apply("DamageTaken", Amount, {
			Source = Source,
			Direction = Direction,
		})
	end

	local OldHealth = self._Humanoid.Health
	local NewHealth = math.max(0, self._Humanoid.Health - ModifiedDamage)
	self._Humanoid.Health = NewHealth

	if self._Stats then
		self._Stats:SetStat("Health", NewHealth)
	end

	self.OnDamaged:Fire({
		Amount = ModifiedDamage,
		Source = Source,
		Direction = Direction,
		OldHealth = OldHealth,
		NewHealth = NewHealth,
	})
end

--[=[
	Destroys the component and cleans up the signal.

	@param self DamageInstance
]=]
function DamageInstance:Destroy()
	self._Trove:Destroy()
end

export type Type = typeof(setmetatable({} :: DamageStorage, DamageInstance))

return DamageComponent