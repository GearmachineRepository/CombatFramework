--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)
local Packets = require(Shared.Network.Packets)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local MIN_VALID_ASSET_ID = 1000000

local SoundHandler = {}

local function IsValidSoundId(SoundId: string): boolean
	if not SoundId or SoundId == "" then
		return false
	end

	local AssetId = tonumber(string.match(SoundId, "%d+"))
	if not AssetId then
		return false
	end

	if AssetId < MIN_VALID_ASSET_ID then
		return false
	end

	return true
end

local function PlaySoundLocally(SoundId: string, Parent: Instance, Volume: number, Speed: number)
	local Sound = Instance.new("Sound")
	Sound.SoundId = SoundId
	Sound.Volume = Volume
	Sound.PlaybackSpeed = Speed
	Sound.Parent = Parent

	Sound:Play()

	Sound.Ended:Once(function()
		Sound:Destroy()
	end)
end

function SoundHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	local SoundId = Block.SoundId
	if not IsValidSoundId(SoundId) then
		return nil
	end

	local Volume = Block.Volume or 0.5
	local Speed = Block.Speed or 1
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

	local RootPart = Target:FindFirstChild("HumanoidRootPart")
	if not RootPart then
		return nil
	end

	if Context.Mode == "Predictive" and not IsServer then
		PlaySoundLocally(SoundId, RootPart, Volume, Speed)
	end

	if Context.Mode == "Authoritative" and IsServer then
		local Player = Context.Entity.Player

		if Player then
			Packets.FireExcept(Packets.PlaySound, Player, SoundId, RootPart, {
				Volume = Volume,
				Speed = Speed,
			})
		else
			Packets.PlaySound:Fire(SoundId, RootPart, {
				Volume = Volume,
				Speed = Speed,
			})
		end
	end

	return nil
end

return SoundHandler