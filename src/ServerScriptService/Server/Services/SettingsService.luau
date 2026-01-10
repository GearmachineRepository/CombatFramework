--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local SettingsTypes = require(Shared.Types.SettingsTypes)

local Signal = Packages.Signal
local Trove = Packages.Trove

local PlayerDataService = require(Server.Services.PlayerDataService)

type PlayerSettings = SettingsTypes.PlayerSettings

local SettingsService = {}

SettingsService.Dependencies = { "PlayerDataService" }

local ServiceTrove: typeof(Trove.new()) = nil :: any
local PlayerSettingsCache: { [Player]: PlayerSettings } = {}

SettingsService.SettingChanged = Signal.new()

function SettingsService.Init()
    ServiceTrove = Trove.new()
end

function SettingsService.Start()
    ServiceTrove:Connect(PlayerDataService.ProfileLoaded :: any, function(Player: Player, Data: any)
        SettingsService.LoadSettings(Player, Data)
    end)

    ServiceTrove:Connect(Players.PlayerRemoving, function(Player: Player)
        PlayerSettingsCache[Player] = nil
    end)

    ServiceTrove:Connect(Packets.SettingChanged.OnServerEvent :: any, function(Player: Player, Key: any, Value: any)
        if typeof(Key) ~= "string" then
            return
        end
        SettingsService.SetSetting(Player, Key :: string, Value)
    end)

    for _, Player in Players:GetPlayers() do
        if PlayerDataService.IsLoaded(Player) then
            local Data = PlayerDataService.GetData(Player)
            if Data then
                task.spawn(SettingsService.LoadSettings, Player, Data)
            end
        end
    end
end

function SettingsService.Stop()
    ServiceTrove:Destroy()
    table.clear(PlayerSettingsCache)
end

function SettingsService.LoadSettings(Player: Player, Data: any?)
    local Settings: PlayerSettings

    local ProfileData = Data or PlayerDataService.GetData(Player)
    if ProfileData and ProfileData.Settings then
        Settings = ProfileData.Settings :: PlayerSettings
    else
        Settings = SettingsTypes.GetAllDefaults()
    end

    PlayerSettingsCache[Player] = Settings
    Packets.SettingsSync:FireClient(Player, Settings)
end

function SettingsService.GetSetting(Player: Player, Key: string): number | boolean
    local Settings = PlayerSettingsCache[Player]
    if not Settings then
        return SettingsTypes.GetDefault(Key)
    end

    local Value = (Settings :: any)[Key]
    return if Value ~= nil then Value else SettingsTypes.GetDefault(Key)
end

function SettingsService.GetAllSettings(Player: Player): PlayerSettings
    local Settings = PlayerSettingsCache[Player]
    if not Settings then
        return SettingsTypes.GetAllDefaults()
    end
    return Settings
end

function SettingsService.SetSetting(Player: Player, Key: string, Value: any)
    local IsValid, ValidatedValue = SettingsTypes.ValidateSetting(Key, Value)
    if not IsValid then
        Packets.SettingChanged:FireClient(Player, Key, SettingsService.GetSetting(Player, Key))
        return
    end

    local Settings = PlayerSettingsCache[Player]
    if not Settings then
        Settings = SettingsTypes.GetAllDefaults()
        PlayerSettingsCache[Player] = Settings
    end

    local OldValue = (Settings :: any)[Key];
    (Settings :: any)[Key] = ValidatedValue

    local Data = PlayerDataService.GetData(Player)
    if Data and Data.Settings then
        (Data.Settings :: any)[Key] = ValidatedValue
    end

    SettingsService.SettingChanged:Fire(Player, Key, ValidatedValue, OldValue)
    Packets.SettingChanged:FireClient(Player, Key, ValidatedValue)
end

return SettingsService