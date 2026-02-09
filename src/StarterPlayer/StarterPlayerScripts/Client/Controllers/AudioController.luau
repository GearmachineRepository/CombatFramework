--!strict

--[=[
	@class AudioController

	SFX and music playback.

	Manages sound groups for music and SFX, adjusts volumes based on player
	settings, and provides methods for playing positional sounds, looping
	music with fade transitions, and responding to server audio packets.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local AudioTypes = require(Shared.Types.AudioTypes)

local Trove = Packages.Trove

local SettingsController = require(script.Parent.SettingsController)

type SoundConfig = AudioTypes.SoundConfig
type MusicConfig = AudioTypes.MusicConfig

local AudioController = {}

AudioController.Dependencies = { "SettingsController" }

local ControllerTrove: typeof(Trove.new()) = nil :: any
local MusicGroup: SoundGroup = nil :: any
local SfxGroup: SoundGroup = nil :: any
local CurrentMusic: Sound? = nil

local function GetSfxVolume(): number
	return SettingsController.GetSetting("SfxVolume") :: number
end

local function GetMusicVolume(): number
	return SettingsController.GetSetting("MusicVolume") :: number
end

--[=[
	Creates the controller Trove and initializes Music and Sfx sound groups.
]=]
function AudioController.Init()
	ControllerTrove = Trove.new()

	MusicGroup = Instance.new("SoundGroup")
	MusicGroup.Name = "Music"
	MusicGroup.Volume = 1
	MusicGroup.Parent = SoundService

	SfxGroup = Instance.new("SoundGroup")
	SfxGroup.Name = "Sfx"
	SfxGroup.Volume = 1
	SfxGroup.Parent = SoundService

	ControllerTrove:Add(MusicGroup)
	ControllerTrove:Add(SfxGroup)
end

--[=[
	Subscribes to volume setting changes and server audio packets.
]=]
function AudioController.Start()
	ControllerTrove:Connect(SettingsController.SettingChanged :: any, function(Key: string, Value: any)
		if Key == "MusicVolume" then
			MusicGroup.Volume = Value :: number
		elseif Key == "SfxVolume" then
			SfxGroup.Volume = Value :: number
		end
	end)

	MusicGroup.Volume = GetMusicVolume()
	SfxGroup.Volume = GetSfxVolume()

	ControllerTrove:Connect(Packets.PlaySound.OnClientEvent :: any, function(SoundId: string, Position: Vector3?, Config: SoundConfig?)
		AudioController.PlaySound(SoundId, Position, Config)
	end)

	ControllerTrove:Connect(Packets.PlayMusic.OnClientEvent :: any, function(SoundId: string, Config: MusicConfig?)
		AudioController.PlayMusic(SoundId, Config)
	end)

	ControllerTrove:Connect(Packets.StopMusic.OnClientEvent :: any, function(FadeTime: number?)
		AudioController.StopMusic(FadeTime)
	end)
end

--[=[
	Destroys the controller Trove and all managed sound groups.
]=]
function AudioController.Stop()
	ControllerTrove:Destroy()
end

--[=[
	Plays a one-shot sound effect. If a Position is provided, the sound
	is spatialized via a temporary Part. Otherwise it plays globally.

	@param SoundId string -- The asset ID of the sound
	@param Position Vector3? -- World position for 3D audio, or nil for 2D
	@param Config SoundConfig? -- Optional volume and playback speed overrides
]=]
function AudioController.PlaySound(SoundId: string, Position: Vector3?, Config: SoundConfig?)
	local Sound = Instance.new("Sound")
	Sound.SoundId = SoundId
	Sound.Volume = (Config and Config.Volume) or 1
	Sound.PlaybackSpeed = (Config and Config.PlaybackSpeed) or 1
	Sound.SoundGroup = SfxGroup

	if Position then
		local Part = Instance.new("Part")
		Part.Anchored = true
		Part.CanCollide = false
		Part.Transparency = 1
		Part.Size = Vector3.new(1, 1, 1)
		Part.Position = Position
		Part.Parent = workspace

		Sound.Parent = Part
		Sound:Play()

		Sound.Ended:Once(function()
			Part:Destroy()
		end)
	else
		Sound.Parent = SoundService
		Sound:Play()

		Sound.Ended:Once(function()
			Sound:Destroy()
		end)
	end
end

--[=[
	Plays looping music with a fade-in. Stops any currently playing music first.

	@param SoundId string -- The asset ID of the music track
	@param Config MusicConfig? -- Optional volume, fade time, and loop overrides
]=]
function AudioController.PlayMusic(SoundId: string, Config: MusicConfig?)
	if CurrentMusic then
		AudioController.StopMusic(0.5)
	end

	local Sound = Instance.new("Sound")
	Sound.SoundId = SoundId
	Sound.Volume = 0
	Sound.Looped = (Config and Config.Looped) or true
	Sound.SoundGroup = MusicGroup
	Sound.Parent = SoundService

	CurrentMusic = Sound
	Sound:Play()

	local TargetVolume = (Config and Config.Volume) or 1
	local FadeIn = (Config and Config.FadeTime) or 1

	TweenService:Create(Sound, TweenInfo.new(FadeIn), { Volume = TargetVolume }):Play()
end

--[=[
	Fades out and destroys the current music track.

	@param FadeTime number? -- Fade duration in seconds, defaults to 1
]=]
function AudioController.StopMusic(FadeTime: number?)
	if not CurrentMusic then
		return
	end

	local Fade = FadeTime or 1
	local Music = CurrentMusic
	CurrentMusic = nil

	TweenService:Create(Music, TweenInfo.new(Fade), { Volume = 0 }):Play()
	task.delay(Fade, function()
		Music:Destroy()
	end)
end

--[=[
	Directly sets the music group volume.

	@param Volume number -- Volume between 0 and 1
]=]
function AudioController.SetMusicVolume(Volume: number)
	MusicGroup.Volume = math.clamp(Volume, 0, 1)
end

--[=[
	Directly sets the SFX group volume.

	@param Volume number -- Volume between 0 and 1
]=]
function AudioController.SetSfxVolume(Volume: number)
	SfxGroup.Volume = math.clamp(Volume, 0, 1)
end

--[=[
	Returns the Music SoundGroup instance.

	@return SoundGroup -- The music group
]=]
function AudioController.GetMusicGroup(): SoundGroup
	return MusicGroup
end

--[=[
	Returns the Sfx SoundGroup instance.

	@return SoundGroup -- The SFX group
]=]
function AudioController.GetSfxGroup(): SoundGroup
	return SfxGroup
end

return AudioController