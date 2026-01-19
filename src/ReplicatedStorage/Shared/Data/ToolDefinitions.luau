--!strict

export type ToolDefinition = {
	ToolId: string,
	DisplayName: string,
	Description: string?,
	Icon: string,
	ActionId: string,
	Cooldown: number?,
}

local ToolDefinitions: { [string]: ToolDefinition } = {
	ThreeHitCombo = {
		ToolId = "ThreeHitCombo",
		DisplayName = "Combo",
		Description = "A basic three-hit combo attack",
		Icon = "rbxassetid://0",
		ActionId = "ThreeHitCombo",
		Cooldown = 0.5,
	},

	UppercutLauncher = {
		ToolId = "UppercutLauncher",
		DisplayName = "Uppercut",
		Description = "Launch enemies into the air",
		Icon = "rbxassetid://0",
		ActionId = "UppercutLauncher",
		Cooldown = 3,
	},

	AerialCombo = {
		ToolId = "AerialCombo",
		DisplayName = "Aerial",
		Description = "Chase and combo airborne targets",
		Icon = "rbxassetid://0",
		ActionId = "AerialCombo",
		Cooldown = 1,
	},

	GrabThrow = {
		ToolId = "GrabThrow",
		DisplayName = "Grab",
		Description = "Grab and throw enemies",
		Icon = "rbxassetid://0",
		ActionId = "GrabThrow",
		Cooldown = 5,
	},
}

local ToolDefinitionsModule = {}

function ToolDefinitionsModule.Get(ToolId: string): ToolDefinition?
	return ToolDefinitions[ToolId]
end

function ToolDefinitionsModule.GetByActionId(ActionId: string): ToolDefinition?
	for _, Definition in ToolDefinitions do
		if Definition.ActionId == ActionId then
			return Definition
		end
	end
	return nil
end

function ToolDefinitionsModule.GetAll(): { [string]: ToolDefinition }
	return table.clone(ToolDefinitions)
end

return ToolDefinitionsModule