--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local EnsembleTypes = require(Shared.Types.EnsembleTypes)

export type EventBus = EnsembleTypes.EventBus
export type Connection = EnsembleTypes.Connection

export type ExecutionEntity = {
	Character: Model,
	Humanoid: Humanoid,
	IsPlayer: boolean,
	Player: Player?,
}

export type Block = {
	BlockType: string,
	[string]: any,
}

export type WaitBlock = {
	BlockType: string,
	Time: number?,
}

export type AnimationBlock = {
	BlockType: string,
	AnimationId: string,
	Speed: number?,
	Loop: boolean?,
	LastHit: number?,
}

export type SoundBlock = {
	BlockType: string,
	SoundId: string,
	Volume: number?,
	Speed: number?,
}

export type VelocityBlock = {
	BlockType: string,
	X: number?,
	Y: number?,
	Z: number?,
	Time: number?,
	Fade: boolean?,
	Track: boolean?,
	LastHit: number?,
	Ragdoll: number?,
	TrueRagdoll: boolean?,
}

export type HitboxBlock = {
	BlockType: string,
	X: number?,
	Y: number?,
	Z: number?,
	SizeX: number?,
	SizeY: number?,
	SizeZ: number?,
	Stun: number?,
	Damage: number?,
	AttackType: string?,
	Blockable: boolean?,
	Block360: boolean?,
	CancelEnemy: boolean?,
}

export type HitCancelBlock = {
	BlockType: string,
	Time: number?,
	Flip: boolean?,
	Endlag: number?,
	Branch: string?,
}

export type SkillBlock = {
	BlockType: string,
	SkillId: string,
	Speed: number?,
	CancelLast: boolean?,
	HoldFor: number?,
}

export type ConnectBlock = {
	BlockType: string,
	Signal: string?,
	Time: number?,
	Range: number?,
}

export type AddResourceBlock = {
	BlockType: string,
	Amount: number?,
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

export type Branch = {
	Entry: boolean?,
	Timeline: { Block },
}

export type SkillDefinition = {
	SkillId: string,
	DisplayName: string?,
	Timeline: { Block }?,
	Branches: { [string]: Branch }?,
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

export type HitRecord = {
	Target: Model,
	Timestamp: number,
	Damage: number,
}

export type ExecutionContext = {
	Entity: ExecutionEntity,
	SkillDefinition: SkillDefinition,
	EventBus: EventBus,
	StartTime: number,
	Canceled: boolean,
	Properties: SkillProperties,
	HitRecords: { HitRecord },
	LastHitTarget: Model?,

	GetElapsedTime: () -> number,
	Cancel: () -> (),
	RecordHit: (Target: Model, Damage: number) -> (),
	HadHitInWindow: (WindowSeconds: number) -> boolean,
	GetLastHitTarget: () -> Model?,
}

export type HandlerResult = {
	JumpToBranch: string?,
	Cancel: boolean?,
}

export type BlockHandler = {
	Execute: (Block: Block, Context: ExecutionContext) -> HandlerResult?,
}

export type HitData = {
	Attacker: ExecutionEntity,
	Target: Model,
	Damage: number,
	Stun: number?,
	AttackType: string?,
	Blockable: boolean?,
	Block360: boolean?,
	CancelEnemy: boolean?,
	Position: Vector3,
}

return nil