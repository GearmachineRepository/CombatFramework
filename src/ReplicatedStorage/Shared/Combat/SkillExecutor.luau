--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local Handlers = require(script.Parent.Handlers)
local ExecutionContext = require(script.Parent.ExecutionContext)

local SkillExecutor = {}

function SkillExecutor.Execute(Entity: any, SkillDefinition: any, EventBus: any): any
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

function SkillExecutor.GetEntryBranch(SkillDefinition: any): any
    if SkillDefinition.Timeline then
        return { Timeline = SkillDefinition.Timeline }
    end

    if SkillDefinition.Branches then
        for _Name, Branch in SkillDefinition.Branches do
            if Branch.Entry then
                return Branch
            end
        end

        if SkillDefinition.Branches.Main then
            return SkillDefinition.Branches.Main
        end
    end

    return { Timeline = {} }
end

function SkillExecutor.RunBranch(Branch: any, Context: any)
    for _, Block in Branch.Timeline do
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

        if Result then
            if Result.JumpToBranch then
                local TargetBranch = Context.SkillDefinition.Branches and Context.SkillDefinition.Branches[Result.JumpToBranch]
                if TargetBranch then
                    Context.EventBus:Publish(Enums.Combat.Skill.BranchChanged, {
                        Entity = Context.Entity,
                        SkillId = Context.SkillDefinition.SkillId,
                        Branch = Result.JumpToBranch,
                    })
                    SkillExecutor.RunBranch(TargetBranch, Context)
                end
                return
            end

            if Result.Cancel then
                Context.Cancel()
                return
            end
        end
    end
end

function SkillExecutor.Cancel(Context: any)
    if Context and not Context.Canceled then
        Context.Cancel()
    end
end

return SkillExecutor