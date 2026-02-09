--!strict

--[=[
	@class PlayerDataService

	ProfileStore session management for player data.

	Handles loading, caching, and releasing player profiles. Supports
	both live ProfileStore sessions and local mock data for Studio testing.
	Fires `ProfileLoaded` and `ProfileReleased` signals for downstream consumers.
]=]

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local ProfileStore = require(ServerScriptService.Packages.ProfileStore)
local Packages = require(ReplicatedStorage.Shared.Packages)
local DataTemplate = require(Shared.Data.PlayerDataTemplate)

local Signal = Packages.Signal
local TableUtil = Packages.TableUtil
local Trove = Packages.Trove

local ENABLED = false

type Profile = typeof(ProfileStore.New("", DataTemplate):StartSessionAsync("", { Cancel = function()
	return false
end }))

local PlayerDataService = {}

local GameStore = if ENABLED then ProfileStore.New("PlayerData", DataTemplate) else nil
local Profiles: { [Player]: Profile } = {}
local MockData: { [Player]: typeof(DataTemplate) } = {}

local ServiceTrove: typeof(Trove.new()) = nil :: any

PlayerDataService.ProfileLoaded = Signal.new()
PlayerDataService.ProfileReleased = Signal.new()

--[=[
	Creates the service Trove for connection cleanup.
]=]
function PlayerDataService.Init()
	ServiceTrove = Trove.new()
end

--[=[
	Connects to player lifecycle events and loads profiles for existing players.
	Uses ProfileStore when ENABLED, otherwise falls back to mock data.
]=]
function PlayerDataService.Start()
	if ENABLED then
		for _, Player in Players:GetPlayers() do
			task.spawn(PlayerDataService.LoadProfile, Player)
		end

		ServiceTrove:Connect(Players.PlayerAdded, PlayerDataService.LoadProfile)
		ServiceTrove:Connect(Players.PlayerRemoving, PlayerDataService.ReleaseProfile)
	else
		for _, Player in Players:GetPlayers() do
			task.spawn(PlayerDataService.LoadMockProfile, Player)
		end

		ServiceTrove:Connect(Players.PlayerAdded, function(Player: Player)
			task.spawn(PlayerDataService.LoadMockProfile, Player)
		end)

		ServiceTrove:Connect(Players.PlayerRemoving, function(Player: Player)
			MockData[Player] = nil
			PlayerDataService.ProfileReleased:Fire(Player)
		end)
	end
end

--[=[
	Destroys the service Trove and clears cached data.
]=]
function PlayerDataService.Stop()
	ServiceTrove:Destroy()
	table.clear(MockData)
end

--[=[
	Creates a deep copy of the data template as mock profile data for the player.
	Used when ProfileStore is disabled (Studio testing).

	@param Player Player -- The player to create mock data for
]=]
function PlayerDataService.LoadMockProfile(Player: Player)
	if Player.Parent ~= Players then
		return
	end

	local Data = TableUtil.Copy(DataTemplate, true)
	MockData[Player] = Data
	PlayerDataService.ProfileLoaded:Fire(Player, Data)
end

--[=[
	Starts a ProfileStore session for the player. Kicks the player if the
	session fails to load or if the session ends unexpectedly.

	@param Player Player -- The player to load a profile for
]=]
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

--[=[
	Ends the ProfileStore session for the given player.

	@param Player Player -- The player whose profile should be released
]=]
function PlayerDataService.ReleaseProfile(Player: Player)
	local Profile = Profiles[Player]
	if Profile then
		Profile:EndSession()
	end
end

--[=[
	Returns the raw ProfileStore profile for the player, or nil.

	@param Player Player -- The player to look up
	@return Profile? -- The ProfileStore profile, or nil
]=]
function PlayerDataService.GetProfile(Player: Player): Profile?
	return Profiles[Player]
end

--[=[
	Returns the player's data table from either the live profile or mock data.

	@param Player Player -- The player to look up
	@return typeof(DataTemplate)? -- The data table, or nil
]=]
function PlayerDataService.GetData(Player: Player): typeof(DataTemplate)?
	local Profile = Profiles[Player]
	if Profile then
		return Profile.Data
	end

	return MockData[Player]
end

--[=[
	Returns whether a profile or mock data has been loaded for the player.

	@param Player Player -- The player to check
	@return boolean -- True if data is available
]=]
function PlayerDataService.IsLoaded(Player: Player): boolean
	if Profiles[Player] ~= nil then
		return true
	end

	return MockData[Player] ~= nil
end

return PlayerDataService