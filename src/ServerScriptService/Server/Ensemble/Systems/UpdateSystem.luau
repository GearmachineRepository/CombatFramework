--!strict

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

function UpdateSystem.OnHeartbeat(DeltaTime: number)
	for _, EntityData in pairs(Entities) do
		UpdateSystem.UpdateEntity(EntityData, DeltaTime)
	end
end

function UpdateSystem.Configure(ComponentLoader: any, EventBus: EventBus)
	EventBusRef = EventBus

	local ComponentsWithUpdates = ComponentLoader.GetWithUpdates()
	for _, ComponentInfo in ComponentsWithUpdates do
		UpdateRates[ComponentInfo.Name] = ComponentInfo.Rate
	end
end

function UpdateSystem.Start()
	if HeartbeatConnection then
		return
	end

	if EventBusRef then
		EntityCreatedConnection = EventBusRef:Subscribe("EntityCreated", function(EventData: any)
			local EntityInstance = EventData.Entity
			if not EntityInstance then
				return
			end

			Entities[EntityInstance] = {
				Entity = EntityInstance,
				Accumulators = {},
			}
		end)

		EntityDestroyedConnection = EventBusRef:Subscribe("EntityDestroyed", function(EventData: any)
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

function UpdateSystem.SetUpdateRate(ComponentName: string, Rate: number)
	UpdateRates[ComponentName] = Rate
end

function UpdateSystem.GetUpdateRate(ComponentName: string): number?
	return UpdateRates[ComponentName]
end

function UpdateSystem.GetEntityCount(): number
	local Count = 0
	for _ in Entities do
		Count = Count + 1
	end
	return Count
end

return UpdateSystem