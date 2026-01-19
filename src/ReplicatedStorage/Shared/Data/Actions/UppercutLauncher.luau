--!strict

local Types = require(script.Parent.Parent.Parent.Types.CombatTypes)

return {
	ActionId = "UppercutLauncher",
	DisplayName = "Uppercut Launcher",
	Cooldown = 3,

	Branches = {
		Main = {
			Entry = true,
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 1 },
				{ BlockType = "Wait", Time = 0.2 },
				{ BlockType = "Sound", SoundId = "rbxassetid://0", Volume = 0.7 },
				{ BlockType = "Velocity", X = 0, Y = 10, Z = 15, Time = 0.15, Fade = true, Track = true },
				{
					BlockType = "Hitbox",
					X = 0, Y = 1, Z = 3,
					SizeX = 5, SizeY = 7, SizeZ = 5,
					Damage = 12,
					Stun = 0.6,
					LaunchY = 35,
					LaunchZ = 5,
					AttackType = "Launch",
				},
				{ BlockType = "HitCancel", Time = 0.4, Flip = false, Branch = "HitRecovery" },
				{ BlockType = "HitCancel", Time = 0.4, Flip = true, Branch = "WhiffRecovery" },
			},
		},

		HitRecovery = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 0.9 },
				{ BlockType = "Wait", Time = 0.3 },
			},
		},

		WhiffRecovery = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 0.6 },
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
	},
} :: Types.ActionDefinition