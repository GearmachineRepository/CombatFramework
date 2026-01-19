--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)
local ActionExecutor = require(script.Parent.Parent.ActionExecutor)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local ActionHandler = {}

local ActionRegistry: any = nil

local function GetActionRegistry(): any
	if not ActionRegistry then
		ActionRegistry = require(Shared.Combat.ActionRegistry)
	end
	return ActionRegistry
end

function ActionHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if not IsServer then
		return nil
	end

	if Context.Mode ~= "Authoritative" then
		return nil
	end

	local ActionId = Block.ActionId
	local CancelLast = Block.CancelLast or false

	if not ActionId or ActionId == "" then
		return nil
	end

	if ActionId == "Cancel" then
		return { Cancel = true }
	end

	local Registry = GetActionRegistry()
	local ActionDef = Registry.Get(ActionId)

	if not ActionDef then
		warn(string.format("[ActionHandler] Unknown Action: %s", ActionId))
		return nil
	end

	local SubContext = ActionExecutor.Execute(Context.Entity, ActionDef, Context.EventBus, Context.Mode)

	for _, Record in SubContext.HitRecords do
		Context.RecordHit(Record.Target, Record.Damage)
	end

	if CancelLast and SubContext.Canceled then
		return { Cancel = true }
	end

	return nil
end

return ActionHandler