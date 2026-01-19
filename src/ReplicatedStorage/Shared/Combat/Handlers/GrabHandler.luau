--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local GrabHandler = {}

local CharactersFolder = workspace:FindFirstChild("Characters")

local function GetStateFromCharacter(Character: Model, StateName: string): boolean
	local AttributeName = "State_" .. StateName
	local Value = Character:GetAttribute(AttributeName)
	return Value == true
end

local function SetStateOnCharacter(Character: Model, StateName: string, Value: boolean)
	local AttributeName = "State_" .. StateName
	Character:SetAttribute(AttributeName, Value)
end

local function DetectTargets(Origin: CFrame, Size: Vector3, Exclude: Model): { Model }
	local Results: { Model } = {}

	if not CharactersFolder then
		CharactersFolder = workspace:FindFirstChild("Characters")
		if not CharactersFolder then
			return Results
		end
	end

	local OverlapParams = OverlapParams.new()
	OverlapParams.FilterType = Enum.RaycastFilterType.Include
	OverlapParams.FilterDescendantsInstances = { CharactersFolder }

	local Parts = workspace:GetPartBoundsInBox(Origin, Size, OverlapParams)

	for _, Part in Parts do
		if Part.Name ~= "HumanoidRootPart" then
			continue
		end

		local Character = Part.Parent :: Model
		if Character == Exclude then
			continue
		end

		if not Character:FindFirstChildOfClass("Humanoid") then
			continue
		end

		if table.find(Results, Character) then
			continue
		end

		table.insert(Results, Character)
	end

	return Results
end

local function FindGrabTarget(
	Character: Model,
	OffsetX: number,
	OffsetY: number,
	OffsetZ: number,
	SizeX: number,
	SizeY: number,
	SizeZ: number
): Model?
	local RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not RootPart then
		return nil
	end

	local Offset = Vector3.new(OffsetX, OffsetY, -OffsetZ)
	local Size = Vector3.new(SizeX, SizeY, SizeZ)
	local Origin = RootPart.CFrame * CFrame.new(Offset)

	local Box = Instance.new("Part")
	Box.Size = Size
	Box.CFrame = Origin
	Box.Material = Enum.Material.SmoothPlastic
	Box.Color = Color3.fromRGB(255, 0, 0)
	Box.Transparency = 0.5
	Box.CastShadow = false
	Box.CanQuery = false
	Box.CanCollide = false
	Box.Anchored = true
	Box.Parent = workspace
	game.Debris:AddItem(Box, 1)

	local Targets = DetectTargets(Origin, Size, Character)

	for _, Target in Targets do
		local TargetHumanoid = Target:FindFirstChildOfClass("Humanoid")
		if not TargetHumanoid or TargetHumanoid.Health <= 0 then
			continue
		end

		local Blocked = GetStateFromCharacter(Target, "Blocking")
		if Blocked then
			continue
		end

		local Grabbed = GetStateFromCharacter(Target, "Grabbed")
		if Grabbed then
			continue
		end

		local Invincible = GetStateFromCharacter(Target, "Invincible")
		if Invincible then
			continue
		end

		return Target
	end

	return nil
end

local function CreateGrabWeld(
	AttackerCharacter: Model,
	TargetCharacter: Model,
	HoldOffsetX: number,
	HoldOffsetY: number,
	HoldOffsetZ: number
): WeldConstraint?
	local AttackerRoot = AttackerCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local TargetRoot = TargetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not AttackerRoot or not TargetRoot then
		return nil
	end

	local Offset = Vector3.new(HoldOffsetX, HoldOffsetY, HoldOffsetZ)
	local TargetPosition = AttackerRoot.CFrame * CFrame.new(Offset)
	local LookAt = CFrame.lookAt(TargetPosition.Position, AttackerRoot.Position)
	TargetRoot.CFrame = LookAt

	local Weld = Instance.new("WeldConstraint")
	Weld.Name = "GrabWeld"
	Weld.Part0 = AttackerRoot
	Weld.Part1 = TargetRoot
	Weld.Parent = AttackerRoot

	return Weld
end

local function DestroyGrabWeld(AttackerCharacter: Model)
	local AttackerRoot = AttackerCharacter:FindFirstChild("HumanoidRootPart")
	if not AttackerRoot then
		return
	end

	local Weld = AttackerRoot:FindFirstChild("GrabWeld")
	if Weld then
		Weld:Destroy()
	end
end

function GrabHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if not IsServer then
		return nil
	end

	if Context.Mode ~= "Authoritative" then
		return nil
	end

	local OffsetX = Block.X or 0
	local OffsetY = Block.Y or 0
	local OffsetZ = Block.Z or 4
	local SizeX = Block.SizeX or 4
	local SizeY = Block.SizeY or 4
	local SizeZ = Block.SizeZ or 4

	local HoldOffsetX = Block.HoldOffsetX or 0
	local HoldOffsetY = Block.HoldOffsetY or 0
	local HoldOffsetZ = Block.HoldOffsetZ or -3

	local Duration = Block.Duration or 2
	local AttackerAnimation = Block.AttackerAnimation
	local TargetAnimation = Block.TargetAnimation
	local ThrowBranch = Block.ThrowBranch
	local ReleaseBranch = Block.ReleaseBranch
	local MissBranch = Block.MissBranch

	local Character = Context.Entity.Character
	local Player = Context.Entity.Player

	local Target = FindGrabTarget(Character, OffsetX, OffsetY, OffsetZ, SizeX, SizeY, SizeZ)

	if not Target then
		if MissBranch then
			return { JumpToBranch = MissBranch }
		end
		return { Cancel = true }
	end

	SetStateOnCharacter(Target, "Grabbed", true)
	SetStateOnCharacter(Character, "Grabbing", true)
	Target:SetAttribute("GrabbedBy", Character.Name)
	Character:SetAttribute("GrabTarget", Target.Name)

	Context.SetGrabTarget(Target)

	local TargetHumanoid = Target:FindFirstChildOfClass("Humanoid")
	local AttackerHumanoid = Context.Entity.Humanoid

	if TargetHumanoid then
		TargetHumanoid.AutoRotate = false
		TargetHumanoid.PlatformStand = true
	end

	if AttackerHumanoid then
		AttackerHumanoid.AutoRotate = false
	end

	local Packets = require(Shared.Network.Packets)

	Packets.GrabSync:Fire("GrabStarted", Character, Target, AttackerAnimation, TargetAnimation)

	local GrabWeld = CreateGrabWeld(Character, Target, HoldOffsetX, HoldOffsetY, HoldOffsetZ)

	local ThrowInput = false
	local GrabEnded = false
	local StartTime = tick()

	local InputConnection: any = nil
	if Player and ThrowBranch then
		InputConnection = Packets.GrabInput.OnServerEvent:Connect(function(InputPlayer: Player, InputType: string)
			if InputPlayer ~= Player then
				return
			end

			if InputType == "Throw" and not GrabEnded then
				ThrowInput = true
			end
		end)
	end

	while not GrabEnded and (tick() - StartTime) < Duration do
		if Context.Canceled then
			GrabEnded = true
			break
		end

		if ThrowInput then
			GrabEnded = true
			break
		end

		local EvasiveUsed = Target:GetAttribute("EvasiveUsed")
		if EvasiveUsed then
			Target:SetAttribute("EvasiveUsed", nil)
			GrabEnded = true
			ThrowInput = false
			break
		end

		if not Target or not Target.Parent then
			GrabEnded = true
			break
		end

		if not GrabWeld or not GrabWeld.Parent then
			GrabEnded = true
			break
		end

		task.wait(0.05)
	end

	if InputConnection then
		InputConnection:Disconnect()
	end

	DestroyGrabWeld(Character)

	if Target and Target.Parent then
		SetStateOnCharacter(Target, "Grabbed", false)
		Target:SetAttribute("GrabbedBy", nil)

		if TargetHumanoid then
			TargetHumanoid.AutoRotate = true
			TargetHumanoid.PlatformStand = false
		end
	end

	SetStateOnCharacter(Character, "Grabbing", false)
	Character:SetAttribute("GrabTarget", nil)

	if AttackerHumanoid then
		AttackerHumanoid.AutoRotate = true
	end

	Packets.GrabSync:Fire("GrabEnded", Character, Target)

	if ThrowInput and ThrowBranch then
		return { JumpToBranch = ThrowBranch }
	end

	if ReleaseBranch then
		return { JumpToBranch = ReleaseBranch }
	end

	return nil
end

return GrabHandler