--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local EnsembleTypes = require(Shared.Types.EnsembleTypes)

export type EventBus = EnsembleTypes.EventBus
export type Connection = EnsembleTypes.Connection

export type ExecutionMode = "Predictive" | "Authoritative"

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

export type WaitForMarkerBlock = {
	BlockType: string,
	Marker: string,
	AnimationId: string?,
	FallbackTime: number?,
	Speed: number?,
}

export type AnimationBlock = {
	BlockType: string,
	AnimationId: string,
	Speed: number?,
	Loop: boolean?,
	Priority: Enum.AnimationPriority?,
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
	BlockDamage: number?,
	CancelEnemy: boolean?,
	Unblockable: boolean?,
	LaunchY: number?,
	LaunchZ: number?,
	KnockbackY: number?,
	KnockbackZ: number?,
	GroundBounce: boolean?,
	JuggleDecay: number?,
}

export type GrabBlock = {
	BlockType: string,
	X: number?,
	Y: number?,
	Z: number?,
	SizeX: number?,
	SizeY: number?,
	SizeZ: number?,
	HoldOffsetX: number?,
	HoldOffsetY: number?,
	HoldOffsetZ: number?,
	Duration: number?,
	AttackerAnimation: string?,
	TargetAnimation: string?,
	ThrowBranch: string?,
	ReleaseBranch: string?,
	MissBranch: string?,
}

export type HitCancelBlock = {
	BlockType: string,
	Time: number?,
	Flip: boolean?,
	Endlag: number?,
	Branch: string?,
}

export type ChaseBlock = {
	BlockType: string,
	Range: number?,
	Time: number?,
	OffsetX: number?,
	OffsetY: number?,
	OffsetZ: number?,
	RequiresTarget: boolean?,
}

export type ActionBlock = {
	BlockType: string,
	ActionId: string,
	Speed: number?,
	CancelLast: boolean?,
	HoldFor: number?,
}

export type AddResourceBlock = {
	BlockType: string,
	Amount: number?,
}

export type ActionConditions = {
	OnAir: boolean?,
	HasTarget: boolean?,
	IsStunned: boolean?,
	IsBlocking: boolean?,
	IsGrabbed: boolean?,
	HasEvasive: number?,
}

export type ActionProperties = {
	DamageMultiplier: number?,
	KnockbackMultiplier: number?,
	Invincible: boolean?,
	SuperArmor: boolean?,
	CanCancel: boolean?,
}

export type Branch = {
	Entry: boolean?,
	Timeline: { Block },
}

export type ActionDefinition = {
	ActionId: string,
	DisplayName: string?,
	Timeline: { Block }?,
	Branches: { [string]: Branch }?,
	Conditions: ActionConditions?,
	Properties: ActionProperties?,
	Cooldown: number?,
}

export type ToolDefinition = {
	ToolId: string,
	DisplayName: string,
	Icon: string,
	DefaultSlot: number,
	Cooldown: number,
	ActionId: string,
}

export type HitRecord = {
	Target: Model,
	Timestamp: number,
	Damage: number,
}

export type Trove = {
	Add: (self: Trove, Item: any, CleanupMethod: string?) -> any,
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
}

export type ExecutionContext = {
	Entity: ExecutionEntity,
	ActionDefinition: ActionDefinition,
	EventBus: EventBus,
	Mode: ExecutionMode,
	StartTime: number,
	Canceled: boolean,
	Properties: ActionProperties,
	HitRecords: { HitRecord },
	LastHitTarget: Model?,
	GrabTarget: Model?,
	Trove: Trove,

	GetElapsedTime: () -> number,
	Cancel: () -> (),
	RecordHit: (Target: Model, Damage: number) -> (),
	HadHitInWindow: (WindowSeconds: number) -> boolean,
	GetLastHitTarget: () -> Model?,
	SetGrabTarget: (Target: Model?) -> (),
	GetGrabTarget: () -> Model?,
	SetCurrentAnimation: (AnimationId: string, Track: AnimationTrack?, Speed: number?) -> (),
	GetCurrentAnimationId: () -> string?,
	GetCurrentAnimationSpeed: () -> number,
	GetCurrentAnimationTrack: () -> AnimationTrack?,
}

export type HandlerResult = {
	JumpToBranch: string?,
	Cancel: boolean?,
	WaitForInput: string?,
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
	LaunchY: number?,
	LaunchZ: number?,
	KnockbackY: number?,
	KnockbackZ: number?,
	GroundBounce: boolean?,
}

export type GrabData = {
	Attacker: ExecutionEntity,
	Target: Model,
	Duration: number,
	AttackerAnimation: string?,
	TargetAnimation: string?,
}

export type MarkerData = {
	Time: number,
	Value: string?,
}

export type AnimationData = {
	Length: number,
	Markers: { [string]: MarkerData },
	PrimaryName: string?,
	Names: { [string]: true },
	AnimationId: string,
}

return nil