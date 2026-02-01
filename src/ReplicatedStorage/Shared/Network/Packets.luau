--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local Packet = Packages.Packet

local IsServer = RunService:IsServer()
local DEFAULT_RADIUS = 100

local function FireNearby(PacketObj: any, Position: Vector3, Radius: number?, ...: any)
	if not IsServer then
		return
	end

	local Range = Radius or DEFAULT_RADIUS

	for _, Player in Players:GetPlayers() do
		local Character = Player.Character
		if not Character then
			continue
		end

		local Root = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not Root then
			continue
		end

		if (Root.Position - Position).Magnitude <= Range then
			PacketObj:FireClient(Player, ...)
		end
	end
end

local function FireExcept(PacketObj: any, ExcludedPlayer: Player, ...: any)
	if not IsServer then
		return
	end

	for _, Player in Players:GetPlayers() do
		if Player ~= ExcludedPlayer then
			PacketObj:FireClient(Player, ...)
		end
	end
end

local function FireList(PacketObj: any, PlayerList: { Player }, ...: any)
	if not IsServer then
		return
	end

	for _, Player in PlayerList do
		PacketObj:FireClient(Player, ...)
	end
end

return {
	FireNearby = FireNearby,
	FireExcept = FireExcept,
	FireList = FireList,

	EntitySpawned = Packet(
		"EntitySpawned",
		Packet.Instance,
		{ Stats = Packet.Any, States = Packet.Any }
	),

	EntityDespawned = Packet(
		"EntityDespawned",
		Packet.Instance
	),

	DamageDealt = Packet(
		"DamageDealt",
		Packet.Instance,
		Packet.NumberF32,
		Packet.Vector3F32,
		Packet.Boolean8
	),

	StatChanged = Packet(
		"StatChanged",
		Packet.String,
		Packet.NumberF32,
		Packet.NumberF32
	),

	StateChanged = Packet(
		"StateChanged",
		Packet.String,
		Packet.Boolean8
	),

	PlaySound = Packet(
		"PlaySound",
		Packet.String,
		Packet.Any,
		Packet.Any
	),

	PlayVFX = Packet(
		"PlayVFX",
		Packet.String,
		Packet.Instance,
		Packet.Vector3F32,
		Packet.NumberF32,
		Packet.String
	),

	PlayMusic = Packet(
		"PlayMusic",
		Packet.String,
		Packet.Any
	),

	StopMusic = Packet(
		"StopMusic",
		Packet.Any
	),

	SpawnEffect = Packet(
		"SpawnEffect",
		Packet.String,
		Packet.Vector3F32,
		Packet.Any
	),

	SettingsSync = Packet(
		"SettingsSync",
		Packet.Any
	),

	SettingChanged = Packet(
		"SettingChanged",
		Packet.String,
		Packet.Any
	),

	FetchData = Packet(
		"FetchData",
		Packet.String,
		Packet.String
	),

	DataResponse = Packet(
		"DataResponse",
		Packet.String,
		Packet.Boolean8,
		Packet.Any
	),
}