--!strict

export type RollOffMode = "Inverse" | "InverseTapered" | "Linear" | "LinearSquare"

export type SoundConfig = {
	Volume: number?,
	PlaybackSpeed: number?,
	TimePosition: number?,
	Looped: boolean?,
	RollOffMode: RollOffMode?,
	RollOffMinDistance: number?,
	RollOffMaxDistance: number?,
}

export type MusicConfig = {
	Volume: number?,
	PlaybackSpeed: number?,
	FadeTime: number?,
	Looped: boolean?,
}

local RollOffModeMap: { [RollOffMode]: Enum.RollOffMode } = {
	Inverse = Enum.RollOffMode.Inverse,
	InverseTapered = Enum.RollOffMode.InverseTapered,
	Linear = Enum.RollOffMode.Linear,
	LinearSquare = Enum.RollOffMode.LinearSquare,
}

local function GetRollOffMode(Mode: RollOffMode?): Enum.RollOffMode
	if not Mode then
		return Enum.RollOffMode.Inverse
	end
	return RollOffModeMap[Mode] or Enum.RollOffMode.Inverse
end

return {
	GetRollOffMode = GetRollOffMode,

	DEFAULT_SOUND_CONFIG = table.freeze({
		Volume = 1,
		PlaybackSpeed = 1,
		TimePosition = 0,
		Looped = false,
		RollOffMode = "Inverse" :: RollOffMode,
		RollOffMinDistance = 10,
		RollOffMaxDistance = 100,
	}),

	DEFAULT_MUSIC_CONFIG = table.freeze({
		Volume = 1,
		PlaybackSpeed = 1,
		FadeTime = 1,
		Looped = true,
	}),
}