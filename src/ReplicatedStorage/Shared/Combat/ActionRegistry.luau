--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local CombatTypes = require(Shared.Types.CombatTypes)

local TableUtil = Packages.TableUtil

type ActionDefinition = CombatTypes.ActionDefinition

local ActionRegistry = {}

local RegisteredActions: { [string]: ActionDefinition } = {}

function ActionRegistry.Register(ActionDefinition: ActionDefinition)
	if not ActionDefinition.ActionId then
		warn("[ActionRegistry] Action missing ActionId")
		return
	end

	if RegisteredActions[ActionDefinition.ActionId] then
		warn(string.format("[ActionRegistry] Action '%s' already registered", ActionDefinition.ActionId))
		return
	end

	RegisteredActions[ActionDefinition.ActionId] = table.freeze(TableUtil.Copy(ActionDefinition, true))
end

function ActionRegistry.Get(ActionId: string): ActionDefinition?
	return RegisteredActions[ActionId]
end

function ActionRegistry.Has(ActionId: string): boolean
	return RegisteredActions[ActionId] ~= nil
end

function ActionRegistry.GetAll(): { [string]: ActionDefinition }
	return table.clone(RegisteredActions)
end

function ActionRegistry.GetAllIds(): { string }
	local Ids: { string } = {}
	for ActionId in RegisteredActions do
		table.insert(Ids, ActionId)
	end
	table.sort(Ids)
	return Ids
end

function ActionRegistry.LoadFolder(Folder: Instance)
	for _, Child in Folder:GetChildren() do
		if not Child:IsA("ModuleScript") then
			continue
		end

		local Success, ActionData = pcall(require, Child)
		if not Success then
			warn(string.format("[ActionRegistry] Failed to load Action '%s': %s", Child.Name, tostring(ActionData)))
			continue
		end

		if type(ActionData) ~= "table" then
			warn(string.format("[ActionRegistry] Action '%s' must return a table", Child.Name))
			continue
		end

		ActionRegistry.Register(ActionData :: ActionDefinition)
	end
end

function ActionRegistry.Clear()
	table.clear(RegisteredActions)
end

return ActionRegistry