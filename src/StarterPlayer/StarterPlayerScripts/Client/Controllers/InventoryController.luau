--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local InventoryTypes = require(Shared.Types.InventoryTypes)
local InventoryConfig = require(Shared.Config.InventoryConfig)
local ItemDatabase = require(Shared.Data.ItemDatabase)
local InventoryUtil = require(Shared.Utils.InventoryUtil)

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
	return InventoryUtil.GetItemCount(TargetInventory, ItemId, MaxSlots, TargetMetadata)
end

function InventoryController.HasItem(InventoryName: string, ItemId: string, Quantity: number, TargetMetadata: Metadata?): boolean
	local TargetInventory = Inventories[InventoryName]
	if not TargetInventory then
		return false
	end

	local MaxSlots = GetMaxSlots(InventoryName)
	return InventoryUtil.HasItem(TargetInventory, ItemId, Quantity, MaxSlots, TargetMetadata)
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

function InventoryController.RequestDeposit(
	SourceInventory: string,
	SourceIndex: number,
	TargetInventory: string
)
	Packets.InventoryDeposit:Fire(SourceInventory, SourceIndex, TargetInventory)
end

function InventoryController.RequestTransferAndDeposit(
	SourceInventory: string,
	SourceIndex: number,
	TargetInventory: string,
	TargetIndex: number
)
	Packets.InventoryTransferDeposit:Fire(SourceInventory, SourceIndex, TargetInventory, TargetIndex)
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

function InventoryController.IsItemTypeAllowed(InventoryName: string, ItemId: string): boolean
	local Rule = InventoryConfig[InventoryName]
	if not Rule or not Rule.AllowedTypes then
		return true
	end

	local ItemType = ItemDatabase.GetItemType(ItemId)
	if not ItemType then
		return false
	end

	return table.find(Rule.AllowedTypes, ItemType) ~= nil
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

--[=[
	Predicts a slot-to-slot transfer locally. Mutates client inventory data
	and fires SlotUpdated for both source and target so the UI refreshes
	instantly before the server round-trip completes.

	@param SourceInventoryName string -- Name of the source inventory
	@param SourceIndex number -- Slot index in the source inventory
	@param TargetInventoryName string -- Name of the target inventory
	@param TargetIndex number -- Slot index in the target inventory
]=]
function InventoryController.PredictTransfer(
	SourceInventoryName: string,
	SourceIndex: number,
	TargetInventoryName: string,
	TargetIndex: number
)
	local SourceInventory = Inventories[SourceInventoryName]
	local TargetInventory = Inventories[TargetInventoryName]
	if not SourceInventory or not TargetInventory then
		return
	end

	local OldSource = SourceInventory[SourceIndex]
	local OldTarget = TargetInventory[TargetIndex]

	local Success = InventoryUtil.TransferSlot(SourceInventory, SourceIndex, TargetInventory, TargetIndex)
	if not Success then
		return
	end

	InventoryController.SlotUpdated:Fire(SourceInventoryName, SourceIndex, SourceInventory[SourceIndex], OldSource)

	if SourceInventoryName ~= TargetInventoryName or SourceIndex ~= TargetIndex then
		InventoryController.SlotUpdated:Fire(TargetInventoryName, TargetIndex, TargetInventory[TargetIndex], OldTarget)
	end
end

--[=[
	Predicts clearing a single source slot locally. Used when the full
	target-side prediction is not feasible and only the source removal
	needs to be shown immediately.

	@param InventoryName string -- Name of the inventory containing the slot
	@param SlotIndex number -- Slot index to clear
]=]
function InventoryController.PredictSourceClear(
	InventoryName: string,
	SlotIndex: number
)
	local TargetInventory = Inventories[InventoryName]
	if not TargetInventory then
		return
	end

	local OldStack = TargetInventory[SlotIndex]
	if not OldStack then
		return
	end

	TargetInventory[SlotIndex] = nil
	InventoryController.SlotUpdated:Fire(InventoryName, SlotIndex, nil, OldStack)
end

--[=[
	Predicts a deposit operation locally. Clears the source slot and runs
	AddItem on the target inventory, firing SlotUpdated for all affected
	slots so the UI updates on both sides without waiting for the server.

	@param SourceInventoryName string -- Name of the source inventory
	@param SourceIndex number -- Slot index being deposited from
	@param TargetInventoryName string -- Name of the target inventory
]=]
function InventoryController.PredictDeposit(
	SourceInventoryName: string,
	SourceIndex: number,
	TargetInventoryName: string
)
	local SourceInventory = Inventories[SourceInventoryName]
	local TargetInventory = Inventories[TargetInventoryName]
	if not SourceInventory or not TargetInventory then
		return
	end

	local SourceStack = SourceInventory[SourceIndex]
	if not SourceStack then
		return
	end

	local TargetMaxSlots = GetMaxSlots(TargetInventoryName)

	local SlotsBefore: { [number]: ItemStack? } = {}
	for Index = 1, TargetMaxSlots do
		local Stack = TargetInventory[Index]
		if Stack then
			SlotsBefore[Index] = { ItemId = Stack.ItemId, Quantity = Stack.Quantity, Metadata = Stack.Metadata }
		end
	end

	local OldSource = SourceStack
	SourceInventory[SourceIndex] = nil

	local Overflow = InventoryUtil.AddItem(
		TargetInventory,
		SourceStack.ItemId,
		SourceStack.Quantity,
		TargetMaxSlots,
		SourceStack.Metadata
	)

	if Overflow > 0 then
		SourceInventory[SourceIndex] = {
			ItemId = SourceStack.ItemId,
			Quantity = Overflow,
			Metadata = SourceStack.Metadata,
		}
	end

	InventoryController.SlotUpdated:Fire(SourceInventoryName, SourceIndex, SourceInventory[SourceIndex], OldSource)

	for Index = 1, TargetMaxSlots do
		local Before = SlotsBefore[Index]
		local After = TargetInventory[Index]

		local Changed =
			(Before == nil and After ~= nil)
			or (
				Before ~= nil
				and After ~= nil
				and Before.Quantity ~= After.Quantity
			)

		if Changed then
			InventoryController.SlotUpdated:Fire(TargetInventoryName, Index, After, Before)
		end
	end
end

--[=[
	Predicts a transfer-and-deposit operation locally. Mirrors the server
	logic: if the target slot is empty or stackable, delegates to
	PredictTransfer. Otherwise places the source item in the target slot
	and redistributes the displaced stack into the source inventory via
	AddItem, firing SlotUpdated for all affected slots.

	@param SourceInventoryName string -- Name of the source inventory
	@param SourceIndex number -- Slot index in the source inventory
	@param TargetInventoryName string -- Name of the target inventory
	@param TargetIndex number -- Slot index in the target inventory
]=]
function InventoryController.PredictTransferAndDeposit(
	SourceInventoryName: string,
	SourceIndex: number,
	TargetInventoryName: string,
	TargetIndex: number
)
	local SourceInventory = Inventories[SourceInventoryName]
	local TargetInventory = Inventories[TargetInventoryName]
	if not SourceInventory or not TargetInventory then
		return
	end

	local SourceStack = SourceInventory[SourceIndex]
	if not SourceStack then
		return
	end

	local DisplacedStack = TargetInventory[TargetIndex]

	if not DisplacedStack or DisplacedStack.ItemId == SourceStack.ItemId then
		InventoryController.PredictTransfer(SourceInventoryName, SourceIndex, TargetInventoryName, TargetIndex)
		return
	end

	local SourceMaxSlots = GetMaxSlots(SourceInventoryName)

	local SourceSlotsBefore: { [number]: ItemStack? } = {}
	for Index = 1, SourceMaxSlots do
		local Stack = SourceInventory[Index]
		if Stack then
			SourceSlotsBefore[Index] = { ItemId = Stack.ItemId, Quantity = Stack.Quantity, Metadata = Stack.Metadata }
		end
	end

	local OldTarget = DisplacedStack

	SourceInventory[SourceIndex] = nil
	TargetInventory[TargetIndex] = SourceStack

	local Overflow = InventoryUtil.AddItem(
		SourceInventory,
		DisplacedStack.ItemId,
		DisplacedStack.Quantity,
		SourceMaxSlots,
		DisplacedStack.Metadata
	)

	if Overflow > 0 then
		SourceInventory[SourceIndex] = {
			ItemId = DisplacedStack.ItemId,
			Quantity = Overflow,
			Metadata = DisplacedStack.Metadata,
		}
	end

	for Index = 1, SourceMaxSlots do
		local Before = SourceSlotsBefore[Index]
		local After = SourceInventory[Index]

		local Changed =
			(Before == nil and After ~= nil)
			or (Before ~= nil and After == nil)
			or (
				Before ~= nil
				and After ~= nil
				and (
					Before.ItemId ~= After.ItemId
					or Before.Quantity ~= After.Quantity
				)
			)


		if Changed then
			InventoryController.SlotUpdated:Fire(SourceInventoryName, Index, After, Before)
		end
	end

	InventoryController.SlotUpdated:Fire(TargetInventoryName, TargetIndex, TargetInventory[TargetIndex], OldTarget)
end

return InventoryController