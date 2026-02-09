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

local GhostGui: ScreenGui? = nil
local GhostFrame: Frame? = nil

local GHOST_TRANSPARENCY = 0.4
local DRAG_THRESHOLD = 4

local DragStartPosition: Vector2? = nil
local DragConfirmed = false

local function GetCursorPosition(): Vector2
	return UserInputService:GetMouseLocation()
end

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

local function CreateGhostFrame(SourceFrame: Frame): Frame
	local Clone = SourceFrame:Clone()
	Clone.Name = "GhostSlot"
	Clone.Active = false
	Clone.AnchorPoint = Vector2.new(0.5, 0.5)
	Clone.Position = UDim2.fromOffset(0, 0)

	for _, Child in Clone:GetDescendants() do
		if Child:IsA("GuiButton") or Child:IsA("TextButton") or Child:IsA("ImageButton") then
			Child.Active = false
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

local function UpdateGhostPosition(Position: Vector2)
	if not GhostFrame then
		return
	end

	GhostFrame.Position = UDim2.fromOffset(Position.X, Position.Y)
end

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

	DragTrove = ControllerTrove:Extend()

	if not GhostGui then
		GhostGui = CreateGhostGui()
		ControllerTrove:Add(GhostGui)
	end

	GhostFrame = CreateGhostFrame(SlotFrame)
	GhostFrame.Parent = GhostGui
	DragTrove:Add(GhostFrame)

	UpdateGhostPosition(GetCursorPosition())
end

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

		local TargetContainerType = UIInventoryController.GetContainerType(TargetInventoryName)
		local SourceContainerType = UIInventoryController.GetContainerType(SourceInventoryName)

		if TargetContainerType == "List" and TargetInventoryName ~= SourceInventoryName then
			InventoryController.RequestDeposit(
				SourceInventoryName,
				SourceSlotIndex,
				TargetInventoryName
			)
		elseif SourceContainerType == "List" and TargetInventoryName ~= SourceInventoryName then
			InventoryController.RequestTransferAndDeposit(
				SourceInventoryName,
				SourceSlotIndex,
				TargetInventoryName,
				TargetSlotIndex
			)
		else
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

		InventoryController.RequestDeposit(
			SourceInventoryName,
			SourceSlotIndex,
			ContainerInventoryName
		)
	end
end

local function CancelDrag()
	if not IsDragging then
		return
	end

	IsDragging = false
	SourceInventoryName = nil
	SourceSlotIndex = nil
	DragStartPosition = nil
	DragConfirmed = false

	if DragTrove then
		DragTrove:Destroy()
		DragTrove = nil :: any
	end

	GhostFrame = nil
end

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
		DragConfirmed = true
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

function DragController.IsDragging(): boolean
	return IsDragging
end

function DragController.GetDragSource(): (string?, number?)
	return SourceInventoryName, SourceSlotIndex
end

return DragController