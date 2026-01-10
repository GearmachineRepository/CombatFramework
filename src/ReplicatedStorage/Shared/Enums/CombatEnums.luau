--!strict

return table.freeze({
	BlockType = table.freeze({
		Wait = "Wait",
		Animation = "Animation",
		Sound = "Sound",
		Velocity = "Velocity",
		Hitbox = "Hitbox",
		HitCancel = "HitCancel",
		Skill = "Skill",
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

	Skill = table.freeze({
		Activated = "Combat.Skill.Activated",
		Completed = "Combat.Skill.Completed",
		Canceled = "Combat.Skill.Canceled",
		Rejected = "Combat.Skill.Rejected",
		BranchChanged = "Combat.Skill.BranchChanged",
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