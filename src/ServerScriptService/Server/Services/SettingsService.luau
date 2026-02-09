--!strict

--[=[
	@class SettingsService

	Server-side settings validation and persistence.

	Caches player settings in memory, validates incoming changes against
	SettingsTypes definitions, persists to PlayerDataService, and replicates
	confirmed values back to the client.
]=]

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

--[=[
	Creates the service Trove for connection cleanup.
]=]
function SettingsService.Init()
    ServiceTrove = Trove.new()
end

--[=[
	Subscribes to profile load, player removal, and client setting change packets.
	Also retroactively loads settings for any players already in-game.
]=]
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

--[=[
	Destroys the service Trove and clears the settings cache.
]=]
function SettingsService.Stop()
    ServiceTrove:Destroy()
    table.clear(PlayerSettingsCache)
end

--[=[
	Loads a player's settings from profile data into the cache and syncs to the client.
	Falls back to defaults if no saved settings exist.

	@param Player Player -- The player to load settings for
	@param Data any? -- Profile data table, or nil to fetch from PlayerDataService
]=]
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

--[=[
	Returns a single setting value for the given player.
	Falls back to the default if no cache exists.

	@param Player Player -- The player to look up
	@param Key string -- The setting key
	@return number | boolean -- The setting value
]=]
function SettingsService.GetSetting(Player: Player, Key: string): number | boolean
    local Settings = PlayerSettingsCache[Player]
    if not Settings then
        return SettingsTypes.GetDefault(Key)
    end

    local Value = (Settings :: any)[Key]
    return if Value ~= nil then Value else SettingsTypes.GetDefault(Key)
end

--[=[
	Returns all settings for the given player.
	Falls back to defaults if no cache exists.

	@param Player Player -- The player to look up
	@return PlayerSettings -- The full settings table
]=]
function SettingsService.GetAllSettings(Player: Player): PlayerSettings
    local Settings = PlayerSettingsCache[Player]
    if not Settings then
        return SettingsTypes.GetAllDefaults()
    end
    return Settings
end

--[=[
	Validates and applies a setting change for the given player.
	Persists the change to profile data and replicates to the client.
	If validation fails, the client receives the current server value instead.

	@param Player Player -- The player changing a setting
	@param Key string -- The setting key
	@param Value any -- The proposed new value
]=]
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

    local SettingsAny = Settings :: any
    local OldValue = SettingsAny[Key]
    SettingsAny[Key] = ValidatedValue

    local Data = PlayerDataService.GetData(Player)
    if Data and Data.Settings then
        local DataSettings = Data.Settings :: any
        DataSettings[Key] = ValidatedValue
    end

    SettingsService.SettingChanged:Fire(Player, Key, ValidatedValue, OldValue)
    Packets.SettingChanged:FireClient(Player, Key, ValidatedValue)
end

return SettingsService