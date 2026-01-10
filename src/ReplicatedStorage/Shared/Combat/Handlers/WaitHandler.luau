--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local WaitHandler = {}

function WaitHandler.Execute(Block: Block, _Context: ExecutionContext): HandlerResult?
	local Duration = Block.Time or 0

	if Duration > 0 then
		task.wait(Duration)
	end

	return nil
end

return WaitHandler