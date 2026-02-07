--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryTypes = require(Shared.Types.InventoryTypes)
local ItemDatabase = require(Shared.Data.ItemDatabase)

type ItemStack = InventoryTypes.ItemStack
type Inventory = InventoryTypes.Inventory
type Metadata = InventoryTypes.Metadata

local InventoryUtil = {}

local function MetadataMatches(MetadataA: Metadata?, MetadataB: Metadata?): boolean
	if MetadataA == nil and MetadataB == nil then
		return true
	end

	if MetadataA == nil or MetadataB == nil then
		return false
	end

	for Key, Value in MetadataA do
		if MetadataB[Key] ~= Value then
			return false
		end
	end

	for Key, Value in MetadataB do
		if MetadataA[Key] ~= Value then
			return false
		end
	end

	return true
end

function InventoryUtil.CanStack(StackA: ItemStack, StackB: ItemStack): boolean
	if StackA.ItemId ~= StackB.ItemId then
		return false
	end

	return MetadataMatches(StackA.Metadata, StackB.Metadata)
end

function InventoryUtil.FindFirstEmptySlot(TargetInventory: Inventory, MaxSlots: number): number?
	for Index = 1, MaxSlots do
		if TargetInventory[Index] == nil then
			return Index
		end
	end

	return nil
end

function InventoryUtil.FindStackableSlot(
	TargetInventory: Inventory,
	ItemId: string,
	TargetMetadata: Metadata?,
	MaxSlots: number
): number?
	local StackLimit = ItemDatabase.GetMaxStack(ItemId)

	for Index = 1, MaxSlots do
		local Stack = TargetInventory[Index]
		if Stack == nil then
			continue
		end

		if Stack.ItemId ~= ItemId then
			continue
		end

		if not MetadataMatches(Stack.Metadata, TargetMetadata) then
			continue
		end

		if Stack.Quantity >= StackLimit then
			continue
		end

		return Index
	end

	return nil
end

function InventoryUtil.AddItem(
	TargetInventory: Inventory,
	ItemId: string,
	Quantity: number,
	MaxSlots: number,
	TargetMetadata: Metadata?
): number
	local Remaining = Quantity
	local StackLimit = ItemDatabase.GetMaxStack(ItemId)

	while Remaining > 0 do
		local StackableIndex = InventoryUtil.FindStackableSlot(
			TargetInventory,
			ItemId,
			TargetMetadata,
			MaxSlots
		)

		if StackableIndex then
			local Stack = TargetInventory[StackableIndex] :: ItemStack
			local SpaceInStack = StackLimit - Stack.Quantity
			local ToAdd = math.min(Remaining, SpaceInStack)
			Stack.Quantity = Stack.Quantity + ToAdd
			Remaining = Remaining - ToAdd
			continue
		end

		local EmptyIndex = InventoryUtil.FindFirstEmptySlot(TargetInventory, MaxSlots)
		if EmptyIndex == nil then
			break
		end

		local ToAdd = math.min(Remaining, StackLimit)
		TargetInventory[EmptyIndex] = {
			ItemId = ItemId,
			Quantity = ToAdd,
			Metadata = TargetMetadata,
		}
		Remaining = Remaining - ToAdd
	end

	return Remaining
end

function InventoryUtil.RemoveItem(
	TargetInventory: Inventory,
	ItemId: string,
	Quantity: number,
	MaxSlots: number,
	TargetMetadata: Metadata?
): number
	local Remaining = Quantity

	for Index = MaxSlots, 1, -1 do
		if Remaining <= 0 then
			break
		end

		local Stack = TargetInventory[Index]
		if Stack == nil then
			continue
		end

		if Stack.ItemId ~= ItemId then
			continue
		end

		if TargetMetadata and not MetadataMatches(Stack.Metadata, TargetMetadata) then
			continue
		end

		local ToRemove = math.min(Remaining, Stack.Quantity)
		Stack.Quantity = Stack.Quantity - ToRemove
		Remaining = Remaining - ToRemove

		if Stack.Quantity <= 0 then
			TargetInventory[Index] = nil
		end
	end

	return Quantity - Remaining
end

function InventoryUtil.GetSlot(TargetInventory: Inventory, SlotIndex: number): ItemStack?
	return TargetInventory[SlotIndex]
end

function InventoryUtil.SetSlot(TargetInventory: Inventory, SlotIndex: number, Stack: ItemStack?)
	TargetInventory[SlotIndex] = Stack
end

function InventoryUtil.SwapSlots(
	SourceInventory: Inventory,
	SourceIndex: number,
	TargetInventory: Inventory,
	TargetIndex: number
)
	local SourceStack = SourceInventory[SourceIndex]
	local TargetStack = TargetInventory[TargetIndex]

	SourceInventory[SourceIndex] = TargetStack
	TargetInventory[TargetIndex] = SourceStack
end

function InventoryUtil.TransferSlot(
	SourceInventory: Inventory,
	SourceIndex: number,
	TargetInventory: Inventory,
	TargetIndex: number
): boolean
	local SourceStack = SourceInventory[SourceIndex]
	if SourceStack == nil then
		return false
	end

	local TargetStack = TargetInventory[TargetIndex]

	if TargetStack == nil then
		TargetInventory[TargetIndex] = SourceStack
		SourceInventory[SourceIndex] = nil
		return true
	end

	if InventoryUtil.CanStack(SourceStack, TargetStack) then
		local StackLimit = ItemDatabase.GetMaxStack(SourceStack.ItemId)
		local SpaceInTarget = StackLimit - TargetStack.Quantity
		local ToTransfer = math.min(SourceStack.Quantity, SpaceInTarget)

		if ToTransfer > 0 then
			TargetStack.Quantity = TargetStack.Quantity + ToTransfer
			SourceStack.Quantity = SourceStack.Quantity - ToTransfer

			if SourceStack.Quantity <= 0 then
				SourceInventory[SourceIndex] = nil
			end

			return true
		end
	end

	InventoryUtil.SwapSlots(SourceInventory, SourceIndex, TargetInventory, TargetIndex)
	return true
end

function InventoryUtil.GetItemCount(
	TargetInventory: Inventory,
	ItemId: string,
	MaxSlots: number,
	TargetMetadata: Metadata?
): number
	local Total = 0

	for Index = 1, MaxSlots do
		local Stack = TargetInventory[Index]
		if Stack == nil then
			continue
		end

		if Stack.ItemId ~= ItemId then
			continue
		end

		if TargetMetadata and not MetadataMatches(Stack.Metadata, TargetMetadata) then
			continue
		end

		Total = Total + Stack.Quantity
	end

	return Total
end

function InventoryUtil.HasItem(
	TargetInventory: Inventory,
	ItemId: string,
	Quantity: number,
	MaxSlots: number,
	TargetMetadata: Metadata?
): boolean
	return InventoryUtil.GetItemCount(TargetInventory, ItemId, MaxSlots, TargetMetadata) >= Quantity
end

function InventoryUtil.ClearInventory(TargetInventory: Inventory, MaxSlots: number)
	for Index = 1, MaxSlots do
		TargetInventory[Index] = nil
	end
end

function InventoryUtil.CloneStack(Stack: ItemStack): ItemStack
	local Clone: ItemStack = {
		ItemId = Stack.ItemId,
		Quantity = Stack.Quantity,
		Metadata = nil,
	}

	if Stack.Metadata then
		Clone.Metadata = table.clone(Stack.Metadata)
	end

	return Clone
end

function InventoryUtil.CloneInventory(TargetInventory: Inventory, MaxSlots: number): Inventory
	local Clone: Inventory = {}

	for Index = 1, MaxSlots do
		local Stack = TargetInventory[Index]
		if Stack then
			Clone[Index] = InventoryUtil.CloneStack(Stack)
		end
	end

	return Clone
end

return InventoryUtil