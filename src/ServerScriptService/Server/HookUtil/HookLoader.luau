--!strict

--[=[
	@class HookLoader

	Loads and manages hook definitions for temporary entity modifiers
	such as buffs, debuffs, status effects, passives, and talents.

	Hooks are validated and registered during `Configure`, then
	accessed by name at runtime.
]=]

local HookLoader = {}

export type HookDefinition = {
	HookName: string,
	Description: string?,
	OnActivate: (Entity: any) -> (() -> ())?,
	OnDeactivate: ((Entity: any) -> ())?,
}

local LoadedHooks: { [string]: HookDefinition } = {}

--[=[
	Validates that a hook definition has the required shape.

	@param ModuleName string -- The name of the ModuleScript being validated
	@param Definition any -- The value returned by requiring the module
	@return boolean -- Whether the definition is valid
	@return string? -- An error message if validation failed
]=]
function HookLoader.ValidateDefinition(ModuleName: string, Definition: any): (boolean, string?)
	if not ModuleName then
		return false, "Hook module must have a name"
	end

	if type(Definition) ~= "table" then
		return false, "Must return a table"
	end

	if type(Definition.HookName) ~= "string" then
		return false, "HookName must be a string"
	end

	if type(Definition.OnActivate) ~= "function" then
		return false, "OnActivate must be a function"
	end

	if Definition.OnDeactivate ~= nil and type(Definition.OnDeactivate) ~= "function" then
		return false, "OnDeactivate must be a function if provided"
	end

	return true, nil
end

--[=[
	Requires and validates a single hook ModuleScript.

	@param ModuleScript ModuleScript -- The hook module to load
	@return HookDefinition? -- The validated hook definition, or nil on failure
	@return string? -- An error message if loading failed
]=]
function HookLoader.LoadHook(ModuleScript: ModuleScript): (HookDefinition?, string?)
	local Success, Result = pcall(require, ModuleScript)
	if not Success then
		return nil, string.format("Failed to require: %s", tostring(Result))
	end

	local IsValid, ValidationError = HookLoader.ValidateDefinition(ModuleScript.Name, Result)
	if not IsValid then
		return nil, ValidationError
	end

	return Result :: HookDefinition, nil
end

--[=[
	Loads all hook ModuleScripts from a folder and validates them.

	@param Folder Instance -- The folder containing hook ModuleScripts
]=]
function HookLoader.Configure(Folder: Instance)
	table.clear(LoadedHooks)

	for _, Child in Folder:GetChildren() do
		if not Child:IsA("ModuleScript") then
			continue
		end

		local Hook, ErrorMessage = HookLoader.LoadHook(Child)
		if not Hook then
			error(string.format("[Ensemble] Hook '%s' failed: %s", Child.Name, ErrorMessage or "Unknown"))
		end

		if LoadedHooks[Hook.HookName] then
			error(string.format("[Ensemble] Duplicate hook: '%s'", Hook.HookName))
		end

		LoadedHooks[Hook.HookName] = Hook
	end
end

--[=[
	Returns the hook definition for a given name.

	@param HookName string -- The hook name to look up
	@return HookDefinition? -- The hook definition, or nil if not found
]=]
function HookLoader.Get(HookName: string): HookDefinition?
	return LoadedHooks[HookName]
end

--[=[
	Returns whether a hook with the given name has been loaded.

	@param HookName string -- The hook name to check
	@return boolean -- True if the hook exists
]=]
function HookLoader.Has(HookName: string): boolean
	return LoadedHooks[HookName] ~= nil
end

--[=[
	Returns an array of all loaded hook names.

	@return { string } -- Array of hook names
]=]
function HookLoader.GetAllNames(): { string }
	local Names = {}
	for Name in LoadedHooks do
		table.insert(Names, Name)
	end
	return Names
end

--[=[
	Returns the description for a given hook, if one was provided.

	@param HookName string -- The hook name
	@return string? -- The description, or nil
]=]
function HookLoader.GetDescription(HookName: string): string?
	local Hook = LoadedHooks[HookName]
	return if Hook then Hook.Description else nil
end

return HookLoader