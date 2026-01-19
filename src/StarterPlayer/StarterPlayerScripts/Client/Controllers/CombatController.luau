--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local CombatTypes = require(Shared.Types.CombatTypes)
local EventBus = require(Shared.Utils.EventBus)

local Trove = Packages.Trove
local Signal = Packages.Signal

local Combat = require(Shared.Combat)
local ActionExecutor = Combat.ActionExecutor
local ActionRegistry = Combat.ActionRegistry
local ActionValidator = require(Shared.Combat.ActionValidator)

type ExecutionEntity = CombatTypes.ExecutionEntity
type ExecutionContext = CombatTypes.ExecutionContext
type ActionDefinition = CombatTypes.ActionDefinition

local LocalPlayer = Players.LocalPlayer :: Player

local CombatController = {}

CombatController.Dependencies = {}

CombatController.ActionStarted = Signal.new()
CombatController.ActionEnded = Signal.new()
CombatController.ActionRejected = Signal.new()
CombatController.HitConfirmed = Signal.new()
CombatController.BranchChanged = Signal.new()

local ControllerTrove: typeof(Trove.new()) = nil :: any
local LocalEventBus: typeof(EventBus.new()) = nil :: any
local Cooldowns: { [string]: number } = {}
local ActiveContext: ExecutionContext? = nil
local CurrentActionId: string? = nil

function CombatController.Init()
	ControllerTrove = Trove.new()
	LocalEventBus = EventBus.new()

	local ActionsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Actions")
	if ActionsFolder then
		ActionRegistry.LoadFolder(ActionsFolder)
	end
end

function CombatController.Start()
	ControllerTrove:Add(Packets.ActionRejected.OnClientEvent:Connect(function(ActionId: string, Reason: string)
		CombatController.OnActionRejected(ActionId, Reason)
	end))

	ControllerTrove:Add(Packets.ActionEnded.OnClientEvent:Connect(function(ActionId: string, Reason: string)
		CombatController.OnActionEnded(ActionId, Reason)
	end))

	ControllerTrove:Add(Packets.BranchSync.OnClientEvent:Connect(function(ActionId: string, BranchName: string)
		CombatController.OnBranchSync(ActionId, BranchName)
	end))

	ControllerTrove:Add(Packets.HitConfirmed.OnClientEvent:Connect(function(
		AttackerCharacter: Instance,
		TargetCharacter: Instance,
		Damage: number,
		Position: Vector3,
		AttackType: string
	)
		CombatController.OnHitConfirmed(AttackerCharacter :: Model, TargetCharacter :: Model, Damage, Position, AttackType)
	end))

	ControllerTrove:Add(Packets.CooldownStarted.OnClientEvent:Connect(function(ActionId: string, Duration: number)
		CombatController.OnCooldownStarted(ActionId, Duration)
	end))

	ControllerTrove:Add(Packets.GrabSync.OnClientEvent:Connect(function(
		EventType: string,
		AttackerCharacter: Instance,
		TargetCharacter: Instance,
		AttackerAnimation: string?,
		TargetAnimation: string?
	)
		CombatController.OnGrabSync(EventType, AttackerCharacter :: Model, TargetCharacter :: Model, AttackerAnimation, TargetAnimation)
	end))
end

function CombatController.Stop()
	if ControllerTrove then
		ControllerTrove:Destroy()
	end
end

function CombatController.IsOnCooldown(ActionId: string): boolean
	local CooldownEnd = Cooldowns[ActionId]
	if not CooldownEnd then
		return false
	end
	return tick() < CooldownEnd
end

function CombatController.CanActivate(ActionId: string): (boolean, string?)
	if ActiveContext then
		return false, "ActionActive"
	end

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

	local ActionDef = ActionRegistry.Get(ActionId)
	if not ActionDef then
		return false, "UnknownAction"
	end

	local Entity: ExecutionEntity = {
		Character = Character,
		Humanoid = Humanoid,
		IsPlayer = true,
		Player = LocalPlayer,
	}

	local CanUse, Reason = ActionValidator.CanActivate(Entity, ActionDef)
	if not CanUse then
		return false, Reason
	end

	return true, nil
end

function CombatController.ActivateAction(ActionId: string): boolean
	local CanUse, Reason = CombatController.CanActivate(ActionId)
	if not CanUse then
		CombatController.ActionRejected:Fire(ActionId, Reason)
		return false
	end

	local ActionDef = ActionRegistry.Get(ActionId)
	if not ActionDef then
		return false
	end

	local Character = LocalPlayer.Character :: Model
	local Humanoid = Character:FindFirstChildOfClass("Humanoid") :: Humanoid

	local Entity: ExecutionEntity = {
		Character = Character,
		Humanoid = Humanoid,
		IsPlayer = true,
		Player = LocalPlayer,
	}

	Packets.ActionActivate:Fire(ActionId, tick())

	ActiveContext = ActionExecutor.CreateContext(Entity, ActionDef, LocalEventBus, "Predictive")
	CurrentActionId = ActionId

	CombatController.ActionStarted:Fire(ActionId)

	task.spawn(function()
		ActionExecutor.Run(ActiveContext :: ExecutionContext)

		if ActiveContext and CurrentActionId == ActionId then
			ActiveContext = nil
			CurrentActionId = nil
		end
	end)

	return true
end

function CombatController.CancelAction(ActionId: string)
	if not ActiveContext then
		return
	end

	if CurrentActionId ~= ActionId then
		return
	end

	Packets.ActionCancel:Fire(ActionId)
end

function CombatController.OnActionRejected(ActionId: string, Reason: string)
	if ActiveContext and CurrentActionId == ActionId then
		ActionExecutor.Cancel(ActiveContext)
		ActiveContext = nil
		CurrentActionId = nil
	end

	CombatController.ActionRejected:Fire(ActionId, Reason)
end

function CombatController.OnActionEnded(ActionId: string, Reason: string)
	if ActiveContext and CurrentActionId == ActionId then
		ActionExecutor.Cancel(ActiveContext)
		ActiveContext = nil
		CurrentActionId = nil
	end

	CombatController.ActionEnded:Fire(ActionId, Reason)
end

function CombatController.OnBranchSync(ActionId: string, BranchName: string)
	local ActionDef = ActionRegistry.Get(ActionId)
	if not ActionDef then
		return
	end

	local Character = LocalPlayer.Character
	if not Character then
		return
	end

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		return
	end

	local Entity: ExecutionEntity = {
		Character = Character,
		Humanoid = Humanoid,
		IsPlayer = true,
		Player = LocalPlayer,
	}

	if ActiveContext then
		ActionExecutor.Cancel(ActiveContext)
	end

	ActiveContext = ActionExecutor.CreateContext(Entity, ActionDef, LocalEventBus, "Predictive")
	CurrentActionId = ActionId

	local Branch = ActionDef.Branches and ActionDef.Branches[BranchName]
	if Branch then
		task.spawn(function()
			ActionExecutor.RunBranch(Branch, ActiveContext :: ExecutionContext)

			if ActiveContext and CurrentActionId == ActionId then
				ActiveContext = nil
				CurrentActionId = nil
			end
		end)
	end

	CombatController.BranchChanged:Fire(ActionId, BranchName)
end

function CombatController.OnHitConfirmed(
	AttackerCharacter: Model,
	TargetCharacter: Model,
	Damage: number,
	Position: Vector3,
	AttackType: string
)
	CombatController.HitConfirmed:Fire(AttackerCharacter, TargetCharacter, Damage, Position, AttackType)
end

function CombatController.OnCooldownStarted(ActionId: string, Duration: number)
	Cooldowns[ActionId] = tick() + Duration
end

function CombatController.OnGrabSync(
	EventType: string,
	AttackerCharacter: Model,
	TargetCharacter: Model,
	AttackerAnimation: string?,
	TargetAnimation: string?
)
	local MyCharacter = LocalPlayer.Character
	if not MyCharacter then
		return
	end

	if EventType == "GrabStarted" then
		local IsAttacker = AttackerCharacter == MyCharacter
		local IsTarget = TargetCharacter == MyCharacter

		if IsAttacker and AttackerAnimation then
			CombatController.PlayGrabAnimation(AttackerCharacter, AttackerAnimation)
		elseif IsTarget and TargetAnimation then
			CombatController.PlayGrabAnimation(TargetCharacter, TargetAnimation)
		end
	-- elseif EventType == "GrabEnded" then
		-- Cleanup if needed
	end
end

function CombatController.PlayGrabAnimation(Character: Model, AnimationId: string)
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		return
	end

	local Animator = Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		return
	end

	local Animation = Instance.new("Animation")
	Animation.AnimationId = AnimationId

	local Track = Animator:LoadAnimation(Animation)
	Track:Play()

	Animation:Destroy()
end

function CombatController.SendGrabInput(InputType: string)
	Packets.GrabInput:Fire(InputType)
end

function CombatController.GetActiveActionId(): string?
	return CurrentActionId
end

function CombatController.IsActionActive(): boolean
	return ActiveContext ~= nil
end

return CombatController