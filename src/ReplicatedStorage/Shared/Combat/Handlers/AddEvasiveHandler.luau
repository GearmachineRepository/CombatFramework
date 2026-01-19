--!strict

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local CombatTypes = require(Shared.Types.CombatTypes)

type Block = CombatTypes.Block
type ExecutionContext = CombatTypes.ExecutionContext
type HandlerResult = CombatTypes.HandlerResult

local IsServer = RunService:IsServer()

local EVASIVE_CAP = 50

local AddEvasiveHandler = {}

function AddEvasiveHandler.Execute(Block: Block, Context: ExecutionContext): HandlerResult?
	if not IsServer then
		return nil
	end

	if Context.Mode ~= "Authoritative" then
		return nil
	end

	local Amount = Block.Amount or 5

	local Character = Context.Entity.Character
	if not Character then
		return nil
	end

	local CurrentEvasive = Character:GetAttribute("Stat_Evasive") or 0
	local NewEvasive = math.clamp(CurrentEvasive + Amount, 0, EVASIVE_CAP)

	Character:SetAttribute("Stat_Evasive", NewEvasive)

	return nil
end

return AddEvasiveHandler