--!strict

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

type StateInstance = {
	GetState: (StateName: string) -> boolean,
	SetState: (StateName: string, Value: boolean) -> (),
	SetStateWithDuration: (StateName: string, Duration: number) -> (),
	GetStateTimeRemaining: (StateName: string) -> number,
	OnStateChanged: (StateName: string, Callback: (Value: boolean) -> ()) -> () -> (),
	GetAllStates: () -> { [string]: boolean },
	Destroy: () -> (),
}

type TimedStateData = {
	StartTime: number,
	Duration: number,
	Cancelled: boolean,
}

function StateComponent.From(EntityInstance: Entity): StateInstance?
	return EntityInstance:GetComponent("States")
end

function StateComponent.Create(EntityInstance: Entity, Context: EntityContext): StateInstance
	local Config: StateConfig = Context.StateConfig or {}
	local CurrentStates: { [string]: boolean } = {}
	local StateCallbacks: { [string]: { (Value: boolean) -> () } } = {}
	local StateTimers: { [string]: TimedStateData } = {}
	local Character = EntityInstance.Character
	local ComponentTrove = Trove.new()

	local StateChangedSignals: { [string]: typeof(Signal.new()) } = {}

	for StateName, Definition in Config do
		CurrentStates[StateName] = Definition.Default or false
		StateCallbacks[StateName] = {}
		StateChangedSignals[StateName] = ComponentTrove:Construct(Signal)

		if Definition.Replicate ~= false and Character then
			Character:SetAttribute(StateName, CurrentStates[StateName])
		end
	end

	local function GetState(StateName: string): boolean
		return CurrentStates[StateName] or false
	end

	local function ClearTimedState(StateName: string)
		local TimerData = StateTimers[StateName]
		if TimerData then
			TimerData.Cancelled = true
			StateTimers[StateName] = nil
		end
	end

	local function SetState(StateName: string, Value: boolean)
		local Definition = Config[StateName]
		if not Definition then
			CurrentStates[StateName] = Value
			return
		end

		if CurrentStates[StateName] == Value then
			return
		end

		if Value and Definition.Conflicts then
			for _, ConflictState in Definition.Conflicts do
				if CurrentStates[ConflictState] then
					SetState(ConflictState, false)
				end
			end
		end

		if not Value then
			ClearTimedState(StateName)
		end

		CurrentStates[StateName] = Value

		if Definition.Replicate ~= false and Character then
			Character:SetAttribute(StateName, Value)
		end

		local Callbacks = StateCallbacks[StateName]
		if Callbacks then
			for _, Callback in Callbacks do
				task.spawn(Callback, Value)
			end
		end

		local ChangedSignal = StateChangedSignals[StateName]
		if ChangedSignal then
			ChangedSignal:Fire(Value)
		end
	end

	local function SetStateWithDuration(StateName: string, Duration: number)
		ClearTimedState(StateName)
		SetState(StateName, true)

		local TimerData: TimedStateData = {
			StartTime = workspace:GetServerTimeNow(),
			Duration = Duration,
			Cancelled = false,
		}

		StateTimers[StateName] = TimerData

		task.delay(Duration, function()
			if not TimerData.Cancelled and StateTimers[StateName] == TimerData then
				SetState(StateName, false)
			end
		end)
	end

	local function GetStateTimeRemaining(StateName: string): number
		local TimerData = StateTimers[StateName]
		if not TimerData then
			return 0
		end

		local Elapsed = workspace:GetServerTimeNow() - TimerData.StartTime
		return math.max(0, TimerData.Duration - Elapsed)
	end

	local function OnStateChanged(StateName: string, Callback: (Value: boolean) -> ()): () -> ()
		if not StateCallbacks[StateName] then
			StateCallbacks[StateName] = {}
		end

		table.insert(StateCallbacks[StateName], Callback)

		return function()
			local Callbacks = StateCallbacks[StateName]
			if Callbacks then
				local Index = table.find(Callbacks, Callback)
				if Index then
					table.remove(Callbacks, Index)
				end
			end
		end
	end

	local function GetAllStates(): { [string]: boolean }
		return table.clone(CurrentStates)
	end

	local function Destroy()
		for StateName in StateTimers do
			ClearTimedState(StateName)
		end

		ComponentTrove:Destroy()

		table.clear(CurrentStates)
		table.clear(StateCallbacks)
		table.clear(StateTimers)
		table.clear(StateChangedSignals)
	end

	return {
		GetState = GetState,
		SetState = SetState,
		SetStateWithDuration = SetStateWithDuration,
		GetStateTimeRemaining = GetStateTimeRemaining,
		OnStateChanged = OnStateChanged,
		GetAllStates = GetAllStates,
		Destroy = Destroy,
	}
end

export type Type = typeof(StateComponent.Create(nil :: any, nil :: any))

return StateComponent