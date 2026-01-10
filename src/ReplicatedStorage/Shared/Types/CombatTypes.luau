--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local EnsembleTypes = require(Shared.Types.EnsembleTypes)

type Entity = EnsembleTypes.Entity
type EventBus = EnsembleTypes.EventBus
type Connection = EnsembleTypes.Connection

export type Block = {
    BlockType: string,
    [string]: any,
}

export type SkillConditions = {
    OnAir: boolean?,
    HasTarget: boolean?,
    IsAwakened: boolean?,
    HasAwkBar: number?,
    Durability: number?,
}

export type SkillProperties = {
    DamageMultiplier: number?,
    KnockbackMultiplier: number?,
    Invincible: boolean?,
}

export type SkillDefinition = {
    SkillId: string,
    DisplayName: string?,
    Timeline: { Block },
    Conditions: SkillConditions?,
    Properties: SkillProperties?,
}

export type ToolDefinition = {
    ToolId: string,
    DisplayName: string,
    Icon: string,
    DefaultSlot: number,
    Cooldown: number,
    SkillId: string,
    GroundOnly: boolean?,
    RequiresTarget: boolean?,
    AwakeningOnly: boolean?,
}

export type ExecutionContext = {
    Entity: Entity,
    SkillDefinition: SkillDefinition,
    EventBus: EventBus,
    StartTime: number,
    HitCount: number,
    Canceled: boolean,
    Properties: SkillProperties,

    GetElapsedTime: () -> number,
    Cancel: () -> (),
    IncrementHitCount: () -> (),
    GenerateId: () -> string,
}

export type BlockHandler = {
    Execute: (Block: Block, Context: ExecutionContext) -> (),
}

export type HitData = {
    Attacker: Entity,
    Target: Model,
    Damage: number,
    Hitstun: number?,
    Knockback: Vector3?,
    HitType: string,
    Position: Vector3,
}

return nil