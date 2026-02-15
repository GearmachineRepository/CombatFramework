--!strict

--[=[
	@class EventBus

	A decoupled pub/sub messaging system built on top of Signal.

	Provides named event channels that are lazily created on first subscribe or publish.
	Useful for cross-system communication without direct module dependencies.

	```lua
	local EventBus = require(Shared.Utils.EventBus)

	local Events = EventBus.new()
	Events:Subscribe("PlayerScored", function(Player, Points)
		print(Player.Name, "scored", Points)
	end)
	Events:Publish("PlayerScored", SomePlayer, 100)
	```
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)

local Signal = Packages.Signal
local Trove = Packages.Trove

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Destroy: (self: Connection) -> (),
	Connected: boolean,
}


export type EventBus = {
	Subscribe: (self: EventBus, EventName: string, Callback: (...any) -> ()) -> Connection,
	SubscribeOnce: (self: EventBus, EventName: string, Callback: (...any) -> ()) -> Connection,
	Publish: (self: EventBus, EventName: string, ...any) -> (),
	Wait: (self: EventBus, EventName: string) -> ...any,
	Clear: (self: EventBus, EventName: string?) -> (),
	HasEvent: (self: EventBus, EventName: string) -> boolean,
	GetEventNames: (self: EventBus) -> { string },
	Destroy: (self: EventBus) -> (),
}

type SignalType = typeof(Signal.new())
type TroveType = typeof(Trove.new())

type EventBusStorage = {
	_Events: { [string]: SignalType },
	_Destroyed: boolean,
	_Trove: TroveType,
}

local EventBus = {}
EventBus.__index = EventBus

type EventBusInternal = typeof(setmetatable({} :: EventBusStorage, EventBus))

local function CreateEventBus(): EventBusInternal
	local BusTrove = Trove.new()

	local SelfTable: EventBusStorage = {
		_Events = {},
		_Destroyed = false,
		_Trove = BusTrove,
	}

	return setmetatable(SelfTable, EventBus)
end

--[=[
	Creates a new EventBus instance.

	@return EventBus -- A new EventBus
]=]
function EventBus.new()
	return CreateEventBus()
end

--[=[
	Returns whether the given value is an EventBus instance.

	@param Value any -- The value to check
	@return boolean -- True if Value is an EventBus
]=]
function EventBus.Is(Value: any): boolean
	return type(Value) == "table" and getmetatable(Value) == EventBus
end

local function GetOrCreateEvent(self: EventBusInternal, EventName: string): SignalType
	assert(not self._Destroyed, "EventBus has been destroyed")

	local Existing = self._Events[EventName]
	if Existing then
		return Existing
	end

	local NewEvent = self._Trove:Construct(Signal)
	self._Events[EventName] = NewEvent
	return NewEvent
end

--[=[
	Subscribes to a named event. The callback fires every time the event is published.

	@param EventName string -- The event channel name
	@param Callback (...any) -> () -- The handler function
	@return Connection -- A connection that can be disconnected
]=]
function EventBus.Subscribe(self: EventBusInternal, EventName: string, Callback: (...any) -> ()): Connection
	local Event = GetOrCreateEvent(self, EventName)
	return Event:Connect(Callback)
end

--[=[
	Subscribes to a named event for a single firing only.

	@param EventName string -- The event channel name
	@param Callback (...any) -> () -- The handler function
	@return Connection -- A connection that auto-disconnects after one fire
]=]
function EventBus.SubscribeOnce(self: EventBusInternal, EventName: string, Callback: (...any) -> ()): Connection
	local Event = GetOrCreateEvent(self, EventName)
	return Event:Once(Callback)
end

--[=[
	Publishes data to all subscribers of the named event.

	@param EventName string -- The event channel name
	@param ... any -- Arguments to pass to subscribers
]=]
function EventBus.Publish(self: EventBusInternal, EventName: string, ...: any)
	assert(not self._Destroyed, "EventBus has been destroyed")

	local Event = self._Events[EventName]
	if Event then
		Event:Fire(...)
	end
end

--[=[
	Yields the current thread until the named event is published.

	@param EventName string -- The event channel name
	@return ...any -- The arguments from the next publish
]=]
function EventBus.Wait(self: EventBusInternal, EventName: string): ...any
	local Event = GetOrCreateEvent(self, EventName)
	return Event:Wait()
end

--[=[
	Clears a specific event channel, or all channels if no name is provided.

	@param EventName string? -- The event channel to clear, or nil to clear all
]=]
function EventBus.Clear(self: EventBusInternal, EventName: string?)
	assert(not self._Destroyed, "EventBus has been destroyed")

	if EventName then
		local Event = self._Events[EventName]
		if Event then
			Event:Destroy()
		end
		self._Events[EventName] = nil
	else
		for _, Event in self._Events do
			Event:Destroy()
		end
		table.clear(self._Events)
	end
end

--[=[
	Returns whether a named event channel has been created.

	@param EventName string -- The event channel name
	@return boolean -- True if the channel exists
]=]
function EventBus.HasEvent(self: EventBusInternal, EventName: string): boolean
	assert(not self._Destroyed, "EventBus has been destroyed")
	return self._Events[EventName] ~= nil
end

--[=[
	Returns a sorted list of all active event channel names.

	@return { string } -- Sorted array of event names
]=]
function EventBus.GetEventNames(self: EventBusInternal): { string }
	assert(not self._Destroyed, "EventBus has been destroyed")

	local Names = {}
	for EventName in self._Events do
		table.insert(Names, EventName)
	end
	table.sort(Names)
	return Names
end

--[=[
	Destroys the EventBus, cleaning up all events and connections.
]=]
function EventBus.Destroy(self: EventBusInternal)
	if self._Destroyed then
		return
	end

	self._Destroyed = true
	self._Trove:Destroy()
	table.clear(self._Events)
end

return EventBus