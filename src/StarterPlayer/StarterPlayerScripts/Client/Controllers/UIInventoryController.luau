--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")
local Templates = UI:WaitForChild("Templates")

local Packages = require(Shared.Packages)
local InventoryTypes = require(Shared.Types.InventoryTypes)
local CategoryConfig = require(Shared.Config.CategoryConfig)
local ItemDatabase = require(Shared.Data.ItemDatabase)

local Trove = Packages.Trove

local InventoryController = require(script.Parent.InventoryController)

type ItemStack = InventoryTypes.ItemStack
type Inventory = InventoryTypes.Inventory
type CategoryDefinition = CategoryConfig.CategoryDefinition

local LocalPlayer = Players.LocalPlayer

local InventoryUIController = {}

InventoryUIController.Dependencies = { "InventoryController" }

local ControllerTrove: typeof(Trove.new()) = nil :: any
local SlotTemplate: Frame = nil :: any
local CategoryTemplate: Frame = nil :: any

local GridContainers: { [string]: Frame } = {}
local ListContainers: { [string]: Frame } = {}
local CategoryFrames: { [string]: { [string]: Frame } } = {}
local SlotFrames: { [string]: { [number]: Frame } } = {}
local CollapsedCategories: { [string]: boolean } = {}

local GRID_TAG = "GridLayout"
local LIST_TAG = "ListLayout"
local INVENTORY_ATTRIBUTE = "InventoryName"

local function GetTemplate(TemplateName: string): Frame?
	local Template = Templates:FindFirstChild(TemplateName)
	return if Template and Template:IsA("Frame") then Template else nil
end

local function ClearChildren(Parent: Instance, IgnoreLayouts: boolean?)
	for _, Child in Parent:GetChildren() do
		if IgnoreLayouts and (Child:IsA("UILayout") or Child:IsA("UIGridStyleLayout") or Child:IsA("UIListLayout")) then
			continue
		end
		Child:Destroy()
	end
end

local function UpdateSlotDisplay(SlotFrame: Frame, Stack: ItemStack?, InventoryName: string, SlotIndex: number)
	local Icon = SlotFrame:FindFirstChild("Icon") :: ImageLabel?
	local TopLabel = SlotFrame:FindFirstChild("TopLabel") :: TextLabel?
	local BottomLabel = SlotFrame:FindFirstChild("BottomLabel") :: TextLabel?

	if not Stack then
		if Icon then
			Icon.Image = ""
			Icon.Visible = false
		end
		if TopLabel then
			TopLabel.Text = ""
			TopLabel.Visible = false
		end
		if BottomLabel then
			BottomLabel.Text = ""
			BottomLabel.Visible = false
		end
		return
	end

	local ItemDef = ItemDatabase.Get(Stack.ItemId)

	if Icon then
		Icon.Image = if ItemDef and ItemDef.Icon then ItemDef.Icon else ""
		Icon.Visible = true
	end

	local IsHotbar = InventoryName == "Hotbar"

	if TopLabel then
		if IsHotbar then
			local KeybindText = tostring(SlotIndex)
			if SlotIndex == 10 then
				KeybindText = "0"
			end
			TopLabel.Text = KeybindText
			TopLabel.Visible = true
		else
			TopLabel.Text = ""
			TopLabel.Visible = false
		end
	end

	if BottomLabel then
		local Metadata = Stack.Metadata

		if Metadata and Metadata.Uses and Metadata.MaxUses then
			BottomLabel.Text = string.format("%d/%d", Metadata.Uses, Metadata.MaxUses)
			BottomLabel.Visible = true
		elseif Stack.Quantity > 1 then
			BottomLabel.Text = "x" .. tostring(Stack.Quantity)
			BottomLabel.Visible = true
		else
			BottomLabel.Text = ""
			BottomLabel.Visible = false
		end
	end

	SlotFrame:SetAttribute("ItemId", Stack.ItemId)
	SlotFrame:SetAttribute("SlotIndex", SlotIndex)
	SlotFrame:SetAttribute("InventoryName", InventoryName)
end

local function CreateSlotFrame(InventoryName: string, SlotIndex: number): Frame
	local SlotFrame = SlotTemplate:Clone()
	SlotFrame.Name = "Slot_" .. SlotIndex
	SlotFrame:SetAttribute("SlotIndex", SlotIndex)
	SlotFrame:SetAttribute("InventoryName", InventoryName)
	SlotFrame.Visible = true

	return SlotFrame
end

local function ToggleCategory(InventoryName: string, CategoryId: string)
	local Key = InventoryName .. "_" .. CategoryId
	CollapsedCategories[Key] = not CollapsedCategories[Key]

	local InventoryCategories = CategoryFrames[InventoryName]
	if not InventoryCategories then
		return
	end

	local CategoryFrame = InventoryCategories[CategoryId]
	if not CategoryFrame then
		return
	end

	local ContentFrame = CategoryFrame:FindFirstChild("ContentFrame") :: Frame?
	local DescriptionFrame = CategoryFrame:FindFirstChild("DescriptionFrame") :: Frame?
	local HeaderFrame = CategoryFrame:FindFirstChild("HeaderFrame") :: Frame?

	local IsCollapsed = CollapsedCategories[Key]

	if ContentFrame then
		ContentFrame.Visible = not IsCollapsed
	end

	if DescriptionFrame then
		DescriptionFrame.Visible = not IsCollapsed
	end

	if HeaderFrame then
		local Arrow = HeaderFrame:FindFirstChild("Arrow") :: TextButton?
		if Arrow then
			Arrow.Text = if IsCollapsed then "▶" else "▼"
		end
	end
end

local function CreateCategoryFrame(InventoryName: string, CategoryId: string, Definition: CategoryDefinition): Frame
	local CategoryFrame = CategoryTemplate:Clone()
	CategoryFrame.Name = "Category_" .. CategoryId
	CategoryFrame.Visible = true

	local HeaderFrame = CategoryFrame:FindFirstChild("HeaderFrame") :: Frame?
	if HeaderFrame then
		local CategoryName = HeaderFrame:FindFirstChild("CategoryName") :: TextLabel?
		if CategoryName then
			CategoryName.Text = Definition.Name
		end

		local ItemCount = HeaderFrame:FindFirstChild("ItemCount") :: TextLabel?
		if ItemCount then
			ItemCount.Text = "0"
		end

		local Arrow = HeaderFrame:FindFirstChild("Arrow") :: TextButton?
		if Arrow then
			Arrow.Text = "▼"
			Arrow.Activated:Connect(function()
				ToggleCategory(InventoryName, CategoryId)
			end)
		end
	end

	local DescriptionFrame = CategoryFrame:FindFirstChild("DescriptionFrame") :: Frame?
	if DescriptionFrame then
		local Description = DescriptionFrame:FindFirstChild("Description") :: TextLabel?
		if Description then
			if Definition.Description and Definition.Description ~= "" then
				Description.Text = Definition.Description
				DescriptionFrame.Visible = true
			else
				DescriptionFrame.Visible = false
			end
		end
	end

	return CategoryFrame
end

local function UpdateCategoryItemCount(InventoryName: string, CategoryId: string, Count: number)
	local InventoryCategories = CategoryFrames[InventoryName]
	if not InventoryCategories then
		return
	end

	local CategoryFrame = InventoryCategories[CategoryId]
	if not CategoryFrame then
		return
	end

	local HeaderFrame = CategoryFrame:FindFirstChild("HeaderFrame") :: Frame?
	if not HeaderFrame then
		return
	end

	local ItemCount = HeaderFrame:FindFirstChild("ItemCount") :: TextLabel?
	if ItemCount then
		ItemCount.Text = tostring(Count)
	end

	CategoryFrame.Visible = true
end

local function RefreshGridInventory(InventoryName: string)
	local Container = GridContainers[InventoryName]
	if not Container then
		return
	end

	local TargetInventory = InventoryController.GetInventory(InventoryName)
	local MaxSlots = InventoryController.GetMaxSlots(InventoryName)

	if not SlotFrames[InventoryName] then
		SlotFrames[InventoryName] = {}
	end

	local Slots = SlotFrames[InventoryName]

	for Index = 1, MaxSlots do
		local SlotFrame = Slots[Index]

		if not SlotFrame then
			local NewSlotFrame = CreateSlotFrame(InventoryName, Index)
			NewSlotFrame.LayoutOrder = Index
			NewSlotFrame.Parent = Container
			Slots[Index] = NewSlotFrame

            SlotFrame = NewSlotFrame
		end

		local Stack = if TargetInventory then TargetInventory[Index] else nil
		UpdateSlotDisplay(SlotFrame, Stack, InventoryName, Index)
	end
end

local function RefreshListInventory(InventoryName: string)
	local Container = ListContainers[InventoryName]
	if not Container then
		return
	end

	local CategoryList = Container:FindFirstChild("CategoryList") :: ScrollingFrame?
	if not CategoryList then
		return
	end

	local TargetInventory = InventoryController.GetInventory(InventoryName)
	local MaxSlots = InventoryController.GetMaxSlots(InventoryName)

	if not CategoryFrames[InventoryName] then
		CategoryFrames[InventoryName] = {}

		local SortedCategories = CategoryConfig.GetSorted()
		for _, Entry in SortedCategories do
			local CategoryId = Entry.CategoryId
			local Definition = Entry.Definition
			local CategoryFrame = CreateCategoryFrame(InventoryName, CategoryId, Definition)
			CategoryFrame.LayoutOrder = Definition.SortOrder
			CategoryFrame.Parent = CategoryList
			CategoryFrames[InventoryName][CategoryId] = CategoryFrame
		end
	end

	local CategoryItems: { [string]: { { Stack: ItemStack, Index: number } } } = {}
	for CategoryId in CategoryFrames[InventoryName] do
		CategoryItems[CategoryId] = {}
	end

	if TargetInventory then
		for Index = 1, MaxSlots do
			local Stack = TargetInventory[Index]
			if not Stack then
				continue
			end

			local ItemDef = ItemDatabase.Get(Stack.ItemId)
			local ItemType = if ItemDef then ItemDef.ItemType else "Misc"
			local CategoryId = CategoryConfig.GetCategoryForItemType(ItemType) or "Miscellaneous"

			if not CategoryItems[CategoryId] then
				CategoryItems[CategoryId] = {}
			end

			table.insert(CategoryItems[CategoryId], { Stack = Stack, Index = Index })
		end
	end

	for CategoryId, Items in CategoryItems do
		local CategoryFrame = CategoryFrames[InventoryName][CategoryId]
		if not CategoryFrame then
			continue
		end

		local ContentFrame = CategoryFrame:FindFirstChild("ContentFrame") :: Frame?
		if not ContentFrame then
			continue
		end

		--ClearChildren(ContentFrame, true)

		for _, ItemData in Items do
			local SlotFrame = CreateSlotFrame(InventoryName, ItemData.Index)
			SlotFrame.Parent = ContentFrame
			UpdateSlotDisplay(SlotFrame, ItemData.Stack, InventoryName, ItemData.Index)
		end

		UpdateCategoryItemCount(InventoryName, CategoryId, #Items)
	end
end

local function RefreshInventory(InventoryName: string)
	if GridContainers[InventoryName] then
		RefreshGridInventory(InventoryName)
	elseif ListContainers[InventoryName] then
		RefreshListInventory(InventoryName)
	end
end

local function SetupContainer(Container: Frame)
	local InventoryName = Container:GetAttribute(INVENTORY_ATTRIBUTE)
	if not InventoryName or typeof(InventoryName) ~= "string" then
		warn("[InventoryUIController] Container missing InventoryName attribute:", Container:GetFullName())
		return
	end

	if CollectionService:HasTag(Container, GRID_TAG) then
		GridContainers[InventoryName] = Container
	elseif CollectionService:HasTag(Container, LIST_TAG) then
		ListContainers[InventoryName] = Container
	end

	RefreshInventory(InventoryName)
end

local function FindContainersInGui(ScreenGui: ScreenGui)
	for _, Descendant in ScreenGui:GetDescendants() do
		if not Descendant:IsA("Frame") then
			continue
		end

		if CollectionService:HasTag(Descendant, GRID_TAG) or CollectionService:HasTag(Descendant, LIST_TAG) then
			SetupContainer(Descendant)
		end
	end
end

function InventoryUIController.Init()
	ControllerTrove = Trove.new()

	SlotTemplate = GetTemplate("InventorySlot") :: Frame
	CategoryTemplate = GetTemplate("CategoryFrame") :: Frame

	if not SlotTemplate then
		warn("[InventoryUIController] Missing InventorySlot template")
	end

	if not CategoryTemplate then
		warn("[InventoryUIController] Missing CategoryFrame template")
	end
end

function InventoryUIController.Start()
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

	for _, ScreenGui in PlayerGui:GetChildren() do
		if ScreenGui:IsA("ScreenGui") then
			FindContainersInGui(ScreenGui)
		end
	end

	ControllerTrove:Connect(PlayerGui.ChildAdded, function(Child: Instance)
		if Child:IsA("ScreenGui") then
			task.defer(FindContainersInGui, Child)
		end
	end)

	ControllerTrove:Connect(InventoryController.InventorySynced :: any, function(InventoryName: string)
		RefreshInventory(InventoryName)
	end)

	ControllerTrove:Connect(InventoryController.SlotUpdated :: any, function(InventoryName: string)
		RefreshInventory(InventoryName)
	end)
end

function InventoryUIController.Stop()
	ControllerTrove:Destroy()
	table.clear(GridContainers)
	table.clear(ListContainers)
	table.clear(CategoryFrames)
	table.clear(SlotFrames)
	table.clear(CollapsedCategories)
end

function InventoryUIController.RefreshAll()
	for InventoryName in GridContainers do
		RefreshGridInventory(InventoryName)
	end

	for InventoryName in ListContainers do
		RefreshListInventory(InventoryName)
	end
end

function InventoryUIController.GetSlotAtPosition(Position: Vector2): (Frame?, string?, number?)
	for InventoryName, Slots in SlotFrames do
		for SlotIndex, SlotFrame in Slots do
			local AbsolutePosition = SlotFrame.AbsolutePosition
			local AbsoluteSize = SlotFrame.AbsoluteSize

			if Position.X >= AbsolutePosition.X
				and Position.X <= AbsolutePosition.X + AbsoluteSize.X
				and Position.Y >= AbsolutePosition.Y
				and Position.Y <= AbsolutePosition.Y + AbsoluteSize.Y
			then
				return SlotFrame, InventoryName, SlotIndex
			end
		end
	end

	return nil, nil, nil
end

return InventoryUIController