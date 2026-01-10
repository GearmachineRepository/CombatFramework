--!strict

export type StateDefinition = {
	Default: boolean?,
	Replicate: boolean?,
	Conflicts: { string }?,
}

export type StateConfig = { [string]: StateDefinition }

--[[
	Always use the Enums module. This avoids typos.

	Example:

	```lua
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:WaitForChild("Shared")
	local Enums = require(Shared.Enums)

	[Enums.State.Attacking] = {
		Default = false,
		Replicate = true,
		Conflicts = { StateEnums.BLOCKING, StateEnums.STUNNED, StateEnums.DODGING },
	},
	```
]]

local StateConfig: StateConfig = {}

return StateConfig