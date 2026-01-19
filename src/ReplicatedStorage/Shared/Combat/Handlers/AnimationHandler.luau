--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)
local Packets = require(Shared.Network.Packets)
local AnimationTimingCache = require(Shared.Combat.AnimationTimingCache)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local AnimationHandler = {}

local VFX_PREFIX = "VFX_"
local SFX_PREFIX = "SFX_"

local function GetAnimator(Character: Model): Animator?
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if not Humanoid then
		return nil
	end

	local Animator = Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		local NewAnimator = Instance.new("Animator")
		NewAnimator.Parent = Humanoid
		Animator = NewAnimator
	end

	return Animator
end

local function SetupMarkerListeners(
	AnimationTrack: AnimationTrack,
	Character: Model,
	Context: ExecutionContext
)
	local Animation = AnimationTrack.Animation
	if not Animation then
		return
	end

	local Markers = AnimationTimingCache.GetAllMarkers(Animation.AnimationId)

	if not Markers then
		return
	end

	for MarkerName, _MarkerData in Markers do
		if string.sub(MarkerName, 1, #VFX_PREFIX) == VFX_PREFIX then
			local EffectName = string.sub(MarkerName, #VFX_PREFIX + 1)

			Context.Trove:Add(AnimationTrack:GetMarkerReachedSignal(MarkerName):Connect(function(Value: string)
				local RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local Position = if RootPart then RootPart.Position else Vector3.zero
				local EffectParams = if Value ~= "" then Value else "VFX"
				Packets.PlayVFX:Fire(EffectName, Character, Position, 0, EffectParams)
			end))

		elseif string.sub(MarkerName, 1, #SFX_PREFIX) == SFX_PREFIX then
			local SoundName = string.sub(MarkerName, #SFX_PREFIX + 1)

			Context.Trove:Add(AnimationTrack:GetMarkerReachedSignal(MarkerName):Connect(function(Value: string)
				local SoundId = if Value ~= "" then Value else nil
				local RootPart = Character:FindFirstChild("HumanoidRootPart")
				if RootPart and SoundId then
					local Sound = Instance.new("Sound")
					Sound.Name = SoundName
					Sound.SoundId = SoundId
					Sound.Volume = 0.8
					Sound.Parent = RootPart
					Sound:Play()
					Sound.Ended:Once(function()
						Sound:Destroy()
					end)
				end
			end))
		end
	end
end

function AnimationHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if IsServer then
		return nil
	end

	if Context.Mode ~= "Predictive" then
		return nil
	end

	local AnimationId = Block.AnimationId
	local Speed = Block.Speed or 1
	local Loop = Block.Loop or false
	local Priority = Block.Priority or Enum.AnimationPriority.Action

	if not AnimationId or AnimationId == "" then
		return nil
	end

	local Character = Context.Entity.Character
	local Animator = GetAnimator(Character)

	if not Animator then
		return nil
	end

	local Animation = Instance.new("Animation")
	Animation.AnimationId = AnimationId

	local AnimationTrack = Animator:LoadAnimation(Animation)
	AnimationTrack.Priority = Priority
	AnimationTrack.Looped = Loop
	AnimationTrack:Play()
	AnimationTrack:AdjustSpeed(Speed)

	Context.SetCurrentAnimation(AnimationId, AnimationTrack)

	SetupMarkerListeners(AnimationTrack, Character, Context)

	Context.Trove:Add(function()
		if AnimationTrack.IsPlaying then
			AnimationTrack:Stop(0.1)
		end
	end)

	Animation:Destroy()

	return nil
end

return AnimationHandler