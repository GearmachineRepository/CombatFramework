--!strict

--[=[
	@class ServiceLoader

	A lightweight lifecycle manager for loading, ordering, and starting service/controller
	ModuleScripts without sacrificing IntelliSense.

	Core guarantees:
	- All ModuleScripts in the provided folder are required before any Init runs.
	- Init runs synchronously in dependency order (topologically sorted).
	- Start runs after all Init has completed; Start is invoked asynchronously via task.spawn.
	- Stop runs in reverse init order (useful for teardown and dependency-safe shutdown).

	Dependencies:
	- Each service may declare `Dependencies = { "OtherServiceName", ... }`
	- Dependency names refer to sibling ModuleScript names in the loaded folder.
	- Circular dependencies error during load ordering.

	```lua
	local ServiceLoader = require(Shared.Utils.ServiceLoader)

	ServiceLoader.LoadServices(Server.Services)
	ServiceLoader.InitAll()
	ServiceLoader.StartAll()
	```
]=]

local ServiceLoader = {}

--[=[
	@within ServiceLoader
	@type ServiceModule { Init: (() -> ())?, Start: (() -> ())?, Stop: (() -> ())?, Dependencies: { string }?, [string]: unknown }
]=]
export type ServiceModule = {
	Init: (() -> ())?,
	Start: (() -> ())?,
	Stop: (() -> ())?,
	Dependencies: { string }?,
	[string]: unknown,
}

--[=[
	@within ServiceLoader
	@type LoadedService { Name: string, Module: ServiceModule, Initialized: boolean, Started: boolean }
]=]
export type LoadedService = {
	Name: string,
	Module: ServiceModule,
	Initialized: boolean,
	Started: boolean,
}

local LoadedServices: { [string]: LoadedService } = {}
local InitOrder: { string } = {}
local IsInitializedFlag = false
local IsStartedFlag = false

local function TopologicalSort(Services: { [string]: LoadedService }): { string }
	local Sorted: { string } = {}
	local Visited: { [string]: boolean } = {}
	local Visiting: { [string]: boolean } = {}

	local function Visit(Name: string)
		if Visited[Name] then
			return
		end

		if Visiting[Name] then
			error(string.format("[ServiceLoader] Circular dependency detected: %s", Name))
		end

		local Service = Services[Name]
		if Service == nil then
			return
		end

		Visiting[Name] = true

		local Dependencies = Service.Module.Dependencies
		if Dependencies ~= nil then
			for _, DepName in ipairs(Dependencies) do
				Visit(DepName)
			end
		end

		Visiting[Name] = false
		Visited[Name] = true
		table.insert(Sorted, Name)
	end

	for Name in pairs(Services) do
		Visit(Name)
	end

	return Sorted
end

--[=[
	Loads (requires) all ModuleScripts under the given Folder.

	This must be called before `InitAll()` and `StartAll()`.

	@param Folder Instance -- The folder containing service ModuleScripts
]=]
function ServiceLoader.LoadServices(Folder: Instance)
	if IsInitializedFlag then
		error("[ServiceLoader] Cannot load services after initialization")
	end

	for _, Child in ipairs(Folder:GetChildren()) do
		if not Child:IsA("ModuleScript") then
			continue
		end

		local Success, Result = pcall(require, Child)
		if not Success then
			error(string.format("[ServiceLoader] Failed to require %s: %s", Child.Name, tostring(Result)))
		end

		if type(Result) ~= "table" then
			error(string.format("[ServiceLoader] Service %s must return a table", Child.Name))
		end

		LoadedServices[Child.Name] = {
			Name = Child.Name,
			Module = Result :: ServiceModule,
			Initialized = false,
			Started = false,
		}
	end

	InitOrder = TopologicalSort(LoadedServices)
end

--[=[
	Invokes `Init()` on all loaded services in dependency order.

	Runs synchronously. If a service has no `Init`, it is still marked initialized.
	Errors if any `Init()` errors.
]=]
function ServiceLoader.InitAll()
	if IsInitializedFlag then
		error("[ServiceLoader] Already initialized")
	end

	for _, Name in ipairs(InitOrder) do
		local Service = LoadedServices[Name]
		if Service ~= nil then
			local InitFunction = Service.Module.Init
			if InitFunction ~= nil then
				local Success, ErrorMessage = pcall(function()
					InitFunction()
					return nil
				end)

				if not Success then
					error(string.format("[ServiceLoader] %s.Init() failed: %s", Name, tostring(ErrorMessage)))
				end
			end

			Service.Initialized = true
		end
	end

	IsInitializedFlag = true
end

--[=[
	Invokes `Start()` on all loaded services in dependency order.

	Requires `InitAll()` to have completed successfully.
	Each `Start()` runs in its own `task.spawn` to prevent one service from blocking others.
	Start failures are warned (not raised as errors) to avoid hard-stopping the experience.
]=]
function ServiceLoader.StartAll()
	if not IsInitializedFlag then
		error("[ServiceLoader] Must call InitAll before StartAll")
	end

	if IsStartedFlag then
		error("[ServiceLoader] Already started")
	end

	for _, Name in ipairs(InitOrder) do
		local Service = LoadedServices[Name]
		if Service ~= nil then
			local StartFunction = Service.Module.Start
			if StartFunction ~= nil then
				task.spawn(function()
					local Success, ErrorMessage = pcall(function()
						StartFunction()
						return nil
					end)

					if not Success then
						warn(string.format("[ServiceLoader] %s.Start() failed: %s", Name, tostring(ErrorMessage)))
					end
				end)
			end

			Service.Started = true
		end
	end

	IsStartedFlag = true
end

--[=[
	Invokes `Stop()` on all loaded services in reverse dependency order.

	No-op if `StartAll()` has not been called.
	Reverse order helps ensure dependents stop before dependencies.
	Stop failures are warned.
]=]
function ServiceLoader.StopAll()
	if not IsStartedFlag then
		return
	end

	for Index = #InitOrder, 1, -1 do
		local Name = InitOrder[Index]
		local Service = LoadedServices[Name]
		if Service ~= nil then
			local StopFunction = Service.Module.Stop
			if StopFunction ~= nil then
				local Success, ErrorMessage = pcall(function()
					StopFunction()
					return nil
				end)

				if not Success then
					warn(string.format("[ServiceLoader] %s.Stop() failed: %s", Name, tostring(ErrorMessage)))
				end
			end
		end
	end

	IsStartedFlag = false
end

--[=[
	Returns whether `InitAll()` has completed successfully.

	@return boolean -- True if initialization is complete
]=]
function ServiceLoader.IsInitialized(): boolean
	return IsInitializedFlag
end

--[=[
	Returns whether `StartAll()` has been called.

	@return boolean -- True if all services have been started
]=]
function ServiceLoader.IsStarted(): boolean
	return IsStartedFlag
end

--[=[
	Returns the service initialization order computed by dependency sorting.

	@return { string } -- Ordered list of service names
]=]
function ServiceLoader.GetLoadOrder(): { string }
	return table.clone(InitOrder)
end

return ServiceLoader