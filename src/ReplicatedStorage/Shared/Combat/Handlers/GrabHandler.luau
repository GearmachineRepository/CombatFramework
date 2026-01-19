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

local function FindGrabTarget(Character: Model, Range: number): Model?
	if not CharactersFolder then
		CharactersFolder = workspace:FindFirstChild("Characters")
		if not CharactersFolder then
			return nil
		end
	end

	local RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not RootPart then
		return nil
	end

	local LookVector = RootPart.CFrame.LookVector
	local NearestTarget: Model? = nil
	local BestScore = -math.huge

	for _, Child in CharactersFolder:GetChildren() do
		if Child == Character then
			continue
		end

		if not Child:IsA("Model") then
			continue
		end

		local TargetHumanoid = Child:FindFirstChildOfClass("Humanoid")
		if not TargetHumanoid or TargetHumanoid.Health <= 0 then
			continue
		end

		local TargetRoot = Child:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not TargetRoot then
			continue
		end

		local ToTarget = (TargetRoot.Position - RootPart.Position)
		local Distance = ToTarget.Magnitude

		if Distance > Range then
			continue
		end

		local Blocked = GetStateFromCharacter(Child, "Blocking")
		if Blocked then
			continue
		end

		local Grabbed = GetStateFromCharacter(Child, "Grabbed")
		if Grabbed then
			continue
		end

		local Invincible = GetStateFromCharacter(Child, "Invincible")
		if Invincible then
			continue
		end

		local DirectionScore = LookVector:Dot(ToTarget.Unit)
		local DistanceScore = 1 - (Distance / Range)
		local Score = DirectionScore * 0.7 + DistanceScore * 0.3

		if Score > BestScore then
			BestScore = Score
			NearestTarget = Child
		end
	end

	if BestScore < 0.3 then
		return nil
	end

	return NearestTarget
end

local function PositionGrabbedTarget(
	AttackerCharacter: Model,
	TargetCharacter: Model,
	OffsetX: number,
	OffsetY: number,
	OffsetZ: number
)
	local AttackerRoot = AttackerCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	local TargetRoot = TargetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not AttackerRoot or not TargetRoot then
		return
	end

	local Offset = Vector3.new(OffsetX, OffsetY, OffsetZ)
	local TargetPosition = AttackerRoot.CFrame * CFrame.new(Offset)

	local LookAt = CFrame.lookAt(TargetPosition.Position, AttackerRoot.Position)

	TargetRoot.CFrame = LookAt
end

function GrabHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if not IsServer then
		return nil
	end

	if Context.Mode ~= "Authoritative" then
		return nil
	end

	local Range = Block.Range or 5
	local Duration = Block.Duration or 2
	local OffsetX = Block.OffsetX or 0
	local OffsetY = Block.OffsetY or 0
	local OffsetZ = Block.OffsetZ or -3
	local AttackerAnimation = Block.AttackerAnimation
	local TargetAnimation = Block.TargetAnimation
	local ThrowBranch = Block.ThrowBranch
	local ReleaseBranch = Block.ReleaseBranch
	local MissBranch = Block.MissBranch

	local Character = Context.Entity.Character
	local Player = Context.Entity.Player

	local Target = FindGrabTarget(Character, Range)

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

	local PositionConnection: RBXScriptConnection? = nil
	PositionConnection = RunService.Heartbeat:Connect(function()
		if not Target or not Target.Parent then
			if PositionConnection then
				PositionConnection:Disconnect()
			end
			return
		end

		if not GetStateFromCharacter(Target, "Grabbed") then
			if PositionConnection then
				PositionConnection:Disconnect()
			end
			return
		end

		PositionGrabbedTarget(Character, Target, OffsetX, OffsetY, OffsetZ)
	end)

	local ThrowInput = false
	local GrabEnded = false
	local StartTime = tick()

	local InputConnection: RBXScriptConnection? = nil
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

		task.wait(0.05)
	end

	if PositionConnection then
		PositionConnection:Disconnect()
	end

	if InputConnection then
		InputConnection:Disconnect()
	end

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