--!strict

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

local StatComponent = {}

StatComponent.ComponentName = "Stats"
StatComponent.Dependencies = {}

type StatInstance = {
	GetStat: (StatName: string) -> number,
	GetBaseStat: (StatName: string) -> number,
	SetStat: (StatName: string, Value: number) -> (),
	SetBaseStat: (StatName: string, Value: number) -> (),
	ModifyStat: (StatName: string, Delta: number) -> (),
	ModifyBaseStat: (StatName: string, Delta: number) -> (),
	GetAllStats: () -> { [string]: number },
	GetMaxFor: (StatName: string) -> number?,
	OnStatChanged: (StatName: string, Callback: (NewValue: number, OldValue: number) -> ()) -> () -> (),
	RecalculateStat: (StatName: string) -> (),
	Destroy: () -> (),
}

local UPDATE_THRESHOLD = 0.001

function StatComponent.From(EntityInstance: Entity): StatInstance?
	return EntityInstance:GetComponent("Stats")
end

function StatComponent.Create(EntityInstance: Entity, Context: EntityContext): StatInstance
	local Config: StatConfig = Context.StatConfig or {}
	local BaseStats: { [string]: number } = {}
	local CurrentStats: { [string]: number } = {}
	local StatCallbacks: { [string]: { (NewValue: number, OldValue: number) -> () } } = {}
	local Character = EntityInstance.Character
	local ComponentTrove = Trove.new()

	local StatChangedSignals: { [string]: typeof(Signal.new()) } = {}

	local function GetBaseStat(StatName: string): number
		return BaseStats[StatName] or 0
	end

	local function GetStat(StatName: string): number
		return CurrentStats[StatName] or 0
	end

	local function GetMaxFor(StatName: string): number?
		local Definition = Config[StatName]
		if not Definition then
			return nil
		end

		if Definition.MaxStat then
			local MaxStatValue = CurrentStats[Definition.MaxStat]
			if MaxStatValue then
				if Definition.Max then
					return math.min(MaxStatValue, Definition.Max)
				end
				return MaxStatValue
			end
		end

		return Definition.Max
	end

	local function ClampValue(StatName: string, Value: number): number
		local Definition = Config[StatName]
		if not Definition then
			return Value
		end

		local Clamped = Value

		if Definition.Min ~= nil then
			Clamped = math.max(Definition.Min, Clamped)
		end

		local MaxValue = GetMaxFor(StatName)
		if MaxValue ~= nil then
			Clamped = math.min(MaxValue, Clamped)
		end

		return Clamped
	end

	local function NotifyChange(StatName: string, NewValue: number, OldValue: number)
		if math.abs(NewValue - OldValue) < UPDATE_THRESHOLD then
			return
		end

		local Definition = Config[StatName]
		if Definition and Definition.Replicate ~= false and Character then
			Character:SetAttribute(StatName, NewValue)
		end

		local Callbacks = StatCallbacks[StatName]
		if Callbacks then
			for _, Callback in Callbacks do
				task.spawn(Callback, NewValue, OldValue)
			end
		end

		local ChangedSignal = StatChangedSignals[StatName]
		if ChangedSignal then
			ChangedSignal:Fire(NewValue, OldValue)
		end
	end

	local function SetStatInternal(StatName: string, Value: number, UpdateDependents: boolean)
		local ClampedValue = ClampValue(StatName, Value)
		local OldValue = CurrentStats[StatName] or 0

		CurrentStats[StatName] = ClampedValue
		NotifyChange(StatName, ClampedValue, OldValue)

		if UpdateDependents then
			for OtherStatName, OtherDefinition in pairs(Config) do
				if OtherDefinition.MaxStat == StatName then
					local CurrentValue = CurrentStats[OtherStatName] or 0
					local NewClamped = ClampValue(OtherStatName, CurrentValue)
					if math.abs(NewClamped - CurrentValue) >= UPDATE_THRESHOLD then
						CurrentStats[OtherStatName] = NewClamped
						NotifyChange(OtherStatName, NewClamped, CurrentValue)
					end
				end
			end
		end
	end

	local function SetStat(StatName: string, Value: number)
		SetStatInternal(StatName, Value, true)
	end

	local function SetBaseStat(StatName: string, Value: number)
		local Definition = Config[StatName]
		local ClampedBase = Value

		if Definition then
			if Definition.Min ~= nil then
				ClampedBase = math.max(Definition.Min, ClampedBase)
			end
			if Definition.Max ~= nil then
				ClampedBase = math.min(Definition.Max, ClampedBase)
			end
		end

		BaseStats[StatName] = ClampedBase
		SetStatInternal(StatName, ClampedBase, true)
	end

	local function ModifyStat(StatName: string, Delta: number)
		local Current = GetStat(StatName)
		SetStat(StatName, Current + Delta)
	end

	local function ModifyBaseStat(StatName: string, Delta: number)
		local Current = GetBaseStat(StatName)
		SetBaseStat(StatName, Current + Delta)
	end

	local function GetAllStats(): { [string]: number }
		return table.clone(CurrentStats)
	end

	local function OnStatChanged(StatName: string, Callback: (NewValue: number, OldValue: number) -> ()): () -> ()
		if not StatCallbacks[StatName] then
			StatCallbacks[StatName] = {}
		end

		table.insert(StatCallbacks[StatName], Callback)

		return function()
			local Callbacks = StatCallbacks[StatName]
			if Callbacks then
				local Index = table.find(Callbacks, Callback)
				if Index then
					table.remove(Callbacks, Index)
				end
			end
		end
	end

	local function RecalculateStat(StatName: string)
		local Current = CurrentStats[StatName] or 0
		SetStatInternal(StatName, Current, false)
	end

	local function Destroy()
		ComponentTrove:Destroy()
		table.clear(BaseStats)
		table.clear(CurrentStats)
		table.clear(StatCallbacks)
		table.clear(StatChangedSignals)
	end

	for StatName, Definition in Config do
		BaseStats[StatName] = Definition.Default
		CurrentStats[StatName] = Definition.Default
		StatCallbacks[StatName] = {}
		StatChangedSignals[StatName] = ComponentTrove:Construct(Signal)

		if Definition.Replicate ~= false and Character then
			Character:SetAttribute(StatName, Definition.Default)
		end
	end

	return {
		GetStat = GetStat,
		GetBaseStat = GetBaseStat,
		SetStat = SetStat,
		SetBaseStat = SetBaseStat,
		ModifyStat = ModifyStat,
		ModifyBaseStat = ModifyBaseStat,
		GetAllStats = GetAllStats,
		GetMaxFor = GetMaxFor,
		OnStatChanged = OnStatChanged,
		RecalculateStat = RecalculateStat,
		Destroy = Destroy,
	}
end

export type Type = typeof(StatComponent.Create(nil :: any, nil :: any))

return StatComponent