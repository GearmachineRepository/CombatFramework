--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local WaitHandler = {}

function WaitHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	local Time = Block.Time or 0

	if Time > 0 then
		local Elapsed = 0
		local StepTime = 0.03

		while Elapsed < Time do
			if Context.Canceled then
				break
			end
			task.wait(StepTime)
			Elapsed = Elapsed + StepTime
		end
	end

	return nil
end

return WaitHandler