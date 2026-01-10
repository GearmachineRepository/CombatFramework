--!strict

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ProfileStore = require(ServerScriptService.Packages.ProfileStore)
local Packages = require(ReplicatedStorage.Shared.Packages)
local DataTemplate = require(Shared.Data.PlayerDataTemplate)

local Signal = Packages.Signal

local ENABLED = false

type Profile = typeof(ProfileStore.New("", DataTemplate):StartSessionAsync("", { Cancel = function()
    return false
end }))

local PlayerDataService = {}

local GameStore = if ENABLED then ProfileStore.New("PlayerData", DataTemplate) else nil
local Profiles: { [Player]: Profile } = {}

PlayerDataService.ProfileLoaded = Signal.new()
PlayerDataService.ProfileReleased = Signal.new()

function PlayerDataService.Init()
end

function PlayerDataService.Start()
    if not ENABLED then
        return
    end

    for _, Player in Players:GetPlayers() do
        task.spawn(PlayerDataService.LoadProfile, Player)
    end

    Players.PlayerAdded:Connect(PlayerDataService.LoadProfile)
    Players.PlayerRemoving:Connect(PlayerDataService.ReleaseProfile)
end

function PlayerDataService.LoadProfile(Player: Player)
    if not GameStore then
        return
    end

    local Profile = GameStore:StartSessionAsync(`Player_{Player.UserId}`, {
        Cancel = function()
            return Player.Parent ~= Players
        end,
    })

    if not Profile then
        Player:Kick("Failed to load data. Please rejoin.")
        return
    end

    Profile:AddUserId(Player.UserId)
    Profile:Reconcile()

    Profile.OnSessionEnd:Connect(function()
        Profiles[Player] = nil
        PlayerDataService.ProfileReleased:Fire(Player)
        Player:Kick("Session ended. Please rejoin.")
    end)

    if Player.Parent ~= Players then
        Profile:EndSession()
        return
    end

    Profiles[Player] = Profile
    PlayerDataService.ProfileLoaded:Fire(Player, Profile.Data)
end

function PlayerDataService.ReleaseProfile(Player: Player)
    local Profile = Profiles[Player]
    if Profile then
        Profile:EndSession()
    end
end

function PlayerDataService.GetProfile(Player: Player): Profile?
    return Profiles[Player]
end

function PlayerDataService.GetData(Player: Player): typeof(DataTemplate)?
    local Profile = Profiles[Player]
    return if Profile then Profile.Data else nil
end

function PlayerDataService.IsLoaded(Player: Player): boolean
    return Profiles[Player] ~= nil
end

return PlayerDataService