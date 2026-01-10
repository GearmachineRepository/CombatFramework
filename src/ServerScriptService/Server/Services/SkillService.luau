--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local Enums = require(Shared.Enums)
local Combat = require(Shared.Combat)
local CombatTypes = require(Shared.Types.CombatTypes)

local Trove = Packages.Trove
local Signal = Packages.Signal

local Ensemble = require(Server.Ensemble)
local StateComponent = require(Server.Components.StateComponent)
local CombatComponent = require(Server.Components.CombatComponent)
local DamageComponent = require(Server.Components.DamageComponent)

local SkillExecutor = Combat.SkillExecutor
local SkillRegistry = Combat.SkillRegistry
local ToolRegistry = Combat.ToolRegistry

type ExecutionEntity = CombatTypes.ExecutionEntity
type ExecutionContext = CombatTypes.ExecutionContext
type HitData = CombatTypes.HitData

local SkillService = {}

SkillService.Dependencies = { "EntityService" }

SkillService.SkillActivated = Signal.new()
SkillService.SkillCompleted = Signal.new()
SkillService.SkillCanceled = Signal.new()
SkillService.HitConfirmed = Signal.new()

local ServiceTrove: typeof(Trove.new()) = nil :: any
local Cooldowns: { [Player]: { [string]: number } } = {}
local ActiveContexts: { [Model]: ExecutionContext } = {}

local LAG_TOLERANCE = 0.2
local MAX_HIT_RANGE = 25

function SkillService.Init()
	ServiceTrove = Trove.new()

	local SkillsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Skills")
	if SkillsFolder then
		SkillRegistry.LoadFolder(SkillsFolder)
	end

	local ToolsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Tools")
	if ToolsFolder then
		ToolRegistry.LoadFolder(ToolsFolder)
	end
end

function SkillService.Start()
	ServiceTrove:Connect(Packets.SkillActivate.OnServerEvent :: any, function(Player: Player, SkillId: string, Timestamp: number)
		SkillService.OnSkillRequested(Player, SkillId, Timestamp)
	end)

	ServiceTrove:Connect(Packets.SkillCancel.OnServerEvent :: any, function(Player: Player, SkillId: string)
		SkillService.OnSkillCanceled(Player, SkillId)
	end)

	ServiceTrove:Connect(Packets.HitCandidates.OnServerEvent :: any, function(Player: Player, SkillId: string, TargetName: string, Damage: number, Timestamp: number)
		SkillService.OnHitCandidate(Player, SkillId, TargetName, Damage, Timestamp)
	end)

	ServiceTrove:Connect(Players.PlayerRemoving, function(Player: Player)
		Cooldowns[Player] = nil
	end)

	ServiceTrove:Add(Ensemble.Events:Subscribe(Enums.Combat.Hitbox.Hit, function(Data: any)
		SkillService.ProcessHit(Data)
	end))
end

function SkillService.Stop()
	ServiceTrove:Destroy()
	table.clear(Cooldowns)
	table.clear(ActiveContexts)
end

function SkillService.IsOnCooldown(Player: Player, SkillId: string): boolean
	local PlayerCooldowns = Cooldowns[Player]
	if not PlayerCooldowns then
		return false
	end

	local CooldownEnd = PlayerCooldowns[SkillId]
	if not CooldownEnd then
		return false
	end

	return tick() < CooldownEnd
end

function SkillService.StartCooldown(Player: Player, SkillId: string, Duration: number)
	if not Cooldowns[Player] then
		Cooldowns[Player] = {}
	end

	Cooldowns[Player][SkillId] = tick() + Duration
	Packets.CooldownStarted:FireClient(Player, SkillId, Duration)
end

function SkillService.CanActivate(Player: Player, SkillId: string): (boolean, string?)
	if SkillService.IsOnCooldown(Player, SkillId) then
		return false, "OnCooldown"
	end

	local Character = Player.Character
	if not Character then
		return false, "NoCharacter"
	end

	local Entity = Ensemble.GetEntity(Character)
	if not Entity then
		return false, "NoEntity"
	end

	if ActiveContexts[Character] then
		return false, "SkillActive"
	end

	local SkillDef = SkillRegistry.Get(SkillId)
	if not SkillDef then
		return false, "UnknownSkill"
	end

	local States = StateComponent.From(Entity)
	if States then
		if States.GetState("Stunned") then
			return false, "Stunned"
		end

		if States.GetState("Dead") then
			return false, "Dead"
		end
	end

	local CombatComp = CombatComponent.From(Entity)
	if CombatComp and not CombatComp.CanAttack() then
		return false, "CannotAttack"
	end

	local Humanoid = Entity.Humanoid

	if SkillDef.Conditions then
		if SkillDef.Conditions.OnAir == false then
			if Humanoid.FloorMaterial == Enum.Material.Air then
				return false, "NotGrounded"
			end
		elseif SkillDef.Conditions.OnAir == true then
			if Humanoid.FloorMaterial ~= Enum.Material.Air then
				return false, "NotAirborne"
			end
		end
	end

	local Tool = ToolRegistry.GetBySkillId(SkillId)
	if Tool and Tool.GroundOnly then
		if Humanoid.FloorMaterial == Enum.Material.Air then
			return false, "NotGrounded"
		end
	end

	return true, nil
end

function SkillService.OnSkillRequested(Player: Player, SkillId: string, _Timestamp: number)
	local CanUse, Reason = SkillService.CanActivate(Player, SkillId)

	if not CanUse then
		Packets.SkillRejected:FireClient(Player, SkillId, Reason or "Unknown")
		return
	end

	local Character = Player.Character :: Model
	local Entity = Ensemble.GetEntity(Character)
	if not Entity then
		return
	end

	local SkillDef = SkillRegistry.Get(SkillId)
	if not SkillDef then
		return
	end

	local Tool = ToolRegistry.GetBySkillId(SkillId)
	if Tool and Tool.Cooldown then
		SkillService.StartCooldown(Player, SkillId, Tool.Cooldown)
	end

	local CombatComp = CombatComponent.From(Entity)
	if CombatComp then
		CombatComp.SetActiveSkill(SkillId)
	end

	local ExecutionEntity: ExecutionEntity = {
		Character = Character,
		Humanoid = Entity.Humanoid,
		IsPlayer = true,
		Player = Player,
	}

	task.spawn(function()
		local Context = SkillExecutor.Execute(ExecutionEntity, SkillDef, Ensemble.Events)
		ActiveContexts[Character] = Context

		SkillService.SkillActivated:Fire(Entity, SkillId)

		while not Context.Canceled do
			if Context.GetElapsedTime() > 30 then
				Context.Cancel()
				break
			end
			task.wait()
		end

		ActiveContexts[Character] = nil

		if CombatComp then
			CombatComp.SetActiveSkill(nil)
		end

		if Context.Canceled then
			SkillService.SkillCanceled:Fire(Entity, SkillId)
		else
			SkillService.SkillCompleted:Fire(Entity, SkillId)
		end
	end)
end

function SkillService.OnSkillCanceled(Player: Player, _SkillId: string)
	local Character = Player.Character
	if not Character then
		return
	end

	local Context = ActiveContexts[Character]
	if Context then
		SkillExecutor.Cancel(Context)
	end
end

function SkillService.OnHitCandidate(Player: Player, SkillId: string, TargetName: string, Damage: number, Timestamp: number)
	local Character = Player.Character
	if not Character then
		return
	end

	local Context = ActiveContexts[Character]
	if not Context then
		return
	end

	if Context.SkillDefinition.SkillId ~= SkillId then
		return
	end

	local TimeDiff = math.abs(tick() - Timestamp)
	if TimeDiff > LAG_TOLERANCE then
		return
	end

	local CharactersFolder = workspace:FindFirstChild("Characters")
	if not CharactersFolder then
		return
	end

	local TargetCharacter = CharactersFolder:FindFirstChild(TargetName) :: Model?
	if not TargetCharacter then
		return
	end

	local TargetHumanoid = TargetCharacter:FindFirstChildOfClass("Humanoid")
	if not TargetHumanoid or TargetHumanoid.Health <= 0 then
		return
	end

	local AttackerRoot = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local TargetRoot = TargetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not AttackerRoot or not TargetRoot then
		return
	end

	local Distance = (AttackerRoot.Position - TargetRoot.Position).Magnitude
	if Distance > MAX_HIT_RANGE then
		return
	end

	local Entity = Ensemble.GetEntity(Character)
	if not Entity then
		return
	end

	local AdjustedDamage = Damage * (Context.Properties.DamageMultiplier or 1)

	Ensemble.Events:Publish(Enums.Combat.Hitbox.Hit, {
		Attacker = Context.Entity,
		Target = TargetCharacter,
		Damage = AdjustedDamage,
		Stun = 0,
		Position = TargetRoot.Position,
		AttackType = "Melee",
		Blockable = true,
		Block360 = false,
		CancelEnemy = true,
	})
end

function SkillService.ProcessHit(Data: any)
	local Target = Data.Target :: Model
	local Damage = Data.Damage or 0
	local Stun = Data.Stun or 0
	local Position = Data.Position
	local AttackType = Data.AttackType or "Melee"
	local Blockable = Data.Blockable ~= false

	local TargetEntity = Ensemble.GetEntity(Target)

	if TargetEntity then
		local TargetStates = StateComponent.From(TargetEntity)
		if TargetStates then
			if Blockable and TargetStates.GetState("Blocking") then
				return
			end

			if TargetStates.GetState("Invulnerable") then
				return
			end

			if Stun > 0 then
				TargetStates.SetStateWithDuration("Stunned", Stun)
			end
		end

		local TargetDamage = DamageComponent.From(TargetEntity)
		if TargetDamage then
			local SourcePlayer = Data.Attacker and Data.Attacker.Player
			TargetDamage.TakeDamage(Damage, SourcePlayer, nil)
		else
			local TargetHumanoid = Target:FindFirstChildOfClass("Humanoid")
			if TargetHumanoid then
				TargetHumanoid:TakeDamage(Damage)
			end
		end

		local TargetCombat = CombatComponent.From(TargetEntity)
		if TargetCombat and Data.Attacker and Data.Attacker.Player then
			TargetCombat.SetLastAttacker(Data.Attacker.Player)
			TargetCombat.SetLastHitTime(tick())
		end
	else
		local TargetHumanoid = Target:FindFirstChildOfClass("Humanoid")
		if TargetHumanoid then
			TargetHumanoid:TakeDamage(Damage)
		end
	end

	local AttackerCharacter = Data.Attacker and Data.Attacker.Character
	local AttackerEntity = AttackerCharacter and Ensemble.GetEntity(AttackerCharacter)

	if AttackerEntity then
		local AttackerCombat = CombatComponent.From(AttackerEntity)
		if AttackerCombat then
			AttackerCombat.IncrementCombo()
			AttackerCombat.SetLastHitTime(tick())
		end
	end

	Packets.HitConfirmed:Fire(
		AttackerCharacter,
		Target,
		Damage,
		Position,
		AttackType
	)

	SkillService.HitConfirmed:Fire(Data)
end

function SkillService.GetActiveContext(Character: Model): ExecutionContext?
	return ActiveContexts[Character]
end

function SkillService.CancelActiveSkill(Character: Model)
	local Context = ActiveContexts[Character]
	if Context then
		SkillExecutor.Cancel(Context)
	end
end

return SkillService