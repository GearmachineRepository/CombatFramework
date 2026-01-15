--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local CombatTypes = require(Shared.Types.CombatTypes)
local Handlers = require(script.Parent.Handlers)
local ExecutionContextModule = require(script.Parent.ExecutionContext)

type ExecutionEntity = CombatTypes.ExecutionEntity
type ActionDefinition = CombatTypes.ActionDefinition
type ExecutionContext = CombatTypes.ExecutionContext
type Branch = CombatTypes.Branch
type Block = CombatTypes.Block
type HandlerResult = CombatTypes.HandlerResult

local ActionExecutor = {}

function ActionExecutor.CreateContext(
	Entity: ExecutionEntity,
	ActionDefinition: ActionDefinition,
	EventBus: any
): ExecutionContext
	return ExecutionContextModule.Create(Entity, ActionDefinition, EventBus)
end

function ActionExecutor.Run(ExecutionContext: ExecutionContext)
	local Entity = ExecutionContext.Entity
	local ActionDefinition = ExecutionContext.ActionDefinition
	local EventBus = ExecutionContext.EventBus

	EventBus:Publish(Enums.Combat.Action.Activated, {
		Entity = Entity,
		ActionId = ActionDefinition.ActionId,
	})

	local EntryBranch = ActionExecutor.GetEntryBranch(ActionDefinition)
	ActionExecutor.RunBranch(EntryBranch, ExecutionContext)

	if ExecutionContext.Canceled then
		EventBus:Publish(Enums.Combat.Action.Canceled, {
			Entity = Entity,
			ActionId = ActionDefinition.ActionId,
		})
	else
		EventBus:Publish(Enums.Combat.Action.Completed, {
			Entity = Entity,
			ActionId = ActionDefinition.ActionId,
		})
	end
end

function ActionExecutor.Execute(
	Entity: ExecutionEntity,
	ActionDefinition: ActionDefinition,
	EventBus: any
): ExecutionContext
	local ExecutionContext = ActionExecutor.CreateContext(Entity, ActionDefinition, EventBus)
	ActionExecutor.Run(ExecutionContext)
	return ExecutionContext
end

function ActionExecutor.GetEntryBranch(ActionDefinition: ActionDefinition): Branch
	if ActionDefinition.Timeline then
		return { Timeline = ActionDefinition.Timeline }
	end

	if ActionDefinition.Branches then
		for _, BranchData in ActionDefinition.Branches do
			if BranchData.Entry then
				return BranchData
			end
		end

		local MainBranch = ActionDefinition.Branches["Main"]
		if MainBranch then
			return MainBranch
		end
	end

	return { Timeline = {} }
end

function ActionExecutor.RunBranch(BranchData: Branch, ExecutionContext: ExecutionContext)
	local Timeline = BranchData.Timeline
	if not Timeline then
		return
	end

	for _Index, Block in Timeline do
		if ExecutionContext.Canceled then
			break
		end

		local Handler = Handlers.Get(Block.BlockType)
		if not Handler then
			continue
		end

		local Success, Result = pcall(function()
			return Handler.Execute(Block, ExecutionContext)
		end)

		if not Success then
			continue
		end

		local HandlerResult = Result :: HandlerResult?

		if HandlerResult then
			if HandlerResult.JumpToBranch then
				local Branches = ExecutionContext.ActionDefinition.Branches
				local TargetBranch = Branches and Branches[HandlerResult.JumpToBranch]
				if TargetBranch then
					ExecutionContext.EventBus:Publish(Enums.Combat.Action.BranchChanged, {
						Entity = ExecutionContext.Entity,
						ActionId = ExecutionContext.ActionDefinition.ActionId,
						Branch = HandlerResult.JumpToBranch,
					})
					ActionExecutor.RunBranch(TargetBranch, ExecutionContext)
				end
				return
			end

			if HandlerResult.Cancel then
				ExecutionContext.Cancel()
				return
			end
		end
	end
end

function ActionExecutor.Cancel(ExecutionContext: ExecutionContext)
	if ExecutionContext and not ExecutionContext.Canceled then
		ExecutionContext.Cancel()
	end
end

return ActionExecutor