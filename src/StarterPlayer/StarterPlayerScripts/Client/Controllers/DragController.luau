--!strict

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local Packages = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Packages)

local Trove = Packages.Trove

local InventoryController = require(script.Parent.InventoryController)
local UIInventoryController = require(script.Parent.UIInventoryController)

local LocalPlayer = Players.LocalPlayer

local DragController = {}

DragController.Dependencies = { "InventoryController", "UIInventoryController" }

local ControllerTrove: typeof(Trove.new()) = nil :: any
local DragTrove: typeof(Trove.new()) = nil :: any

local IsDragging = false
local SourceInventoryName: string? = nil
local SourceSlotIndex: number? = nil
local SourceSlotFrame: Frame? = nil

local GhostGui: ScreenGui? = nil
local GhostFrame: Frame? = nil

local GHOST_TRANSPARENCY = 0
local DRAG_THRESHOLD = 0

local DragStartPosition: Vector2? = nil
local DragConfirmed = false
local DidPredict = false

--[=[
	Returns the current cursor position.

	@return Vector2 -- The screen position of the cursor
]=]
local function GetCursorPosition(): Vector2
	return UserInputService:GetMouseLocation()
end

--[=[
	Creates the ScreenGui used to display the drag ghost above all other UI.

	@return ScreenGui -- The newly created ghost ScreenGui
]=]
local function CreateGhostGui(): ScreenGui
	local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name = "DragGhost"
	ScreenGui.DisplayOrder = 999
	ScreenGui.IgnoreGuiInset = true
	ScreenGui.ResetOnSpawn = false
	ScreenGui.Parent = PlayerGui

	return ScreenGui
end

--[=[
	Clones the source frame as a semi-transparent ghost for dragging.

	@param SourceFrame Frame -- The slot frame to clone
	@return Frame -- The ghost clone with transparency applied
]=]
local function CreateGhostFrame(SourceFrame: Frame): Frame
	local Clone = SourceFrame:Clone()
	Clone.Name = "GhostSlot"
	Clone.Active = false
	Clone.AnchorPoint = Vector2.new(0.5, 0.5)
	Clone.Position = UDim2.fromOffset(0, 0)

	for _, Child in Clone:GetDescendants() do
		if Child:IsA("GuiButton") or Child:IsA("TextButton") or Child:IsA("ImageButton") then
			(Child :: GuiButton).Active = false
		end
	end

	for _, Child in Clone:GetChildren() do
		if Child:IsA("UIGridStyleLayout") or Child:IsA("UIListLayout") then
			Child:Destroy()
		end
	end

	local function ApplyTransparency(Target: Instance)
		if Target:IsA("GuiObject") then
			if Target:IsA("ImageLabel") or Target:IsA("ImageButton") then
				(Target :: ImageLabel).ImageTransparency = math.max((Target :: ImageLabel).ImageTransparency, GHOST_TRANSPARENCY)
			end
			if Target:IsA("TextLabel") or Target:IsA("TextButton") then
				(Target :: TextLabel).TextTransparency = math.max((Target :: TextLabel).TextTransparency, GHOST_TRANSPARENCY)
			end
			Target.BackgroundTransparency = math.max(Target.BackgroundTransparency, GHOST_TRANSPARENCY)
		end
	end

	ApplyTransparency(Clone)
	for _, Descendant in Clone:GetDescendants() do
		ApplyTransparency(Descendant)
	end

	return Clone
end

--[=[
	Moves the ghost frame to follow the cursor.

	@param Position Vector2 -- The screen position to move to
]=]
local function UpdateGhostPosition(Position: Vector2)
	if not GhostFrame then
		return
	end

	GhostFrame.Position = UDim2.fromOffset(Position.X, Position.Y)
end

--[=[
	Hides the source slot during a drag. Grids show the empty content
	frame underneath, lists hide the slot entirely so the layout reflows.
]=]
local function HideSourceSlot()
	if not SourceSlotFrame or not SourceInventoryName then
		return
	end

	local ContainerType = UIInventoryController.GetContainerType(SourceInventoryName)

	if ContainerType == "Grid" then
		local FilledContent = SourceSlotFrame:FindFirstChild("FilledContent")
		local EmptyContent = SourceSlotFrame:FindFirstChild("EmptyContent")
		if FilledContent and FilledContent:IsA("GuiObject") then
			FilledContent.Visible = false
		end
		if EmptyContent and EmptyContent:IsA("GuiObject") then
			EmptyContent.Visible = true
		end
	else
		SourceSlotFrame.Visible = false
	end
end

--[=[
	Restores source slot visibility when a drag is cancelled without
	a successful drop. Only called when no prediction was applied.
]=]
local function RestoreSourceSlot()
	if not SourceSlotFrame or not SourceInventoryName then
		return
	end

	local ContainerType = UIInventoryController.GetContainerType(SourceInventoryName)

	if ContainerType == "Grid" then
		local FilledContent = SourceSlotFrame:FindFirstChild("FilledContent")
		local EmptyContent = SourceSlotFrame:FindFirstChild("EmptyContent")
		if FilledContent and FilledContent:IsA("GuiObject") then
			FilledContent.Visible = true
		end
		if EmptyContent and EmptyContent:IsA("GuiObject") then
			EmptyContent.Visible = false
		end
	else
		SourceSlotFrame.Visible = true
	end
end

--[=[
	Confirms the drag visually: shows the ghost and hides the source slot.
]=]
local function ConfirmDrag()
	if DragConfirmed then
		return
	end

	DragConfirmed = true

	if GhostFrame then
		GhostFrame.Visible = true
	end

	HideSourceSlot()
end

--[=[
	Begins tracking a drag from the given slot. If the threshold is zero,
	the drag is confirmed immediately so the source hides on press.

	@param SlotFrame Frame -- The UI frame of the slot being dragged
	@param InventoryName string -- Name of the inventory the slot belongs to
	@param SlotIndex number -- Index of the slot being dragged
]=]
local function StartDrag(SlotFrame: Frame, InventoryName: string, SlotIndex: number)
	if IsDragging then
		return
	end

	local Stack = InventoryController.GetSlot(InventoryName, SlotIndex)
	if not Stack then
		return
	end

	IsDragging = true
	SourceInventoryName = InventoryName
	SourceSlotIndex = SlotIndex
	SourceSlotFrame = SlotFrame

	DragTrove = ControllerTrove:Extend()

	if not GhostGui then
		GhostGui = CreateGhostGui()
		if GhostGui then
			ControllerTrove:Add(GhostGui)
		end
	end

	GhostFrame = CreateGhostFrame(SlotFrame)
	if GhostFrame then
		GhostFrame.Visible = false
		GhostFrame.Parent = GhostGui
		DragTrove:Add(GhostFrame)
	end

	UpdateGhostPosition(GetCursorPosition())

	if DRAG_THRESHOLD <= 0 then
		ConfirmDrag()
	end
end

--[=[
	Resolves a completed drag by predicting the result locally then
	sending the request to the server. Prediction mutates client
	inventory data and fires SlotUpdated, so the UI refreshes instantly.
	Server sync arrives later with the authoritative data.

	@param DropPosition Vector2 -- The screen position where the drag ended
]=]
local function ResolveDrop(DropPosition: Vector2)
	if not IsDragging or not SourceInventoryName or not SourceSlotIndex then
		return
	end

	if GhostFrame then
		GhostFrame.Visible = false
	end

	local TargetFrame, TargetInventoryName, TargetSlotIndex = UIInventoryController.GetSlotAtPosition(DropPosition)

	if TargetFrame and TargetInventoryName and TargetSlotIndex then
		if TargetInventoryName == SourceInventoryName and TargetSlotIndex == SourceSlotIndex then
			return
		end

		local SourceStack = InventoryController.GetSlot(SourceInventoryName, SourceSlotIndex)
		if not SourceStack then
			return
		end

		if not InventoryController.IsItemTypeAllowed(TargetInventoryName, SourceStack.ItemId) then
			return
		end

		local TargetStack = InventoryController.GetSlot(TargetInventoryName, TargetSlotIndex)
		if TargetStack and not InventoryController.IsItemTypeAllowed(SourceInventoryName, TargetStack.ItemId) then
			return
		end

		local TargetContainerType = UIInventoryController.GetContainerType(TargetInventoryName)
		local SourceContainerType = UIInventoryController.GetContainerType(SourceInventoryName)

		if TargetContainerType == "List" and TargetInventoryName ~= SourceInventoryName then
			InventoryController.PredictDeposit(SourceInventoryName, SourceSlotIndex, TargetInventoryName)
			DidPredict = true
			InventoryController.RequestDeposit(
				SourceInventoryName,
				SourceSlotIndex,
				TargetInventoryName
			)
		elseif SourceContainerType == "List" and TargetInventoryName ~= SourceInventoryName then
			InventoryController.PredictTransferAndDeposit(SourceInventoryName, SourceSlotIndex, TargetInventoryName, TargetSlotIndex)
			DidPredict = true
			InventoryController.RequestTransferAndDeposit(
				SourceInventoryName,
				SourceSlotIndex,
				TargetInventoryName,
				TargetSlotIndex
			)
		else
			InventoryController.PredictTransfer(SourceInventoryName, SourceSlotIndex, TargetInventoryName, TargetSlotIndex)
			DidPredict = true
			InventoryController.RequestTransfer(
				SourceInventoryName,
				SourceSlotIndex,
				TargetInventoryName,
				TargetSlotIndex
			)
		end
		return
	end

	local ContainerInventoryName = UIInventoryController.GetContainerAtPosition(DropPosition)

	if ContainerInventoryName then
		if ContainerInventoryName == SourceInventoryName then
			return
		end

		local SourceStack = InventoryController.GetSlot(SourceInventoryName, SourceSlotIndex)
		if not SourceStack then
			return
		end

		if not InventoryController.IsItemTypeAllowed(ContainerInventoryName, SourceStack.ItemId) then
			return
		end

		InventoryController.PredictDeposit(SourceInventoryName, SourceSlotIndex, ContainerInventoryName)
		DidPredict = true
		InventoryController.RequestDeposit(
			SourceInventoryName,
			SourceSlotIndex,
			ContainerInventoryName
		)
		return
	end
end

--[=[
	Cleans up all drag state. If no prediction was applied (drag was
	cancelled or dropped on nothing), restores the source slot visually.
	If a prediction was applied, the data is already correct so no
	restoration is needed.
]=]
local function CancelDrag()
	if not IsDragging then
		return
	end

	if not DidPredict then
		RestoreSourceSlot()
	end

	IsDragging = false
	SourceInventoryName = nil
	SourceSlotIndex = nil
	SourceSlotFrame = nil
	DragStartPosition = nil
	DragConfirmed = false
	DidPredict = false

	if DragTrove then
		DragTrove:Destroy()
		DragTrove = nil :: any
	end

	GhostFrame = nil
end

--[=[
	Finalizes a drag on mouse/touch release. Resolves the drop if
	the drag was confirmed, then cleans up.

	@param DropPosition Vector2 -- The screen position where the input ended
]=]
local function EndDrag(DropPosition: Vector2)
	if not IsDragging then
		return
	end

	if DragConfirmed then
		ResolveDrop(DropPosition)
	end

	CancelDrag()
end

local function OnInputBegan(InputObject: InputObject, _GameProcessed: boolean)
	if IsDragging then
		return
	end

	local InputType = InputObject.UserInputType
	if InputType ~= Enum.UserInputType.MouseButton1 and InputType ~= Enum.UserInputType.Touch then
		return
	end

	local Position = Vector2.new(InputObject.Position.X, InputObject.Position.Y)
	local SlotFrame, InventoryName, SlotIndex = UIInventoryController.GetSlotAtPosition(Position)

	if not SlotFrame or not InventoryName or not SlotIndex then
		return
	end

	if InventoryName == "Hotbar" and not UIInventoryController.IsOpen() then
		return
	end

	local Stack = InventoryController.GetSlot(InventoryName, SlotIndex)
	if not Stack then
		return
	end

	DragStartPosition = Position
	DragConfirmed = false

	StartDrag(SlotFrame, InventoryName, SlotIndex)
end

local function OnInputChanged(InputObject: InputObject)
	if not IsDragging then
		return
	end

	local InputType = InputObject.UserInputType
	if InputType ~= Enum.UserInputType.MouseMovement and InputType ~= Enum.UserInputType.Touch then
		return
	end

	local Position = Vector2.new(InputObject.Position.X, InputObject.Position.Y)

	if not DragConfirmed and DragStartPosition then
		local Delta = (Position - DragStartPosition).Magnitude
		if Delta < DRAG_THRESHOLD then
			return
		end
		ConfirmDrag()
	end

	UpdateGhostPosition(GetCursorPosition())
end

local function OnInputEnded(InputObject: InputObject)
	if not IsDragging then
		return
	end

	local InputType = InputObject.UserInputType
	if InputType ~= Enum.UserInputType.MouseButton1 and InputType ~= Enum.UserInputType.Touch then
		return
	end

	local Position = Vector2.new(InputObject.Position.X, InputObject.Position.Y)
	EndDrag(Position)
end

function DragController.Init()
	ControllerTrove = Trove.new()
end

function DragController.Start()
	ControllerTrove:Connect(UserInputService.InputBegan, OnInputBegan)
	ControllerTrove:Connect(UserInputService.InputChanged, OnInputChanged)
	ControllerTrove:Connect(UserInputService.InputEnded, OnInputEnded)
end

function DragController.Stop()
	CancelDrag()
	ControllerTrove:Destroy()
	GhostGui = nil
end

--[=[
	Returns whether a drag is currently active.

	@return boolean -- True if a drag is in progress
]=]
function DragController.IsDragging(): boolean
	return IsDragging
end

--[=[
	Returns the inventory name and slot index of the current drag source.

	@return string? -- The source inventory name, or nil
	@return number? -- The source slot index, or nil
]=]
function DragController.GetDragSource(): (string?, number?)
	return SourceInventoryName, SourceSlotIndex
end

return DragController