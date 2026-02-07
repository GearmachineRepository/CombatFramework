--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local InventoryTypes = require(Shared.Types.InventoryTypes)

type InventoryRule = InventoryTypes.InventoryRule

local InventoryConfig: { [string]: InventoryRule } = {
	Backpack = {
		MaxSlots = 20,
		AllowedTypes = nil,
	},

	Hotbar = {
		MaxSlots = 6,
		AllowedTypes = { "Skill", "Consumable", "Weapon" },
	},

	Bank = {
		MaxSlots = 50,
		AllowedTypes = nil,
	},
}

return InventoryConfig