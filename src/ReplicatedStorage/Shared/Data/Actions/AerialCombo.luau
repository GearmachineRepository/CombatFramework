--!strict

local Types = require(script.Parent.Parent.Parent.Types.CombatTypes)

return {
	ActionId = "AerialCombo",
	DisplayName = "Aerial Combo",
	Cooldown = 1,

	Branches = {
		Main = {
			Entry = true,
			Timeline = {
				{ BlockType = "Chase", Range = 20, Time = 0.2, OffsetZ = -3, RequiresTarget = true },
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 1.1 },
				{ BlockType = "Wait", Time = 0.08 },
				{
					BlockType = "Hitbox",
					X = 0, Y = 0, Z = 3,
					SizeX = 5, SizeY = 5, SizeZ = 5,
					Damage = 8,
					Stun = 0.2,
					LaunchY = 5,
					RagdollBypass = true,
					JuggleDecay = 0.85,
				},
				{ BlockType = "HitCancel", Time = 0.25, Flip = false, Branch = "SecondHit" },
				{ BlockType = "HitCancel", Time = 0.25, Flip = true, Branch = "Drop" },
			},
		},

		SecondHit = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 1.2 },
				{ BlockType = "Wait", Time = 0.1 },
				{
					BlockType = "Hitbox",
					X = 0, Y = 0, Z = 3,
					SizeX = 5, SizeY = 5, SizeZ = 5,
					Damage = 10,
					Stun = 0.25,
					LaunchY = 3,
					RagdollBypass = true,
					JuggleDecay = 0.85,
				},
				{ BlockType = "HitCancel", Time = 0.25, Flip = false, Branch = "Spike" },
				{ BlockType = "HitCancel", Time = 0.25, Flip = true, Branch = "Drop" },
			},
		},

		Spike = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 1.3 },
				{ BlockType = "Wait", Time = 0.12 },
				{ BlockType = "Sound", SoundId = "rbxassetid://0", Volume = 0.9 },
				{
					BlockType = "Hitbox",
					X = 0, Y = -1, Z = 4,
					SizeX = 6, SizeY = 6, SizeZ = 6,
					Damage = 18,
					Stun = 0.5,
					LaunchY = -60,
					LaunchZ = 10,
					GroundBounce = true,
					AttackType = "Slam",
					Unblockable = true,
				},
				{ BlockType = "Wait", Time = 0.4 },
			},
		},

		Drop = {
			Timeline = {
				{ BlockType = "Wait", Time = 0.3 },
			},
		},
	},

	Conditions = {
		OnAir = true,
	},

	Properties = {
		DamageMultiplier = 1,
		KnockbackMultiplier = 1,
	},
} :: Types.ActionDefinition