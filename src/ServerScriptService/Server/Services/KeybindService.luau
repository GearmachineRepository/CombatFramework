--!strict

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

type KeybindCategory = { [number]: string }
type KeybindData = { [string]: KeybindCategory }

local KeybindService = {}

KeybindService.Dependencies = { "PlayerDataService" }

local ServiceTrove: typeof(Trove.new()) = nil :: any
local PlayerKeybindCache: { [Player]: KeybindData } = {}

KeybindService.KeybindChanged = Signal.new()

local function GetDefaults(): KeybindData
	return TableUtil.Copy(PlayerDataTemplate.Keybinds, true)
end

local function IsValidKeyCode(KeyCodeName: string): boolean
	return (Enum.KeyCode :: any)[KeyCodeName] ~= nil
end

local function IsValidCategory(Category: string): boolean
	local Defaults = PlayerDataTemplate.Keybinds
	return (Defaults :: any)[Category] ~= nil
end

function KeybindService.Init()
	ServiceTrove = Trove.new()
end

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

function KeybindService.Stop()
	ServiceTrove:Destroy()
	table.clear(PlayerKeybindCache)
end

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

function KeybindService.GetKeybind(Player: Player, Category: string, SlotIndex: number): string?
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

function KeybindService.GetCategoryKeybinds(Player: Player, Category: string): KeybindCategory?
	local Keybinds = PlayerKeybindCache[Player]
	if not Keybinds then
		return nil
	end

	return Keybinds[Category]
end

function KeybindService.GetAllKeybinds(Player: Player): KeybindData
	local Keybinds = PlayerKeybindCache[Player]
	if not Keybinds then
		return GetDefaults()
	end
	return Keybinds
end

function KeybindService.SetKeybind(Player: Player, Category: string, SlotIndex: number, KeyCodeName: string)
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