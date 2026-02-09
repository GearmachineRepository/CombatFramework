--!strict

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

function InventoryService.Init()
	ServiceTrove = Trove.new()
end

function InventoryService.Start()
	ServiceTrove:Add(Players.PlayerRemoving:Connect(function(Player: Player)
		InventoryService.CleanupPlayerRuntimeInventories(Player)
	end))

	ServiceTrove:Connect(PlayerDataService.ProfileLoaded :: any, function(Player: Player, _Data: any)
		SyncAllInventories(Player)
	end)

	ServiceTrove:Connect(Packets.InventoryTransfer.OnServerEvent :: any, function(
		Player: Player,
		SourceInventory: any,
		SourceIndex: any,
		TargetInventory: any,
		TargetIndex: any
	)
		if typeof(SourceInventory) ~= "string" then return end
		if typeof(SourceIndex) ~= "number" then return end
		if typeof(TargetInventory) ~= "string" then return end
		if typeof(TargetIndex) ~= "number" then return end

		InventoryService.TransferSlot(Player, SourceInventory, SourceIndex, TargetInventory, TargetIndex)
	end)

	ServiceTrove:Connect(Packets.InventorySwap.OnServerEvent :: any, function(
		Player: Player,
		SourceInventory: any,
		SourceIndex: any,
		TargetInventory: any,
		TargetIndex: any
	)
		if typeof(SourceInventory) ~= "string" then return end
		if typeof(SourceIndex) ~= "number" then return end
		if typeof(TargetInventory) ~= "string" then return end
		if typeof(TargetIndex) ~= "number" then return end

		InventoryService.SwapSlots(Player, SourceInventory, SourceIndex, TargetInventory, TargetIndex)
	end)

	ServiceTrove:Connect(Packets.InventoryDrop.OnServerEvent :: any, function(
		Player: Player,
		InventoryName: any,
		SlotIndex: any,
		Quantity: any
	)
		if typeof(InventoryName) ~= "string" then return end
		if typeof(SlotIndex) ~= "number" then return end
		if typeof(Quantity) ~= "number" then return end

		InventoryService.DropItem(Player, InventoryName, SlotIndex, Quantity)
	end)

	ServiceTrove:Connect(Packets.InventoryDeposit.OnServerEvent :: any, function(
		Player: Player,
		SourceInventory: any,
		SourceIndex: any,
		TargetInventory: any
	)
		if typeof(SourceInventory) ~= "string" then return end
		if typeof(SourceIndex) ~= "number" then return end
		if typeof(TargetInventory) ~= "string" then return end

		InventoryService.DepositSlot(Player, SourceInventory, SourceIndex, TargetInventory)
	end)

	ServiceTrove:Connect(Packets.InventoryTransferDeposit.OnServerEvent :: any, function(
		Player: Player,
		SourceInventory: any,
		SourceIndex: any,
		TargetInventory: any,
		TargetIndex: any
	)
		if typeof(SourceInventory) ~= "string" then return end
		if typeof(SourceIndex) ~= "number" then return end
		if typeof(TargetInventory) ~= "string" then return end
		if typeof(TargetIndex) ~= "number" then return end

		InventoryService.TransferAndDeposit(Player, SourceInventory, SourceIndex, TargetInventory, TargetIndex)
	end)

	for _, Player in Players:GetPlayers() do
		if PlayerDataService.IsLoaded(Player) then
			task.spawn(SyncAllInventories, Player)
		end
	end
end

function InventoryService.Stop()
	ServiceTrove:Destroy()
	table.clear(RuntimeInventories)
end

function InventoryService.GetInventory(Player: Player, InventoryName: string): Inventory?
	return GetPlayerInventory(Player, InventoryName)
end

function InventoryService.GetSlot(Player: Player, InventoryName: string, SlotIndex: number): ItemStack?
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if not TargetInventory then
		return nil
	end

	return InventoryUtil.GetSlot(TargetInventory, SlotIndex)
end

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
	local Overflow = InventoryUtil.AddItem(TargetInventory, ItemId, Quantity, MaxSlots, TargetMetadata)
	local Added = Quantity - Overflow

	if Added > 0 then
		InventoryService.ItemAdded:Fire(Player, InventoryName, ItemId, Added, TargetMetadata)
		InventoryService.InventoryChanged:Fire(Player, InventoryName)

		SyncInventory(Player, InventoryName)
		Packets.InventoryItemAdded:FireClient(Player, InventoryName, ItemId, Added)
	end

	return Overflow
end

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
	local Removed = InventoryUtil.RemoveItem(TargetInventory, ItemId, Quantity, MaxSlots, TargetMetadata)

	if Removed > 0 then
		InventoryService.ItemRemoved:Fire(Player, InventoryName, ItemId, Removed, TargetMetadata)
		InventoryService.InventoryChanged:Fire(Player, InventoryName)

		SyncInventory(Player, InventoryName)
		Packets.InventoryItemRemoved:FireClient(Player, InventoryName, ItemId, Removed)
	end

	return Removed
end

function InventoryService.HasItem(
	Player: Player,
	InventoryName: string,
	ItemId: string,
	Quantity: number,
	TargetMetadata: Metadata?
): boolean
	local TargetInventory = GetPlayerInventory(Player, InventoryName)
	if not TargetInventory then
		return false
	end

	local MaxSlots = GetMaxSlots(InventoryName)
	return InventoryUtil.HasItem(TargetInventory, ItemId, Quantity, MaxSlots, TargetMetadata)
end

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

	local Success = InventoryUtil.TransferSlot(SourceInventory, SourceIndex, TargetInventory, TargetIndex)

	if Success then
		InventoryService.SlotChanged:Fire(Player, SourceInventoryName, SourceIndex, SourceInventory[SourceIndex], SourceStack)
		InventoryService.SlotChanged:Fire(Player, TargetInventoryName, TargetIndex, TargetInventory[TargetIndex], TargetStack)
		InventoryService.InventoryChanged:Fire(Player, SourceInventoryName)

		SyncSlot(Player, SourceInventoryName, SourceIndex)
		SyncSlot(Player, TargetInventoryName, TargetIndex)

		if SourceInventoryName ~= TargetInventoryName then
			InventoryService.InventoryChanged:Fire(Player, TargetInventoryName)
		end
	end

	return Success
end

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

function InventoryService.GetRuntimeInventory(InventoryId: string): Inventory?
	local RuntimeData = RuntimeInventories[InventoryId]
	return if RuntimeData then RuntimeData.Inventory else nil
end

function InventoryService.DestroyRuntimeInventory(InventoryId: string): boolean
	if not RuntimeInventories[InventoryId] then
		return false
	end

	RuntimeInventories[InventoryId] = nil
	return true
end

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

function InventoryService.CleanupPlayerRuntimeInventories(Player: Player)
	local Prefix = string.format("Player_%d_", Player.UserId)

	for InventoryId in RuntimeInventories do
		if string.sub(InventoryId, 1, #Prefix) == Prefix then
			RuntimeInventories[InventoryId] = nil
		end
	end
end

return InventoryService