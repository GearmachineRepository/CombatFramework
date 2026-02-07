--!strict

export type CategoryDefinition = {
	Name: string,
	Description: string?,
	ItemTypes: { string },
	SortOrder: number,
}

export type CategoryEntry = {
	CategoryId: string,
	Definition: CategoryDefinition,
}

local CategoryConfig: { [string]: CategoryDefinition } = {
	Abilities = {
		Name = "Abilities",
		Description = "Active skills and techniques",
		ItemTypes = { "Skill", "Ability" },
		SortOrder = 1,
	},

	Weapons = {
		Name = "Weapons",
		Description = "Offensive equipment",
		ItemTypes = { "Weapon" },
		SortOrder = 2,
	},

	Equipment = {
		Name = "Equipment",
		Description = "Armor and accessories",
		ItemTypes = { "Armor", "Accessory" },
		SortOrder = 3,
	},

	Consumables = {
		Name = "Consumables",
		Description = "Food, potions, and other consumables",
		ItemTypes = { "Consumable", "Food", "Potion" },
		SortOrder = 4,
	},

	Materials = {
		Name = "Materials",
		Description = "Crafting components",
		ItemTypes = { "Crafting", "Material" },
		SortOrder = 5,
	},

	Tools = {
		Name = "Tools",
		Description = "Utility items",
		ItemTypes = { "Tool" },
		SortOrder = 6,
	},

	Miscellaneous = {
		Name = "Miscellaneous",
		Description = "Other items",
		ItemTypes = { "Misc", "Junk" },
		SortOrder = 99,
	},
}

local CategoryConfigModule = {}

function CategoryConfigModule.GetAll(): { [string]: CategoryDefinition }
	return CategoryConfig
end

function CategoryConfigModule.Get(CategoryId: string): CategoryDefinition?
	return CategoryConfig[CategoryId]
end

function CategoryConfigModule.GetSorted(): { CategoryEntry }
	local Sorted: { CategoryEntry } = {}

	for CategoryId, Definition in CategoryConfig do
		table.insert(Sorted, {
			CategoryId = CategoryId,
			Definition = Definition,
		})
	end

	table.sort(Sorted, function(A, B)
		return A.Definition.SortOrder < B.Definition.SortOrder
	end)

	return Sorted
end

function CategoryConfigModule.GetCategoryForItemType(ItemType: string): string?
	for CategoryId, Definition in CategoryConfig do
		if table.find(Definition.ItemTypes, ItemType) then
			return CategoryId
		end
	end

	return "Miscellaneous"
end

return CategoryConfigModule