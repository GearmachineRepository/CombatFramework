--!strict

--[=[
	@class ItemDatabase

	Static registry of all item definitions. Provides lookups by ItemId
	for display info, stack limits, item types, and default metadata.

	Item IDs are the string keys in the Items table. Definitions do not
	redundantly store their own ID.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryTypes = require(Shared.Types.InventoryTypes)

type Metadata = InventoryTypes.Metadata

export type ItemDefinition = {
	DisplayName: string,
	Description: string?,
	ItemType: string,
	MaxStack: number,
	Icon: string?,
	DefaultMetadata: Metadata?,
}

local Items: { [string]: ItemDefinition } = {
	HealthPotion = {
		DisplayName = "Health Potion",
		Description = "Restores 50 health.",
		ItemType = "Consumable",
		MaxStack = 20,
		Icon = "rbxassetid://0",
	},

	IronSword = {
		DisplayName = "Iron Sword",
		Description = "A basic iron sword.",
		ItemType = "Weapon",
		MaxStack = 1,
		Icon = "rbxassetid://0",
		DefaultMetadata = { Durability = 100 },
	},

	WoodLog = {
		DisplayName = "Wood Log",
		Description = "A piece of wood.",
		ItemType = "Crafting",
		MaxStack = 99,
		Icon = "rbxassetid://0",
	},
}

local ItemDatabase = {}

--[=[
	Returns the full item definition for the given ID, or nil.

	@param ItemId string -- The item key to look up
	@return ItemDefinition? -- The definition, or nil if not found
]=]
function ItemDatabase.Get(ItemId: string): ItemDefinition?
	return Items[ItemId]
end

--[=[
	Returns the maximum stack size for the given item, defaulting to 1.

	@param ItemId string -- The item key
	@return number -- The max stack size
]=]
function ItemDatabase.GetMaxStack(ItemId: string): number
	local Definition = Items[ItemId]
	return if Definition then Definition.MaxStack else 1
end

--[=[
	Returns the item type string for the given item, or nil.

	@param ItemId string -- The item key
	@return string? -- The item type, or nil
]=]
function ItemDatabase.GetItemType(ItemId: string): string?
	local Definition = Items[ItemId]
	return if Definition then Definition.ItemType else nil
end

--[=[
	Returns whether an item with the given ID exists.

	@param ItemId string -- The item key to check
	@return boolean -- True if the item exists
]=]
function ItemDatabase.Exists(ItemId: string): boolean
	return Items[ItemId] ~= nil
end

--[=[
	Returns the full items table. Keys are item IDs.

	@return { [string]: ItemDefinition } -- All registered items
]=]
function ItemDatabase.GetAll(): { [string]: ItemDefinition }
	return Items
end

return ItemDatabase