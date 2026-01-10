--!strict
export type StatDefinition = {
	Default: number,
	Min: number?,
	Max: number?,
	MaxStat: string?,
	Replicate: boolean?,
}

export type StatConfig = { [string]: StatDefinition }

--[[
	Always use the Enums module. This avoids typos.

	Example:

	```lua
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Enums = require(Shared.Enums)

	[Enums.Stat.Health] = {
		Default = 100,
		Min = 0,
		MaxStat = Enums.Stat.MaxHealth,
		Replicate = true,
	},
	[Enums.Stat.MaxHealth] = {
		Default = 100,
		Min = 1,
		Max = 250,
		Replicate = true,
	},
	```
]]

local StatConfig: StatConfig = {}

return StatConfig