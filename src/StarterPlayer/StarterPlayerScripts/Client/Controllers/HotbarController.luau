--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local Combat = require(Shared.Combat)

local Trove = Packages.Trove
local Signal = Packages.Signal

local ActionRegistry = Combat.ActionRegistry
local CombatController = require(script.Parent.CombatController)

local HotbarController = {}

HotbarController.Dependencies = { "CombatController" }

HotbarController.SlotActivated = Signal.new()
HotbarController.SlotChanged = Signal.new()
HotbarController.HotbarSynced = Signal.new()

local ControllerTrove: typeof(Trove.new()) = nil :: any

local CurrentHotbar: { [number]: string } = {}
local Cooldowns: { [number]: number } = {}

local MAX_SLOTS = 6

local SLOT_KEYCODES: { [number]: Enum.KeyCode } = {
	[1] = Enum.KeyCode.One,
	[2] = Enum.KeyCode.Two,
	[3] = Enum.KeyCode.Three,
	[4] = Enum.KeyCode.Four,
	[5] = Enum.KeyCode.Five,
	[6] = Enum.KeyCode.Six,
}

function HotbarController.Init()
	ControllerTrove = Trove.new()
end

function HotbarController.Start()
	ControllerTrove:Add(Packets.HotbarSync.OnClientEvent:Connect(function(Hotbar: { [number]: string })
		HotbarController.OnHotbarSynced(Hotbar)
	end))

	ControllerTrove:Add(Packets.HotbarSlotUpdated.OnClientEvent:Connect(function(SlotNumber: number, ActionId: string?)
		HotbarController.OnSlotUpdated(SlotNumber, ActionId)
	end))

	ControllerTrove:Add(Packets.CooldownStarted.OnClientEvent:Connect(function(ActionId: string, Duration: number)
		HotbarController.OnCooldownStarted(ActionId, Duration)
	end))

	for Slot, KeyCode in SLOT_KEYCODES do
		local ActionName = "HotbarSlot" .. Slot

		ContextActionService:BindAction(
			ActionName,
			function(_Name: string, State: Enum.UserInputState, _Input: InputObject)
				if State == Enum.UserInputState.Begin then
					HotbarController.ActivateSlot(Slot)
				end
				return Enum.ContextActionResult.Pass
			end,
			false,
			KeyCode
		)

		ControllerTrove:Add(function()
			ContextActionService:UnbindAction(ActionName)
		end)
	end
end

function HotbarController.Stop()
	if ControllerTrove then
		ControllerTrove:Destroy()
	end
end

function HotbarController.OnHotbarSynced(Hotbar: { [number]: string })
	CurrentHotbar = Hotbar
	HotbarController.HotbarSynced:Fire(Hotbar)
end

function HotbarController.OnSlotUpdated(SlotNumber: number, ActionId: string?)
    if not ActionId then return end
	CurrentHotbar[SlotNumber] = ActionId
	HotbarController.SlotChanged:Fire(SlotNumber, ActionId)
end

function HotbarController.OnCooldownStarted(ActionId: string, Duration: number)
	for Slot, Id in CurrentHotbar do
		if Id == ActionId then
			Cooldowns[Slot] = tick() + Duration
		end
	end
end

function HotbarController.ActivateSlot(SlotNumber: number)
	if SlotNumber < 1 or SlotNumber > MAX_SLOTS then
		return
	end

	local ActionId = CurrentHotbar[SlotNumber]
	if not ActionId then
		return
	end

	local CooldownEnd = Cooldowns[SlotNumber]
	if CooldownEnd and tick() < CooldownEnd then
		return
	end

	if CombatController.IsActionActive() then
		return
	end

	local CanActivate, _Reason = CombatController.CanActivate(ActionId)
	if not CanActivate then
		return
	end

	Packets.HotbarActivate:Fire(SlotNumber)

	CombatController.ActivateAction(ActionId)

	HotbarController.SlotActivated:Fire(SlotNumber, ActionId)
end

function HotbarController.GetSlot(SlotNumber: number): string?
	return CurrentHotbar[SlotNumber]
end

function HotbarController.GetHotbar(): { [number]: string }
	return table.clone(CurrentHotbar)
end

function HotbarController.IsSlotOnCooldown(SlotNumber: number): boolean
	local CooldownEnd = Cooldowns[SlotNumber]
	if not CooldownEnd then
		return false
	end
	return tick() < CooldownEnd
end

function HotbarController.GetSlotCooldownRemaining(SlotNumber: number): number
	local CooldownEnd = Cooldowns[SlotNumber]
	if not CooldownEnd then
		return 0
	end

	local Remaining = CooldownEnd - tick()
	return math.max(0, Remaining)
end

function HotbarController.RequestAssign(SlotNumber: number, ActionId: string?)
	if SlotNumber < 1 or SlotNumber > MAX_SLOTS then
		return
	end

	Packets.HotbarAssign:Fire(SlotNumber, ActionId)
end

function HotbarController.FindSlotByAction(ActionId: string): number?
	for Slot, Id in CurrentHotbar do
		if Id == ActionId then
			return Slot
		end
	end
	return nil
end

function HotbarController.GetActionDefinition(SlotNumber: number): any?
	local ActionId = CurrentHotbar[SlotNumber]
	if not ActionId then
		return nil
	end

	return ActionRegistry.Get(ActionId)
end

return HotbarController