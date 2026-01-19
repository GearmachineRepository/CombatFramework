--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type ExecutionEntity = CombatTypes.ExecutionEntity
type ActionDefinition = CombatTypes.ActionDefinition
type ActionConditions = CombatTypes.ActionConditions

local ActionValidator = {}

local GROUND_CHECK_DISTANCE = 4
local GROUND_CHECK_OFFSET = Vector3.new(0, 0.5, 0)

local GroundRayParams = RaycastParams.new()
GroundRayParams.FilterType = Enum.RaycastFilterType.Exclude

local function IsGrounded(Character: Model): boolean
	local RootPart = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not RootPart then
		return true
	end

	GroundRayParams.FilterDescendantsInstances = { Character }

	local Origin = RootPart.Position + GROUND_CHECK_OFFSET
	local Direction = Vector3.new(0, -GROUND_CHECK_DISTANCE, 0)

	local Result = workspace:Raycast(Origin, Direction, GroundRayParams)

	return Result ~= nil
end

local function IsAirborne(Character: Model): boolean
	return not IsGrounded(Character)
end

local function GetStateFromCharacter(Character: Model, StateName: string): boolean
	local AttributeName = "State_" .. StateName
	local Value = Character:GetAttribute(AttributeName)
	return Value == true
end

local function GetStatFromCharacter(Character: Model, StatName: string): number
	local AttributeName = "Stat_" .. StatName
	local Value = Character:GetAttribute(AttributeName)
	if type(Value) == "number" then
		return Value
	end
	return 0
end

function ActionValidator.CanActivate(Entity: ExecutionEntity, ActionDefinition: ActionDefinition): (boolean, string?)
	local Character = Entity.Character
	local Humanoid = Entity.Humanoid

	if not Character or not Humanoid then
		return false, "NoCharacter"
	end

	if Humanoid.Health <= 0 then
		return false, "Dead"
	end

	local Conditions = ActionDefinition.Conditions
	if not Conditions then
		return true, nil
	end

	if Conditions.OnAir ~= nil then
		local Airborne = IsAirborne(Character)
		if Conditions.OnAir == true and not Airborne then
			return false, "MustBeAirborne"
		end
		if Conditions.OnAir == false and Airborne then
			return false, "MustBeGrounded"
		end
	end

	if Conditions.IsStunned ~= nil then
		local Stunned = GetStateFromCharacter(Character, "Stunned")
		if Conditions.IsStunned == false and Stunned then
			return false, "IsStunned"
		end
		if Conditions.IsStunned == true and not Stunned then
			return false, "NotStunned"
		end
	end

	if Conditions.IsBlocking ~= nil then
		local Blocking = GetStateFromCharacter(Character, "Blocking")
		if Conditions.IsBlocking == false and Blocking then
			return false, "IsBlocking"
		end
		if Conditions.IsBlocking == true and not Blocking then
			return false, "NotBlocking"
		end
	end

	if Conditions.IsGrabbed ~= nil then
		local Grabbed = GetStateFromCharacter(Character, "Grabbed")
		if Conditions.IsGrabbed == false and Grabbed then
			return false, "IsGrabbed"
		end
		if Conditions.IsGrabbed == true and not Grabbed then
			return false, "NotGrabbed"
		end
	end

	if Conditions.HasEvasive ~= nil then
		local Evasive = GetStatFromCharacter(Character, "Evasive")
		local HasEvasive = Evasive > 0
		if Conditions.HasEvasive == true and not HasEvasive then
			return false, "NoEvasive"
		end
		if Conditions.HasEvasive == false and HasEvasive then
			return false, "HasEvasive"
		end
	end

	if Conditions.MinHealth ~= nil then
		local HealthPercent = Humanoid.Health / Humanoid.MaxHealth
		if HealthPercent < Conditions.MinHealth then
			return false, "HealthTooLow"
		end
	end

	if Conditions.MaxHealth ~= nil then
		local HealthPercent = Humanoid.Health / Humanoid.MaxHealth
		if HealthPercent > Conditions.MaxHealth then
			return false, "HealthTooHigh"
		end
	end

	return true, nil
end

function ActionValidator.IsGrounded(Character: Model): boolean
	return IsGrounded(Character)
end

function ActionValidator.IsAirborne(Character: Model): boolean
	return IsAirborne(Character)
end

function ActionValidator.GetState(Character: Model, StateName: string): boolean
	return GetStateFromCharacter(Character, StateName)
end

function ActionValidator.GetStat(Character: Model, StatName: string): number
	return GetStatFromCharacter(Character, StatName)
end

function ActionValidator.CanBeHit(TargetCharacter: Model): boolean
	local Humanoid = TargetCharacter:FindFirstChildOfClass("Humanoid")
	if not Humanoid or Humanoid.Health <= 0 then
		return false
	end

	local Invincible = GetStateFromCharacter(TargetCharacter, "Invincible")
	if Invincible then
		return false
	end

	return true
end

function ActionValidator.CanBeGrabbed(TargetCharacter: Model): boolean
	if not ActionValidator.CanBeHit(TargetCharacter) then
		return false
	end

	local Grabbed = GetStateFromCharacter(TargetCharacter, "Grabbed")
	if Grabbed then
		return false
	end

	local Blocking = GetStateFromCharacter(TargetCharacter, "Blocking")
	if Blocking then
		return false
	end

	return true
end

function ActionValidator.IsJuggleable(TargetCharacter: Model): boolean
	local Airborne = IsAirborne(TargetCharacter)
	local Stunned = GetStateFromCharacter(TargetCharacter, "Stunned")
	return Airborne and Stunned
end

return ActionValidator