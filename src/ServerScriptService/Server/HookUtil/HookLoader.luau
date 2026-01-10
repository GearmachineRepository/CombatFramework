--!strict

local HookLoader = {}

export type HookDefinition = {
	HookName: string,
	Description: string?,
	OnActivate: (Entity: any) -> (() -> ())?,
	OnDeactivate: ((Entity: any) -> ())?,
}

local LoadedHooks: { [string]: HookDefinition } = {}

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

function HookLoader.Get(HookName: string): HookDefinition?
	return LoadedHooks[HookName]
end

function HookLoader.Has(HookName: string): boolean
	return LoadedHooks[HookName] ~= nil
end

function HookLoader.GetAllNames(): { string }
	local Names = {}
	for Name in LoadedHooks do
		table.insert(Names, Name)
	end
	return Names
end

function HookLoader.GetDescription(HookName: string): string?
	local Hook = LoadedHooks[HookName]
	return if Hook then Hook.Description else nil
end

return HookLoader