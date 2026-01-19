--!strict

local Types = require(script.Parent.Parent.Parent.Types.CombatTypes)

return {
	ActionId = "GrabThrow",
	DisplayName = "Grab and Throw",
	Cooldown = 5,

	Branches = {
		Main = {
			Entry = true,
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 1 },
				{ BlockType = "Wait", Time = 0.15 },
				{
					BlockType = "Grab",
					X = 0, Y = 0, Z = 3,
					SizeX = 5, SizeY = 5, SizeZ = 5,
					HoldOffsetX = 0,
					HoldOffsetY = 0,
					HoldOffsetZ = -2.5,
					Duration = 2,
					AttackerAnimation = "rbxassetid://0",
					TargetAnimation = "rbxassetid://0",
					ThrowBranch = "Throw",
					ReleaseBranch = "Release",
					MissBranch = "WhiffRecovery",
				},
			},
		},

		Throw = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 1.2 },
				{ BlockType = "Wait", Time = 0.1 },
				{ BlockType = "Sound", SoundId = "rbxassetid://0", Volume = 0.8 },
				{
					BlockType = "Hitbox",
					X = 0, Y = 0, Z = 3,
					SizeX = 4, SizeY = 4, SizeZ = 4,
					Damage = 20,
					Stun = 0.6,
					LaunchY = 15,
					LaunchZ = 40,
					AttackType = "Grab",
					Unblockable = true,
				},
				{ BlockType = "Wait", Time = 0.4 },
			},
		},

		Release = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 0.8 },
				{ BlockType = "Wait", Time = 0.3 },
			},
		},

		WhiffRecovery = {
			Timeline = {
				{ BlockType = "Animation", AnimationId = "rbxassetid://0", Speed = 0.6 },
				{ BlockType = "Wait", Time = 0.7 },
			},
		},
	},

	Conditions = {
		OnAir = false,
	},

	Properties = {
		DamageMultiplier = 1,
		KnockbackMultiplier = 1,
		CanCancel = false,
	},
} :: Types.ActionDefinition