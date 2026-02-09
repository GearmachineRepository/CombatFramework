--!strict

--[=[
	@class KeybindService

	Server-side keybind validation and persistence.

	Caches player keybinds in memory, validates incoming changes against
	the data template categories, persists to PlayerDataService, and
	replicates confirmed bindings back to the client.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local PlayerDataTemplate = require(Shared.Data.PlayerDataTemplate)

local Signal = Packages.Signal
local Trove = Packages.Trove
local TableUtil = Packages.TableUtil

local PlayerDataService = require(Server.Services.PlayerDataService)

type KeybindCategory = { [string]: string }
type KeybindData = { [string]: KeybindCategory }

local KeybindService = {}

KeybindService.Dependencies = { "PlayerDataService" }

local ServiceTrove: typeof(Trove.new()) = nil :: any
local PlayerKeybindCache: { [Player]: KeybindData } = {}

KeybindService.KeybindChanged = Signal.new()

local function GetDefaults(): KeybindData
	return TableUtil.Copy(PlayerDataTemplate.Keybinds, true) :: KeybindData
end

local function IsValidKeyCode(KeyCodeName: string): boolean
	return (Enum.KeyCode :: any)[KeyCodeName] ~= nil
end

local function IsValidCategory(Category: string): boolean
	local Defaults = PlayerDataTemplate.Keybinds
	return (Defaults :: any)[Category] ~= nil
end

--[=[
	Creates the service Trove for connection cleanup.
]=]
function KeybindService.Init()
	ServiceTrove = Trove.new()
end

--[=[
	Subscribes to profile load, player removal, and client keybind change packets.
	Also retroactively loads keybinds for any players already in-game.
]=]
function KeybindService.Start()
	ServiceTrove:Connect(PlayerDataService.ProfileLoaded :: any, function(Player: Player, Data: any)
		KeybindService.LoadKeybinds(Player, Data)
	end)

	ServiceTrove:Connect(Players.PlayerRemoving, function(Player: Player)
		PlayerKeybindCache[Player] = nil
	end)

	ServiceTrove:Connect(Packets.KeybindChanged.OnServerEvent :: any, function(Player: Player, Category: any, SlotIndex: any, KeyCodeName: any)
		if typeof(Category) ~= "string" or typeof(SlotIndex) ~= "number" or typeof(KeyCodeName) ~= "string" then
			return
		end

		KeybindService.SetKeybind(Player, Category, SlotIndex, KeyCodeName)
	end)

	for _, Player in Players:GetPlayers() do
		if PlayerDataService.IsLoaded(Player) then
			local Data = PlayerDataService.GetData(Player)
			if Data then
				task.spawn(KeybindService.LoadKeybinds, Player, Data)
			end
		end
	end
end

--[=[
	Destroys the service Trove and clears the keybind cache.
]=]
function KeybindService.Stop()
	ServiceTrove:Destroy()
	table.clear(PlayerKeybindCache)
end

--[=[
	Loads a player's keybinds from profile data into the cache and syncs to the client.
	Falls back to defaults if no saved keybinds exist.

	@param Player Player -- The player to load keybinds for
	@param Data any? -- Profile data table, or nil to fetch from PlayerDataService
]=]
function KeybindService.LoadKeybinds(Player: Player, Data: any?)
	local Keybinds: KeybindData

	local ProfileData = Data or PlayerDataService.GetData(Player)
	if ProfileData and ProfileData.Keybinds then
		Keybinds = ProfileData.Keybinds :: KeybindData
	else
		Keybinds = GetDefaults()
	end

	PlayerKeybindCache[Player] = Keybinds
	Packets.KeybindSync:FireClient(Player, Keybinds)
end

--[=[
	Returns a single keybind value for the given player, category, and slot.

	@param Player Player -- The player to look up
	@param Category string -- The keybind category (e.g. "Hotbar")
	@param SlotIndex any -- The slot index within the category
	@return string? -- The KeyCode name, or nil
]=]
function KeybindService.GetKeybind(Player: Player, Category: string, SlotIndex: any): string?
	local Keybinds = PlayerKeybindCache[Player]
	if not Keybinds then
		return nil
	end

	local CategoryData = Keybinds[Category]
	if not CategoryData then
		return nil
	end

	return CategoryData[SlotIndex]
end

--[=[
	Returns all keybinds for a specific category.

	@param Player Player -- The player to look up
	@param Category string -- The keybind category
	@return KeybindCategory? -- The category's keybinds, or nil
]=]
function KeybindService.GetCategoryKeybinds(Player: Player, Category: string): KeybindCategory?
	local Keybinds = PlayerKeybindCache[Player]
	if not Keybinds then
		return nil
	end

	return Keybinds[Category]
end

--[=[
	Returns all keybind data for the given player.

	@param Player Player -- The player to look up
	@return KeybindData -- The full keybind table
]=]
function KeybindService.GetAllKeybinds(Player: Player): KeybindData
	local Keybinds = PlayerKeybindCache[Player]
	if not Keybinds then
		return GetDefaults()
	end
	return Keybinds
end

--[=[
	Validates and applies a keybind change for the given player.
	Persists the change to profile data and replicates to the client.
	If validation fails, the client receives the current server value instead.

	@param Player Player -- The player changing a keybind
	@param Category string -- The keybind category
	@param SlotIndex any -- The slot index within the category
	@param KeyCodeName string -- The new KeyCode name
]=]
function KeybindService.SetKeybind(Player: Player, Category: string, SlotIndex: any, KeyCodeName: string)
	if not IsValidCategory(Category) then
		return
	end

	if not IsValidKeyCode(KeyCodeName) then
		local CurrentValue = KeybindService.GetKeybind(Player, Category, SlotIndex)
		if CurrentValue then
			Packets.KeybindChanged:FireClient(Player, Category, SlotIndex, CurrentValue)
		end
		return
	end

	local Keybinds = PlayerKeybindCache[Player]
	if not Keybinds then
		Keybinds = GetDefaults()
		PlayerKeybindCache[Player] = Keybinds
	end

	if not Keybinds[Category] then
		Keybinds[Category] = {}
	end

	local OldValue = Keybinds[Category][SlotIndex]
	Keybinds[Category][SlotIndex] = KeyCodeName

	local Data = PlayerDataService.GetData(Player)
	if Data and Data.Keybinds then
		local DataCategory = (Data.Keybinds :: any)[Category]
		if DataCategory then
			DataCategory[SlotIndex] = KeyCodeName
		end
	end

	KeybindService.KeybindChanged:Fire(Player, Category, SlotIndex, KeyCodeName, OldValue)
	Packets.KeybindChanged:FireClient(Player, Category, SlotIndex, KeyCodeName)
end

return KeybindService