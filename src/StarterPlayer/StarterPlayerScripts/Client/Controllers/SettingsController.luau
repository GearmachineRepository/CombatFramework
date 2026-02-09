--!strict

--[=[
	@class SettingsController

	Client-side settings cache and sync.

	Maintains a local cache of player settings, synced from the server on load.
	Setting changes are validated locally, applied to the cache, and sent to the
	server for persistence. Provides convenience getters for common settings.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local SettingsTypes = require(Shared.Types.SettingsTypes)

local Trove = Packages.Trove
local Signal = Packages.Signal

type PlayerSettings = SettingsTypes.PlayerSettings

local SettingsController = {}

local ControllerTrove: typeof(Trove.new()) = nil :: any
local CachedSettings: PlayerSettings = SettingsTypes.GetAllDefaults()
local IsLoaded = false

SettingsController.SettingChanged = Signal.new()
SettingsController.SettingsLoaded = Signal.new()

--[=[
	Creates the controller Trove for connection cleanup.
]=]
function SettingsController.Init()
    ControllerTrove = Trove.new()
end

--[=[
	Subscribes to server settings sync and individual setting change packets.
]=]
function SettingsController.Start()
    ControllerTrove:Connect(Packets.SettingsSync.OnClientEvent :: any, function(Settings: PlayerSettings)
        CachedSettings = Settings
        IsLoaded = true
        SettingsController.SettingsLoaded:Fire(Settings)
    end)

    ControllerTrove:Connect(Packets.SettingChanged.OnClientEvent :: any, function(Key: string, Value: any)
        local TypedKey = Key :: string
        local CachedAny = CachedSettings :: any
        local OldValue = CachedAny[TypedKey]
        CachedAny[TypedKey] = Value
        SettingsController.SettingChanged:Fire(Key, Value, OldValue)
    end)
end

--[=[
	Destroys the controller Trove.
]=]
function SettingsController.Stop()
    ControllerTrove:Destroy()
end

--[=[
	Returns the value of a single setting from the local cache.
	Falls back to the default if the key is not present.

	@param Key string -- The setting key to look up
	@return number | boolean -- The setting value
]=]
function SettingsController.GetSetting(Key: string): number | boolean
    local Value = (CachedSettings :: any)[Key]
    return if Value ~= nil then Value else SettingsTypes.GetDefault(Key)
end

--[=[
	Returns all cached settings.

	@return PlayerSettings -- The full settings table
]=]
function SettingsController.GetAllSettings(): PlayerSettings
    return CachedSettings
end

--[=[
	Validates and applies a setting change locally, then sends it to the server.

	@param Key string -- The setting key to change
	@param Value any -- The proposed new value
]=]
function SettingsController.SetSetting(Key: string, Value: any)
    local IsValid, ValidatedValue = SettingsTypes.ValidateSetting(Key, Value)
    if not IsValid then
        return
    end

    local CachedAny = CachedSettings :: any
    local OldValue = CachedAny[Key]
    CachedAny[Key] = ValidatedValue

    Packets.SettingChanged:Fire(Key, ValidatedValue)
    SettingsController.SettingChanged:Fire(Key, ValidatedValue, OldValue)
end

--[=[
	Returns whether the initial settings sync from the server has completed.

	@return boolean -- True if settings have been loaded
]=]
function SettingsController.IsLoaded(): boolean
    return IsLoaded
end

--[=[
	Blocks until settings have been loaded from the server and returns them.

	@return PlayerSettings -- The loaded settings
]=]
function SettingsController.WaitForLoad(): PlayerSettings
    if IsLoaded then
        return CachedSettings
    end
    return SettingsController.SettingsLoaded:Wait()
end

--[=[
	Returns the current music volume setting.

	@return number -- Music volume between 0 and 1
]=]
function SettingsController.GetMusicVolume(): number
    return SettingsController.GetSetting("MusicVolume") :: number
end

--[=[
	Returns the current SFX volume setting.

	@return number -- SFX volume between 0 and 1
]=]
function SettingsController.GetSfxVolume(): number
    return SettingsController.GetSetting("SfxVolume") :: number
end

--[=[
	Returns the current VFX quality setting.

	@return number -- Quality multiplier between 0.1 and 1
]=]
function SettingsController.GetVfxQuality(): number
    return SettingsController.GetSetting("VfxQuality") :: number
end

--[=[
	Returns the current VFX render distance setting.

	@return number -- Render distance multiplier between 0.25 and 1
]=]
function SettingsController.GetVfxRenderDistance(): number
    return SettingsController.GetSetting("VfxRenderDistance") :: number
end

--[=[
	Returns whether screen shake is enabled.

	@return boolean -- True if screen shake is on
]=]
function SettingsController.IsScreenShakeEnabled(): boolean
    return SettingsController.GetSetting("ScreenShakeEnabled") :: boolean
end

return SettingsController