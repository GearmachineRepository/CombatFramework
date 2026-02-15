--!strict

--[=[
	@class StatComponent

	Tracks numeric stats for an entity with base values, clamping, dependent max stats,
	replication via character attributes, and per-stat change callbacks.

	Stats are defined via `StatConfig` on the entity context. Each stat supports
	optional min/max bounds, a `MaxStat` reference for dynamic caps, and
	automatic attribute replication to the character model.

	```lua
	local Stats = StatComponent.From(Entity)
	if Stats then
		Stats:SetStat("Health", 50)
		local Current = Stats:GetStat("Health")
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
local Signal = Packages.Signal

type StatConfig = Types.StatConfig
type EntityContext = Types.EntityContext
type Entity = Types.Entity

local UPDATE_THRESHOLD = 0.001

local StatComponent = {}
StatComponent.ComponentName = "Stats"
StatComponent.Dependencies = {}

local StatInstance = {}
StatInstance.__index = StatInstance

type StatStorage = {
	_Config: StatConfig,
	_BaseStats: { [string]: number },
	_CurrentStats: { [string]: number },
	_StatCallbacks: { [string]: { (NewValue: number, OldValue: number) -> () } },
	_StatChangedSignals: { [string]: typeof(Signal.new()) },
	_Character: Model?,
	_Trove: typeof(Trove.new()),
}

type StatInstanceInternal = typeof(setmetatable({} :: StatStorage, {} :: typeof(StatInstance)))

--[=[
	Returns the StatComponent attached to the given entity, or nil.

	@param EntityInstance Entity -- The entity to look up
	@return StatInstance? -- The stat instance, or nil
]=]
function StatComponent.From(EntityInstance: Entity): StatInstanceInternal?
	return EntityInstance:GetComponent("Stats")
end

--[=[
	Creates a new StatComponent for the given entity and context.

	Reads `StatConfig` from the context and initializes all stats to their
	default values. Stats with `Replicate ~= false` are written as character
	attributes immediately.

	@param EntityInstance Entity -- The owning entity
	@param Context EntityContext -- Context containing StatConfig
	@return StatInstance -- The new stat instance
]=]
function StatComponent.Create(EntityInstance: Entity, Context: EntityContext): StatInstanceInternal
	local Config: StatConfig = Context.StatConfig or {}
	local ComponentTrove = Trove.new()

	local Storage: StatStorage = {
		_Config = Config,
		_BaseStats = {},
		_CurrentStats = {},
		_StatCallbacks = {},
		_StatChangedSignals = {},
		_Character = EntityInstance.Character,
		_Trove = ComponentTrove,
	}

	local Instance = setmetatable(Storage, StatInstance)

	for StatName, Definition in Config do
		Storage._BaseStats[StatName] = Definition.Default
		Storage._CurrentStats[StatName] = Definition.Default
		Storage._StatCallbacks[StatName] = {}
		Storage._StatChangedSignals[StatName] = ComponentTrove:Construct(Signal)

		if Definition.Replicate ~= false and Storage._Character then
			Storage._Character:SetAttribute(StatName, Definition.Default)
		end
	end

	return Instance
end

--[=[
	Returns the effective max value for a stat, accounting for MaxStat references
	and hard caps.

	@param self StatInstance
	@param StatName string -- The stat to query
	@return number? -- The max value, or nil if unbounded
]=]
function StatInstance:GetMaxFor(StatName: string): number?
	local Definition = self._Config[StatName]
	if not Definition then
		return nil
	end

	if Definition.MaxStat then
		local MaxStatValue = self._CurrentStats[Definition.MaxStat]
		if MaxStatValue then
			if Definition.Max then
				return math.min(MaxStatValue, Definition.Max)
			end
			return MaxStatValue
		end
	end

	return Definition.Max
end

local function ClampValue(Self: StatInstanceInternal, StatName: string, Value: number): number
	local Definition = Self._Config[StatName]
	if not Definition then
		return Value
	end

	local Clamped = Value

	if Definition.Min ~= nil then
		Clamped = math.max(Definition.Min, Clamped)
	end

	local MaxValue = Self:GetMaxFor(StatName)
	if MaxValue ~= nil then
		Clamped = math.min(MaxValue, Clamped)
	end

	return Clamped
end

local function NotifyChange(Self: StatInstanceInternal, StatName: string, NewValue: number, OldValue: number)
	if math.abs(NewValue - OldValue) < UPDATE_THRESHOLD then
		return
	end

	local Definition = Self._Config[StatName]
	if Definition and Definition.Replicate ~= false and Self._Character then
		Self._Character:SetAttribute(StatName, NewValue)
	end

	local Callbacks = Self._StatCallbacks[StatName]
	if Callbacks then
		for _, Callback in Callbacks do
			task.spawn(Callback, NewValue, OldValue)
		end
	end

	local ChangedSignal = Self._StatChangedSignals[StatName]
	if ChangedSignal then
		ChangedSignal:Fire(NewValue, OldValue)
	end
end

local function SetStatInternal(Self: StatInstanceInternal, StatName: string, Value: number, UpdateDependents: boolean)
	local ClampedValue = ClampValue(Self, StatName, Value)
	local OldValue = Self._CurrentStats[StatName] or 0

	Self._CurrentStats[StatName] = ClampedValue
	NotifyChange(Self, StatName, ClampedValue, OldValue)

	if UpdateDependents then
		for OtherStatName, OtherDefinition in pairs(Self._Config) do
			if OtherDefinition.MaxStat == StatName then
				local CurrentValue = Self._CurrentStats[OtherStatName] or 0
				local NewClamped = ClampValue(Self, OtherStatName, CurrentValue)
				if math.abs(NewClamped - CurrentValue) >= UPDATE_THRESHOLD then
					Self._CurrentStats[OtherStatName] = NewClamped
					NotifyChange(Self, OtherStatName, NewClamped, CurrentValue)
				end
			end
		end
	end
end

--[=[
	Returns the current value of a stat.

	@param self StatInstance
	@param StatName string -- The stat to read
	@return number -- The current value, or 0 if undefined
]=]
function StatInstance:GetStat(StatName: string): number
	return self._CurrentStats[StatName] or 0
end

--[=[
	Returns the base (unmodified) value of a stat.

	@param self StatInstance
	@param StatName string -- The stat to read
	@return number -- The base value, or 0 if undefined
]=]
function StatInstance:GetBaseStat(StatName: string): number
	return self._BaseStats[StatName] or 0
end

--[=[
	Sets the current value of a stat, clamping to bounds and updating dependents.

	@param self StatInstance
	@param StatName string -- The stat to set
	@param Value number -- The new value
]=]
function StatInstance:SetStat(StatName: string, Value: number)
	SetStatInternal(self, StatName, Value, true)
end

--[=[
	Sets the base value of a stat. Also updates the current value to match.

	@param self StatInstance
	@param StatName string -- The stat to set
	@param Value number -- The new base value
]=]
function StatInstance:SetBaseStat(StatName: string, Value: number)
	local Definition = self._Config[StatName]
	local ClampedBase = Value

	if Definition then
		if Definition.Min ~= nil then
			ClampedBase = math.max(Definition.Min, ClampedBase)
		end
		if Definition.Max ~= nil then
			ClampedBase = math.min(Definition.Max, ClampedBase)
		end
	end

	self._BaseStats[StatName] = ClampedBase
	SetStatInternal(self, StatName, ClampedBase, true)
end

--[=[
	Adds a delta to the current stat value.

	@param self StatInstance
	@param StatName string -- The stat to modify
	@param Delta number -- The amount to add (or subtract if negative)
]=]
function StatInstance:ModifyStat(StatName: string, Delta: number)
	local Current = self:GetStat(StatName)
	self:SetStat(StatName, Current + Delta)
end

--[=[
	Adds a delta to the base stat value.

	@param self StatInstance
	@param StatName string -- The stat to modify
	@param Delta number -- The amount to add (or subtract if negative)
]=]
function StatInstance:ModifyBaseStat(StatName: string, Delta: number)
	local Current = self:GetBaseStat(StatName)
	self:SetBaseStat(StatName, Current + Delta)
end

--[=[
	Returns a shallow copy of all current stat values.

	@param self StatInstance
	@return { [string]: number } -- Map of stat names to current values
]=]
function StatInstance:GetAllStats(): { [string]: number }
	return table.clone(self._CurrentStats)
end

--[=[
	Registers a callback that fires when a stat changes.
	Returns an unsubscribe function.

	@param self StatInstance
	@param StatName string -- The stat to observe
	@param Callback (NewValue: number, OldValue: number) -> () -- Called on change
	@return () -> () -- Call to unsubscribe
]=]
function StatInstance:OnStatChanged(StatName: string, Callback: (NewValue: number, OldValue: number) -> ()): () -> ()
	if not self._StatCallbacks[StatName] then
		self._StatCallbacks[StatName] = {}
	end

	table.insert(self._StatCallbacks[StatName], Callback)

	return function()
		local Callbacks = self._StatCallbacks[StatName]
		if Callbacks then
			local Index = table.find(Callbacks, Callback)
			if Index then
				table.remove(Callbacks, Index)
			end
		end
	end
end

--[=[
	Forces a stat to re-clamp and re-notify without changing its value.
	Useful after a MaxStat or modifier change.

	@param self StatInstance
	@param StatName string -- The stat to recalculate
]=]
function StatInstance:RecalculateStat(StatName: string)
	local Current = self._CurrentStats[StatName] or 0
	SetStatInternal(self, StatName, Current, false)
end

--[=[
	Destroys the component and cleans up all internal state.

	@param self StatInstance
]=]
function StatInstance:Destroy()
	self._Trove:Destroy()
	table.clear(self._BaseStats)
	table.clear(self._CurrentStats)
	table.clear(self._StatCallbacks)
	table.clear(self._StatChangedSignals)
end

export type Type = typeof(setmetatable({} :: StatStorage, StatInstance))

return StatComponent