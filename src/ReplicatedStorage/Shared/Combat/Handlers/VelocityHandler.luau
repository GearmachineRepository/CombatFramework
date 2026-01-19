--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local VelocityHandler = {}

function VelocityHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if IsServer then
		return nil
	end

	if Context.Mode ~= "Predictive" then
		return nil
	end

	local VelocityX = Block.X or 0
	local VelocityY = Block.Y or 0
	local VelocityZ = Block.Z or 0
	local Duration = Block.Time or 0.1
	local Fade = Block.Fade or false
	local Track = Block.Track or false
	local LastHit = Block.LastHit or -1

	local Target: Model
	if LastHit >= 0 then
		local LastHitTarget = Context.GetLastHitTarget()
		if not LastHitTarget then
			return nil
		end
		Target = LastHitTarget
	else
		Target = Context.Entity.Character
	end

	local RootPart = Target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not RootPart then
		return nil
	end

	local Direction: Vector3
	if Track then
		local LookVector = RootPart.CFrame.LookVector
		local RightVector = RootPart.CFrame.RightVector
		local UpVector = Vector3.new(0, 1, 0)
		Direction = (RightVector * VelocityX) + (UpVector * VelocityY) + (LookVector * VelocityZ)
	else
		Direction = Vector3.new(VelocityX, VelocityY, VelocityZ)
	end

	local BodyVelocity = Instance.new("BodyVelocity")
	BodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	BodyVelocity.Velocity = Direction
	BodyVelocity.Parent = RootPart

	if Fade then
		local Steps = 10
		local StepDuration = Duration / Steps
		local VelocityStep = Direction / Steps

		for Step = 1, Steps do
			task.wait(StepDuration)
			if Context.Canceled then
				break
			end
			BodyVelocity.Velocity = Direction - (VelocityStep * Step)
		end
	else
		task.wait(Duration)
	end

	BodyVelocity:Destroy()

	return nil
end

return VelocityHandler