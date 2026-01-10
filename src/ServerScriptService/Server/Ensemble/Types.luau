--!strict

local Types = {}

Types.EngineName = "[Ensemble]"

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

export type StateConfig = {
	[string]: {
		Default: boolean?,
		Replicate: boolean?,
		Conflicts: { string }?,
	},
}

export type StatConfig = {
	[string]: {
		Default: number,
		Min: number?,
		Max: number?,
		MaxStat: string?,
		Replicate: boolean?,
	},
}

export type EntityContext = {
	Player: Player?,
	Data: { [string]: any }?,
	EventBus: EventBus?,
	StateConfig: StateConfig?,
	StatConfig: StatConfig?,
}

export type Component = {
	Init: (() -> ())?,
	Start: (() -> ())?,
	Destroy: () -> (),
	Update: ((DeltaTime: number) -> ())?,
	[string]: any,
}

export type ComponentDefinition = {
	ComponentName: string,
	Dependencies: { string }?,
	UpdateRate: number?,
	Create: (Entity: Entity, Context: EntityContext) -> Component,
}

export type Entity = {
	Character: Model,
	Humanoid: Humanoid,
	IsPlayer: boolean,
	Player: Player?,
	Context: EntityContext,

	GetComponent: (self: Entity, ComponentName: string) -> any?,
	HasComponent: (self: Entity, ComponentName: string) -> boolean,
	AddComponent: (self: Entity, ComponentName: string, ComponentInstance: Component) -> (),
	RemoveComponent: (self: Entity, ComponentName: string) -> (),
	Destroy: (self: Entity) -> (),
}

export type EntityBuilder = {
	WithComponent: (self: EntityBuilder, ComponentName: string, ...any) -> EntityBuilder,
	WithComponents: (self: EntityBuilder, ...string) -> EntityBuilder,
	WithArchetype: (self: EntityBuilder, ArchetypeName: string) -> EntityBuilder,
	WithoutComponent: (self: EntityBuilder, ComponentName: string) -> EntityBuilder,
	Build: (self: EntityBuilder) -> Entity,
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

return Types