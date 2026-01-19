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
		Chase = "Chase",
		Grab = "Grab",
		AddHealth = "AddHealth",
		AddEvasive = "AddEvasive",
	}),

	AttackType = table.freeze({
		Melee = "Melee",
		Heavy = "Heavy",
		Projectile = "Projectile",
		Grab = "Grab",
		Launch = "Launch",
		Slam = "Slam",
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

	Grab = table.freeze({
		Started = "Combat.Grab.Started",
		Ended = "Combat.Grab.Ended",
		Escaped = "Combat.Grab.Escaped",
		Thrown = "Combat.Grab.Thrown",
	}),

	State = table.freeze({
		Stunned = "Stunned",
		Blocking = "Blocking",
		Grabbed = "Grabbed",
		Grabbing = "Grabbing",
		Invincible = "Invincible",
		SuperArmor = "SuperArmor",
	}),
})