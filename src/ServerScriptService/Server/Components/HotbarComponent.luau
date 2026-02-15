--!strict

--[=[
	@class HotbarComponent

	Manages a fixed-size hotbar of item slots for an entity.

	Slots are indexed from 1 to SlotCount. Each slot holds an optional ItemId string.
	Supports an initial loadout from the entity context and fires callbacks on
	slot changes.

	```lua
	local Hotbar = HotbarComponent.From(Entity)
	if Hotbar then
		Hotbar:SetSlot(1, "Sword")
		local ItemId = Hotbar:GetSlot(1)
	end
	```
]=]

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

local HotbarInstance = {}
HotbarInstance.__index = HotbarInstance

type SlotChangedCallback = (SlotIndex: number, NewItemId: string?, OldItemId: string?) -> ()

type HotbarStorage = {
	_SlotCount: number,
	_Slots: { [number]: string? },
	_SlotCallbacks: { SlotChangedCallback },
	_Trove: typeof(Trove.new()),
}

type HotbarInstanceInternal = typeof(setmetatable({} :: HotbarStorage, {} :: typeof(HotbarInstance)))

--[=[
	Returns the HotbarComponent attached to the given entity, or nil.

	@param EntityInstance Entity -- The entity to look up
	@return HotbarInstance? -- The hotbar instance, or nil
]=]
function HotbarComponent.From(EntityInstance: Entity): HotbarInstanceInternal?
	return EntityInstance:GetComponent("Hotbar")
end

--[=[
	Creates a new HotbarComponent for the given entity.

	Reads `HotbarConfig` from the context for slot count and initial loadout.
	Defaults to 6 slots if no config is provided.

	@param _EntityInstance Entity -- The owning entity (unused)
	@param Context EntityContext -- Context containing HotbarConfig
	@return HotbarInstance -- The new hotbar instance
]=]
function HotbarComponent.Create(_EntityInstance: Entity, Context: EntityContext): HotbarInstanceInternal
	local HotbarConfig = Context.HotbarConfig
	local SlotCount = if HotbarConfig and HotbarConfig.SlotCount then HotbarConfig.SlotCount else DEFAULT_SLOT_COUNT

	local Storage: HotbarStorage = {
		_SlotCount = SlotCount,
		_Slots = {},
		_SlotCallbacks = {},
		_Trove = Trove.new(),
	}

	local Instance = setmetatable(Storage, HotbarInstance)

	local Loadout = if HotbarConfig then HotbarConfig.Loadout else nil
	if Loadout then
		for SlotIndex, ItemId in Loadout do
			if SlotIndex >= 1 and SlotIndex <= SlotCount then
				Storage._Slots[SlotIndex] = ItemId
			end
		end
	end

	return Instance
end

local function NotifySlotChanged(Self: HotbarInstanceInternal, SlotIndex: number, NewItemId: string?, OldItemId: string?)
	for _, Callback in Self._SlotCallbacks do
		task.spawn(Callback, SlotIndex, NewItemId, OldItemId)
	end
end

--[=[
	Returns the item in a slot, or nil if the slot is empty.

	@param self HotbarInstance
	@param SlotIndex number -- The slot to query (1-based)
	@return string? -- The ItemId, or nil
]=]
function HotbarInstance:GetSlot(SlotIndex: number): string?
	return self._Slots[SlotIndex]
end

--[=[
	Sets the item in a slot. Pass nil to clear the slot.
	Warns and returns early if the index is out of range.

	@param self HotbarInstance
	@param SlotIndex number -- The slot to set (1-based)
	@param ItemId string? -- The item to place, or nil to clear
]=]
function HotbarInstance:SetSlot(SlotIndex: number, ItemId: string?)
	if SlotIndex < 1 or SlotIndex > self._SlotCount then
		warn(string.format("[HotbarComponent] Slot index %d out of range (1-%d)", SlotIndex, self._SlotCount))
		return
	end

	local OldItemId = self._Slots[SlotIndex]
	if OldItemId == ItemId then
		return
	end

	self._Slots[SlotIndex] = ItemId
	NotifySlotChanged(self, SlotIndex, ItemId, OldItemId)
end

--[=[
	Returns a table of all slots from 1 to SlotCount.

	@param self HotbarInstance
	@return { [number]: string? } -- Map of slot index to ItemId
]=]
function HotbarInstance:GetAllSlots(): { [number]: string? }
	local Result: { [number]: string? } = {}
	for Index = 1, self._SlotCount do
		Result[Index] = self._Slots[Index]
	end
	return Result
end

--[=[
	Returns the number of slots in this hotbar.

	@param self HotbarInstance
	@return number -- The slot count
]=]
function HotbarInstance:GetSlotCount(): number
	return self._SlotCount
end

--[=[
	Finds the first slot containing a given ItemId, or nil if not found.

	@param self HotbarInstance
	@param ItemId string -- The item to search for
	@return number? -- The slot index, or nil
]=]
function HotbarInstance:FindSlot(ItemId: string): number?
	for Index = 1, self._SlotCount do
		if self._Slots[Index] == ItemId then
			return Index
		end
	end
	return nil
end

--[=[
	Clears a single slot.

	@param self HotbarInstance
	@param SlotIndex number -- The slot to clear (1-based)
]=]
function HotbarInstance:ClearSlot(SlotIndex: number)
	self:SetSlot(SlotIndex, nil)
end

--[=[
	Clears all slots.

	@param self HotbarInstance
]=]
function HotbarInstance:ClearAll()
	for Index = 1, self._SlotCount do
		self:ClearSlot(Index)
	end
end

--[=[
	Registers a callback that fires when any slot changes.
	Returns an unsubscribe function.

	@param self HotbarInstance
	@param Callback (SlotIndex: number, NewItemId: string?, OldItemId: string?) -> () -- Called on change
	@return () -> () -- Call to unsubscribe
]=]
function HotbarInstance:OnSlotChanged(Callback: SlotChangedCallback): () -> ()
	table.insert(self._SlotCallbacks, Callback)

	return function()
		local Index = table.find(self._SlotCallbacks, Callback)
		if Index then
			table.remove(self._SlotCallbacks, Index)
		end
	end
end

--[=[
	Destroys the component and cleans up all internal state.

	@param self HotbarInstance
]=]
function HotbarInstance:Destroy()
	self._Trove:Destroy()
	table.clear(self._Slots)
	table.clear(self._SlotCallbacks)
end

export type Type = typeof(setmetatable({} :: HotbarStorage, HotbarInstance))

return HotbarComponent