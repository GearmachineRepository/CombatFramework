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

local ActionExecutor = Combat.ActionExecutor
local ActionRegistry = Combat.ActionRegistry
local ToolRegistry = Combat.ToolRegistry

type ExecutionEntity = CombatTypes.ExecutionEntity
type ExecutionContext = CombatTypes.ExecutionContext
type HitData = CombatTypes.HitData

local ActionService = {}

ActionService.Dependencies = { "EntityService" }

ActionService.ActionActivated = Signal.new()
ActionService.ActionCompleted = Signal.new()
ActionService.ActionCanceled = Signal.new()
ActionService.HitConfirmed = Signal.new()

local ServiceTrove: typeof(Trove.new()) = nil :: any
local Cooldowns: { [Player]: { [string]: number } } = {}
local ActiveContexts: { [Model]: ExecutionContext } = {}

local LAG_TOLERANCE = 0.2
local MAX_HIT_RANGE = 25

function ActionService.Init()
	ServiceTrove = Trove.new()

	local ActionsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Actions")
	if ActionsFolder then
		ActionRegistry.LoadFolder(ActionsFolder)
	end

	local ToolsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Tools")
	if ToolsFolder then
		ToolRegistry.LoadFolder(ToolsFolder)
	end
end

function ActionService.Start()
	ServiceTrove:Connect(Packets.ActionActivate.OnServerEvent :: any, function(Player: Player, ActionId: string, Timestamp: number)
		ActionService.OnActionRequested(Player, ActionId, Timestamp)
	end)

	ServiceTrove:Connect(Packets.ActionCancel.OnServerEvent :: any, function(Player: Player, ActionId: string)
		ActionService.OnActionCanceled(Player, ActionId)
	end)

	ServiceTrove:Connect(Packets.HitCandidates.OnServerEvent :: any, function(
		Player: Player,
		ActionId: string,
		TargetName: string,
		Damage: number,
		Stun: number,
		AttackType: string,
		Blockable: boolean,
		Block360: boolean,
		CancelEnemy: boolean,
		Timestamp: number
	)
		ActionService.OnHitCandidate(Player, ActionId, TargetName, Damage, Stun, AttackType, Blockable, Block360, CancelEnemy, Timestamp)
	end)

	ServiceTrove:Connect(Players.PlayerRemoving, function(Player: Player)
		Cooldowns[Player] = nil
	end)

	ServiceTrove:Add(Ensemble.Events:Subscribe(Enums.Combat.Hitbox.Hit, function(Data: any)
		ActionService.ProcessHit(Data)
	end))
end

function ActionService.Stop()
	ServiceTrove:Destroy()
	table.clear(Cooldowns)
	table.clear(ActiveContexts)
end

function ActionService.IsOnCooldown(Player: Player, ActionId: string): boolean
	local PlayerCooldowns = Cooldowns[Player]
	if not PlayerCooldowns then
		return false
	end

	local CooldownEnd = PlayerCooldowns[ActionId]
	if not CooldownEnd then
		return false
	end

	return tick() < CooldownEnd
end

function ActionService.StartCooldown(Player: Player, ActionId: string, Duration: number)
	if not Cooldowns[Player] then
		Cooldowns[Player] = {}
	end

	Cooldowns[Player][ActionId] = tick() + Duration
	Packets.CooldownStarted:FireClient(Player, ActionId, Duration)
end

function ActionService.CanActivate(Player: Player, ActionId: string): (boolean, string?)
	if ActionService.IsOnCooldown(Player, ActionId) then
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
		return false, "ActionActive"
	end

	local ActionDef = ActionRegistry.Get(ActionId)
	if not ActionDef then
		return false, "UnknownAction"
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

	if ActionDef.Conditions then
		if ActionDef.Conditions.OnAir == false then
			if Humanoid.FloorMaterial == Enum.Material.Air then
				return false, "NotGrounded"
			end
		elseif ActionDef.Conditions.OnAir == true then
			if Humanoid.FloorMaterial ~= Enum.Material.Air then
				return false, "NotAirborne"
			end
		end
	end

	local Tool = ToolRegistry.GetByActionId(ActionId)
	if Tool and Tool.GroundOnly then
		if Humanoid.FloorMaterial == Enum.Material.Air then
			return false, "NotGrounded"
		end
	end

	return true, nil
end

function ActionService.OnActionRequested(Player: Player, ActionId: string, _Timestamp: number)
	local CanUse, Reason = ActionService.CanActivate(Player, ActionId)

	if not CanUse then
		Packets.ActionRejected:FireClient(Player, ActionId, Reason or "Unknown")
		return
	end

	local Character = Player.Character :: Model
	local Entity = Ensemble.GetEntity(Character)
	if not Entity then
		return
	end

	local ActionDef = ActionRegistry.Get(ActionId)
	if not ActionDef then
		return
	end

	local Tool = ToolRegistry.GetByActionId(ActionId)
	if Tool and Tool.Cooldown then
		ActionService.StartCooldown(Player, ActionId, Tool.Cooldown)
	end

	local CombatComp = CombatComponent.From(Entity)
	if CombatComp then
		CombatComp.SetActiveAction(ActionId)
	end

	local ExecutionEntity: ExecutionEntity = {
		Character = Character,
		Humanoid = Entity.Humanoid,
		IsPlayer = true,
		Player = Player,
	}

	task.spawn(function()
		local Context = ActionExecutor.CreateContext(ExecutionEntity, ActionDef, Ensemble.Events)
		ActiveContexts[Character] = Context

		ActionService.ActionActivated:Fire(Entity, ActionId)

		ActionExecutor.Run(Context)

		local WasCanceled = Context.Canceled
		ActiveContexts[Character] = nil

		if CombatComp then
			CombatComp.SetActiveAction(nil)
		end

		if WasCanceled then
			ActionService.ActionCanceled:Fire(Entity, ActionId)
		else
			ActionService.ActionCompleted:Fire(Entity, ActionId)
		end
	end)
end

function ActionService.OnActionCanceled(Player: Player, _ActionId: string)
	local Character = Player.Character
	if not Character then
		return
	end

	local Context = ActiveContexts[Character]
	if Context then
		ActionExecutor.Cancel(Context)
	end
end

function ActionService.OnHitCandidate(
    Player: Player,
    ActionId: string,
    TargetName: string,
    Damage: number,
    Stun: number,
    AttackType: string,
    Blockable: boolean,
    Block360: boolean,
    CancelEnemy: boolean,
    Timestamp: number
)
	local Character = Player.Character
	if not Character then
		return
	end

	local Context = ActiveContexts[Character]
	if not Context then
		return
	end

	if Context.ActionDefinition.ActionId ~= ActionId then
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
        Stun = Stun,
        Position = TargetRoot.Position,
        AttackType = AttackType,
        Blockable = Blockable,
        Block360 = Block360,
        CancelEnemy = CancelEnemy,
    })
end

function ActionService.ProcessHit(Data: any)
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

	ActionService.HitConfirmed:Fire(Data)
end

function ActionService.GetActiveContext(Character: Model): ExecutionContext?
	return ActiveContexts[Character]
end

function ActionService.CancelActiveAction(Character: Model)
	local Context = ActiveContexts[Character]
	if Context then
		ActionExecutor.Cancel(Context)
	end
end

return ActionService