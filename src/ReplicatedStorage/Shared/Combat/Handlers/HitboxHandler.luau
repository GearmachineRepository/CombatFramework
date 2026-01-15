--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local Packets = require(Shared.Network.Packets)

local IsServer = RunService:IsServer()

local HitboxHandler = {}

local CharactersFolder = workspace:FindFirstChild("Characters")

local function DetectTargets(Origin: CFrame, Size: Vector3, Exclude: Model): { Model }
	local Results: { Model } = {}

	if not CharactersFolder then
		return Results
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

function HitboxHandler.Execute(Block: any, ExecutionContext: any): any?
	local OffsetX = Block.X or 0
	local OffsetY = Block.Y or 0
	local OffsetZ = Block.Z or 4
	local SizeX = Block.SizeX or 6
	local SizeY = Block.SizeY or 6
	local SizeZ = Block.SizeZ or 6

	local Stun = Block.Stun or 0
	local Damage = (Block.Damage or 0) * ExecutionContext.Properties.DamageMultiplier
	local AttackType = Block.AttackType or "Melee"
	local Blockable = Block.Blockable ~= false
	local Block360 = Block.Block360 or false
	local CancelEnemy = Block.CancelEnemy ~= false

	local Character = ExecutionContext.Entity.Character
	local RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not RootPart then
		return nil
	end

	local Offset = Vector3.new(OffsetX, OffsetY, -OffsetZ)
	local Size = Vector3.new(SizeX, SizeY, SizeZ)
	local Origin = RootPart.CFrame * CFrame.new(Offset)

	local DebugPart = Instance.new("Part")
	DebugPart.Name = "HitboxDebug"
	DebugPart.Size = Size
	DebugPart.CFrame = Origin
	DebugPart.Anchored = true
	DebugPart.CanCollide = false
	DebugPart.Transparency = 0.5
	DebugPart.Color = Color3.fromRGB(255, 0, 0)
	DebugPart.Parent = workspace
	task.delay(0.5, function()
		DebugPart:Destroy()
	end)

	local Targets = DetectTargets(Origin, Size, Character)

	if #Targets > 0 then
		for _, Target in Targets do
			ExecutionContext.RecordHit(Target, Damage)

			if not IsServer then
				Packets.HitCandidates:Fire(
					ExecutionContext.ActionDefinition.ActionId,
					Target.Name,
					Damage,
					Stun,
					AttackType,
					Blockable,
					Block360,
					CancelEnemy,
					tick()
				)
			end
		end
	else
		ExecutionContext.EventBus:Publish(Enums.Combat.Hitbox.Missed, {
			Entity = ExecutionContext.Entity,
			ActionId = ExecutionContext.ActionDefinition.ActionId,
		})
	end

	return nil
end

return HitboxHandler