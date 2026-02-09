--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Types = require(Server.Ensemble.Types)
local Packages = require(Shared.Packages)

local Trove = Packages.Trove

type Entity = Types.Entity
type EntityContext = Types.EntityContext

local DEFAULT_SLOT_COUNT = 6

local HotbarComponent = {}

HotbarComponent.ComponentName = "Hotbar"
HotbarComponent.Dependencies = {}

type HotbarInstance = {
	GetSlot: (SlotIndex: number) -> string?,
	SetSlot: (SlotIndex: number, ItemId: string?) -> (),
	GetAllSlots: () -> { [number]: string? },
	GetSlotCount: () -> number,
	FindSlot: (ItemId: string) -> number?,
	ClearSlot: (SlotIndex: number) -> (),
	ClearAll: () -> (),
	OnSlotChanged: (Callback: (SlotIndex: number, NewItemId: string?, OldItemId: string?) -> ()) -> () -> (),
	Destroy: () -> (),
}

function HotbarComponent.From(EntityInstance: Entity): HotbarInstance?
	return EntityInstance:GetComponent("Hotbar")
end

function HotbarComponent.Create(_EntityInstance: Entity, Context: EntityContext): HotbarInstance
	local HotbarConfig = Context.HotbarConfig
	local SlotCount = if HotbarConfig and HotbarConfig.SlotCount then HotbarConfig.SlotCount else DEFAULT_SLOT_COUNT
	local Slots: { [number]: string? } = {}
	local SlotCallbacks: { (SlotIndex: number, NewItemId: string?, OldItemId: string?) -> () } = {}
	local ComponentTrove = Trove.new()

	local function NotifySlotChanged(SlotIndex: number, NewItemId: string?, OldItemId: string?)
		for _, Callback in SlotCallbacks do
			task.spawn(Callback, SlotIndex, NewItemId, OldItemId)
		end
	end

	local function GetSlot(SlotIndex: number): string?
		return Slots[SlotIndex]
	end

	local function SetSlot(SlotIndex: number, ItemId: string?)
		if SlotIndex < 1 or SlotIndex > SlotCount then
			warn(string.format("[HotbarComponent] Slot index %d out of range (1-%d)", SlotIndex, SlotCount))
			return
		end

		local OldItemId = Slots[SlotIndex]
		if OldItemId == ItemId then
			return
		end

		Slots[SlotIndex] = ItemId

		NotifySlotChanged(SlotIndex, ItemId, OldItemId)
	end

	local function GetAllSlots(): { [number]: string? }
		local Result: { [number]: string? } = {}
		for Index = 1, SlotCount do
			Result[Index] = Slots[Index]
		end
		return Result
	end

	local function GetSlotCount(): number
		return SlotCount
	end

	local function FindSlot(ItemId: string): number?
		for Index = 1, SlotCount do
			if Slots[Index] == ItemId then
				return Index
			end
		end
		return nil
	end

	local function ClearSlot(SlotIndex: number)
		SetSlot(SlotIndex, nil)
	end

	local function ClearAll()
		for Index = 1, SlotCount do
			ClearSlot(Index)
		end
	end

	local function OnSlotChanged(Callback: (SlotIndex: number, NewItemId: string?, OldItemId: string?) -> ()): () -> ()
		table.insert(SlotCallbacks, Callback)

		return function()
			local Index = table.find(SlotCallbacks, Callback)
			if Index then
				table.remove(SlotCallbacks, Index)
			end
		end
	end

	local function Destroy()
		ComponentTrove:Destroy()
		table.clear(Slots)
		table.clear(SlotCallbacks)
	end

	local Loadout = if HotbarConfig then HotbarConfig.Loadout else nil
	if Loadout then
		for SlotIndex, ItemId in Loadout do
			if SlotIndex >= 1 and SlotIndex <= SlotCount then
				Slots[SlotIndex] = ItemId
			end
		end
	end

	return {
		GetSlot = GetSlot,
		SetSlot = SetSlot,
		GetAllSlots = GetAllSlots,
		GetSlotCount = GetSlotCount,
		FindSlot = FindSlot,
		ClearSlot = ClearSlot,
		ClearAll = ClearAll,
		OnSlotChanged = OnSlotChanged,
		Destroy = Destroy,
	}
end

export type Type = typeof(HotbarComponent.Create(nil :: any, nil :: any))

return HotbarComponent