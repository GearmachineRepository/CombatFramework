--!strict

--[=[
	@class UpdateSystem

	Drives per-entity component updates on Heartbeat.

	Components that define an `UpdateRate` are ticked at their specified
	interval using per-component accumulators. Automatically tracks
	entities via EventBus lifecycle events.
]=]

local RunService = game:GetService("RunService")

local Types = require(script.Parent.Parent.Types)

type Entity = Types.Entity
type EventBus = Types.EventBus
type Connection = Types.Connection

type EntityUpdateData = {
	Entity: Entity,
	Accumulators: { [string]: number },
}

local UpdateSystem = {}

local Entities: { [Entity]: EntityUpdateData } = {}
local UpdateRates: { [string]: number } = {}
local HeartbeatConnection: RBXScriptConnection? = nil
local EventBusRef: EventBus? = nil
local EntityCreatedConnection: Connection? = nil
local EntityDestroyedConnection: Connection? = nil

--[=[
	Runs a single update tick for one entity, advancing all component accumulators.

	@param EntityData EntityUpdateData -- The entity's update tracking data
	@param DeltaTime number -- Time elapsed since last heartbeat
]=]
function UpdateSystem.UpdateEntity(EntityData: EntityUpdateData, DeltaTime: number)
	local EntityInstance = EntityData.Entity

	if not EntityInstance.Character or not EntityInstance.Character.Parent then
		return
	end

	for ComponentName, UpdateRate in UpdateRates do
		local Component = EntityInstance:GetComponent(ComponentName)
		if not Component then
			continue
		end

		if not Component.Update then
			continue
		end

		local Accumulator = EntityData.Accumulators[ComponentName] or 0
		Accumulator = Accumulator + DeltaTime

		if Accumulator >= UpdateRate then
			local Success, ErrorMessage = pcall(Component.Update, Accumulator)
			if not Success then
				warn(string.format("%s Component '%s' update failed: %s", Types.EngineName, ComponentName, tostring(ErrorMessage)))
			end
			EntityData.Accumulators[ComponentName] = 0
		else
			EntityData.Accumulators[ComponentName] = Accumulator
		end
	end
end

--[=[
	Heartbeat callback that updates all tracked entities.

	@param DeltaTime number -- Time elapsed since last heartbeat
]=]
function UpdateSystem.OnHeartbeat(DeltaTime: number)
	for _, EntityData in pairs(Entities) do
		UpdateSystem.UpdateEntity(EntityData, DeltaTime)
	end
end

--[=[
	Configures the update system with component update rates and the EventBus.

	@param ComponentLoader any -- The ComponentLoader module
	@param EventBus EventBus -- The EventBus for entity lifecycle events
]=]
function UpdateSystem.Configure(ComponentLoader: any, EventBus: EventBus)
	EventBusRef = EventBus

	local ComponentsWithUpdates = ComponentLoader.GetWithUpdates()
	for _, ComponentInfo in ComponentsWithUpdates do
		UpdateRates[ComponentInfo.Name] = ComponentInfo.Rate
	end
end

--[=[
	Starts the update loop by connecting to Heartbeat and subscribing to entity events.
]=]
function UpdateSystem.Start()
	if HeartbeatConnection then
		return
	end

	if EventBusRef then
		EntityCreatedConnection = EventBusRef:Subscribe("Entity.Created", function(EventData: any)
			local EntityInstance = EventData.Entity
			if not EntityInstance then
				return
			end

			Entities[EntityInstance] = {
				Entity = EntityInstance,
				Accumulators = {},
			}
		end)

		EntityDestroyedConnection = EventBusRef:Subscribe("Entity.Destroyed", function(EventData: any)
			local EntityInstance = EventData.Entity
			if not EntityInstance then
				return
			end

			local EntityData = Entities[EntityInstance]
			if EntityData then
				table.clear(EntityData.Accumulators)
			end

			Entities[EntityInstance] = nil
		end)
	end

	HeartbeatConnection = RunService.Heartbeat:Connect(UpdateSystem.OnHeartbeat)
end

--[=[
	Stops the update loop and disconnects all event subscriptions.
]=]
function UpdateSystem.Stop()
	if HeartbeatConnection then
		HeartbeatConnection:Disconnect()
		HeartbeatConnection = nil
	end

	if EntityCreatedConnection then
		EntityCreatedConnection:Disconnect()
		EntityCreatedConnection = nil
	end

	if EntityDestroyedConnection then
		EntityDestroyedConnection:Disconnect()
		EntityDestroyedConnection = nil
	end

	table.clear(Entities)
end

--[=[
	Overrides the update rate for a specific component.

	@param ComponentName string -- The component name
	@param Rate number -- The new update interval in seconds
]=]
function UpdateSystem.SetUpdateRate(ComponentName: string, Rate: number)
	UpdateRates[ComponentName] = Rate
end

--[=[
	Returns the current update rate for a component, or nil if it has no update.

	@param ComponentName string -- The component name
	@return number? -- The update interval in seconds, or nil
]=]
function UpdateSystem.GetUpdateRate(ComponentName: string): number?
	return UpdateRates[ComponentName]
end

return UpdateSystem