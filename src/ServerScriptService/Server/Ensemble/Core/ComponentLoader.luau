--!strict

local Types = require(script.Parent.Parent.Types)

type ComponentDefinition = Types.ComponentDefinition

type LoadedComponent = {
	Definition: ComponentDefinition,
	Module: ModuleScript,
}

local ComponentLoader = {}

local LoadedComponents: { [string]: LoadedComponent } = {}
local DependencyGraph: { [string]: { string } } = {}

function ComponentLoader.ValidateDefinition(ModuleName: string, Definition: any): (boolean, string?)
	if not ModuleName then
		return false, "Module must have a name"
	end

	if type(Definition) ~= "table" then
		return false, "Must return a table"
	end

	if type(Definition.ComponentName) ~= "string" then
		return false, "ComponentName must be a string"
	end

	if type(Definition.Create) ~= "function" then
		return false, "Create must be a function"
	end

	if Definition.Dependencies ~= nil and type(Definition.Dependencies) ~= "table" then
		return false, "Dependencies must be an array"
	end

	if Definition.UpdateRate ~= nil and type(Definition.UpdateRate) ~= "number" then
		return false, "UpdateRate must be a number"
	end

	return true, nil
end

function ComponentLoader.LoadComponent(ModuleScript: ModuleScript): (LoadedComponent?, string?)
	local Success, Result = pcall(require, ModuleScript)
	if not Success then
		return nil, string.format("Failed to require: %s", tostring(Result))
	end

	local IsValid, ValidationError = ComponentLoader.ValidateDefinition(ModuleScript.Name, Result)
	if not IsValid then
		return nil, ValidationError
	end

	return {
		Definition = Result :: ComponentDefinition,
		Module = ModuleScript,
	}, nil
end

function ComponentLoader.ValidateDependencies()
	local Available: { [string]: boolean } = {}
	for ComponentName in LoadedComponents do
		Available[ComponentName] = true
	end

	for ComponentName, Dependencies in DependencyGraph do
		for _, Dependency in Dependencies do
			if not Available[Dependency] then
				error(string.format(
					"%s Component '%s' depends on '%s' which does not exist",
					Types.EngineName,
					ComponentName,
					Dependency
				))
			end
		end
	end

	for ComponentName in LoadedComponents do
		local Visited: { [string]: boolean } = {}
		local Stack: { [string]: boolean } = {}

		local function HasCycle(Name: string): boolean
			if Stack[Name] then
				return true
			end
			if Visited[Name] then
				return false
			end

			Visited[Name] = true
			Stack[Name] = true

			local Dependencies = DependencyGraph[Name] or {}
			for _, Dependency in pairs(Dependencies) do
				if HasCycle(Dependency) then
					return true
				end
			end

			Stack[Name] = false
			return false
		end

		if HasCycle(ComponentName) then
			error(string.format("%s Circular dependency involving '%s'", Types.EngineName, ComponentName))
		end
	end
end

function ComponentLoader.Configure(Folder: Instance)
	table.clear(LoadedComponents)
	table.clear(DependencyGraph)

	for _, Child in Folder:GetChildren() do
		if not Child:IsA("ModuleScript") then
			continue
		end

		local Loaded, ErrorMessage = ComponentLoader.LoadComponent(Child)
		if not Loaded then
			error(string.format("%s Component '%s' failed: %s", Types.EngineName, Child.Name, ErrorMessage or "Unknown"))
		end

		local ComponentName = Loaded.Definition.ComponentName
		if LoadedComponents[ComponentName] then
			error(string.format("%s Duplicate component: '%s'", Types.EngineName, ComponentName))
		end

		LoadedComponents[ComponentName] = Loaded
		DependencyGraph[ComponentName] = Loaded.Definition.Dependencies or {}
	end

	ComponentLoader.ValidateDependencies()
end

function ComponentLoader.Get(ComponentName: string): LoadedComponent?
	return LoadedComponents[ComponentName]
end

function ComponentLoader.Has(ComponentName: string): boolean
	return LoadedComponents[ComponentName] ~= nil
end

function ComponentLoader.GetDependencies(ComponentName: string): { string }
	return DependencyGraph[ComponentName] or {}
end

function ComponentLoader.GetAllNames(): { string }
	local Names = {}
	for Name in LoadedComponents do
		table.insert(Names, Name)
	end
	return Names
end

function ComponentLoader.GetWithUpdates(): { { Name: string, Rate: number } }
	local Result = {}
	for Name, Loaded in LoadedComponents do
		if Loaded.Definition.UpdateRate then
			table.insert(Result, {
				Name = Name,
				Rate = Loaded.Definition.UpdateRate,
			})
		end
	end
	return Result
end

function ComponentLoader.ResolveDependencyOrder(ComponentNames: { string }): { string }
	local Resolved: { string } = {}
	local ResolvedSet: { [string]: boolean } = {}
	local Visiting: { [string]: boolean } = {}

	local function Visit(Name: string)
		if ResolvedSet[Name] or Visiting[Name] then
			return
		end

		Visiting[Name] = true

		local Dependencies = DependencyGraph[Name] or {}
		for _, Dependency in pairs(Dependencies) do
			if LoadedComponents[Dependency] then
				Visit(Dependency)
			end
		end

		Visiting[Name] = false
		ResolvedSet[Name] = true
		table.insert(Resolved, Name)
	end

	for _, Name in pairs(ComponentNames) do
		if LoadedComponents[Name] then
			Visit(Name)
		end
	end

	return Resolved
end

return ComponentLoader