--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local ANIMATION_MAX_DURATION = 5
local MIN_VALID_ASSET_ID = 1000000

local AnimationHandler = {}

local function IsValidAnimationId(AnimationId: string): boolean
	if not AnimationId or AnimationId == "" then
		return false
	end

	local AssetId = tonumber(string.match(AnimationId, "%d+"))
	if not AssetId then
		return false
	end

	if AssetId < MIN_VALID_ASSET_ID then
		return false
	end

	return true
end

function AnimationHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if IsServer then
		return nil
	end

	if Context.Mode ~= "Predictive" then
		return nil
	end

	local AnimationId = Block.AnimationId
	if not IsValidAnimationId(AnimationId) then
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
		if Track.Length == 0 then
			task.wait()
		end

		local Duration = math.min(Track.Length / Speed, ANIMATION_MAX_DURATION)

		if Duration > 0 then
			local Completed = false

			local Connection = Track.Stopped:Once(function()
				Completed = true
			end)

			local StartTime = tick()
			while not Completed and (tick() - StartTime) < Duration do
				if Context.Canceled then
					Track:Stop()
					break
				end
				task.wait()
			end

			if Connection.Connected then
				Connection:Disconnect()
			end

			if not Completed then
				Track:Stop()
			end
		end
	end

	Animation:Destroy()

	return nil
end

return AnimationHandler