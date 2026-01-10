--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ServerScriptService.Server.Ensemble.Types)
local StateComponent = require(script.Parent.StateComponent)
local StatComponent = require(script.Parent.StatComponent)
local ModifierComponent = require(script.Parent.ModifierComponent)

type Entity = Types.Entity
type EntityContext = Types.EntityContext

local DamageComponent = {}

DamageComponent.ComponentName = "Damage"
DamageComponent.Dependencies = { "States", "Stats", "Modifiers" }

type DamageInstance = {
	TakeDamage: (Amount: number, Source: Player?, Direction: Vector3?) -> (),
	IsInvulnerable: () -> boolean,
	Destroy: () -> (),
}

function DamageComponent.From(Entity: Entity): Type?
	return Entity:GetComponent("Damage")
end

function DamageComponent.Create(Entity: Entity, _Context: EntityContext): DamageInstance
	local States = StateComponent.From(Entity)
	local Stats = StatComponent.From(Entity)
	local Modifiers = ModifierComponent.From(Entity)
	local Humanoid = Entity.Humanoid

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

		local NewHealth = math.max(0, Humanoid.Health - ModifiedDamage)
		Humanoid.Health = NewHealth

		if Stats then
			Stats.SetStat("Health", NewHealth)
		end
	end

	local function Destroy()
	end

	return {
		TakeDamage = TakeDamage,
		IsInvulnerable = IsInvulnerable,
		Destroy = Destroy,
	}
end

export type Type = typeof(DamageComponent.Create(nil :: any, nil :: any))

return DamageComponent