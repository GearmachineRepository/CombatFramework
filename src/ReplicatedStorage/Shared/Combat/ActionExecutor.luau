--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local CombatTypes = require(Shared.Types.CombatTypes)
local ExecutionContextModule = require(script.Parent.ExecutionContext)

type ExecutionEntity = CombatTypes.ExecutionEntity
type ActionDefinition = CombatTypes.ActionDefinition
type ExecutionContext = CombatTypes.ExecutionContext
type ExecutionMode = CombatTypes.ExecutionMode
type Branch = CombatTypes.Branch
type Block = CombatTypes.Block
type HandlerResult = CombatTypes.HandlerResult

local ActionExecutor = {}

local Handlers: any = nil

local PREDICTABLE_BLOCKS: { [string]: boolean } = {
	Animation = true,
	Sound = true,
	Velocity = true,
	Wait = true,
}

local SERVER_ONLY_BLOCKS: { [string]: boolean } = {
	Hitbox = true,
	HitCancel = true,
	Grab = true,
	AddHealth = true,
	AddEvasive = true,
}

local function GetHandlers(): any
	if not Handlers then
		Handlers = require(script.Parent.Handlers)
	end
	return Handlers
end

local function ShouldRunBlock(BlockType: string, Mode: ExecutionMode): boolean
	if Mode == "Authoritative" then
		return true
	end

	if Mode == "Predictive" then
		return PREDICTABLE_BLOCKS[BlockType] == true
	end

	return false
end

function ActionExecutor.CreateContext(
	Entity: ExecutionEntity,
	ActionDefinition: ActionDefinition,
	EventBus: any,
	Mode: ExecutionMode
): ExecutionContext
	return ExecutionContextModule.Create(Entity, ActionDefinition, EventBus, Mode)
end

function ActionExecutor.Run(Context: ExecutionContext)
	local Entity = Context.Entity
	local ActionDefinition = Context.ActionDefinition
	local EventBus = Context.EventBus
	local Mode = Context.Mode

	if Mode == "Authoritative" then
		EventBus:Publish(Enums.Combat.Action.Activated, {
			Entity = Entity,
			ActionId = ActionDefinition.ActionId,
		})
	end

	local EntryBranch = ActionExecutor.GetEntryBranch(ActionDefinition)
	ActionExecutor.RunBranch(EntryBranch, Context)

	if Mode == "Authoritative" then
		if Context.Canceled then
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
end

function ActionExecutor.Execute(
	Entity: ExecutionEntity,
	ActionDefinition: ActionDefinition,
	EventBus: any,
	Mode: ExecutionMode
): ExecutionContext
	local Context = ActionExecutor.CreateContext(Entity, ActionDefinition, EventBus, Mode)
	ActionExecutor.Run(Context)
	return Context
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

function ActionExecutor.RunBranch(BranchData: Branch, Context: ExecutionContext): string?
	local Timeline = BranchData.Timeline
	if not Timeline then
		return nil
	end

	local HandlerModule = GetHandlers()

	for _, Block in Timeline do
		if Context.Canceled then
			break
		end

		local BlockType = Block.BlockType

		if not ShouldRunBlock(BlockType, Context.Mode) then
			if BlockType == "Wait" then
				task.wait(Block.Time or 0)
			end
			continue
		end

		local Handler = HandlerModule.Get(BlockType)
		if not Handler then
			continue
		end

		local Success, Result = pcall(function()
			return Handler.Execute(Block, Context)
		end)

		if not Success then
			warn(string.format("[ActionExecutor] Handler error for %s: %s", BlockType, tostring(Result)))
			continue
		end

		local HandlerResult = Result :: HandlerResult?

		if HandlerResult then
			if HandlerResult.JumpToBranch then
				local Branches = Context.ActionDefinition.Branches
				local TargetBranch = Branches and Branches[HandlerResult.JumpToBranch]
				if TargetBranch then
					if Context.Mode == "Authoritative" then
						Context.EventBus:Publish(Enums.Combat.Action.BranchChanged, {
							Entity = Context.Entity,
							ActionId = Context.ActionDefinition.ActionId,
							Branch = HandlerResult.JumpToBranch,
						})
					end
					ActionExecutor.RunBranch(TargetBranch, Context)
				end
				return HandlerResult.JumpToBranch
			end

			if HandlerResult.Cancel then
				Context.Cancel()
				return nil
			end
		end
	end

	return nil
end

function ActionExecutor.RunBranchByName(BranchName: string, Context: ExecutionContext): string?
	local Branches = Context.ActionDefinition.Branches
	if not Branches then
		return nil
	end

	local Branch = Branches[BranchName]
	if not Branch then
		return nil
	end

	return ActionExecutor.RunBranch(Branch, Context)
end

function ActionExecutor.Cancel(Context: ExecutionContext)
	if Context and not Context.Canceled then
		Context.Cancel()
	end
end

function ActionExecutor.IsPredictableBlock(BlockType: string): boolean
	return PREDICTABLE_BLOCKS[BlockType] == true
end

function ActionExecutor.IsServerOnlyBlock(BlockType: string): boolean
	return SERVER_ONLY_BLOCKS[BlockType] == true
end

return ActionExecutor