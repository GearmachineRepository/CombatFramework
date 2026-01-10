--!strict

--[[
	EventBus

	A publish/subscribe event system for decoupled communication.

	```lua
	local EventBus = require(path.to.EventBus)
	local Bus = EventBus.new()

	Bus:Subscribe("PlayerDied", function(Data)
		print(Data.Player.Name, "died")
	end)

	Bus:Publish("PlayerDied", { Player = Player })
	```
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)

local Signal = Packages.Signal

export type Connection = {
	Disconnect: (self: Connection) -> (),
	Destroy: (self: Connection) -> (),
	Connected: boolean,
}

export type Signal<T...> = {
	Fire: (self: Signal<T...>, T...) -> (),
	FireDeferred: (self: Signal<T...>, T...) -> (),
	Connect: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, fn: (T...) -> ()) -> Connection,
	DisconnectAll: (self: Signal<T...>) -> (),
	GetConnections: (self: Signal<T...>) -> { Connection },
	Destroy: (self: Signal<T...>) -> (),
	Wait: (self: Signal<T...>) -> T...,
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

type EventBusInternal = EventBus & {
	_Events: { [string]: Signal<...any> },
	_Destroyed: boolean,
}

local EventBus = {}
EventBus.__index = EventBus

local function CreateEventBus(): EventBusInternal
	local self = {
		_Events = {} :: { [string]: Signal<...any> },
		_Destroyed = false,
	}
	return setmetatable(self, EventBus) :: any
end

--[[
	Creates a new EventBus.

	```lua
	local Bus = EventBus.new()
	```
]]
function EventBus.new(): EventBus
	return CreateEventBus()
end

--[[
	Returns `true` if the value is an EventBus.

	```lua
	if EventBus.Is(Obj) then
		Obj:Publish("Event")
	end
	```
]]
function EventBus.Is(Value: any): boolean
	return type(Value) == "table" and getmetatable(Value) == EventBus
end

local function GetOrCreateEvent(self: EventBusInternal, EventName: string): Signal<...any>
	assert(not self._Destroyed, "EventBus has been destroyed")

	local Existing = self._Events[EventName]
	if Existing then
		return Existing
	end

	local NewEvent = Signal.new()
	self._Events[EventName] = NewEvent
	return NewEvent
end

--[[
	Subscribes to an event. Returns a connection.

	```lua
	local Connection = Bus:Subscribe("PlayerJoined", function(Player)
		print(Player.Name, "joined")
	end)
	```
]]
function EventBus.Subscribe(self: EventBusInternal, EventName: string, Callback: (...any) -> ()): Connection
	local Event = GetOrCreateEvent(self, EventName)
	return Event:Connect(Callback)
end

--[[
	Subscribes to an event once. Disconnects after first fire.

	```lua
	Bus:SubscribeOnce("GameStart", function()
		print("Game started!")
	end)
	```
]]
function EventBus.SubscribeOnce(self: EventBusInternal, EventName: string, Callback: (...any) -> ()): Connection
	local Event = GetOrCreateEvent(self, EventName)
	return Event:Once(Callback)
end

--[[
	Publishes an event with the given arguments.

	```lua
	Bus:Publish("DamageDealt", {
		Source = Attacker,
		Target = Target,
		Amount = 50,
	})
	```
]]
function EventBus.Publish(self: EventBusInternal, EventName: string, ...: any)
	assert(not self._Destroyed, "EventBus has been destroyed")

	local Event = self._Events[EventName]
	if Event then
		Event:Fire(...)
	end
end

--[[
	Yields until the event is published.

	```lua
	local Data = Bus:Wait("GameEnd")
	print("Game ended with result:", Data.Result)
	```
]]
function EventBus.Wait(self: EventBusInternal, EventName: string): ...any
	local Event = GetOrCreateEvent(self, EventName)
	return Event:Wait()
end

--[[
	Clears an event or all events.

	```lua
	Bus:Clear("PlayerDied")
	Bus:Clear()
	```
]]
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

--[[
	Returns `true` if the event has been registered.

	```lua
	if Bus:HasEvent("PlayerDied") then
		-- Event exists
	end
	```
]]
function EventBus.HasEvent(self: EventBusInternal, EventName: string): boolean
	assert(not self._Destroyed, "EventBus has been destroyed")

	return self._Events[EventName] ~= nil
end

--[[
	Returns all registered event names.

	```lua
	local Events = Bus:GetEventNames()
	```
]]
function EventBus.GetEventNames(self: EventBusInternal): { string }
	assert(not self._Destroyed, "EventBus has been destroyed")

	local Names = {}
	for EventName in self._Events do
		table.insert(Names, EventName)
	end
	table.sort(Names)
	return Names
end

--[[
	Destroys the EventBus and clears all events.

	```lua
	Bus:Destroy()
	```
]]
function EventBus.Destroy(self: EventBusInternal)
	if self._Destroyed then
		return
	end

	self._Destroyed = true
	for _, Event in self._Events do
		Event:Destroy()
	end
	table.clear(self._Events)
end

return EventBus