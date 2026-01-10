--!strict

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

type EventBusInternal = EventBus & {
	_Events: { [string]: SignalType },
	_Destroyed: boolean,
	_Trove: typeof(Trove.new()),
}

local EventBus = {}
EventBus.__index = EventBus

local function CreateEventBus(): EventBusInternal
	local BusTrove = Trove.new()
	local self = {
		_Events = {} :: { [string]: SignalType },
		_Destroyed = false,
		_Trove = BusTrove,
	}
	return setmetatable(self, EventBus) :: any
end

function EventBus.new(): EventBus
	return CreateEventBus()
end

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

function EventBus.Subscribe(self: EventBusInternal, EventName: string, Callback: (...any) -> ()): Connection
	local Event = GetOrCreateEvent(self, EventName)
	return Event:Connect(Callback)
end

function EventBus.SubscribeOnce(self: EventBusInternal, EventName: string, Callback: (...any) -> ()): Connection
	local Event = GetOrCreateEvent(self, EventName)
	return Event:Once(Callback)
end

function EventBus.Publish(self: EventBusInternal, EventName: string, ...: any)
	assert(not self._Destroyed, "EventBus has been destroyed")

	local Event = self._Events[EventName]
	if Event then
		Event:Fire(...)
	end
end

function EventBus.Wait(self: EventBusInternal, EventName: string): ...any
	local Event = GetOrCreateEvent(self, EventName)
	return Event:Wait()
end

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

function EventBus.HasEvent(self: EventBusInternal, EventName: string): boolean
	assert(not self._Destroyed, "EventBus has been destroyed")
	return self._Events[EventName] ~= nil
end

function EventBus.GetEventNames(self: EventBusInternal): { string }
	assert(not self._Destroyed, "EventBus has been destroyed")

	local Names = {}
	for EventName in self._Events do
		table.insert(Names, EventName)
	end
	table.sort(Names)
	return Names
end

function EventBus.Destroy(self: EventBusInternal)
	if self._Destroyed then
		return
	end

	self._Destroyed = true
	self._Trove:Destroy()
	table.clear(self._Events)
end

return EventBus