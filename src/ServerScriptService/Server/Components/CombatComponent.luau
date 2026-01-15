--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Server.Ensemble.Types)
local Packages = require(Shared.Packages)
local StateComponent = require(script.Parent.StateComponent)

local Trove = Packages.Trove
local Signal = Packages.Signal

type Entity = Types.Entity
type EntityContext = Types.EntityContext
type Signal = Types.Signal<number>

local CombatComponent = {}

CombatComponent.ComponentName = "Combat"
CombatComponent.Dependencies = { "States", "Stats" }

type CombatInstance = {
	GetActiveActionId: () -> string?,
	SetActiveAction: (ActionId: string?) -> (),
	CanAttack: () -> boolean,
	CanBlock: () -> boolean,
	IsStunned: () -> boolean,
	GetLastAttacker: () -> Player?,
	SetLastAttacker: (Attacker: Player?) -> (),
	GetComboCount: () -> number,
	IncrementCombo: () -> (),
	ResetCombo: () -> (),
	GetLastHitTime: () -> number,
	SetLastHitTime: (Time: number) -> (),
	OnActionChanged: any,
	OnComboChanged: any,
	Destroy: () -> (),
}

function CombatComponent.From(EntityInstance: Entity): CombatInstance?
	return EntityInstance:GetComponent("Combat")
end

function CombatComponent.Create(EntityInstance: Entity, _Context: EntityContext): CombatInstance
	local States = StateComponent.From(EntityInstance)
	local ComponentTrove = Trove.new()

	local ActiveActionId: string? = nil
	local LastAttacker: Player? = nil
	local ComboCount: number = 0
	local LastHitTime: number = 0

	local ActionChangedSignal = ComponentTrove:Construct(Signal)
	local ComboChangedSignal = ComponentTrove:Construct(Signal)

	local function GetActiveActionId(): string?
		return ActiveActionId
	end

	local function SetActiveAction(ActionId: string?)
		if ActiveActionId == ActionId then
			return
		end
		ActiveActionId = ActionId
		ActionChangedSignal:Fire(ActionId)
	end

	local function CanAttack(): boolean
		if not States then
			return true
		end

		if States.GetState("Stunned") then
			return false
		end

		if States.GetState("Blocking") then
			return false
		end

		if States.GetState("Dead") then
			return false
		end

		return true
	end

	local function CanBlock(): boolean
		if not States then
			return true
		end

		if States.GetState("Stunned") then
			return false
		end

		if States.GetState("Dead") then
			return false
		end

		if ActiveActionId then
			return false
		end

		return true
	end

	local function IsStunned(): boolean
		if not States then
			return false
		end
		return States.GetState("Stunned")
	end

	local function GetLastAttacker(): Player?
		return LastAttacker
	end

	local function SetLastAttacker(Attacker: Player?)
		LastAttacker = Attacker
	end

	local function GetComboCount(): number
		return ComboCount
	end

	local function IncrementCombo()
		ComboCount = ComboCount + 1
		ComboChangedSignal:Fire(ComboCount)
	end

	local function ResetCombo()
		if ComboCount == 0 then
			return
		end
		ComboCount = 0
		ComboChangedSignal:Fire(ComboCount)
	end

	local function GetLastHitTime(): number
		return LastHitTime
	end

	local function SetLastHitTime(Time: number)
		LastHitTime = Time
	end

	local function Destroy()
		ComponentTrove:Destroy()
	end

	return {
		GetActiveActionId = GetActiveActionId,
		SetActiveAction = SetActiveAction,
		CanAttack = CanAttack,
		CanBlock = CanBlock,
		IsStunned = IsStunned,
		GetLastAttacker = GetLastAttacker,
		SetLastAttacker = SetLastAttacker,
		GetComboCount = GetComboCount,
		IncrementCombo = IncrementCombo,
		ResetCombo = ResetCombo,
		GetLastHitTime = GetLastHitTime,
		SetLastHitTime = SetLastHitTime,
		OnActionChanged = ActionChangedSignal,
		OnComboChanged = ComboChangedSignal,
		Destroy = Destroy,
	}
end

export type Type = typeof(CombatComponent.Create(nil :: any, nil :: any))

return CombatComponent