--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local InventoryTypes = require(Shared.Types.InventoryTypes)
local InventoryConfig = require(Shared.Config.InventoryConfig)
local ItemDatabase = require(Shared.Data.ItemDatabase)

local Trove = Packages.Trove
local Signal = Packages.Signal

type ItemStack = InventoryTypes.ItemStack
type Inventory = InventoryTypes.Inventory
type Metadata = InventoryTypes.Metadata

local InventoryController = {}

InventoryController.InventorySynced = Signal.new()
InventoryController.SlotUpdated = Signal.new()
InventoryController.ItemAdded = Signal.new()
InventoryController.ItemRemoved = Signal.new()

local ControllerTrove: typeof(Trove.new()) = nil :: any
local Inventories: { [string]: Inventory } = {}

local function GetMaxSlots(InventoryName: string): number
	local Rule = InventoryConfig[InventoryName]
	return if Rule then Rule.MaxSlots else 20
end

function InventoryController.Init()
	ControllerTrove = Trove.new()

	for InventoryName in InventoryConfig do
		Inventories[InventoryName] = {}
	end
end

function InventoryController.Start()
	ControllerTrove:Connect(Packets.InventorySync.OnClientEvent :: any, function(
		InventoryName: string,
		InventoryData: Inventory
	)
		Inventories[InventoryName] = InventoryData
		InventoryController.InventorySynced:Fire(InventoryName, InventoryData)
	end)

	ControllerTrove:Connect(Packets.InventorySlotUpdate.OnClientEvent :: any, function(
		InventoryName: string,
		SlotIndex: number,
		Stack: ItemStack?
	)
		local TargetInventory = Inventories[InventoryName]
		if not TargetInventory then
			Inventories[InventoryName] = {}
			TargetInventory = Inventories[InventoryName]
		end

		local OldStack = TargetInventory[SlotIndex]
		TargetInventory[SlotIndex] = Stack

		InventoryController.SlotUpdated:Fire(InventoryName, SlotIndex, Stack, OldStack)
	end)

	ControllerTrove:Connect(Packets.InventoryItemAdded.OnClientEvent :: any, function(
		InventoryName: string,
		ItemId: string,
		Quantity: number
	)
		InventoryController.ItemAdded:Fire(InventoryName, ItemId, Quantity)
	end)

	ControllerTrove:Connect(Packets.InventoryItemRemoved.OnClientEvent :: any, function(
		InventoryName: string,
		ItemId: string,
		Quantity: number
	)
		InventoryController.ItemRemoved:Fire(InventoryName, ItemId, Quantity)
	end)
end

function InventoryController.Stop()
	ControllerTrove:Destroy()
	table.clear(Inventories)
end

function InventoryController.GetInventory(InventoryName: string): Inventory?
	return Inventories[InventoryName]
end

function InventoryController.GetSlot(InventoryName: string, SlotIndex: number): ItemStack?
	local TargetInventory = Inventories[InventoryName]
	if not TargetInventory then
		return nil
	end

	return TargetInventory[SlotIndex]
end

function InventoryController.GetMaxSlots(InventoryName: string): number
	return GetMaxSlots(InventoryName)
end

function InventoryController.GetItemCount(InventoryName: string, ItemId: string, TargetMetadata: Metadata?): number
	local TargetInventory = Inventories[InventoryName]
	if not TargetInventory then
		return 0
	end

	local MaxSlots = GetMaxSlots(InventoryName)
	local Total = 0

	for Index = 1, MaxSlots do
		local Stack = TargetInventory[Index]
		if not Stack then
			continue
		end

		if Stack.ItemId ~= ItemId then
			continue
		end

		if TargetMetadata then
			local Matches = true
			for Key, Value in TargetMetadata do
				if not Stack.Metadata or Stack.Metadata[Key] ~= Value then
					Matches = false
					break
				end
			end
			if not Matches then
				continue
			end
		end

		Total = Total + Stack.Quantity
	end

	return Total
end

function InventoryController.HasItem(InventoryName: string, ItemId: string, Quantity: number, TargetMetadata: Metadata?): boolean
	return InventoryController.GetItemCount(InventoryName, ItemId, TargetMetadata) >= Quantity
end

function InventoryController.RequestTransfer(
	SourceInventory: string,
	SourceIndex: number,
	TargetInventory: string,
	TargetIndex: number
)
	Packets.InventoryTransfer:Fire(SourceInventory, SourceIndex, TargetInventory, TargetIndex)
end

function InventoryController.RequestSwap(
	SourceInventory: string,
	SourceIndex: number,
	TargetInventory: string,
	TargetIndex: number
)
	Packets.InventorySwap:Fire(SourceInventory, SourceIndex, TargetInventory, TargetIndex)
end

function InventoryController.RequestDrop(InventoryName: string, SlotIndex: number, Quantity: number?)
	local DropQuantity = Quantity or 0
	Packets.InventoryDrop:Fire(InventoryName, SlotIndex, DropQuantity)
end

function InventoryController.GetItemDefinition(ItemId: string)
	return ItemDatabase.Get(ItemId)
end

function InventoryController.GetAllInventoryNames(): { string }
	local Names: { string } = {}
	for Name in InventoryConfig do
		table.insert(Names, Name)
	end
	return Names
end

function InventoryController.IsInventoryEmpty(InventoryName: string): boolean
	local TargetInventory = Inventories[InventoryName]
	if not TargetInventory then
		return true
	end

	local MaxSlots = GetMaxSlots(InventoryName)
	for Index = 1, MaxSlots do
		if TargetInventory[Index] then
			return false
		end
	end

	return true
end

function InventoryController.GetFilledSlotCount(InventoryName: string): number
	local TargetInventory = Inventories[InventoryName]
	if not TargetInventory then
		return 0
	end

	local MaxSlots = GetMaxSlots(InventoryName)
	local Count = 0

	for Index = 1, MaxSlots do
		if TargetInventory[Index] then
			Count = Count + 1
		end
	end

	return Count
end

function InventoryController.GetEmptySlotCount(InventoryName: string): number
	local MaxSlots = GetMaxSlots(InventoryName)
	local Filled = InventoryController.GetFilledSlotCount(InventoryName)
	return MaxSlots - Filled
end

return InventoryController