--!strict

return table.freeze({
	BlockType = table.freeze({
		Wait = "Wait",
		Animation = "Animation",
		Sound = "Sound",
		Velocity = "Velocity",
		Hitbox = "Hitbox",
		HitCancel = "HitCancel",
		Action = "Action",
		Connect = "Connect",
		AddAwakening = "AddAwakening",
		AddHealth = "AddHealth",
		AddEvasive = "AddEvasive",
		Branch = "Branch",
	}),

	AttackType = table.freeze({
		Melee = "Melee",
		Bullet = "Bullet",
		Explosion = "Explosion",
		Swarm = "Swarm",
		Domain = "Domain",
	}),

	Action = table.freeze({
		Activated = "Combat.Action.Activated",
		Completed = "Combat.Action.Completed",
		Canceled = "Combat.Action.Canceled",
		Rejected = "Combat.Action.Rejected",
		BranchChanged = "Combat.Action.BranchChanged",
	}),

	Hitbox = table.freeze({
		Created = "Combat.Hitbox.Created",
		Hit = "Combat.Hitbox.Hit",
		Missed = "Combat.Hitbox.Missed",
		Expired = "Combat.Hitbox.Expired",
		Blocked = "Combat.Hitbox.Blocked",
	}),

	Connect = table.freeze({
		SignalSent = "Combat.Connect.SignalSent",
		SignalReceived = "Combat.Connect.SignalReceived",
	}),
})