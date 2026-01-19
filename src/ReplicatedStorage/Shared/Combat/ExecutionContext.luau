--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local CombatTypes = require(Shared.Types.CombatTypes)

local TableUtil = Packages.TableUtil
local Trove = Packages.Trove

type ExecutionEntity = CombatTypes.ExecutionEntity
type ActionDefinition = CombatTypes.ActionDefinition
type ActionProperties = CombatTypes.ActionProperties
type HitRecord = CombatTypes.HitRecord
type ExecutionContext = CombatTypes.ExecutionContext
type ExecutionMode = CombatTypes.ExecutionMode
type EventBus = CombatTypes.EventBus

local ExecutionContextModule = {}

local DEFAULT_PROPERTIES: ActionProperties = table.freeze({
	DamageMultiplier = 1,
	KnockbackMultiplier = 1,
	Invincible = false,
	SuperArmor = false,
	CanCancel = true,
})

function ExecutionContextModule.Create(
	Entity: ExecutionEntity,
	ActionDefinition: ActionDefinition,
	EventBus: any,
	Mode: ExecutionMode
): ExecutionContext
	local StartTime = tick()

	local Properties: any = TableUtil.Copy(DEFAULT_PROPERTIES)
	if ActionDefinition.Properties then
		Properties = TableUtil.Assign(Properties, ActionDefinition.Properties)
	end

	local HitRecords: { HitRecord } = {}
	local LastHitTarget: Model? = nil
	local GrabTarget: Model? = nil
	local Canceled = false

	local CurrentAnimationId: string? = nil
	local CurrentAnimationSpeed: number = 1
	local CurrentAnimationTrack: AnimationTrack? = nil

	local ContextTrove = Trove.new()

	local function GetElapsedTime(): number
		return tick() - StartTime
	end

	local function Cancel()
		Canceled = true
		ContextTrove:Clean()
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

	local function SetGrabTarget(Target: Model?)
		GrabTarget = Target
	end

	local function GetGrabTarget(): Model?
		return GrabTarget
	end

	local function SetCurrentAnimation(AnimationId: string, Track: AnimationTrack?, Speed: number?)
		CurrentAnimationId = AnimationId
		CurrentAnimationTrack = Track
		CurrentAnimationSpeed = Speed or 1
	end

	local function GetCurrentAnimationId(): string?
		return CurrentAnimationId
	end

	local function GetCurrentAnimationSpeed(): number
		return CurrentAnimationSpeed
	end

	local function GetCurrentAnimationTrack(): AnimationTrack?
		return CurrentAnimationTrack
	end

	local Context: ExecutionContext = {
		Entity = Entity,
		ActionDefinition = ActionDefinition,
		EventBus = EventBus,
		Mode = Mode,
		StartTime = StartTime,
		Canceled = Canceled,
		Properties = Properties,
		HitRecords = HitRecords,
		LastHitTarget = LastHitTarget,
		GrabTarget = GrabTarget,
		Trove = ContextTrove,

		GetElapsedTime = GetElapsedTime,
		Cancel = Cancel,
		RecordHit = RecordHit,
		HadHitInWindow = HadHitInWindow,
		GetLastHitTarget = GetLastHitTarget,
		SetGrabTarget = SetGrabTarget,
		GetGrabTarget = GetGrabTarget,
		SetCurrentAnimation = SetCurrentAnimation,
		GetCurrentAnimationId = GetCurrentAnimationId,
		GetCurrentAnimationSpeed = GetCurrentAnimationSpeed,
		GetCurrentAnimationTrack = GetCurrentAnimationTrack,
	}

	return setmetatable({}, {
		__index = function(_, Key)
			if Key == "Canceled" then
				return Canceled
			elseif Key == "HitRecords" then
				return HitRecords :: any
			elseif Key == "LastHitTarget" then
				return LastHitTarget :: any
			elseif Key == "GrabTarget" then
				return GrabTarget :: any
			elseif Key == "Trove" then
				return ContextTrove :: any
			else
				return (Context :: any)[Key]
			end
		end,
		__newindex = function(_, Key, Value)
			if Key == "Canceled" then
				Canceled = Value
			elseif Key == "GrabTarget" then
				GrabTarget = Value :: any
			end
		end,
	}) :: any
end

return ExecutionContextModule