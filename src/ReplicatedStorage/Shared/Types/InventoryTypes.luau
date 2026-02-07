--!strict

export type Metadata = { [string]: any }

export type ItemStack = {
	ItemId: string,
	Quantity: number,
	Metadata: Metadata?,
}

export type Inventory = { ItemStack? }

export type InventoryRule = {
	MaxSlots: number,
	AllowedTypes: { string }?,
}

export type InventoryCollection = {
	Backpack: Inventory,
	Hotbar: Inventory,
	Bank: Inventory,
}

return nil