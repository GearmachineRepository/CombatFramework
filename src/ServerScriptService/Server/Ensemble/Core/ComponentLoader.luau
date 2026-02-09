--!strict

--[=[
	@class ComponentLoader

	Loads, validates, and manages component definitions for Ensemble.

	Handles requiring component ModuleScripts, validating their shape,
	building a dependency graph, and resolving initialization order.
]=]

local Types = require(script.Parent.Parent.Types)

type ComponentDefinition = Types.ComponentDefinition

type LoadedComponent = {
	Definition: ComponentDefinition,
	Module: ModuleScript,
}

local ComponentLoader = {}

local LoadedComponents: { [string]: LoadedComponent } = {}
local DependencyGraph: { [string]: { string } } = {}

--[=[
	Validates that a component definition has the required shape.

	@param ModuleName string -- The name of the ModuleScript being validated
	@param Definition any -- The value returned by requiring the module
	@return boolean -- Whether the definition is valid
	@return string? -- An error message if validation failed
]=]
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

--[=[
	Requires and validates a single component ModuleScript.

	@param ModuleScript ModuleScript -- The component module to load
	@return LoadedComponent? -- The loaded component, or nil on failure
	@return string? -- An error message if loading failed
]=]
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

--[=[
	Validates all dependencies exist and that no circular dependencies are present.

	Uses a single-pass three-state traversal (unvisited, visiting, visited)
	to detect cycles across the entire dependency graph at once.
]=]
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

	local Visited: { [string]: boolean } = {}
	local Visiting: { [string]: boolean } = {}

	local function CheckCycle(Name: string)
		if Visited[Name] then
			return
		end

		if Visiting[Name] then
			error(string.format("%s Circular dependency involving '%s'", Types.EngineName, Name))
		end

		Visiting[Name] = true

		local Dependencies = DependencyGraph[Name] or {}
		for _, Dependency in pairs(Dependencies) do
			CheckCycle(Dependency)
		end

		Visiting[Name] = false
		Visited[Name] = true
	end

	for ComponentName in LoadedComponents do
		CheckCycle(ComponentName)
	end
end

--[=[
	Loads all component ModuleScripts from a folder, validates them,
	builds the dependency graph, and checks for circular dependencies.

	@param Folder Instance -- The folder containing component ModuleScripts
]=]
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

--[=[
	Returns the loaded component for a given name.

	@param ComponentName string -- The component name to look up
	@return LoadedComponent? -- The loaded component, or nil if not found
]=]
function ComponentLoader.Get(ComponentName: string): LoadedComponent?
	return LoadedComponents[ComponentName]
end

--[=[
	Returns whether a component with the given name has been loaded.

	@param ComponentName string -- The component name to check
	@return boolean -- True if the component exists
]=]
function ComponentLoader.Has(ComponentName: string): boolean
	return LoadedComponents[ComponentName] ~= nil
end

--[=[
	Returns the dependency list for a given component.

	@param ComponentName string -- The component name
	@return { string } -- Array of dependency names
]=]
function ComponentLoader.GetDependencies(ComponentName: string): { string }
	return DependencyGraph[ComponentName] or {}
end

--[=[
	Returns an array of all loaded component names.

	@return { string } -- Array of component names
]=]
function ComponentLoader.GetAllNames(): { string }
	local Names = {}
	for Name in LoadedComponents do
		table.insert(Names, Name)
	end
	return Names
end

--[=[
	Returns component names and their update rates for all components that define an UpdateRate.

	@return { { Name: string, Rate: number } } -- Array of component update info
]=]
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

--[=[
	Resolves a topological initialization order for the given component names
	based on the dependency graph.

	@param ComponentNames { string } -- The components to resolve
	@return { string } -- Dependency-ordered component names
]=]
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