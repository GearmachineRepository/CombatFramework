--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local SoundHandler = {}

function SoundHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if IsServer then
		return nil
	end

	local SoundId = Block.SoundId
	if not SoundId then
		return nil
	end

	local Volume = Block.Volume or 0.5
	local Speed = Block.Speed or 1

	local Character = Context.Entity.Character
	local RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not RootPart then
		return nil
	end

	local Sound = Instance.new("Sound")
	Sound.SoundId = SoundId
	Sound.Volume = Volume
	Sound.PlaybackSpeed = Speed
	Sound.Parent = RootPart

	Sound:Play()

	Sound.Ended:Once(function()
		Sound:Destroy()
	end)

	return nil
end

return SoundHandler