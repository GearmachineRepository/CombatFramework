--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local Enums = require(Shared.Enums)
local CombatTypes = require(Shared.Types.CombatTypes)

local Trove = Packages.Trove
local Signal = Packages.Signal

local Combat = require(Shared.Combat)
local ActionExecutor = Combat.ActionExecutor
local ActionRegistry = Combat.ActionRegistry
local ActionValidator = require(Shared.Combat.ActionValidator)

type ExecutionEntity = CombatTypes.ExecutionEntity
type ExecutionContext = CombatTypes.ExecutionContext

local ActionService = {}

ActionService.Dependencies = { "EntityService" }

ActionService.ActionActivated = Signal.new()
ActionService.ActionCompleted = Signal.new()
ActionService.ActionCanceled = Signal.new()
ActionService.HitConfirmed = Signal.new()

local ServiceTrove: typeof(Trove.new()) = nil :: any
local Cooldowns: { [Player]: { [string]: number } } = {}
local ActiveContexts: { [Model]: ExecutionContext } = {}

local LAG_TOLERANCE = 0.3

local Ensemble: any = nil

local function GetEnsemble(): any
	if not Ensemble then
		Ensemble = require(Server.Ensemble)
	end
	return Ensemble
end

function ActionService.Init()
	ServiceTrove = Trove.new()

	local ActionsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Actions")
	if ActionsFolder then
		ActionRegistry.LoadFolder(ActionsFolder)
	end
end

function ActionService.Start()
	ServiceTrove:Connect(Packets.ActionActivate.OnServerEvent :: any, function(Player: Player, ActionId: string, Timestamp: number)
		ActionService.OnActionRequested(Player, ActionId, Timestamp)
	end)

	ServiceTrove:Connect(Packets.ActionCancel.OnServerEvent :: any, function(Player: Player, ActionId: string)
		ActionService.OnActionCanceled(Player, ActionId)
	end)

	ServiceTrove:Add(Players.PlayerAdded:Connect(function(Player: Player)
		Cooldowns[Player] = {}
	end))

	ServiceTrove:Add(Players.PlayerRemoving:Connect(function(Player: Player)
		Cooldowns[Player] = nil

		if Player.Character then
			ActiveContexts[Player.Character] = nil
		end
	end))

	for _, Player in Players:GetPlayers() do
		Cooldowns[Player] = {}
	end

	local EnsembleModule = GetEnsemble()
	ServiceTrove:Add(EnsembleModule.Events:Subscribe(Enums.Combat.Action.BranchChanged, function(Data: any)
		local Entity = Data.Entity
		local ActionId = Data.ActionId
		local Branch = Data.Branch

		if Entity and Entity.Player then
			Packets.BranchSync:FireClient(Entity.Player, ActionId, Branch)
		end
	end))
end

function ActionService.Stop()
	if ServiceTrove then
		ServiceTrove:Destroy()
	end
end

function ActionService.StartCooldown(Player: Player, ActionId: string, Duration: number)
	local PlayerCooldowns = Cooldowns[Player]
	if not PlayerCooldowns then
		PlayerCooldowns = {}
		Cooldowns[Player] = PlayerCooldowns
	end

	PlayerCooldowns[ActionId] = tick() + Duration
	Packets.CooldownStarted:FireClient(Player, ActionId, Duration)
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

function ActionService.CanActivate(Player: Player, ActionId: string): (boolean, string?)
	local Character = Player.Character
	if not Character then
		return false, "NoCharacter"
	end

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid or Humanoid.Health <= 0 then
		return false, "Dead"
	end

	if ActiveContexts[Character] then
		return false, "ActionActive"
	end

	if ActionService.IsOnCooldown(Player, ActionId) then
		return false, "OnCooldown"
	end

	local ActionDef = ActionRegistry.Get(ActionId)
	if not ActionDef then
		return false, "UnknownAction"
	end

	local Entity: ExecutionEntity = {
		Character = Character,
		Humanoid = Humanoid,
		IsPlayer = true,
		Player = Player,
	}

	local CanUse, Reason = ActionValidator.CanActivate(Entity, ActionDef)
	if not CanUse then
		return false, Reason
	end

	return true, nil
end

function ActionService.OnActionRequested(Player: Player, ActionId: string, Timestamp: number)
	local TimeDiff = math.abs(tick() - Timestamp)
	if TimeDiff > LAG_TOLERANCE then
		Packets.ActionRejected:FireClient(Player, ActionId, "TimestampInvalid")
		return
	end

	local CanUse, Reason = ActionService.CanActivate(Player, ActionId)

	print(ActionId, Reason)

	if not CanUse then
		Packets.ActionRejected:FireClient(Player, ActionId, Reason or "Unknown")
		return
	end

	local ActionDef = ActionRegistry.Get(ActionId)
	if not ActionDef then
		return
	end

	local Character = Player.Character :: Model
	local Humanoid = Character:FindFirstChildOfClass("Humanoid") :: Humanoid

	if ActionDef.Cooldown then
		ActionService.StartCooldown(Player, ActionId, ActionDef.Cooldown)
	end

	Character:SetAttribute("ActiveAction", ActionId)

	local Entity: ExecutionEntity = {
		Character = Character,
		Humanoid = Humanoid,
		IsPlayer = true,
		Player = Player,
	}

	local EnsembleModule = GetEnsemble()

	task.spawn(function()
		local Context = ActionExecutor.CreateContext(Entity, ActionDef, EnsembleModule.Events, "Authoritative")
		ActiveContexts[Character] = Context

		ActionService.ActionActivated:Fire(Entity, ActionId)

		ActionExecutor.Run(Context)

		local WasCanceled = Context.Canceled
		ActiveContexts[Character] = nil

		Character:SetAttribute("ActiveAction", nil)

		if WasCanceled then
			ActionService.ActionCanceled:Fire(Entity, ActionId)
			Packets.ActionEnded:FireClient(Player, ActionId, "Canceled")
		else
			ActionService.ActionCompleted:Fire(Entity, ActionId)
			Packets.ActionEnded:FireClient(Player, ActionId, "Completed")
		end
	end)
end

function ActionService.OnActionCanceled(Player: Player, ActionId: string)
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

	if Context.Properties.CanCancel == false then
		return
	end

	ActionExecutor.Cancel(Context)
end

function ActionService.GetActiveContext(Character: Model): ExecutionContext?
	return ActiveContexts[Character]
end

function ActionService.ForceCancel(Character: Model)
	local Context = ActiveContexts[Character]
	if Context then
		ActionExecutor.Cancel(Context)
	end
end

return ActionService