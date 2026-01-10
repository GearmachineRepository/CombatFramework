--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packets = require(Shared.Network.Packets)
local AudioTypes = require(Shared.Types.AudioTypes)

type SoundConfig = AudioTypes.SoundConfig
type MusicConfig = AudioTypes.MusicConfig

export type EffectConfig = {
	Scale: number?,
	Duration: number?,
	Color: Color3?,
	[string]: any,
}

local ReplicationService = {}

function ReplicationService.Init()
end

function ReplicationService.Start()
end

function ReplicationService.PlaySound(SoundId: string, Position: Vector3?, Config: SoundConfig?, Radius: number?)
	local Range = Radius or 100

	if Position then
		Packets.FireNearby(Packets.PlaySound, Position, Range, SoundId, Position, Config)
	else
		Packets.PlaySound:Fire(SoundId, nil, Config)
	end
end

function ReplicationService.PlaySoundForPlayer(Player: Player, SoundId: string, Position: Vector3?, Config: SoundConfig?)
	Packets.PlaySound:FireClient(Player, SoundId, Position, Config)
end

function ReplicationService.PlaySoundExcept(ExcludedPlayer: Player, SoundId: string, Position: Vector3?, Config: SoundConfig?, Radius: number?)
	local Range = Radius or 100

	if Position then
		for _, Player in Players:GetPlayers() do
			if Player == ExcludedPlayer then
				continue
			end

			local Character = Player.Character
			if not Character then
				continue
			end

			local Root = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not Root then
				continue
			end

			if (Root.Position - Position).Magnitude <= Range then
				Packets.PlaySound:FireClient(Player, SoundId, Position, Config)
			end
		end
	else
		Packets.FireExcept(Packets.PlaySound, ExcludedPlayer, SoundId, nil, Config)
	end
end

function ReplicationService.PlayMusic(Player: Player, SoundId: string, Config: MusicConfig?)
	Packets.PlayMusic:FireClient(Player, SoundId, Config)
end

function ReplicationService.PlayMusicForAll(SoundId: string, Config: MusicConfig?)
	Packets.PlayMusic:Fire(SoundId, Config)
end

function ReplicationService.StopMusic(Player: Player, FadeTime: number?)
	Packets.StopMusic:FireClient(Player, FadeTime)
end

function ReplicationService.StopMusicForAll(FadeTime: number?)
	Packets.StopMusic:Fire(FadeTime)
end

function ReplicationService.SpawnEffect(EffectName: string, Position: Vector3, Config: EffectConfig?, Radius: number?)
	local Range = Radius or 100
	Packets.FireNearby(Packets.SpawnEffect, Position, Range, EffectName, Position, Config)
end

function ReplicationService.SpawnEffectForPlayer(Player: Player, EffectName: string, Position: Vector3, Config: EffectConfig?)
	Packets.SpawnEffect:FireClient(Player, EffectName, Position, Config)
end

function ReplicationService.SpawnEffectExcept(ExcludedPlayer: Player, EffectName: string, Position: Vector3, Config: EffectConfig?, Radius: number?)
	local Range = Radius or 100

	for _, Player in Players:GetPlayers() do
		if Player == ExcludedPlayer then
			continue
		end

		local Character = Player.Character
		if not Character then
			continue
		end

		local Root = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not Root then
			continue
		end

		if (Root.Position - Position).Magnitude <= Range then
			Packets.SpawnEffect:FireClient(Player, EffectName, Position, Config)
		end
	end
end

return ReplicationService