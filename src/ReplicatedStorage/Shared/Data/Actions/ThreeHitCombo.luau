--!strict

local Types = require(script.Parent.Parent.Parent.Types.CombatTypes)

return {
	ActionId = "ThreeHitCombo",
	DisplayName = "Three Hit Combo",
	Cooldown = 0.5,

	Branches = {
		Main = {
			Entry = true,
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 1 },
				{ BlockType = "Wait", Time = 0.1 },
				{ BlockType = "Velocity", X = 0, Y = 0, Z = 55, Time = 0.1, Fade = true, Track = true },
				{ BlockType = "Hitbox", X = 0, Y = 0, Z = 4, SizeX = 6, SizeY = 6, SizeZ = 6, LaunchZ = 15, Damage = 8, Stun = 0.25 },
				{ BlockType = "HitCancel", Time = 0.3, Flip = false, Branch = "SecondHit" },
				{ BlockType = "HitCancel", Time = 0.3, Flip = true, Branch = "WhiffRecovery" },
			},
		},

		SecondHit = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 1.2 },
				{ BlockType = "Wait", Time = 0.12 },
				{ BlockType = "Velocity", X = 0, Y = 0, Z = 15, Time = 0.1, Fade = true, Track = true },
				{ BlockType = "Hitbox", X = 0, Y = 0, Z = 4, SizeX = 7, SizeY = 6, SizeZ = 7, LaunchZ = 15, Damage = 10, Stun = 0.3 },
				{ BlockType = "HitCancel", Time = 0.3, Flip = false, Branch = "ThirdHit" },
				{ BlockType = "HitCancel", Time = 0.3, Flip = true, Branch = "ComboDropRecovery" },
			},
		},

		ThirdHit = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 1.4 },
				{ BlockType = "Wait", Time = 0.15 },
				{ BlockType = "Sound", SoundId = "rbxassetid://0", Volume = 0.8 },
				{ BlockType = "Velocity", X = 0, Y = 5, Z = 35, Time = 0.15, Fade = true, Track = true },
				{ BlockType = "Hitbox", X = 0, Y = 0, Z = 5, SizeX = 8, SizeY = 8, SizeZ = 10, LaunchZ = 55, Damage = 15, Stun = 0.5, KnockbackZ = 20 },
				{ BlockType = "Wait", Time = 0.4 },
			},
		},

		WhiffRecovery = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 0.7 },
				{ BlockType = "Wait", Time = 0.6 },
			},
		},

		ComboDropRecovery = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 0.8 },
				{ BlockType = "Wait", Time = 0.4 },
			},
		},
	},

	Conditions = {
		OnAir = false,
	},

	Properties = {
		DamageMultiplier = 1,
		KnockbackMultiplier = 1,
	},
} :: Types.ActionDefinition