--!strict

--[=[
	@class HookComponent

	Toggleable hook registration and cleanup for entity modifiers.

	Manages activation and deactivation of named hooks (buffs, debuffs,
	status effects, etc.) on an entity. Each hook can return a cleanup
	function from its OnActivate, which is called on unregister.
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local HookLoader = require(Server.HookUtil.HookLoader)

local HookComponent = {}

HookComponent.ComponentName = "Hooks"
HookComponent.Dependencies = {}

type HookInstance = {
	Register: (HookName: string) -> boolean,
	Unregister: (HookName: string) -> (),
	Has: (HookName: string) -> boolean,
	GetActive: () -> { string },
	Destroy: () -> (),
}

type ActiveHook = {
	Name: string,
	Cleanup: (() -> ())?,
}

--[=[
	Returns the Hooks component instance from the given entity, or nil.

	@param Entity any -- The entity to look up
	@return Type? -- The hooks component, or nil
]=]
function HookComponent.From(Entity: any): Type?
	return Entity:GetComponent("Hooks")
end

--[=[
	Creates a new HookComponent instance bound to the given entity.

	@param Entity any -- The entity this component belongs to
	@param _Context any -- Entity context (unused)
	@return HookInstance -- The component instance
]=]
function HookComponent.Create(Entity: any, _Context: any): HookInstance
	local ActiveHooks: { [string]: ActiveHook } = {}

	local function Register(HookName: string): boolean
		if ActiveHooks[HookName] then
			return false
		end

		local Hook = HookLoader.Get(HookName)
		if not Hook then
			warn(string.format("[HookComponent] Hook not found: '%s'", HookName))
			return false
		end

		local Success, CleanupOrError = pcall(Hook.OnActivate, Entity)
		if not Success then
			warn(string.format("[HookComponent] Hook '%s' activation failed: %s", HookName, tostring(CleanupOrError)))
			return false
		end

		ActiveHooks[HookName] = {
			Name = HookName,
			Cleanup = if type(CleanupOrError) == "function" then CleanupOrError else nil,
		}

		return true
	end

	local function Unregister(HookName: string)
		local ActiveHook = ActiveHooks[HookName]
		if not ActiveHook then
			return
		end

		if ActiveHook.Cleanup then
			local Success = pcall(function()
				ActiveHook.Cleanup()
			end)
			if not Success then
				warn(string.format("[HookComponent] Hook '%s' cleanup failed", HookName))
			end
		end

		if HookLoader then
			local Hook = HookLoader.Get(HookName)
			if Hook and Hook.OnDeactivate then
				local Success = pcall(Hook.OnDeactivate, Entity)
				if not Success then
					warn(string.format("[HookComponent] Hook '%s' deactivation failed", HookName))
				end
			end
		end

		ActiveHooks[HookName] = nil
	end

	local function Has(HookName: string): boolean
		return ActiveHooks[HookName] ~= nil
	end

	local function GetActive(): { string }
		local Names = {}
		for Name in ActiveHooks do
			table.insert(Names, Name)
		end
		return Names
	end

	local function Destroy()
		for HookName in pairs(table.clone(ActiveHooks)) do
			Unregister(HookName)
		end
		table.clear(ActiveHooks)
	end

	return {
		Register = Register,
		Unregister = Unregister,
		Has = Has,
		GetActive = GetActive,
		Destroy = Destroy,
	}
end

export type Type = typeof(HookComponent.Create(nil :: any, nil :: any))

return HookComponent