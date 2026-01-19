--!strict

export type ExecutionMode = "Authoritative" | "Predictive"

export type EventBus = {
	Publish: (self: EventBus, EventName: string, Data: any) -> (),
	Subscribe: (self: EventBus, EventName: string, Callback: (Data: any) -> ()) -> () -> (),
}

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
	LastHit: number?,
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
	Damage: number?,
	Stun: number?,
	AttackType: string?,
	Blockable: boolean?,
	Block360: boolean?,
	BlockDamage: number?,
	CancelEnemy: boolean?,
	KnockbackX: number?,
	KnockbackY: number?,
	KnockbackZ: number?,
	LaunchY: number?,
	LaunchZ: number?,
	GroundBounce: boolean?,
	WallBounce: boolean?,
	RagdollBypass: boolean?,
	Unblockable: boolean?,
	JuggleDecay: number?,
}

export type HitCancelBlock = {
	BlockType: string,
	Time: number?,
	Flip: boolean?,
	Endlag: number?,
	Branch: string?,
}

export type ActionBlock = {
	BlockType: string,
	ActionId: string,
	Speed: number?,
	CancelLast: boolean?,
	HoldFor: number?,
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

export type GrabBlock = {
	BlockType: string,
	Range: number?,
	Duration: number?,
	OffsetX: number?,
	OffsetY: number?,
	OffsetZ: number?,
	AttackerAnimation: string?,
	TargetAnimation: string?,
	ThrowBranch: string?,
	ReleaseBranch: string?,
	MissBranch: string?,
}

export type AddResourceBlock = {
	BlockType: string,
	Resource: string?,
	Amount: number?,
}

export type ActionConditions = {
	OnAir: boolean?,
	HasTarget: boolean?,
	IsStunned: boolean?,
	IsBlocking: boolean?,
	IsGrabbed: boolean?,
	HasEvasive: boolean?,
	MinHealth: number?,
	MaxHealth: number?,
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
	GroundOnly: boolean?,
	AirOnly: boolean?,
}

export type ToolDefinition = {
	ToolId: string,
	DisplayName: string,
	Icon: string,
	DefaultSlot: number,
	Cooldown: number,
	ActionId: string,
	GroundOnly: boolean?,
	RequiresTarget: boolean?,
}

export type HitRecord = {
	Target: Model,
	Timestamp: number,
	Damage: number,
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

	GetElapsedTime: () -> number,
	Cancel: () -> (),
	RecordHit: (Target: Model, Damage: number) -> (),
	HadHitInWindow: (WindowSeconds: number) -> boolean,
	GetLastHitTarget: () -> Model?,
	SetGrabTarget: (Target: Model?) -> (),
	GetGrabTarget: () -> Model?,
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

return nil