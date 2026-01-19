--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Enums = require(Shared.Enums)
local CombatTypes = require(Shared.Types.CombatTypes)
local Packets = require(Shared.Network.Packets)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local HitboxHandler = {}

local CharactersFolder = workspace:FindFirstChild("Characters")

local DEFAULT_JUGGLE_DECAY = 0.85
local GROUND_CHECK_DISTANCE = 3.5

local GroundRayParams = RaycastParams.new()
GroundRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function IsGrounded(Character: Model): boolean
	local RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not RootPart then
		return true
	end

	GroundRayParams.FilterDescendantsInstances = { Character }

	local Origin = RootPart.Position + Vector3.new(0, 0.5, 0)
	local Direction = Vector3.new(0, -GROUND_CHECK_DISTANCE, 0)

	local Result = workspace:Raycast(Origin, Direction, GroundRayParams)
	return Result ~= nil
end

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

local function ApplyLaunchVelocity(
	AttackerCharacter: Model,
	TargetCharacter: Model,
	LaunchY: number?,
	LaunchZ: number?,
	KnockbackMultiplier: number
)
	local TargetRoot = TargetCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not TargetRoot then
		return
	end

	local AttackerRoot = AttackerCharacter:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not AttackerRoot then
		return
	end

	local LaunchVelY = (LaunchY or 0) * KnockbackMultiplier
	local LaunchVelZ = (LaunchZ or 0) * KnockbackMultiplier

	if LaunchVelY == 0 and LaunchVelZ == 0 then
		return
	end

	local AttackerLook = AttackerRoot.CFrame.LookVector
	local UpVector = Vector3.new(0, 1, 0)

	local WorldVelocity = (AttackerLook * LaunchVelZ) + (UpVector * LaunchVelY)

	local BodyVelocity = Instance.new("BodyVelocity")
	BodyVelocity.Name = "LaunchVelocity"
	BodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	BodyVelocity.Velocity = WorldVelocity
	BodyVelocity.Parent = TargetRoot

	task.delay(0.15, function()
		if BodyVelocity and BodyVelocity.Parent then
			BodyVelocity:Destroy()
		end
	end)
end

local function ApplyStun(TargetCharacter: Model, StunDuration: number)
	if StunDuration <= 0 then
		return
	end

	SetStateOnCharacter(TargetCharacter, "Stunned", true)

	task.delay(StunDuration, function()
		if TargetCharacter and TargetCharacter.Parent then
			SetStateOnCharacter(TargetCharacter, "Stunned", false)
		end
	end)
end

local function ApplyDamage(TargetCharacter: Model, Damage: number)
	local Humanoid = TargetCharacter:FindFirstChildOfClass("Humanoid")
	if Humanoid and Humanoid.Health > 0 then
		Humanoid:TakeDamage(Damage)
	end
end

function HitboxHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if not IsServer then
		return nil
	end

	if Context.Mode ~= "Authoritative" then
		return nil
	end

	local OffsetX = Block.X or 0
	local OffsetY = Block.Y or 0
	local OffsetZ = Block.Z or 4
	local SizeX = Block.SizeX or 6
	local SizeY = Block.SizeY or 6
	local SizeZ = Block.SizeZ or 6

	local BaseDamage = Block.Damage or 0
	local BaseStun = Block.Stun or 0
	local AttackType = Block.AttackType or "Melee"
	local Blockable = Block.Blockable ~= false
	local Block360 = Block.Block360 or false
	local CancelEnemy = Block.CancelEnemy ~= false
	--local RagdollBypass = Block.RagdollBypass or false
	local Unblockable = Block.Unblockable or false

	local LaunchY = Block.LaunchY
	local LaunchZ = Block.LaunchZ
	local GroundBounce = Block.GroundBounce or false
	local JuggleDecay = Block.JuggleDecay or DEFAULT_JUGGLE_DECAY

	local DamageMultiplier = Context.Properties.DamageMultiplier or 1
	local KnockbackMultiplier = Context.Properties.KnockbackMultiplier or 1

	local Character = Context.Entity.Character
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

	if #Targets == 0 then
		Context.EventBus:Publish(Enums.Combat.Hitbox.Missed, {
			Entity = Context.Entity,
			ActionId = Context.ActionDefinition.ActionId,
		})
		return nil
	end

	for _, Target in Targets do
		local TargetHumanoid = Target:FindFirstChildOfClass("Humanoid")
		if not TargetHumanoid or TargetHumanoid.Health <= 0 then
			continue
		end

		local Invincible = GetStateFromCharacter(Target, "Invincible")
		if Invincible then
			continue
		end

		local IsTargetStunned = GetStateFromCharacter(Target, "Stunned")
		local IsTargetAirborne = not IsGrounded(Target)
		local IsJuggle = IsTargetAirborne and IsTargetStunned

		local JuggleCountAttribute = Target:GetAttribute("JuggleCount") :: number?
		local JuggleCount =  JuggleCountAttribute or 0

		local FinalDamage = BaseDamage * DamageMultiplier
		local FinalStun = BaseStun

		if IsJuggle then
			JuggleCount += 1
			Target:SetAttribute("JuggleCount", JuggleCount)

			local DecayMultiplier = JuggleDecay ^ JuggleCount
			FinalDamage = FinalDamage * DecayMultiplier
			FinalStun = FinalStun * DecayMultiplier
		else
			Target:SetAttribute("JuggleCount", 0)
		end

		local IsBlocking = GetStateFromCharacter(Target, "Blocking")
		local WasBlocked = false

		if IsBlocking and Blockable and not Unblockable then
			local TargetRoot = Target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if TargetRoot then
				local ToAttacker = (RootPart.Position - TargetRoot.Position).Unit
				local TargetLook = TargetRoot.CFrame.LookVector
				local DotProduct = ToAttacker:Dot(TargetLook)

				if Block360 or DotProduct > 0.3 then
					WasBlocked = true
					FinalDamage = Block.BlockDamage or 0
					FinalStun = 0

					Context.EventBus:Publish(Enums.Combat.Hitbox.Blocked, {
						Entity = Context.Entity,
						Target = Target,
						ActionId = Context.ActionDefinition.ActionId,
					})
				end
			end
		end

		if not WasBlocked then
			ApplyDamage(Target, FinalDamage)
			ApplyStun(Target, FinalStun)

			if LaunchY or LaunchZ then
				ApplyLaunchVelocity(Character, Target, LaunchY, LaunchZ, KnockbackMultiplier)
			end

			if GroundBounce then
				Target:SetAttribute("GroundBounce", true)
				task.delay(1, function()
					if Target and Target.Parent then
						Target:SetAttribute("GroundBounce", nil)
					end
				end)
			end

			if CancelEnemy then
				local TargetAction = Target:GetAttribute("ActiveAction")
				if TargetAction then
					Target:SetAttribute("ActionCanceled", true)
				end
			end

			Context.RecordHit(Target, FinalDamage)

			Context.EventBus:Publish(Enums.Combat.Hitbox.Hit, {
				Entity = Context.Entity,
				Target = Target,
				Damage = FinalDamage,
				ActionId = Context.ActionDefinition.ActionId,
			})

			local TargetRoot = Target:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not TargetRoot then return end
			local HitPosition = TargetRoot and TargetRoot.Position or Origin.Position

			if Context.Entity.Player then
				Packets.HitConfirmed:FireClient(
					Context.Entity.Player,
					Character,
					Target,
					FinalDamage,
					HitPosition,
					AttackType
				)
			end

			Packets.PlayVFX:Fire("HitImpact", Target, HitPosition, FinalDamage, AttackType)
		end
	end

	return nil
end

return HitboxHandler