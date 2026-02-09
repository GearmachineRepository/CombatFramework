--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local EnsembleTypes = require(Shared.Types.EnsembleTypes)

export type Connection = EnsembleTypes.Connection
export type Signal<T...> = EnsembleTypes.Signal<T...>
export type StateConfig = EnsembleTypes.StateConfig
export type StatConfig = EnsembleTypes.StatConfig
export type HotbarConfig = EnsembleTypes.HotbarConfig
export type EventBus = EnsembleTypes.EventBus
export type EntityContext = EnsembleTypes.EntityContext
export type Component = EnsembleTypes.Component
export type ComponentDefinition = EnsembleTypes.ComponentDefinition
export type Entity = EnsembleTypes.Entity
export type EntityBuilder = EnsembleTypes.EntityBuilder

return EnsembleTypes