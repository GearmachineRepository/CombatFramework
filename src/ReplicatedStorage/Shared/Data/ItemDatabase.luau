--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryTypes = require(Shared.Types.InventoryTypes)

type Metadata = InventoryTypes.Metadata

export type ItemDefinition = {
	ItemId: string,
	DisplayName: string,
	Description: string?,
	ItemType: string,
	MaxStack: number,
	Icon: string?,
	DefaultMetadata: Metadata?,
}

local Items: { [string]: ItemDefinition } = {
	HealthPotion = {
		ItemId = "HealthPotion",
		DisplayName = "Health Potion",
		Description = "Restores 50 health.",
		ItemType = "Consumable",
		MaxStack = 20,
		Icon = "rbxassetid://0",
	},

	IronSword = {
		ItemId = "IronSword",
		DisplayName = "Iron Sword",
		Description = "A basic iron sword.",
		ItemType = "Weapon",
		MaxStack = 1,
		Icon = "rbxassetid://0",
		DefaultMetadata = { Durability = 100 },
	},

	WoodLog = {
		ItemId = "WoodLog",
		DisplayName = "Wood Log",
		Description = "A piece of wood.",
		ItemType = "Crafting",
		MaxStack = 99,
		Icon = "rbxassetid://0",
	},
}

local ItemDatabase = {}

function ItemDatabase.Get(ItemId: string): ItemDefinition?
	return Items[ItemId]
end

function ItemDatabase.GetMaxStack(ItemId: string): number
	local Definition = Items[ItemId]
	return if Definition then Definition.MaxStack else 1
end

function ItemDatabase.GetItemType(ItemId: string): string?
	local Definition = Items[ItemId]
	return if Definition then Definition.ItemType else nil
end

function ItemDatabase.Exists(ItemId: string): boolean
	return Items[ItemId] ~= nil
end

function ItemDatabase.GetAll(): { [string]: ItemDefinition }
	return Items
end

return ItemDatabase