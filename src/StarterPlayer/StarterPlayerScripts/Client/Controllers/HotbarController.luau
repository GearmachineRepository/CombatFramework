--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local InventoryConfig = require(Shared.Config.InventoryConfig)

local Trove = Packages.Trove
local Signal = Packages.Signal

local InputController = require(script.Parent.InputController)
local InventoryController = require(script.Parent.InventoryController)

local HotbarController = {}

HotbarController.Dependencies = { "InputController", "InventoryController" }

HotbarController.SlotSelected = Signal.new()
HotbarController.SlotDeselected = Signal.new()
HotbarController.KeybindsUpdated = Signal.new()

local ControllerTrove: typeof(Trove.new()) = nil :: any
local SelectedSlot: number? = nil
local HotbarKeybinds: { [number]: string } = {}

local KEYBIND_CATEGORY = "Hotbar"
local ACTION_PREFIX = "HotbarSlot"

local function GetSlotCount(): number
	local Rule = InventoryConfig.Hotbar
	return if Rule then Rule.MaxSlots else 6
end

local function GetActionName(SlotIndex: number): string
	return ACTION_PREFIX .. tostring(SlotIndex)
end

local function OnSlotPressed(SlotIndex: number)
	local Inventory = InventoryController.GetInventory("Hotbar")
	local Stack = if Inventory then Inventory[SlotIndex] else nil

	if not Stack then
		return
	end

	if SelectedSlot == SlotIndex then
		HotbarController.DeselectSlot()
		return
	end

	local PreviousSlot = SelectedSlot
	SelectedSlot = SlotIndex

	if PreviousSlot then
		HotbarController.SlotDeselected:Fire(PreviousSlot)
	end

	HotbarController.SlotSelected:Fire(SlotIndex, Stack)
end

local function BindSlot(SlotIndex: number, KeyCodeName: string)
	local KeyCode = (Enum.KeyCode :: any)[KeyCodeName]
	if not KeyCode then
		warn(string.format("[HotbarController] Invalid KeyCode name: %s", KeyCodeName))
		return
	end

	InputController.BindAction(GetActionName(SlotIndex), function(State: Enum.UserInputState)
		if State == Enum.UserInputState.Begin then
			OnSlotPressed(SlotIndex)
		end
	end, KeyCode)
end

local function BindAllSlots()
	local SlotCount = GetSlotCount()
	for SlotIndex = 1, SlotCount do
		local KeyCodeName = HotbarKeybinds[SlotIndex]
		if KeyCodeName then
			BindSlot(SlotIndex, KeyCodeName)
		end
	end
end

local function UnbindAllSlots()
	local SlotCount = GetSlotCount()
	for SlotIndex = 1, SlotCount do
		InputController.UnbindAction(GetActionName(SlotIndex))
	end
end

local function ApplyAllKeybinds(Keybinds: { [number]: string })
	UnbindAllSlots()
	HotbarKeybinds = Keybinds
	BindAllSlots()
	HotbarController.KeybindsUpdated:Fire()
end

local function ApplySingleKeybind(SlotIndex: number, KeyCodeName: string)
	InputController.UnbindAction(GetActionName(SlotIndex))
	HotbarKeybinds[SlotIndex] = KeyCodeName
	BindSlot(SlotIndex, KeyCodeName)
	HotbarController.KeybindsUpdated:Fire()
end

function HotbarController.Init()
	ControllerTrove = Trove.new()
end

function HotbarController.Start()
	ControllerTrove:Connect(Packets.KeybindSync.OnClientEvent :: any, function(AllKeybinds: any)
		if typeof(AllKeybinds) ~= "table" then
			return
		end

		local HotbarData = AllKeybinds[KEYBIND_CATEGORY]
		if typeof(HotbarData) ~= "table" then
			return
		end

		local Keybinds: { [number]: string } = {}
		for SlotIndex, KeyCodeName in HotbarData do
			if typeof(SlotIndex) == "number" and typeof(KeyCodeName) == "string" then
				Keybinds[SlotIndex] = KeyCodeName
			end
		end

		ApplyAllKeybinds(Keybinds)
	end)

	ControllerTrove:Connect(Packets.KeybindChanged.OnClientEvent :: any, function(Category: string, SlotIndex: number, KeyCodeName: string)
		if Category ~= KEYBIND_CATEGORY then
			return
		end

		ApplySingleKeybind(SlotIndex, KeyCodeName)
	end)

	ControllerTrove:Connect(InventoryController.SlotUpdated :: any, function(InventoryName: string, SlotIndex: number)
		if InventoryName ~= "Hotbar" then
			return
		end

		if SelectedSlot ~= SlotIndex then
			return
		end

		local Inventory = InventoryController.GetInventory("Hotbar")
		local Stack = if Inventory then Inventory[SlotIndex] else nil

		if not Stack then
			HotbarController.DeselectSlot()
		end
	end)
end

function HotbarController.Stop()
	UnbindAllSlots()
	ControllerTrove:Destroy()
	SelectedSlot = nil
	table.clear(HotbarKeybinds)
end

function HotbarController.SelectSlot(SlotIndex: number)
	OnSlotPressed(SlotIndex)
end

function HotbarController.DeselectSlot()
	local PreviousSlot = SelectedSlot
	SelectedSlot = nil

	if PreviousSlot then
		HotbarController.SlotDeselected:Fire(PreviousSlot)
	end
end

function HotbarController.GetSelectedSlot(): number?
	return SelectedSlot
end

function HotbarController.GetKeybind(SlotIndex: number): string?
	return HotbarKeybinds[SlotIndex]
end

function HotbarController.SetKeybind(SlotIndex: number, KeyCodeName: string)
	ApplySingleKeybind(SlotIndex, KeyCodeName)
	Packets.KeybindChanged:Fire(KEYBIND_CATEGORY, SlotIndex, KeyCodeName)
end

return HotbarController