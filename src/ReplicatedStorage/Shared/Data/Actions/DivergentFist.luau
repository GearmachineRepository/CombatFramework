--!strict

return {
	ActionId = "DivergentFist",
	DisplayName = "Divergent Fist",

	Branches = {
		Main = {
			Entry = true,
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://123456", Speed = 1.2 },
				{ BlockType = "Wait", Time = 0.2 },
				{ BlockType = "Velocity", X = 0, Y = 0, Z = -40, Time = 0.15, Fade = true, Track = true },
				{ BlockType = "Hitbox", X = 0, Y = 0, Z = 4, SizeX = 8, SizeY = 6, SizeZ = 8, Damage = 18, Stun = 0.4 },
				{ BlockType = "HitCancel", Time = 0.5, Flip = true, Branch = "WhiffRecovery" },
				{ BlockType = "Sound", SoundId = "rbxassetid://789", Volume = 0.6 },
				{ BlockType = "Wait", Time = 0.35 },
			},
		},

		WhiffRecovery = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://999", Speed = 0.8 },
				{ BlockType = "Wait", Time = 0.5 },
			},
		},
	},

	Conditions = {
		OnAir = false,
	},

	Properties = {
		DamageMultiplier = 1,
		KnockbackMultiplier = 1,
		Invincible = false,
	},
}