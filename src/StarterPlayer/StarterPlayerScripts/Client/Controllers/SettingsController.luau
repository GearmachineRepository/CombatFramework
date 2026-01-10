--!strict

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

function SettingsController.Init()
    ControllerTrove = Trove.new()
end

function SettingsController.Start()
    ControllerTrove:Connect(Packets.SettingsSync.OnClientEvent :: any, function(Settings: PlayerSettings)
        CachedSettings = Settings
        IsLoaded = true
        SettingsController.SettingsLoaded:Fire(Settings)
    end)

    ControllerTrove:Connect(Packets.SettingChanged.OnClientEvent :: any, function(Key: string, Value: any)
        local TypedKey = Key :: string
        local OldValue = (CachedSettings :: any)[TypedKey];
        (CachedSettings :: any)[TypedKey] = Value
        SettingsController.SettingChanged:Fire(Key, Value, OldValue)
    end)
end

function SettingsController.Stop()
    ControllerTrove:Destroy()
end

function SettingsController.GetSetting(Key: string): number | boolean
    local Value = (CachedSettings :: any)[Key]
    return if Value ~= nil then Value else SettingsTypes.GetDefault(Key)
end

function SettingsController.GetAllSettings(): PlayerSettings
    return CachedSettings
end

function SettingsController.SetSetting(Key: string, Value: any)
    local IsValid, ValidatedValue = SettingsTypes.ValidateSetting(Key, Value)
    if not IsValid then
        return
    end

    local OldValue = (CachedSettings :: any)[Key];
    (CachedSettings :: any)[Key] = ValidatedValue

    Packets.SettingChanged:Fire(Key, ValidatedValue)
    SettingsController.SettingChanged:Fire(Key, ValidatedValue, OldValue)
end

function SettingsController.IsLoaded(): boolean
    return IsLoaded
end

function SettingsController.WaitForLoad(): PlayerSettings
    if IsLoaded then
        return CachedSettings
    end
    return SettingsController.SettingsLoaded:Wait()
end

function SettingsController.GetMusicVolume(): number
    return SettingsController.GetSetting("MusicVolume") :: number
end

function SettingsController.GetSfxVolume(): number
    return SettingsController.GetSetting("SfxVolume") :: number
end

function SettingsController.GetVfxQuality(): number
    return SettingsController.GetSetting("VfxQuality") :: number
end

function SettingsController.GetVfxRenderDistance(): number
    return SettingsController.GetSetting("VfxRenderDistance") :: number
end

function SettingsController.IsScreenShakeEnabled(): boolean
    return SettingsController.GetSetting("ScreenShakeEnabled") :: boolean
end

return SettingsController