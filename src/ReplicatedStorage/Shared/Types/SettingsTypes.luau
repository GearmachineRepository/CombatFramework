--!strict

export type PlayerSettings = {
	MusicVolume: number,
	SfxVolume: number,
	VfxQuality: number,
	VfxRenderDistance: number,
	ScreenShakeEnabled: boolean,
}

export type SettingDefinition = {
	Default: number | boolean,
	Min: number?,
	Max: number?,
	Type: "number" | "boolean",
}

local SettingDefinitions: { [string]: SettingDefinition } = {
	MusicVolume = { Default = 1, Min = 0, Max = 1, Type = "number" },
	SfxVolume = { Default = 1, Min = 0, Max = 1, Type = "number" },
	VfxQuality = { Default = 1, Min = 0.1, Max = 1, Type = "number" },
	VfxRenderDistance = { Default = 1, Min = 0.25, Max = 1, Type = "number" },
	ScreenShakeEnabled = { Default = true, Type = "boolean" },
}

local function GetDefault(Key: string): number | boolean
	local Definition = SettingDefinitions[Key]
	return if Definition then Definition.Default else 1
end

local function ValidateSetting(Key: string, Value: any): (boolean, number | boolean)
	local Definition = SettingDefinitions[Key]
	if not Definition then
		return false, GetDefault(Key)
	end

	if Definition.Type == "boolean" then
		if typeof(Value) ~= "boolean" then
			return false, Definition.Default
		end
		return true, Value
	end

	if typeof(Value) ~= "number" then
		return false, Definition.Default :: number
	end

	local ClampedValue = Value
	if Definition.Min ~= nil then
		ClampedValue = math.max(Definition.Min, ClampedValue)
	end
	if Definition.Max ~= nil then
		ClampedValue = math.min(Definition.Max, ClampedValue)
	end

	return true, ClampedValue
end

local function GetAllDefaults(): PlayerSettings
	return {
		MusicVolume = SettingDefinitions.MusicVolume.Default :: number,
		SfxVolume = SettingDefinitions.SfxVolume.Default :: number,
		VfxQuality = SettingDefinitions.VfxQuality.Default :: number,
		VfxRenderDistance = SettingDefinitions.VfxRenderDistance.Default :: number,
		ScreenShakeEnabled = SettingDefinitions.ScreenShakeEnabled.Default :: boolean,
	}
end

return {
	Definitions = SettingDefinitions,
	GetDefault = GetDefault,
	ValidateSetting = ValidateSetting,
	GetAllDefaults = GetAllDefaults,
}