--!strict

--[=[
	@class InventoryService

	Server-side inventory management with slot-based CRUD, rate limiting,
	cross-inventory transfers, and runtime (session-scoped) inventories.

	Validates all client requests against type checks, inventory rules, and
	rate limits before performing mutations. Fires signals and syncs slot
	changes back to the client.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local InventoryTypes = require(Shared.Types.InventoryTypes)
local InventoryConfig = require(Shared.Config.InventoryConfig)
local InventoryUtil = require(Shared.Utils.InventoryUtil)
local ItemDatabase = require(Shared.Data.ItemDatabase)
local RateLimiter = require(Shared.Utils.RateLimiter)

local Signal = Packages.Signal
local Trove = Packages.Trove

local PlayerDataService = require(Server.Services.PlayerDataService)

type ItemStack = InventoryTypes.ItemStack
type Inventory = InventoryTypes.Inventory
type InventoryRule = InventoryTypes.InventoryRule
type Metadata = InventoryTypes.Metadata

local InventoryService = {}

InventoryService.Dependencies = { "PlayerDataService" }

local ServiceTrove: typeof(Trove.new()) = nil :: any

InventoryService.SlotChanged = Signal.new()
InventoryService.InventoryChanged = Signal.new()
InventoryService.ItemAdded = Signal.new()
InventoryService.ItemRemoved = Signal.new()

local RuntimeInventories: {
	[string]: {
		Inventory: Inventory,
		MaxSlots: number,
		AllowedTypes: { string }?,
	},
} = {}

local InventoryActionLimiter: typeof(RateLimiter.Create({} :: any)) = nil :: any

-- Internal helpers

local function IsValidInventoryName(InventoryName: string): boolean
	return InventoryConfig[InventoryName] ~= nil
end

local function GetPlayerRateKey(Player: Player): string
	return tostring(Player.UserId)
end

local function GetInventoryRule(InventoryName: string): InventoryRule?
	return InventoryConfig[InventoryName]
end

local function IsItemTypeAllowed(InventoryName: string, ItemId: string): boolean
	local Rule = GetInventoryRule(InventoryName)
	if not Rule then
		return true
	end

	if not Rule.AllowedTypes then
		return true
	end

	local ItemType = ItemDatabase.GetItemType(ItemId)
	if not ItemType then
		return false
	end

	return table.find(Rule.AllowedTypes, ItemType) ~= nil
end

local function GetPlayerInventory(Player: Player, InventoryName: string): Inventory?
	if not Player then
		warn(string.format("[InventoryService] Could not fetch inventory for Player %s", InventoryName))
		return nil
	end

	local Data = PlayerDataService.GetData(Player)
	if not Data then
		return nil
	end

	local InventoryData = Data.Inventory :: { [string]: Inventory }
	return InventoryData[InventoryName]
end

local function GetMaxSlots(InventoryName: string): number
	local Rule = GetInventoryRule(InventoryName)
	return if Rule then Rule.MaxSlots else 20
end

local function SyncInventory(Player: Player, InventoryName: string)
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if TargetInventory then
		Packets.InventorySync:FireClient(Player, InventoryName, TargetInventory)
	end
end

local function SyncSlot(Player: Player, InventoryName: string, SlotIndex: number)
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if TargetInventory then
		Packets.InventorySlotUpdate:FireClient(Player, InventoryName, SlotIndex, TargetInventory[SlotIndex])
	end
end

local function SyncAllInventories(Player: Player)
	for InventoryName in InventoryConfig do
		SyncInventory(Player, InventoryName)
	end
end

--[=[
	Validates that each value matches the expected Luau type name at the same index.
	Returns false on the first mismatch.

	@param Values { any } -- The values to check
	@param ExpectedTypes { string } -- Parallel array of typeof() strings
	@return boolean -- True if all values match their expected type
]=]
local function ValidateTypes(Values: { any }, ExpectedTypes: { string }): boolean
	for Index, Expected in ExpectedTypes do
		if typeof(Values[Index]) ~= Expected then
			return false
		end
	end
	return true
end

--[=[
	Checks that every inventory name in the list is recognized in InventoryConfig.

	@param ... string -- One or more inventory names
	@return boolean -- True if all names are valid
]=]
local function ValidateInventoryNames(...: string): boolean
	for Index = 1, select("#", ...) do
		if not IsValidInventoryName(select(Index, ...)) then
			return false
		end
	end
	return true
end

--[=[
	Consumes a rate limit token for the player. Returns true if allowed.

	@param Player Player -- The player to rate-check
	@return boolean -- True if the action is permitted
]=]
local function ConsumeRateLimit(Player: Player): boolean
	return InventoryActionLimiter.Consume(GetPlayerRateKey(Player))
end

-- Packet handlers

local function OnPlayerRemoving(Player: Player)
	local Data = PlayerDataService.GetData(Player)
    if Data then
        local InventoryData = Data.Inventory
        print(Player.Name, "leaving with inventory:", InventoryData)
    end

	InventoryService.CleanupPlayerRuntimeInventories(Player)
	InventoryActionLimiter.Reset(GetPlayerRateKey(Player))
end

local function OnProfileLoaded(Player: Player, _Data: any)
	SyncAllInventories(Player)
end

local function OnInventoryRequest(Player: Player)
	if PlayerDataService.IsLoaded(Player) then
		SyncAllInventories(Player)
	end
end

local function OnInventoryTransfer(
	Player: Player,
	SourceInventory: any,
	SourceIndex: any,
	TargetInventory: any,
	TargetIndex: any
)
	if not ValidateTypes({ SourceInventory, SourceIndex, TargetInventory, TargetIndex }, { "string", "number", "string", "number" }) then
		return
	end

	if not ValidateInventoryNames(SourceInventory, TargetInventory) then
		return
	end

	if not ConsumeRateLimit(Player) then
		SyncSlot(Player, SourceInventory, SourceIndex)
		SyncSlot(Player, TargetInventory, TargetIndex)
		return
	end

	local Success = InventoryService.TransferSlot(Player, SourceInventory, SourceIndex, TargetInventory, TargetIndex)
	if not Success then
		SyncSlot(Player, SourceInventory, SourceIndex)
		SyncSlot(Player, TargetInventory, TargetIndex)
	end
end

local function OnInventorySwap(
	Player: Player,
	SourceInventory: any,
	SourceIndex: any,
	TargetInventory: any,
	TargetIndex: any
)
	if not ValidateTypes({ SourceInventory, SourceIndex, TargetInventory, TargetIndex }, { "string", "number", "string", "number" }) then
		return
	end

	if not ValidateInventoryNames(SourceInventory, TargetInventory) then
		return
	end

	if not ConsumeRateLimit(Player) then
		SyncSlot(Player, SourceInventory, SourceIndex)
		SyncSlot(Player, TargetInventory, TargetIndex)
		return
	end

	local Success = InventoryService.SwapSlots(Player, SourceInventory, SourceIndex, TargetInventory, TargetIndex)
	if not Success then
		SyncSlot(Player, SourceInventory, SourceIndex)
		SyncSlot(Player, TargetInventory, TargetIndex)
	end
end

local function OnInventoryDrop(
	Player: Player,
	InventoryName: any,
	SlotIndex: any,
	Quantity: any
)
	if not ValidateTypes({ InventoryName, SlotIndex, Quantity }, { "string", "number", "number" }) then
		return
	end

	if not ValidateInventoryNames(InventoryName) then
		return
	end

	if not ConsumeRateLimit(Player) then
		SyncSlot(Player, InventoryName, SlotIndex)
		return
	end

	local Success = InventoryService.DropItem(Player, InventoryName, SlotIndex, Quantity)
	if not Success then
		SyncSlot(Player, InventoryName, SlotIndex)
	end
end

local function OnInventoryDeposit(
	Player: Player,
	SourceInventory: any,
	SourceIndex: any,
	TargetInventory: any
)
	if not ValidateTypes({ SourceInventory, SourceIndex, TargetInventory }, { "string", "number", "string" }) then
		return
	end

	if not ValidateInventoryNames(SourceInventory, TargetInventory) then
		return
	end

	if not ConsumeRateLimit(Player) then
		SyncSlot(Player, SourceInventory, SourceIndex)
		SyncInventory(Player, TargetInventory)
		return
	end

	local Success = InventoryService.DepositSlot(Player, SourceInventory, SourceIndex, TargetInventory)
	if not Success then
		SyncSlot(Player, SourceInventory, SourceIndex)
		SyncInventory(Player, TargetInventory)
	end
end

local function OnInventoryTransferDeposit(
	Player: Player,
	SourceInventory: any,
	SourceIndex: any,
	TargetInventory: any,
	TargetIndex: any
)
	if not ValidateTypes({ SourceInventory, SourceIndex, TargetInventory, TargetIndex }, { "string", "number", "string", "number" }) then
		return
	end

	if not ValidateInventoryNames(SourceInventory, TargetInventory) then
		return
	end

	if not ConsumeRateLimit(Player) then
		SyncInventory(Player, SourceInventory)
		SyncSlot(Player, TargetInventory, TargetIndex)
		return
	end

	local Success = InventoryService.TransferAndDeposit(Player, SourceInventory, SourceIndex, TargetInventory, TargetIndex)
	if not Success then
		SyncInventory(Player, SourceInventory)
		SyncSlot(Player, TargetInventory, TargetIndex)
	end
end

-- Lifecycle

--[=[
	Creates the service Trove and rate limiter.
]=]
function InventoryService.Init()
	ServiceTrove = Trove.new()

	InventoryActionLimiter = RateLimiter.Create({
		MaxTokens = 10,
		RefillRate = 5,
		RefillInterval = 1,
	})
end

--[=[
	Subscribes to player lifecycle events and client inventory action packets.
]=]
function InventoryService.Start()
	ServiceTrove:Connect(Players.PlayerRemoving, OnPlayerRemoving)
	ServiceTrove:Connect(PlayerDataService.ProfileLoaded :: any, OnProfileLoaded)
	ServiceTrove:Connect(Packets.InventoryRequest.OnServerEvent :: any, OnInventoryRequest)
	ServiceTrove:Connect(Packets.InventoryTransfer.OnServerEvent :: any, OnInventoryTransfer)
	ServiceTrove:Connect(Packets.InventorySwap.OnServerEvent :: any, OnInventorySwap)
	ServiceTrove:Connect(Packets.InventoryDrop.OnServerEvent :: any, OnInventoryDrop)
	ServiceTrove:Connect(Packets.InventoryDeposit.OnServerEvent :: any, OnInventoryDeposit)
	ServiceTrove:Connect(Packets.InventoryTransferDeposit.OnServerEvent :: any, OnInventoryTransferDeposit)

	for _, Player in Players:GetPlayers() do
		if PlayerDataService.IsLoaded(Player) then
			task.spawn(SyncAllInventories, Player)
		end
	end
end

--[=[
	Destroys the service Trove, rate limiter, and clears runtime inventories.
]=]
function InventoryService.Stop()
	ServiceTrove:Destroy()
	InventoryActionLimiter.Destroy()
	table.clear(RuntimeInventories)
end

-- ────────────────────────────────────────────────────────────
-- Public API
-- ────────────────────────────────────────────────────────────

--[=[
	Returns the full inventory table for the given player and inventory name.

	@param Player Player -- The owning player
	@param InventoryName string -- The inventory to fetch
	@return Inventory? -- The inventory table, or nil
]=]
function InventoryService.GetInventory(Player: Player, InventoryName: string): Inventory?
	return GetPlayerInventory(Player, InventoryName)
end

--[=[
	Returns the ItemStack at a specific slot.

	@param Player Player -- The owning player
	@param InventoryName string -- The inventory to look in
	@param SlotIndex number -- The slot to check
	@return ItemStack? -- The stack at that slot, or nil
]=]
function InventoryService.GetSlot(Player: Player, InventoryName: string, SlotIndex: number): ItemStack?
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if not TargetInventory then
		return nil
	end

	return InventoryUtil.GetSlot(TargetInventory, SlotIndex)
end

--[=[
	Adds items to a player's inventory, distributing across existing stacks and empty slots.
	Returns the number of items that could not fit (overflow).

	@param Player Player -- The owning player
	@param InventoryName string -- The target inventory
	@param ItemId string -- The item type to add
	@param Quantity number -- How many to add
	@param TargetMetadata Metadata? -- Optional metadata for the items
	@return number -- The overflow quantity that did not fit
]=]
function InventoryService.AddItem(
	Player: Player,
	InventoryName: string,
	ItemId: string,
	Quantity: number,
	TargetMetadata: Metadata?
): number
	if not ItemDatabase.Exists(ItemId) then
		warn(string.format("[InventoryService] Unknown item: %s", ItemId))
		return Quantity
	end

	if not IsItemTypeAllowed(InventoryName, ItemId) then
		warn(string.format("[InventoryService] Item type not allowed in %s: %s", InventoryName, ItemId))
		return Quantity
	end

	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if not TargetInventory then
		return Quantity
	end

	local MaxSlots = GetMaxSlots(InventoryName)

	local SlotsBefore: { [number]: ItemStack? } = {}
	for Index = 1, MaxSlots do
		local Stack = TargetInventory[Index]
		if Stack then
			SlotsBefore[Index] = { ItemId = Stack.ItemId, Quantity = Stack.Quantity, Metadata = Stack.Metadata }
		end
	end

	local Overflow = InventoryUtil.AddItem(TargetInventory, ItemId, Quantity, MaxSlots, TargetMetadata)
	local Added = Quantity - Overflow

	if Added > 0 then
		for Index = 1, MaxSlots do
			local Before = SlotsBefore[Index]
			local After = TargetInventory[Index]

			local Changed = false
			if (Before == nil and After ~= nil) or (Before ~= nil and After ~= nil and Before.Quantity ~= After.Quantity) then
				Changed = true
			end

			if Changed then
				SyncSlot(Player, InventoryName, Index)
			end
		end

		InventoryService.ItemAdded:Fire(Player, InventoryName, ItemId, Added, TargetMetadata)
		InventoryService.InventoryChanged:Fire(Player, InventoryName)

		Packets.InventoryItemAdded:FireClient(Player, InventoryName, ItemId, Added)
	end

	return Overflow
end

--[=[
	Removes items from a player's inventory. Returns the number actually removed.

	@param Player Player -- The owning player
	@param InventoryName string -- The target inventory
	@param ItemId string -- The item type to remove
	@param Quantity number -- How many to remove
	@param TargetMetadata Metadata? -- Optional metadata filter
	@return number -- The number of items actually removed
]=]
function InventoryService.RemoveItem(
	Player: Player,
	InventoryName: string,
	ItemId: string,
	Quantity: number,
	TargetMetadata: Metadata?
): number
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if not TargetInventory then
		return 0
	end

	local MaxSlots = GetMaxSlots(InventoryName)

	local SlotsBefore: { [number]: ItemStack? } = {}
	for Index = 1, MaxSlots do
		local Stack = TargetInventory[Index]
		if Stack then
			SlotsBefore[Index] = { ItemId = Stack.ItemId, Quantity = Stack.Quantity, Metadata = Stack.Metadata }
		end
	end

	local Removed = InventoryUtil.RemoveItem(TargetInventory, ItemId, Quantity, MaxSlots, TargetMetadata)

	if Removed > 0 then
		for Index = 1, MaxSlots do
			local Before = SlotsBefore[Index]
			local After = TargetInventory[Index]

			local Changed = false
			if (Before ~= nil and After == nil) or (Before ~= nil and After ~= nil and Before.Quantity ~= After.Quantity) then
				Changed = true
			end

			if Changed then
				SyncSlot(Player, InventoryName, Index)
			end
		end

		InventoryService.ItemRemoved:Fire(Player, InventoryName, ItemId, Removed, TargetMetadata)
		InventoryService.InventoryChanged:Fire(Player, InventoryName)

		Packets.InventoryItemRemoved:FireClient(Player, InventoryName, ItemId, Removed)
	end

	return Removed
end

--[=[
	Checks whether a player has at least the specified quantity of an item.

	@param Player Player -- The owning player
	@param InventoryName string -- The inventory to check
	@param ItemId string -- The item type
	@param Quantity number -- Required quantity
	@param TargetMetadata Metadata? -- Optional metadata filter
	@return boolean -- True if the player has enough
]=]
function InventoryService.HasItem(
	Player: Player,
	InventoryName: string,
	ItemId: string,
	Quantity: number,
	TargetMetadata: Metadata?
): boolean
	return InventoryService.GetItemCount(Player, InventoryName, ItemId, TargetMetadata) >= Quantity
end

--[=[
	Returns the total quantity of an item across all slots in an inventory.

	@param Player Player -- The owning player
	@param InventoryName string -- The inventory to count in
	@param ItemId string -- The item type
	@param TargetMetadata Metadata? -- Optional metadata filter
	@return number -- The total quantity
]=]
function InventoryService.GetItemCount(
	Player: Player,
	InventoryName: string,
	ItemId: string,
	TargetMetadata: Metadata?
): number
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if not TargetInventory then
		return 0
	end

	local MaxSlots = GetMaxSlots(InventoryName)
	return InventoryUtil.GetItemCount(TargetInventory, ItemId, MaxSlots, TargetMetadata)
end

--[=[
	Directly sets a slot to a given ItemStack (or nil to clear it).

	@param Player Player -- The owning player
	@param InventoryName string -- The target inventory
	@param SlotIndex number -- The slot to set
	@param Stack ItemStack? -- The stack to place, or nil to clear
	@return boolean -- True if the operation succeeded
]=]
function InventoryService.SetSlot(
	Player: Player,
	InventoryName: string,
	SlotIndex: number,
	Stack: ItemStack?
): boolean
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if not TargetInventory then
		return false
	end

	local MaxSlots = GetMaxSlots(InventoryName)
	if SlotIndex < 1 or SlotIndex > MaxSlots then
		return false
	end

	if Stack and not IsItemTypeAllowed(InventoryName, Stack.ItemId) then
		return false
	end

	local OldStack = TargetInventory[SlotIndex]
	InventoryUtil.SetSlot(TargetInventory, SlotIndex, Stack)

	InventoryService.SlotChanged:Fire(Player, InventoryName, SlotIndex, Stack, OldStack)
	InventoryService.InventoryChanged:Fire(Player, InventoryName)

	SyncSlot(Player, InventoryName, SlotIndex)

	return true
end

--[=[
	Transfers (or merges) a slot from one inventory to another.

	@param Player Player -- The owning player
	@param SourceInventoryName string -- Source inventory name
	@param SourceIndex number -- Source slot index
	@param TargetInventoryName string -- Target inventory name
	@param TargetIndex number -- Target slot index
	@return boolean -- True if the transfer succeeded
]=]
function InventoryService.TransferSlot(
	Player: Player,
	SourceInventoryName: string,
	SourceIndex: number,
	TargetInventoryName: string,
	TargetIndex: number
): boolean
	local SourceInventory = GetPlayerInventory(Player, SourceInventoryName)
	local TargetInventory = GetPlayerInventory(Player, TargetInventoryName)

	if not SourceInventory or not TargetInventory then
		return false
	end

	local SourceMaxSlots = GetMaxSlots(SourceInventoryName)
	local TargetMaxSlots = GetMaxSlots(TargetInventoryName)

	if SourceIndex < 1 or SourceIndex > SourceMaxSlots then
		return false
	end

	if TargetIndex < 1 or TargetIndex > TargetMaxSlots then
		return false
	end

	local SourceStack = SourceInventory[SourceIndex]
	local TargetStack = TargetInventory[TargetIndex]

	if SourceStack and not IsItemTypeAllowed(TargetInventoryName, SourceStack.ItemId) then
		return false
	end

	if TargetStack and not IsItemTypeAllowed(SourceInventoryName, TargetStack.ItemId) then
		return false
	end

	local OldSource = SourceInventory[SourceIndex]
	local OldTarget = TargetInventory[TargetIndex]

	local Success = InventoryUtil.TransferSlot(SourceInventory, SourceIndex, TargetInventory, TargetIndex)

	if Success then
		InventoryService.SlotChanged:Fire(Player, SourceInventoryName, SourceIndex, SourceInventory[SourceIndex], OldSource)
		InventoryService.SlotChanged:Fire(Player, TargetInventoryName, TargetIndex, TargetInventory[TargetIndex], OldTarget)
		InventoryService.InventoryChanged:Fire(Player, SourceInventoryName)

		SyncSlot(Player, SourceInventoryName, SourceIndex)
		SyncSlot(Player, TargetInventoryName, TargetIndex)

		if SourceInventoryName ~= TargetInventoryName then
			InventoryService.InventoryChanged:Fire(Player, TargetInventoryName)
		end
	end

	return Success
end

--[=[
	Swaps two slots between inventories without merging.

	@param Player Player -- The owning player
	@param SourceInventoryName string -- Source inventory name
	@param SourceIndex number -- Source slot index
	@param TargetInventoryName string -- Target inventory name
	@param TargetIndex number -- Target slot index
	@return boolean -- True if the swap succeeded
]=]
function InventoryService.SwapSlots(
	Player: Player,
	SourceInventoryName: string,
	SourceIndex: number,
	TargetInventoryName: string,
	TargetIndex: number
): boolean
	local SourceInventory = GetPlayerInventory(Player, SourceInventoryName)
	local TargetInventory = GetPlayerInventory(Player, TargetInventoryName)

	if not SourceInventory or not TargetInventory then
		return false
	end

	local SourceMaxSlots = GetMaxSlots(SourceInventoryName)
	local TargetMaxSlots = GetMaxSlots(TargetInventoryName)

	if SourceIndex < 1 or SourceIndex > SourceMaxSlots then
		return false
	end

	if TargetIndex < 1 or TargetIndex > TargetMaxSlots then
		return false
	end

	local SourceStack = SourceInventory[SourceIndex]
	local TargetStack = TargetInventory[TargetIndex]

	if SourceStack and not IsItemTypeAllowed(TargetInventoryName, SourceStack.ItemId) then
		return false
	end

	if TargetStack and not IsItemTypeAllowed(SourceInventoryName, TargetStack.ItemId) then
		return false
	end

	InventoryUtil.SwapSlots(SourceInventory, SourceIndex, TargetInventory, TargetIndex)

	InventoryService.SlotChanged:Fire(Player, SourceInventoryName, SourceIndex, SourceInventory[SourceIndex], SourceStack)
	InventoryService.SlotChanged:Fire(Player, TargetInventoryName, TargetIndex, TargetInventory[TargetIndex], TargetStack)
	InventoryService.InventoryChanged:Fire(Player, SourceInventoryName)

	SyncSlot(Player, SourceInventoryName, SourceIndex)
	SyncSlot(Player, TargetInventoryName, TargetIndex)

	if SourceInventoryName ~= TargetInventoryName then
		InventoryService.InventoryChanged:Fire(Player, TargetInventoryName)
	end

	return true
end

--[=[
	Deposits a slot's contents into another inventory, distributing across
	existing stacks and empty slots. Partial deposits leave overflow in the source.

	@param Player Player -- The owning player
	@param SourceInventoryName string -- Source inventory name
	@param SourceIndex number -- Source slot index
	@param TargetInventoryName string -- Target inventory name
	@return boolean -- True if at least one item was deposited
]=]
function InventoryService.DepositSlot(
	Player: Player,
	SourceInventoryName: string,
	SourceIndex: number,
	TargetInventoryName: string
): boolean
	if SourceInventoryName == TargetInventoryName then
		return false
	end

	local SourceInventory = GetPlayerInventory(Player, SourceInventoryName)
	if not SourceInventory then
		return false
	end

	local SourceMaxSlots = GetMaxSlots(SourceInventoryName)
	if SourceIndex < 1 or SourceIndex > SourceMaxSlots then
		return false
	end

	local SourceStack = SourceInventory[SourceIndex]
	if not SourceStack then
		return false
	end

	if not IsItemTypeAllowed(TargetInventoryName, SourceStack.ItemId) then
		return false
	end

	local TargetInventory = GetPlayerInventory(Player, TargetInventoryName)
	if not TargetInventory then
		return false
	end

	local TargetMaxSlots = GetMaxSlots(TargetInventoryName)

	SourceInventory[SourceIndex] = nil

	local Overflow = InventoryUtil.AddItem(
		TargetInventory,
		SourceStack.ItemId,
		SourceStack.Quantity,
		TargetMaxSlots,
		SourceStack.Metadata
	)

	if Overflow > 0 then
		SourceInventory[SourceIndex] = {
			ItemId = SourceStack.ItemId,
			Quantity = Overflow,
			Metadata = SourceStack.Metadata,
		}
	end

	local Deposited = SourceStack.Quantity - Overflow

	if Deposited > 0 then
		InventoryService.SlotChanged:Fire(Player, SourceInventoryName, SourceIndex, SourceInventory[SourceIndex], SourceStack)
		InventoryService.InventoryChanged:Fire(Player, SourceInventoryName)
		InventoryService.InventoryChanged:Fire(Player, TargetInventoryName)

		SyncSlot(Player, SourceInventoryName, SourceIndex)
		SyncInventory(Player, TargetInventoryName)
	end

	return Deposited > 0
end

--[=[
	Transfers a slot to a target slot, depositing overflow back into the source inventory.

	@param Player Player -- The owning player
	@param SourceInventoryName string -- Source inventory name
	@param SourceIndex number -- Source slot index
	@param TargetInventoryName string -- Target inventory name
	@param TargetIndex number -- Target slot index
	@return boolean -- True if the operation succeeded
]=]
function InventoryService.TransferAndDeposit(
	Player: Player,
	SourceInventoryName: string,
	SourceIndex: number,
	TargetInventoryName: string,
	TargetIndex: number
): boolean
	local SourceInventory = GetPlayerInventory(Player, SourceInventoryName)
	local TargetInventory = GetPlayerInventory(Player, TargetInventoryName)

	if not SourceInventory or not TargetInventory then
		return false
	end

	local SourceMaxSlots = GetMaxSlots(SourceInventoryName)
	local TargetMaxSlots = GetMaxSlots(TargetInventoryName)

	if SourceIndex < 1 or SourceIndex > SourceMaxSlots then
		return false
	end

	if TargetIndex < 1 or TargetIndex > TargetMaxSlots then
		return false
	end

	local SourceStack = SourceInventory[SourceIndex]
	if not SourceStack then
		return false
	end

	if not IsItemTypeAllowed(TargetInventoryName, SourceStack.ItemId) then
		return false
	end

	local DisplacedStack = TargetInventory[TargetIndex]

	if not DisplacedStack or DisplacedStack.ItemId == SourceStack.ItemId then
		return InventoryService.TransferSlot(Player, SourceInventoryName, SourceIndex, TargetInventoryName, TargetIndex)
	end

	if not IsItemTypeAllowed(SourceInventoryName, DisplacedStack.ItemId) then
		return false
	end

	SourceInventory[SourceIndex] = nil
	TargetInventory[TargetIndex] = SourceStack

	local Overflow = InventoryUtil.AddItem(
		SourceInventory,
		DisplacedStack.ItemId,
		DisplacedStack.Quantity,
		SourceMaxSlots,
		DisplacedStack.Metadata
	)

	if Overflow > 0 then
		SourceInventory[SourceIndex] = {
			ItemId = DisplacedStack.ItemId,
			Quantity = Overflow,
			Metadata = DisplacedStack.Metadata,
		}
	else
		SourceInventory[SourceIndex] = nil
	end

	InventoryService.SlotChanged:Fire(Player, SourceInventoryName, SourceIndex, SourceInventory[SourceIndex], SourceStack)
	InventoryService.SlotChanged:Fire(Player, TargetInventoryName, TargetIndex, TargetInventory[TargetIndex], DisplacedStack)
	InventoryService.InventoryChanged:Fire(Player, SourceInventoryName)

	SyncInventory(Player, SourceInventoryName)
	SyncSlot(Player, TargetInventoryName, TargetIndex)

	if SourceInventoryName ~= TargetInventoryName then
		InventoryService.InventoryChanged:Fire(Player, TargetInventoryName)
	end

	return true
end

--[=[
	Drops items from a slot, reducing quantity or clearing the slot entirely.

	@param Player Player -- The owning player
	@param InventoryName string -- The inventory to drop from
	@param SlotIndex number -- The slot index
	@param Quantity number -- How many to drop (0 = all)
	@return boolean -- True if items were dropped
]=]
function InventoryService.DropItem(
	Player: Player,
	InventoryName: string,
	SlotIndex: number,
	Quantity: number
): boolean
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if not TargetInventory then
		return false
	end

	local MaxSlots = GetMaxSlots(InventoryName)
	if SlotIndex < 1 or SlotIndex > MaxSlots then
		return false
	end

	local Stack = TargetInventory[SlotIndex]
	if not Stack then
		return false
	end

	local DropQuantity = if Quantity <= 0 then Stack.Quantity else math.min(Quantity, Stack.Quantity)

	Stack.Quantity = Stack.Quantity - DropQuantity
	if Stack.Quantity <= 0 then
		TargetInventory[SlotIndex] = nil
	end

	InventoryService.ItemRemoved:Fire(Player, InventoryName, Stack.ItemId, DropQuantity, Stack.Metadata)
	InventoryService.InventoryChanged:Fire(Player, InventoryName)

	SyncSlot(Player, InventoryName, SlotIndex)
	Packets.InventoryItemRemoved:FireClient(Player, InventoryName, Stack.ItemId, DropQuantity)

	return true
end

--[=[
	Clears all slots in a player's inventory.

	@param Player Player -- The owning player
	@param InventoryName string -- The inventory to clear
	@return boolean -- True if the inventory was cleared
]=]
function InventoryService.ClearInventory(Player: Player, InventoryName: string): boolean
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if not TargetInventory then
		return false
	end

	local MaxSlots = GetMaxSlots(InventoryName)
	InventoryUtil.ClearInventory(TargetInventory, MaxSlots)

	InventoryService.InventoryChanged:Fire(Player, InventoryName)
	SyncInventory(Player, InventoryName)

	return true
end

--[=[
	Creates a session-scoped runtime inventory (not persisted).

	@param InventoryId string -- Unique identifier for the runtime inventory
	@param MaxSlots number -- Maximum number of slots
	@param AllowedTypes { string }? -- Optional item type whitelist
	@return boolean -- True if created successfully
]=]
function InventoryService.CreateRuntimeInventory(
	InventoryId: string,
	MaxSlots: number,
	AllowedTypes: { string }?
): boolean
	if RuntimeInventories[InventoryId] then
		warn(string.format("[InventoryService] Runtime inventory already exists: %s", InventoryId))
		return false
	end

	RuntimeInventories[InventoryId] = {
		Inventory = {},
		MaxSlots = MaxSlots,
		AllowedTypes = AllowedTypes,
	}

	return true
end

--[=[
	Returns the inventory table for a runtime inventory.

	@param InventoryId string -- The runtime inventory identifier
	@return Inventory? -- The inventory table, or nil
]=]
function InventoryService.GetRuntimeInventory(InventoryId: string): Inventory?
	local RuntimeData = RuntimeInventories[InventoryId]
	return if RuntimeData then RuntimeData.Inventory else nil
end

--[=[
	Destroys a runtime inventory.

	@param InventoryId string -- The runtime inventory identifier
	@return boolean -- True if destroyed
]=]
function InventoryService.DestroyRuntimeInventory(InventoryId: string): boolean
	if not RuntimeInventories[InventoryId] then
		return false
	end

	RuntimeInventories[InventoryId] = nil
	return true
end

--[=[
	Adds items to a runtime inventory. Returns the overflow quantity.

	@param InventoryId string -- The runtime inventory identifier
	@param ItemId string -- The item type to add
	@param Quantity number -- How many to add
	@param TargetMetadata Metadata? -- Optional metadata
	@return number -- The overflow quantity
]=]
function InventoryService.AddItemToRuntime(
	InventoryId: string,
	ItemId: string,
	Quantity: number,
	TargetMetadata: Metadata?
): number
	local RuntimeData = RuntimeInventories[InventoryId]
	if not RuntimeData then
		return Quantity
	end

	if not ItemDatabase.Exists(ItemId) then
		return Quantity
	end

	if RuntimeData.AllowedTypes then
		local ItemType = ItemDatabase.GetItemType(ItemId)
		if not ItemType or not table.find(RuntimeData.AllowedTypes, ItemType) then
			return Quantity
		end
	end

	return InventoryUtil.AddItem(RuntimeData.Inventory, ItemId, Quantity, RuntimeData.MaxSlots, TargetMetadata)
end

--[=[
	Transfers a slot from a player inventory into a runtime inventory.

	@param Player Player -- The owning player
	@param SourceInventoryName string -- The player's source inventory
	@param SourceIndex number -- Source slot index
	@param RuntimeInventoryId string -- Target runtime inventory
	@param TargetIndex number -- Target slot index
	@return boolean -- True if the transfer succeeded
]=]
function InventoryService.TransferToRuntime(
	Player: Player,
	SourceInventoryName: string,
	SourceIndex: number,
	RuntimeInventoryId: string,
	TargetIndex: number
): boolean
	local RuntimeData = RuntimeInventories[RuntimeInventoryId]
	local SourceInventory = GetPlayerInventory(Player, SourceInventoryName)

	if not RuntimeData or not SourceInventory then
		return false
	end

	local SourceMaxSlots = GetMaxSlots(SourceInventoryName)

	if SourceIndex < 1 or SourceIndex > SourceMaxSlots then
		return false
	end

	if TargetIndex < 1 or TargetIndex > RuntimeData.MaxSlots then
		return false
	end

	local SourceStack = SourceInventory[SourceIndex]
	local TargetStack = RuntimeData.Inventory[TargetIndex]

	if SourceStack and RuntimeData.AllowedTypes then
		local ItemType = ItemDatabase.GetItemType(SourceStack.ItemId)
		if not ItemType or not table.find(RuntimeData.AllowedTypes, ItemType) then
			return false
		end
	end

	if TargetStack and not IsItemTypeAllowed(SourceInventoryName, TargetStack.ItemId) then
		return false
	end

	local Success = InventoryUtil.TransferSlot(SourceInventory, SourceIndex, RuntimeData.Inventory, TargetIndex)

	if Success then
		InventoryService.SlotChanged:Fire(Player, SourceInventoryName, SourceIndex, SourceInventory[SourceIndex], SourceStack)
		InventoryService.InventoryChanged:Fire(Player, SourceInventoryName)

		SyncSlot(Player, SourceInventoryName, SourceIndex)
	end

	return Success
end

--[=[
	Transfers a slot from a runtime inventory back into a player inventory.

	@param Player Player -- The owning player
	@param RuntimeInventoryId string -- Source runtime inventory
	@param SourceIndex number -- Source slot index
	@param TargetInventoryName string -- The player's target inventory
	@param TargetIndex number -- Target slot index
	@return boolean -- True if the transfer succeeded
]=]
function InventoryService.TransferFromRuntime(
	Player: Player,
	RuntimeInventoryId: string,
	SourceIndex: number,
	TargetInventoryName: string,
	TargetIndex: number
): boolean
	local RuntimeData = RuntimeInventories[RuntimeInventoryId]
	local TargetInventory = GetPlayerInventory(Player, TargetInventoryName)

	if not RuntimeData or not TargetInventory then
		return false
	end

	local TargetMaxSlots = GetMaxSlots(TargetInventoryName)

	if SourceIndex < 1 or SourceIndex > RuntimeData.MaxSlots then
		return false
	end

	if TargetIndex < 1 or TargetIndex > TargetMaxSlots then
		return false
	end

	local SourceStack = RuntimeData.Inventory[SourceIndex]
	local TargetStack = TargetInventory[TargetIndex]

	if SourceStack and not IsItemTypeAllowed(TargetInventoryName, SourceStack.ItemId) then
		return false
	end

	if TargetStack and RuntimeData.AllowedTypes then
		local ItemType = ItemDatabase.GetItemType(TargetStack.ItemId)
		if not ItemType or not table.find(RuntimeData.AllowedTypes, ItemType) then
			return false
		end
	end

	local OldTargetStack = TargetInventory[TargetIndex]
	local Success = InventoryUtil.TransferSlot(RuntimeData.Inventory, SourceIndex, TargetInventory, TargetIndex)

	if Success then
		InventoryService.SlotChanged:Fire(Player, TargetInventoryName, TargetIndex, TargetInventory[TargetIndex], OldTargetStack)
		InventoryService.InventoryChanged:Fire(Player, TargetInventoryName)

		SyncSlot(Player, TargetInventoryName, TargetIndex)
	end

	return Success
end

--[=[
	Removes all runtime inventories associated with a player (prefixed with "Player_{UserId}_").

	@param Player Player -- The player whose runtime inventories should be cleaned up
]=]
function InventoryService.CleanupPlayerRuntimeInventories(Player: Player)
	local Prefix = string.format("Player_%d_", Player.UserId)

	for InventoryId in RuntimeInventories do
		if string.sub(InventoryId, 1, #Prefix) == Prefix then
			RuntimeInventories[InventoryId] = nil
		end
	end
end

return InventoryService