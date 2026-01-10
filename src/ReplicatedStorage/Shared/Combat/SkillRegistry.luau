--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local CombatTypes = require(Shared.Types.CombatTypes)

local TableUtil = Packages.TableUtil

type SkillDefinition = CombatTypes.SkillDefinition

local SkillRegistry = {}

local RegisteredSkills: { [string]: SkillDefinition } = {}

function SkillRegistry.Register(SkillDefinition: SkillDefinition)
	if not SkillDefinition.SkillId then
		warn("[SkillRegistry] Skill missing SkillId")
		return
	end

	if RegisteredSkills[SkillDefinition.SkillId] then
		warn(string.format("[SkillRegistry] Skill '%s' already registered", SkillDefinition.SkillId))
		return
	end

	RegisteredSkills[SkillDefinition.SkillId] = table.freeze(TableUtil.Copy(SkillDefinition, true))
end

function SkillRegistry.Get(SkillId: string): SkillDefinition?
	return RegisteredSkills[SkillId]
end

function SkillRegistry.Has(SkillId: string): boolean
	return RegisteredSkills[SkillId] ~= nil
end

function SkillRegistry.GetAll(): { [string]: SkillDefinition }
	return table.clone(RegisteredSkills)
end

function SkillRegistry.GetAllIds(): { string }
	local Ids: { string } = {}
	for SkillId in RegisteredSkills do
		table.insert(Ids, SkillId)
	end
	table.sort(Ids)
	return Ids
end

function SkillRegistry.LoadFolder(Folder: Instance)
	for _, Child in Folder:GetChildren() do
		if not Child:IsA("ModuleScript") then
			continue
		end

		local Success, SkillData = pcall(require, Child)
		if not Success then
			warn(string.format("[SkillRegistry] Failed to load skill '%s': %s", Child.Name, tostring(SkillData)))
			continue
		end

		if type(SkillData) ~= "table" then
			warn(string.format("[SkillRegistry] Skill '%s' must return a table", Child.Name))
			continue
		end

		SkillRegistry.Register(SkillData :: SkillDefinition)
	end
end

function SkillRegistry.Clear()
	table.clear(RegisteredSkills)
end

return SkillRegistry