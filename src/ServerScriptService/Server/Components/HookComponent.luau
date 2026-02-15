--!strict

--[=[
	@class HookComponent

	Toggleable hook registration and cleanup for entity modifiers.

	Manages activation and deactivation of named hooks (buffs, debuffs,
	status effects, etc.) on an entity. Each hook can return a cleanup
	function from its OnActivate, which is called on unregister.

	```lua
	local Hooks = HookComponent.From(Entity)
	if Hooks then
		Hooks:Register("SpeedBoost")
		Hooks:Unregister("SpeedBoost")
	end
	```
]=]

local ServerScriptService = game:GetService("ServerScriptService")
local Server = ServerScriptService:WaitForChild("Server")
local HookLoader = require(Server.HookUtil.HookLoader)

local HookComponent = {}
HookComponent.ComponentName = "Hooks"
HookComponent.Dependencies = {}

local HookInstance = {}
HookInstance.__index = HookInstance

type ActiveHook = {
	Name: string,
	Cleanup: (() -> ())?,
}

type ActiveHooks = { [string]: ActiveHook }

type HookStorage = {
	_ActiveHooks: ActiveHooks,
	_Entity: any,
}

type HookInstanceInternal = typeof(setmetatable({} :: HookStorage, {} :: typeof(HookInstance)))

--[=[
	Returns the HookComponent attached to the given entity, or nil.

	@param EntityInstance any -- The entity to look up
	@return HookInstance? -- The hooks instance, or nil
]=]
function HookComponent.From(EntityInstance: any): HookInstanceInternal?
	return EntityInstance:GetComponent("Hooks")
end

--[=[
	Creates a new HookComponent instance bound to the given entity.

	@param Entity any -- The entity this component belongs to
	@param _Context any -- Entity context (unused)
	@return HookInstance -- The component instance
]=]
function HookComponent.Create(Entity: any, _Context: any): HookInstanceInternal
	local Storage: HookStorage = {
		_ActiveHooks = {},
		_Entity = Entity,
	}

	return setmetatable(Storage, HookInstance)
end

--[=[
	Activates a named hook on this entity. Returns false if the hook
	is already active or if the hook definition is not found.

	@param self HookInstance
	@param HookName string -- The hook to activate
	@return boolean -- True if activation succeeded
]=]
function HookInstance:Register(HookName: string): boolean
	if self._ActiveHooks[HookName] then
		return false
	end

	local Hook = HookLoader.Get(HookName)
	if not Hook then
		warn(string.format("[HookComponent] Hook not found: '%s'", HookName))
		return false
	end

	local Success, CleanupOrError = pcall(Hook.OnActivate, self._Entity)
	if not Success then
		warn(string.format("[HookComponent] Hook '%s' activation failed: %s", HookName, tostring(CleanupOrError)))
		return false
	end

	self._ActiveHooks[HookName] = {
		Name = HookName,
		Cleanup = if type(CleanupOrError) == "function" then CleanupOrError else nil,
	}

	return true
end

--[=[
	Deactivates a named hook, running its cleanup and OnDeactivate if present.

	@param self HookInstance
	@param HookName string -- The hook to deactivate
]=]
function HookInstance:Unregister(HookName: string)
	local ActiveHook = self._ActiveHooks[HookName] :: ActiveHook?
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

	local Hook = HookLoader.Get(HookName)
	if Hook and Hook.OnDeactivate then
		local Success = pcall(Hook.OnDeactivate, self._Entity)
		if not Success then
			warn(string.format("[HookComponent] Hook '%s' deactivation failed", HookName))
		end
	end

	self._ActiveHooks[HookName] = nil
end

--[=[
	Returns whether a hook is currently active.

	@param self HookInstance
	@param HookName string -- The hook to check
	@return boolean -- True if the hook is active
]=]
function HookInstance:Has(HookName: string): boolean
	return self._ActiveHooks[HookName] ~= nil
end

--[=[
	Returns an array of all currently active hook names.

	@param self HookInstance
	@return { string } -- Array of active hook names
]=]
function HookInstance:GetActive(): { string }
	local Names = {}
	for Name in self._ActiveHooks :: ActiveHooks do
		table.insert(Names, Name)
	end
	return Names
end

--[=[
	Destroys the component, unregistering all active hooks.

	@param self HookInstance
]=]
function HookInstance:Destroy()
	for HookName in pairs(table.clone(self._ActiveHooks)) do
		self:Unregister(HookName)
	end
	table.clear(self._ActiveHooks)
end

export type Type = typeof(setmetatable({} :: HookStorage, HookInstance))

return HookComponent