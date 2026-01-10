--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local CombatTypes = require(Shared.Types.CombatTypes)

local TableUtil = Packages.TableUtil

type ExecutionEntity = CombatTypes.ExecutionEntity
type SkillDefinition = CombatTypes.SkillDefinition
type SkillProperties = CombatTypes.SkillProperties
type HitRecord = CombatTypes.HitRecord
type ExecutionContext = CombatTypes.ExecutionContext
type EventBus = CombatTypes.EventBus

local ExecutionContextModule = {}

local DEFAULT_PROPERTIES: SkillProperties = table.freeze({
	DamageMultiplier = 1,
	KnockbackMultiplier = 1,
	Invincible = false,
})

function ExecutionContextModule.Create(
	Entity: ExecutionEntity,
	SkillDefinition: SkillDefinition,
	EventBus: any
): ExecutionContext
	local StartTime = tick()

	local Properties: any = TableUtil.Copy(DEFAULT_PROPERTIES)
	if SkillDefinition.Properties then
		Properties = TableUtil.Assign(Properties, SkillDefinition.Properties)
	end

	local HitRecords: { HitRecord } = {}
	local LastHitTarget: Model? = nil
	local Canceled = false

	local function GetElapsedTime(): number
		return tick() - StartTime
	end

	local function Cancel()
		Canceled = true
	end

	local function RecordHit(Target: Model, Damage: number)
		local Record: HitRecord = {
			Target = Target,
			Timestamp = tick(),
			Damage = Damage,
		}
		table.insert(HitRecords, Record)
		LastHitTarget = Target
	end

	local function HadHitInWindow(WindowSeconds: number): boolean
		local CutoffTime = tick() - WindowSeconds
		for _, Record in HitRecords do
			if Record.Timestamp >= CutoffTime then
				return true
			end
		end
		return false
	end

	local function GetLastHitTarget(): Model?
		return LastHitTarget
	end

	local Context: ExecutionContext = {
		Entity = Entity,
		SkillDefinition = SkillDefinition,
		EventBus = EventBus,
		StartTime = StartTime,
		Canceled = Canceled,
		Properties = Properties,
		HitRecords = HitRecords,
		LastHitTarget = LastHitTarget,

		GetElapsedTime = GetElapsedTime,
		Cancel = Cancel,
		RecordHit = RecordHit,
		HadHitInWindow = HadHitInWindow,
		GetLastHitTarget = GetLastHitTarget,
	}

	return setmetatable({}, {
		__index = function(_, Key)
			if Key == "Canceled" then
				return Canceled
			elseif Key == "HitRecords" then
				return HitRecords
			elseif Key == "LastHitTarget" then
				return LastHitTarget
			else
				return (Context :: any)[Key]
			end
		end,
		__newindex = function(_, Key, Value)
			if Key == "Canceled" then
				Canceled = Value
			end
		end,
	}) :: any
end

return ExecutionContextModule