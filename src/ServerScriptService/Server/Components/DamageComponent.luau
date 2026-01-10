--!strict

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

type DamageInstance = {
	TakeDamage: (Amount: number, Source: Player?, Direction: Vector3?) -> (),
	IsInvulnerable: () -> boolean,
	OnDamaged: typeof(Signal.new()),
	Destroy: () -> (),
}

function DamageComponent.From(EntityInstance: Entity): DamageInstance?
	return EntityInstance:GetComponent("Damage")
end

function DamageComponent.Create(EntityInstance: Entity, _Context: EntityContext): DamageInstance
	local States = StateComponent.From(EntityInstance)
	local Stats = StatComponent.From(EntityInstance)
	local Modifiers = ModifierComponent.From(EntityInstance)
	local Humanoid = EntityInstance.Humanoid
	local ComponentTrove = Trove.new()

	local DamagedSignal = ComponentTrove:Construct(Signal)

	local function IsInvulnerable(): boolean
		if not States then
			return false
		end
		return States.GetState("Invulnerable")
	end

	local function TakeDamage(Amount: number, Source: Player?, Direction: Vector3?)
		if IsInvulnerable() then
			return
		end

		local ModifiedDamage = Amount

		if Modifiers then
			ModifiedDamage = Modifiers.Apply("DamageTaken", Amount, {
				Source = Source,
				Direction = Direction,
			})
		end

		local OldHealth = Humanoid.Health
		local NewHealth = math.max(0, Humanoid.Health - ModifiedDamage)
		Humanoid.Health = NewHealth

		if Stats then
			Stats.SetStat("Health", NewHealth)
		end

		DamagedSignal:Fire({
			Amount = ModifiedDamage,
			Source = Source,
			Direction = Direction,
			OldHealth = OldHealth,
			NewHealth = NewHealth,
		})
	end

	local function Destroy()
		ComponentTrove:Destroy()
	end

	return {
		TakeDamage = TakeDamage,
		IsInvulnerable = IsInvulnerable,
		OnDamaged = DamagedSignal,
		Destroy = Destroy,
	}
end

export type Type = typeof(DamageComponent.Create(nil :: any, nil :: any))

return DamageComponent