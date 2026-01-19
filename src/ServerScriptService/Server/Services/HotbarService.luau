--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)

local Trove = Packages.Trove
local Signal = Packages.Signal

local ActionService = require(script.Parent.ActionService)
local DefaultHotbar = require(Shared.Data.Hotbars.DefaultHotbar)

local HotbarService = {}

HotbarService.Dependencies = { "ActionService" }

HotbarService.SlotChanged = Signal.new()
HotbarService.HotbarCleared = Signal.new()

local ServiceTrove: typeof(Trove.new()) = nil :: any

local PlayerHotbars: { [Player]: { [number]: string } } = {}

local MAX_SLOTS = 6

function HotbarService.Init()
	ServiceTrove = Trove.new()
end

function HotbarService.Start()
	ServiceTrove:Add(Players.PlayerAdded:Connect(function(Player: Player)
		HotbarService.SetupPlayer(Player)
	end))

	ServiceTrove:Add(Players.PlayerRemoving:Connect(function(Player: Player)
		HotbarService.CleanupPlayer(Player)
	end))

	for _, Player in Players:GetPlayers() do
		HotbarService.SetupPlayer(Player)
	end

	ServiceTrove:Connect(Packets.HotbarActivate.OnServerEvent :: any, function(Player: Player, SlotNumber: number)
		HotbarService.OnSlotActivated(Player, SlotNumber)
	end)

	ServiceTrove:Connect(Packets.HotbarAssign.OnServerEvent :: any, function(Player: Player, SlotNumber: number, ActionId: string?)
		HotbarService.OnSlotAssigned(Player, SlotNumber, ActionId)
	end)
end

function HotbarService.Stop()
	if ServiceTrove then
		ServiceTrove:Destroy()
	end
end

function HotbarService.SetupPlayer(Player: Player)
	PlayerHotbars[Player] = {}

	for Slot, ActionId in DefaultHotbar do
		if type(Slot) == "number" and Slot >= 1 and Slot <= MAX_SLOTS then
			PlayerHotbars[Player][Slot] = ActionId
		end
	end

	Packets.HotbarSync:FireClient(Player, PlayerHotbars[Player])
end

function HotbarService.CleanupPlayer(Player: Player)
	PlayerHotbars[Player] = nil
	HotbarService.HotbarCleared:Fire(Player)
end

function HotbarService.OnSlotActivated(Player: Player, SlotNumber: number)
	if type(SlotNumber) ~= "number" then
		return
	end

	if SlotNumber < 1 or SlotNumber > MAX_SLOTS then
		return
	end

	local Hotbar = PlayerHotbars[Player]
	if not Hotbar then
		return
	end

	local ActionId = Hotbar[SlotNumber]
	if not ActionId then
		return
	end

	ActionService.OnActionRequested(Player, ActionId, tick())
end

function HotbarService.OnSlotAssigned(Player: Player, SlotNumber: number, ActionId: string?)
	if type(SlotNumber) ~= "number" then
		return
	end

	if SlotNumber < 1 or SlotNumber > MAX_SLOTS then
		return
	end

	local Hotbar = PlayerHotbars[Player]
	if not Hotbar then
		return
	end

	if not ActionId then return end

	Hotbar[SlotNumber] = ActionId

	Packets.HotbarSlotUpdated:FireClient(Player, SlotNumber, ActionId)

	HotbarService.SlotChanged:Fire(Player, SlotNumber, ActionId)
end

function HotbarService.GetSlot(Player: Player, SlotNumber: number): string?
	local Hotbar = PlayerHotbars[Player]
	if not Hotbar then
		return nil
	end

	return Hotbar[SlotNumber]
end

function HotbarService.SetSlot(Player: Player, SlotNumber: number, ActionId: string?)
	if SlotNumber < 1 or SlotNumber > MAX_SLOTS then
		return
	end

	local Hotbar = PlayerHotbars[Player]
	if not Hotbar then
		return
	end

	if not ActionId then return end

	Hotbar[SlotNumber] = ActionId

	Packets.HotbarSlotUpdated:FireClient(Player, SlotNumber, ActionId)

	HotbarService.SlotChanged:Fire(Player, SlotNumber, ActionId)
end

function HotbarService.GetHotbar(Player: Player): { [number]: string }?
	local Hotbar = PlayerHotbars[Player]
	if not Hotbar then
		return nil
	end

	return table.clone(Hotbar)
end

function HotbarService.ClearSlot(Player: Player, SlotNumber: number)
	HotbarService.SetSlot(Player, SlotNumber, nil)
end

function HotbarService.SwapSlots(Player: Player, SlotA: number, SlotB: number)
	local Hotbar = PlayerHotbars[Player]
	if not Hotbar then
		return
	end

	if SlotA < 1 or SlotA > MAX_SLOTS then
		return
	end

	if SlotB < 1 or SlotB > MAX_SLOTS then
		return
	end

	local ActionA = Hotbar[SlotA]
	local ActionB = Hotbar[SlotB]

	Hotbar[SlotA] = ActionB
	Hotbar[SlotB] = ActionA

	Packets.HotbarSlotUpdated:FireClient(Player, SlotA, ActionB)
	Packets.HotbarSlotUpdated:FireClient(Player, SlotB, ActionA)

	HotbarService.SlotChanged:Fire(Player, SlotA, ActionB)
	HotbarService.SlotChanged:Fire(Player, SlotB, ActionA)
end

function HotbarService.FindSlotByAction(Player: Player, ActionId: string): number?
	local Hotbar = PlayerHotbars[Player]
	if not Hotbar then
		return nil
	end

	for Slot, Id in Hotbar do
		if Id == ActionId then
			return Slot
		end
	end

	return nil
end

return HotbarService