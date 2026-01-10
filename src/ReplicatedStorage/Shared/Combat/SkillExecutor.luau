--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local CombatTypes = require(Shared.Types.CombatTypes)
local Handlers = require(script.Parent.Handlers)
local ExecutionContext = require(script.Parent.ExecutionContext)

type ExecutionEntity = CombatTypes.ExecutionEntity
type SkillDefinition = CombatTypes.SkillDefinition
type ExecutionContext = CombatTypes.ExecutionContext
type Branch = CombatTypes.Branch
type Block = CombatTypes.Block
type HandlerResult = CombatTypes.HandlerResult

local SkillExecutor = {}

function SkillExecutor.Execute(
	Entity: ExecutionEntity,
	SkillDefinition: SkillDefinition,
	EventBus: any
): ExecutionContext
	local Context = ExecutionContext.Create(Entity, SkillDefinition, EventBus)

	EventBus:Publish(Enums.Combat.Skill.Activated, {
		Entity = Entity,
		SkillId = SkillDefinition.SkillId,
	})

	local EntryBranch = SkillExecutor.GetEntryBranch(SkillDefinition)
	SkillExecutor.RunBranch(EntryBranch, Context)

	if Context.Canceled then
		EventBus:Publish(Enums.Combat.Skill.Canceled, {
			Entity = Entity,
			SkillId = SkillDefinition.SkillId,
		})
	else
		EventBus:Publish(Enums.Combat.Skill.Completed, {
			Entity = Entity,
			SkillId = SkillDefinition.SkillId,
		})
	end

	return Context
end

function SkillExecutor.GetEntryBranch(SkillDefinition: SkillDefinition): Branch
	if SkillDefinition.Timeline then
		return { Timeline = SkillDefinition.Timeline }
	end

	if SkillDefinition.Branches then
		for _, BranchData in SkillDefinition.Branches do
			if BranchData.Entry then
				return BranchData
			end
		end

		local MainBranch = SkillDefinition.Branches["Main"]
		if MainBranch then
			return MainBranch
		end
	end

	return { Timeline = {} }
end

function SkillExecutor.RunBranch(BranchData: Branch, Context: ExecutionContext)
	local Timeline = BranchData.Timeline
	if not Timeline then
		return
	end

	for _, Block in Timeline do
		if Context.Canceled then
			break
		end

		local Handler = Handlers.Get(Block.BlockType)
		if not Handler then
			warn(string.format("[SkillExecutor] Unknown BlockType: %s", tostring(Block.BlockType)))
			continue
		end

		local Success, Result = pcall(function()
			return Handler.Execute(Block, Context)
		end)

		if not Success then
			warn(string.format("[SkillExecutor] Handler %s failed: %s", Block.BlockType, tostring(Result)))
			continue
		end

		local HandlerResult = Result :: HandlerResult?
		if HandlerResult then
			if HandlerResult.JumpToBranch then
				local Branches = Context.SkillDefinition.Branches
				local TargetBranch = Branches and Branches[HandlerResult.JumpToBranch]
				if TargetBranch then
					Context.EventBus:Publish(Enums.Combat.Skill.BranchChanged, {
						Entity = Context.Entity,
						SkillId = Context.SkillDefinition.SkillId,
						Branch = HandlerResult.JumpToBranch,
					})
					SkillExecutor.RunBranch(TargetBranch, Context)
				end
				return
			end

			if HandlerResult.Cancel then
				Context.Cancel()
				return
			end
		end
	end
end

function SkillExecutor.Cancel(Context: ExecutionContext)
	if Context and not Context.Canceled then
		Context.Cancel()
	end
end

return SkillExecutor