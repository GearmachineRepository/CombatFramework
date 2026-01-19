--!strict

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local ChaseHandler = {}

local CharactersFolder = workspace:FindFirstChild("Characters")

local function FindNearestTarget(Character: Model, Range: number): Model?
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

	local NearestTarget: Model? = nil
	local NearestDistance = Range

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

		local Distance = (TargetRoot.Position - RootPart.Position).Magnitude
		if Distance < NearestDistance then
			NearestDistance = Distance
			NearestTarget = Child
		end
	end

	return NearestTarget
end

function ChaseHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if not IsServer then
		return nil
	end

	if Context.Mode ~= "Authoritative" then
		return nil
	end

	local Range = Block.Range or 25
	local Time = Block.Time or 0.2
	local OffsetX = Block.OffsetX or 0
	local OffsetY = Block.OffsetY or 0
	local OffsetZ = Block.OffsetZ or -3
	local RequiresTarget = Block.RequiresTarget ~= false

	local Character = Context.Entity.Character
	local RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not RootPart then
		return nil
	end

	local Target = Context.GetLastHitTarget()
	if not Target then
		Target = FindNearestTarget(Character, Range)
	end

	if not Target then
		if RequiresTarget then
			return { Cancel = true }
		end
		return nil
	end

	local TargetRoot = Target:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not TargetRoot then
		if RequiresTarget then
			return { Cancel = true }
		end
		return nil
	end

	local Distance = (TargetRoot.Position - RootPart.Position).Magnitude
	if Distance > Range then
		if RequiresTarget then
			return { Cancel = true }
		end
		return nil
	end

	local Offset = Vector3.new(OffsetX, OffsetY, OffsetZ)
	local TargetCFrame = TargetRoot.CFrame * CFrame.new(Offset)

	local LookAt = CFrame.lookAt(TargetCFrame.Position, TargetRoot.Position)
	local FinalCFrame = CFrame.new(LookAt.Position) * CFrame.Angles(0, select(2, LookAt:ToEulerAnglesYXZ()), 0)

	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	if Humanoid then
		Humanoid.AutoRotate = false
	end

	local TweenData = TweenInfo.new(Time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local Tween = TweenService:Create(RootPart, TweenData, { CFrame = FinalCFrame })

	local Completed = false

	Tween.Completed:Once(function()
		Completed = true
	end)

	Tween:Play()

	local StartTime = tick()
	while not Completed and (tick() - StartTime) < (Time + 0.1) do
		if Context.Canceled then
			Tween:Cancel()
			break
		end
		task.wait()
	end

	if Humanoid then
		Humanoid.AutoRotate = true
	end

	return nil
end

return ChaseHandler