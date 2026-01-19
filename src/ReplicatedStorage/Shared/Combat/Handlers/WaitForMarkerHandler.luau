--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local WaitForMarkerHandler = {}

function WaitForMarkerHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	local MarkerName = Block.Marker
	local AnimationId = Block.AnimationId
	local FallbackTime = Block.FallbackTime
	local Speed = Block.Speed

	if not MarkerName then
		warn("[WaitForMarkerHandler] No Marker specified")
		return nil
	end

	if not AnimationId then
		local CurrentAnimationId = Context.GetCurrentAnimationId()
		if CurrentAnimationId then
			AnimationId = CurrentAnimationId
		else
			warn("[WaitForMarkerHandler] No AnimationId specified and no current animation in context")
			if FallbackTime then
				task.wait(FallbackTime)
			end
			return nil
		end
	end

	if not Speed then
		Speed = Context.GetCurrentAnimationSpeed() or 1
	end

	local AnimationTimingCache = require(Shared.Combat.AnimationTimingCache)

	local MarkerTime = AnimationTimingCache.GetMarkerTime(AnimationId, MarkerName, Speed)

	if not MarkerTime then
		if FallbackTime then
			local AdjustedFallback = FallbackTime / Speed
			local Elapsed = 0
			local StepTime = 0.03

			while Elapsed < AdjustedFallback do
				if Context.Canceled then
					break
				end
				task.wait(StepTime)
				Elapsed = Elapsed + StepTime
			end
		else
			warn(string.format(
				"[WaitForMarkerHandler] Marker '%s' not found in animation '%s' and no FallbackTime provided",
				MarkerName,
				AnimationId
			))
		end
		return nil
	end

	local StartTime = Context.GetElapsedTime()
	local WaitDuration = MarkerTime - StartTime

	if WaitDuration > 0 then
		local Elapsed = 0
		local StepTime = 0.03

		while Elapsed < WaitDuration do
			if Context.Canceled then
				break
			end
			task.wait(StepTime)
			Elapsed = Elapsed + StepTime
		end
	end

	return nil
end

return WaitForMarkerHandler