--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local Enums = require(Shared.Enums)
local Combat = require(Shared.Combat)
local EventBus = require(Shared.Utils.EventBus)
local CombatTypes = require(Shared.Types.CombatTypes)

local Trove = Packages.Trove
local Signal = Packages.Signal

local ActionExecutor = Combat.ActionExecutor
local ActionRegistry = Combat.ActionRegistry
local ToolRegistry = Combat.ToolRegistry

type ExecutionEntity = CombatTypes.ExecutionEntity
type ExecutionContext = CombatTypes.ExecutionContext
type ActionDefinition = CombatTypes.ActionDefinition

local LocalPlayer = Players.LocalPlayer :: Player

local CombatController = {}

CombatController.Dependencies = {}

CombatController.ActionActivated = Signal.new()
CombatController.ActionCompleted = Signal.new()
CombatController.ActionCanceled = Signal.new()
CombatController.ActionRejected = Signal.new()
CombatController.HitConfirmed = Signal.new()

local ControllerTrove: typeof(Trove.new()) = nil :: any
local LocalEventBus: typeof(EventBus.new()) = nil :: any
local Cooldowns: { [string]: number } = {}
local ActiveContext: ExecutionContext? = nil

function CombatController.Init()
	ControllerTrove = Trove.new()
	LocalEventBus = EventBus.new()

	local ActionsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Actions")
	if ActionsFolder then
		ActionRegistry.LoadFolder(ActionsFolder)
	end

	local ToolsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Tools")
	if ToolsFolder then
		ToolRegistry.LoadFolder(ToolsFolder)
	end
end

function CombatController.Start()
	ControllerTrove:Connect(Packets.ActionRejected.OnClientEvent :: any, function(ActionId: string, Reason: string)
		CombatController.OnActionRejected(ActionId, Reason)
	end)

	ControllerTrove:Connect(Packets.ActionSync.OnClientEvent :: any, function(ActionId: string, Branch: string, Canceled: boolean)
		CombatController.OnActionSync(ActionId, Branch, Canceled)
	end)

	ControllerTrove:Connect(Packets.CooldownStarted.OnClientEvent :: any, function(ActionId: string, Duration: number)
		CombatController.OnCooldownStarted(ActionId, Duration)
	end)

	ControllerTrove:Connect(Packets.HitConfirmed.OnClientEvent :: any, function(Attacker: Instance?, Target: Instance?, Damage: number, Position: Vector3, AttackType: string)
		CombatController.OnHitConfirmed(Attacker, Target, Damage, Position, AttackType)
	end)
end

function CombatController.Stop()
	ControllerTrove:Destroy()
	LocalEventBus:Destroy()
	table.clear(Cooldowns)
	ActiveContext = nil
end

function CombatController.IsOnCooldown(ActionId: string): boolean
	local CooldownEnd = Cooldowns[ActionId]
	if not CooldownEnd then
		return false
	end
	return tick() < CooldownEnd
end

function CombatController.CanActivate(ActionId: string): (boolean, string?)
	if CombatController.IsOnCooldown(ActionId) then
		return false, "OnCooldown"
	end

	local Character = LocalPlayer.Character
	if not Character then
		return false, "NoCharacter"
	end

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid or Humanoid.Health <= 0 then
		return false, "Dead"
	end

	if ActiveContext then
		return false, "ActionActive"
	end

	local ActionDef = ActionRegistry.Get(ActionId)
	if not ActionDef then
		return false, "UnknownAction"
	end

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

	return true, nil
end

function CombatController.ActivateAction(ActionId: string): boolean
    local CanUse, _Reason = CombatController.CanActivate(ActionId)
    if not CanUse then
        return false
    end

    local ActionDef = ActionRegistry.Get(ActionId)
    if not ActionDef then
        return false
    end

    local Character = LocalPlayer.Character :: Model
    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid then
        return false
    end

    local Tool = ToolRegistry.GetByActionId(ActionId)
    if Tool and Tool.Cooldown then
        Cooldowns[ActionId] = tick() + Tool.Cooldown
    end

    local Entity: ExecutionEntity = {
        Character = Character,
        Humanoid = Humanoid,
        IsPlayer = true,
        Player = LocalPlayer,
    }

    Packets.ActionActivate:Fire(ActionId, tick())

	task.spawn(function()
		local Context = ActionExecutor.CreateContext(Entity, ActionDef, LocalEventBus)
		ActiveContext = Context

		CombatController.ActionActivated:Fire(ActionId)

		ActionExecutor.Run(Context)

		local WasCanceled = Context.Canceled
		ActiveContext = nil

		if WasCanceled then
			CombatController.ActionCanceled:Fire(ActionId)
		else
			CombatController.ActionCompleted:Fire(ActionId)
		end
	end)

	return true
end

function CombatController.CancelAction()
	if ActiveContext then
		local ActionId = ActiveContext.ActionDefinition.ActionId
		ActionExecutor.Cancel(ActiveContext)
		Packets.ActionCancel:Fire(ActionId)
	end
end

function CombatController.OnActionRejected(ActionId: string, Reason: string)
	if ActiveContext and ActiveContext.ActionDefinition.ActionId == ActionId then
		ActionExecutor.Cancel(ActiveContext)
	end

	CombatController.ActionRejected:Fire(ActionId, Reason)
end

function CombatController.OnActionSync(ActionId: string, _Branch: string, Canceled: boolean)
	if Canceled and ActiveContext then
		if ActiveContext.ActionDefinition.ActionId == ActionId then
			ActionExecutor.Cancel(ActiveContext)
		end
	end
end

function CombatController.OnCooldownStarted(ActionId: string, Duration: number)
	Cooldowns[ActionId] = tick() + Duration
end

function CombatController.OnHitConfirmed(Attacker: Instance?, Target: Instance?, Damage: number, Position: Vector3, AttackType: string)
	local HitData = {
		Attacker = Attacker,
		Target = Target,
		Damage = Damage,
		Position = Position,
		AttackType = AttackType,
	}

	CombatController.HitConfirmed:Fire(HitData)

	LocalEventBus:Publish(Enums.Combat.Hitbox.Hit, HitData)
end

function CombatController.IsActionActive(): boolean
	return ActiveContext ~= nil
end

function CombatController.GetActiveActionId(): string?
	if ActiveContext then
		return ActiveContext.ActionDefinition.ActionId
	end
	return nil
end

function CombatController.GetEventBus(): typeof(EventBus.new())
	return LocalEventBus
end

return CombatController