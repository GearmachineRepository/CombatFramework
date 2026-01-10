--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local AnimationHandler = {}

function AnimationHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if IsServer then
		return nil
	end

	local AnimationId = Block.AnimationId
	if not AnimationId then
		return nil
	end

	local Speed = Block.Speed or 1
	local Loop = Block.Loop or false
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

	local Humanoid = Target:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		return nil
	end

	local Animator = Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		return nil
	end

	local Animation = Instance.new("Animation")
	Animation.AnimationId = AnimationId

	local Track = Animator:LoadAnimation(Animation)
	Track.Looped = Loop
	Track:Play()
	Track:AdjustSpeed(Speed)

	if not Loop then
		Track.Stopped:Wait()
	end

	Animation:Destroy()

	return nil
end

return AnimationHandler