--!strict

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UI = ReplicatedStorage:WaitForChild("UI")
local Templates = UI:WaitForChild("Templates")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local InventoryTypes = require(Shared.Types.InventoryTypes)
local CategoryConfig = require(Shared.Config.CategoryConfig)
local ItemDatabase = require(Shared.Data.ItemDatabase)

local Trove = Packages.Trove

local InventoryController = require(script.Parent.InventoryController)
local HotbarController = require(script.Parent.HotbarController)
local InputController = require(script.Parent.InputController)
local UIController = require(script.Parent.UIController)

type ItemStack = InventoryTypes.ItemStack
type Inventory = InventoryTypes.Inventory
type CategoryDefinition = CategoryConfig.CategoryDefinition

local LocalPlayer = Players.LocalPlayer

local InventoryUIController = {}

InventoryUIController.Dependencies = { "InventoryController", "HotbarController", "InputController", "UIController" }

local ControllerTrove: typeof(Trove.new()) = nil :: any
local SlotTemplate: Frame = nil :: any
local CategoryTemplate: Frame = nil :: any

local GridContainers: { [string]: Frame } = {}
local ListContainers: { [string]: Frame } = {}
local CategoryFrames: { [string]: { [string]: Frame } } = {}
local SlotFrames: { [string]: { [number]: Frame } } = {}
local CollapsedCategories: { [string]: boolean } = {}

local IsInventoryOpen = false

local GRID_TAG = "GridLayout"
local LIST_TAG = "ListLayout"
local INVENTORY_ATTRIBUTE = "InventoryName"
local INVENTORY_SCREEN = "InventoryGui"
local TOGGLE_ACTION = "ToggleInventory"
local KEYBIND_CATEGORY = "UI"

local ToggleKeybind = "Tab"

local function GetTemplate(TemplateName: string): Frame?
	local Template = Templates:FindFirstChild(TemplateName)
	return if Template and Template:IsA("Frame") then Template else nil
end

local function ClearChildren(Parent: Instance, IgnoreLayouts: boolean?)
	for _, Child in Parent:GetChildren() do
		if IgnoreLayouts and (Child:IsA("UIPadding") or Child:IsA("UIGridStyleLayout") or Child:IsA("UIListLayout")) then
			continue
		end
		Child:Destroy()
	end
end

local function GetKeybindDisplayText(SlotIndex: number): string
	local KeyCodeName = HotbarController.GetKeybind(SlotIndex)
	if not KeyCodeName then
		return ""
	end

	local KeyCode = (Enum.KeyCode :: any)[KeyCodeName]
	if not KeyCode then
		return KeyCodeName
	end

	local DisplayText = UserInputService:GetStringForKeyCode(KeyCode)
	if DisplayText and DisplayText ~= "" then
		return DisplayText
	end

	return KeyCodeName
end

local function SetSlotSelected(SlotFrame: Frame, IsSelected: boolean)
	SlotFrame:SetAttribute("Selected", IsSelected)

	local FilledContent = SlotFrame:FindFirstChild("FilledContent")
	if not FilledContent then
		return
	end

	local SelectionIndicator = FilledContent:FindFirstChild("SelectionIndicator")
	if SelectionIndicator and SelectionIndicator:IsA("GuiObject") then
		SelectionIndicator.Visible = IsSelected
	end
end

local function UpdateSlotDisplay(SlotFrame: Frame, Stack: ItemStack?, InventoryName: string, SlotIndex: number)
	local FilledContent = SlotFrame:FindFirstChild("FilledContent") :: Frame?
	local EmptyContent = SlotFrame:FindFirstChild("EmptyContent") :: Frame?
	local IsHotbar = InventoryName == "Hotbar"

	local Icon = if FilledContent then FilledContent:FindFirstChild("Icon") :: ImageLabel? else nil
	local TopLabel = if FilledContent then FilledContent:FindFirstChild("TopLabel") :: TextLabel? else nil
	local BottomLabel = if FilledContent then FilledContent:FindFirstChild("BottomLabel") :: TextLabel? else nil
	local ItemNameLabel = if FilledContent then FilledContent:FindFirstChild("ItemName") :: TextLabel? else nil

	if TopLabel then
		if IsHotbar then
			TopLabel.Text = GetKeybindDisplayText(SlotIndex)
			TopLabel.Visible = true
		else
			TopLabel.Text = ""
			TopLabel.Visible = false
		end
	end

	if not Stack then
		if FilledContent then
			FilledContent.Visible = false
		end
		if EmptyContent then
			EmptyContent.Visible = true
		end

		if IsHotbar and not IsInventoryOpen then
			SlotFrame.Visible = false
		elseif IsHotbar and IsInventoryOpen then
			SlotFrame.Visible = true
		end

		if Icon then
			Icon.Image = ""
			Icon.Visible = false
		end
		if BottomLabel then
			BottomLabel.Text = ""
			BottomLabel.Visible = false
		end
		if ItemNameLabel then
			ItemNameLabel.Text = ""
			ItemNameLabel.Visible = false
		end

		SetSlotSelected(SlotFrame, false)
		SlotFrame:SetAttribute("ItemId", nil)
		SlotFrame:SetAttribute("SlotIndex", SlotIndex)
		SlotFrame:SetAttribute("InventoryName", InventoryName)
		return
	end

	SlotFrame.Visible = true

	if FilledContent then
		FilledContent.Visible = true
	end
	if EmptyContent then
		EmptyContent.Visible = false
	end

	local ItemDef = ItemDatabase.Get(Stack.ItemId)

	if Icon then
		Icon.Image = if ItemDef and ItemDef.Icon then ItemDef.Icon else ""
		Icon.Visible = true
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

	if ItemNameLabel then
		ItemNameLabel.Text = if ItemDef and ItemDef.DisplayName then ItemDef.DisplayName else Stack.ItemId
		ItemNameLabel.Visible = true
	end

	if IsHotbar then
		local CurrentSelected = HotbarController.GetSelectedSlot()
		SetSlotSelected(SlotFrame, CurrentSelected == SlotIndex)
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

local function UpdateHotbarSelection(SlotIndex: number, IsSelected: boolean)
	local HotbarSlots = SlotFrames["Hotbar"]
	if not HotbarSlots then
		return
	end

	local SlotFrame = HotbarSlots[SlotIndex]
	if not SlotFrame then
		return
	end

	SetSlotSelected(SlotFrame, IsSelected)
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

	if SlotFrames[InventoryName] then
		table.clear(SlotFrames[InventoryName])
	else
		SlotFrames[InventoryName] = {}
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

		ClearChildren(ContentFrame, true)

		for _, ItemData in Items do
			local SlotFrame = CreateSlotFrame(InventoryName, ItemData.Index)
			SlotFrame.Parent = ContentFrame
			UpdateSlotDisplay(SlotFrame, ItemData.Stack, InventoryName, ItemData.Index)
			SlotFrames[InventoryName][ItemData.Index] = SlotFrame
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

local function IsPointInGuiObject(Position: Vector2, GuiObject: GuiObject): boolean
	local AbsolutePosition = GuiObject.AbsolutePosition
	local AbsoluteSize = GuiObject.AbsoluteSize

	return Position.X >= AbsolutePosition.X
		and Position.X <= AbsolutePosition.X + AbsoluteSize.X
		and Position.Y >= AbsolutePosition.Y
		and Position.Y <= AbsolutePosition.Y + AbsoluteSize.Y
end

local function BindToggle()
	local KeyCode = (Enum.KeyCode :: any)[ToggleKeybind]
	if not KeyCode then
		warn(string.format("[InventoryUIController] Invalid toggle keybind: %s", ToggleKeybind))
		return
	end

	InputController.BindAction(TOGGLE_ACTION, function(State: Enum.UserInputState)
		if State == Enum.UserInputState.Begin then
			UIController.ToggleScreen(INVENTORY_SCREEN)
		end
	end, KeyCode)
end

local function OnInventoryOpened()
	IsInventoryOpen = true
	RefreshInventory("Hotbar")
end

local function OnInventoryClosed()
	IsInventoryOpen = false
	HotbarController.DeselectSlot()
	RefreshInventory("Hotbar")
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
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

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

	ControllerTrove:Connect(HotbarController.SlotSelected :: any, function(SlotIndex: number)
		UpdateHotbarSelection(SlotIndex, true)
	end)

	ControllerTrove:Connect(HotbarController.SlotDeselected :: any, function(SlotIndex: number)
		UpdateHotbarSelection(SlotIndex, false)
	end)

	ControllerTrove:Connect(HotbarController.KeybindsUpdated :: any, function()
		RefreshInventory("Hotbar")
	end)

	ControllerTrove:Connect(UIController.ScreenShown :: any, function(Name: string)
		if Name == INVENTORY_SCREEN then
			OnInventoryOpened()
		end
	end)

	ControllerTrove:Connect(UIController.ScreenHidden :: any, function(Name: string)
		if Name == INVENTORY_SCREEN then
			OnInventoryClosed()
		end
	end)

	ControllerTrove:Connect(Packets.KeybindSync.OnClientEvent :: any, function(AllKeybinds: any)
		if typeof(AllKeybinds) ~= "table" then
			return
		end

		local UIKeybinds = AllKeybinds[KEYBIND_CATEGORY]
		if typeof(UIKeybinds) ~= "table" then
			return
		end

		local InventoryKeybind = UIKeybinds.Inventory
		if typeof(InventoryKeybind) == "string" then
			ToggleKeybind = InventoryKeybind
			BindToggle()
		end
	end)

	BindToggle()
end

function InventoryUIController.Stop()
	InputController.UnbindAction(TOGGLE_ACTION)
	ControllerTrove:Destroy()
	table.clear(GridContainers)
	table.clear(ListContainers)
	table.clear(CategoryFrames)
	table.clear(SlotFrames)
	table.clear(CollapsedCategories)
	IsInventoryOpen = false
end

function InventoryUIController.IsOpen(): boolean
	return IsInventoryOpen
end

function InventoryUIController.GetKeybindDisplay(SlotIndex: number): string
	return GetKeybindDisplayText(SlotIndex)
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
			if not SlotFrame.Visible then
				continue
			end

			if IsPointInGuiObject(Position, SlotFrame) then
				return SlotFrame, InventoryName, SlotIndex
			end
		end
	end

	return nil, nil, nil
end

function InventoryUIController.GetContainerAtPosition(Position: Vector2): (string?, string?)
	for InventoryName, Container in GridContainers do
		if Container.Visible and IsPointInGuiObject(Position, Container) then
			return InventoryName, "Grid"
		end
	end

	for InventoryName, Container in ListContainers do
		if Container.Visible and IsPointInGuiObject(Position, Container) then
			return InventoryName, "List"
		end
	end

	return nil, nil
end

function InventoryUIController.GetContainerType(InventoryName: string): string?
	if GridContainers[InventoryName] then
		return "Grid"
	end

	if ListContainers[InventoryName] then
		return "List"
	end

	return nil
end

function InventoryUIController.GetSlotFrame(InventoryName: string, SlotIndex: number): Frame?
	local Slots = SlotFrames[InventoryName]
	if not Slots then
		return nil
	end

	return Slots[SlotIndex]
end

return InventoryUIController