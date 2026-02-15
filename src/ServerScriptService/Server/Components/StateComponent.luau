--!strict

--[=[
	@class StateComponent

	Tracks boolean states for an entity with conflict resolution, timed durations,
	replication via character attributes, and per-state change callbacks.

	States are defined via `StateConfig` on the entity context. Each state supports
	optional conflict lists (setting one state automatically disables conflicts),
	timed durations that auto-expire, and attribute replication.

	```lua
	local States = StateComponent.From(Entity)
	if States then
		States:SetState("Stunned", true)
		States:SetStateWithDuration("Stunned", 2)
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

type StateConfig = Types.StateConfig
type EntityContext = Types.EntityContext
type Entity = Types.Entity

local StateComponent = {}
StateComponent.ComponentName = "States"
StateComponent.Dependencies = {}

local StateInstance = {}
StateInstance.__index = StateInstance

type TimedStateData = {
	StartTime: number,
	Duration: number,
	Cancelled: boolean,
}

type StateStorage = {
	_Config: StateConfig,
	_CurrentStates: { [string]: boolean },
	_StateCallbacks: { [string]: { (Value: boolean) -> () } },
	_StateTimers: { [string]: TimedStateData },
	_StateChangedSignals: { [string]: typeof(Signal.new()) },
	_Character: Model?,
	_Trove: typeof(Trove.new()),
}

type StateInstanceInternal = typeof(setmetatable({} :: StateStorage, {} :: typeof(StateInstance)))

--[=[
	Returns the StateComponent attached to the given entity, or nil.

	@param EntityInstance Entity -- The entity to look up
	@return StateInstance? -- The state instance, or nil
]=]
function StateComponent.From(EntityInstance: Entity): StateInstanceInternal?
	return EntityInstance:GetComponent("States")
end

--[=[
	Creates a new StateComponent for the given entity and context.

	Reads `StateConfig` from the context and initializes all states to their
	default values. States with `Replicate ~= false` are written as character
	attributes immediately.

	@param EntityInstance Entity -- The owning entity
	@param Context EntityContext -- Context containing StateConfig
	@return StateInstance -- The new state instance
]=]
function StateComponent.Create(EntityInstance: Entity, Context: EntityContext): StateInstanceInternal
	local Config: StateConfig = Context.StateConfig or {}
	local ComponentTrove = Trove.new()

	local Storage: StateStorage = {
		_Config = Config,
		_CurrentStates = {},
		_StateCallbacks = {},
		_StateTimers = {},
		_StateChangedSignals = {},
		_Character = EntityInstance.Character,
		_Trove = ComponentTrove,
	}

	local Instance = setmetatable(Storage, StateInstance)

	for StateName, Definition in Config do
		Storage._CurrentStates[StateName] = Definition.Default or false
		Storage._StateCallbacks[StateName] = {}
		Storage._StateChangedSignals[StateName] = ComponentTrove:Construct(Signal)

		if Definition.Replicate ~= false and Storage._Character then
			Storage._Character:SetAttribute(StateName, Storage._CurrentStates[StateName])
		end
	end

	return Instance
end

local function ClearTimedState(Self: StateInstanceInternal, StateName: string)
	local TimerData = Self._StateTimers[StateName]
	if TimerData then
		TimerData.Cancelled = true
		Self._StateTimers[StateName] = nil
	end
end

--[=[
	Returns the current boolean value of a state.

	@param self StateInstance
	@param StateName string -- The state to read
	@return boolean -- The current value, or false if undefined
]=]
function StateInstance:GetState(StateName: string): boolean
	return self._CurrentStates[StateName] or false
end

--[=[
	Sets a state to true or false. Handles conflict resolution: setting a state
	to true will disable any conflicting states defined in the config.

	@param self StateInstance
	@param StateName string -- The state to set
	@param Value boolean -- The new value
]=]
function StateInstance:SetState(StateName: string, Value: boolean)
	local Definition = self._Config[StateName]
	if not Definition then
		self._CurrentStates[StateName] = Value
		return
	end

	if self._CurrentStates[StateName] == Value then
		return
	end

	if Value and Definition.Conflicts then
		for _, ConflictState in Definition.Conflicts do
			if self._CurrentStates[ConflictState] then
				self:SetState(ConflictState, false)
			end
		end
	end

	if not Value then
		ClearTimedState(self, StateName)
	end

	self._CurrentStates[StateName] = Value

	if Definition.Replicate ~= false and self._Character then
		self._Character:SetAttribute(StateName, Value)
	end

	local Callbacks = self._StateCallbacks[StateName]
	if Callbacks then
		for _, Callback in Callbacks do
			task.spawn(Callback, Value)
		end
	end

	local ChangedSignal = self._StateChangedSignals[StateName]
	if ChangedSignal then
		ChangedSignal:Fire(Value)
	end
end

--[=[
	Sets a state to true for a given duration, then automatically sets it to false.
	Replaces any existing timer for the same state.

	@param self StateInstance
	@param StateName string -- The state to set
	@param Duration number -- How long the state stays active, in seconds
]=]
function StateInstance:SetStateWithDuration(StateName: string, Duration: number)
	ClearTimedState(self, StateName)
	self:SetState(StateName, true)

	local TimerData: TimedStateData = {
		StartTime = workspace:GetServerTimeNow(),
		Duration = Duration,
		Cancelled = false,
	}

	self._StateTimers[StateName] = TimerData

	task.delay(Duration, function()
		if not TimerData.Cancelled and self._StateTimers[StateName] == TimerData then
			self:SetState(StateName, false)
		end
	end)
end

--[=[
	Returns the remaining duration of a timed state, or 0 if no timer is active.

	@param self StateInstance
	@param StateName string -- The state to query
	@return number -- Remaining time in seconds
]=]
function StateInstance:GetStateTimeRemaining(StateName: string): number
	local TimerData = self._StateTimers[StateName]
	if not TimerData then
		return 0
	end

	local Elapsed = workspace:GetServerTimeNow() - TimerData.StartTime
	return math.max(0, TimerData.Duration - Elapsed)
end

--[=[
	Registers a callback that fires when a state changes.
	Returns an unsubscribe function.

	@param self StateInstance
	@param StateName string -- The state to observe
	@param Callback (Value: boolean) -> () -- Called on change
	@return () -> () -- Call to unsubscribe
]=]
function StateInstance:OnStateChanged(StateName: string, Callback: (Value: boolean) -> ()): () -> ()
	if not self._StateCallbacks[StateName] then
		self._StateCallbacks[StateName] = {}
	end

	table.insert(self._StateCallbacks[StateName], Callback)

	return function()
		local Callbacks = self._StateCallbacks[StateName]
		if Callbacks then
			local Index = table.find(Callbacks, Callback)
			if Index then
				table.remove(Callbacks, Index)
			end
		end
	end
end

--[=[
	Returns a shallow copy of all current state values.

	@param self StateInstance
	@return { [string]: boolean } -- Map of state names to current values
]=]
function StateInstance:GetAllStates(): { [string]: boolean }
	return table.clone(self._CurrentStates)
end

--[=[
	Destroys the component, cancels all timers, and cleans up internal state.

	@param self StateInstance
]=]
function StateInstance:Destroy()
	for StateName in self._StateTimers do
		ClearTimedState(self, StateName)
	end

	self._Trove:Destroy()

	table.clear(self._CurrentStates)
	table.clear(self._StateCallbacks)
	table.clear(self._StateTimers)
	table.clear(self._StateChangedSignals)
end

export type Type = typeof(setmetatable({} :: StateStorage, StateInstance))

return StateComponent