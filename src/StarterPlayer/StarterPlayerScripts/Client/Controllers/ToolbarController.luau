--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Packages = require(Shared.Packages)

local Trove = Packages.Trove
local Signal = Packages.Signal

local CombatController = require(script.Parent.CombatController)

local LocalPlayer = Players.LocalPlayer :: Player

local ToolbarController = {}

ToolbarController.Dependencies = { "InputController", "CombatController" }

ToolbarController.ToolEquipped = Signal.new()
ToolbarController.ToolUnequipped = Signal.new()
ToolbarController.ToolActivated = Signal.new()

local ControllerTrove: typeof(Trove.new()) = nil :: any
local CharacterTrove: typeof(Trove.new()) = nil :: any
local ToolTrove: typeof(Trove.new()) = nil :: any
local EquippedTool: Tool? = nil

function ToolbarController.Init()
	ControllerTrove = Trove.new()
end

function ToolbarController.Start()
	ControllerTrove:Connect(LocalPlayer.CharacterAdded, function(Character: Model)
		ToolbarController.OnCharacterAdded(Character)
	end)

	if LocalPlayer.Character then
		ToolbarController.OnCharacterAdded(LocalPlayer.Character)
	end
end

function ToolbarController.Stop()
	if ToolTrove then
		ToolTrove:Destroy()
		ToolTrove = nil :: any
	end
	if CharacterTrove then
		CharacterTrove:Destroy()
		CharacterTrove = nil :: any
	end
	ControllerTrove:Destroy()
	EquippedTool = nil
end

function ToolbarController.OnCharacterAdded(Character: Model)
	if ToolTrove then
		ToolTrove:Destroy()
		ToolTrove = nil :: any
	end
	if CharacterTrove then
		CharacterTrove:Destroy()
	end
	CharacterTrove = ControllerTrove:Extend()
	EquippedTool = nil

	CharacterTrove:Connect(Character.ChildAdded, function(Child: Instance)
		if Child:IsA("Tool") then
			ToolbarController.OnToolEquipped(Child)
		end
	end)

	CharacterTrove:Connect(Character.ChildRemoved, function(Child: Instance)
		if Child:IsA("Tool") and Child == EquippedTool then
			ToolbarController.OnToolUnequipped(Child)
		end
	end)

	for _, Child in Character:GetChildren() do
		if Child:IsA("Tool") then
			ToolbarController.OnToolEquipped(Child)
			break
		end
	end
end

function ToolbarController.OnToolEquipped(Tool: Tool)
	if ToolTrove then
		ToolTrove:Destroy()
	end
	ToolTrove = Trove.new()

	EquippedTool = Tool
	ToolbarController.ToolEquipped:Fire(Tool)

	ToolTrove:Connect(Tool.Activated, function()
		ToolbarController.OnToolActivated(Tool)
	end)
end

function ToolbarController.OnToolUnequipped(Tool: Tool)
	if ToolTrove then
		ToolTrove:Destroy()
		ToolTrove = nil :: any
	end

	if EquippedTool == Tool then
		EquippedTool = nil
	end
	ToolbarController.ToolUnequipped:Fire(Tool)
end

function ToolbarController.OnToolActivated(Tool: Tool)
	local ActionId = Tool:GetAttribute("ActionId") :: string?

	if not ActionId then
		return
	end

	ToolbarController.ToolActivated:Fire(Tool, ActionId)

	local CanActivate, _Reason = CombatController.CanActivate(ActionId)
	if not CanActivate then
		return
	end

	CombatController.ActivateAction(ActionId)
end

function ToolbarController.GetEquippedTool(): Tool?
	return EquippedTool
end

function ToolbarController.GetEquippedActionId(): string?
	if not EquippedTool then
		return nil
	end
	return EquippedTool:GetAttribute("ActionId") :: string?
end

return ToolbarController