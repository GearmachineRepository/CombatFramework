--!strict

return {
	ActionId = "TestPunch",
	DisplayName = "Test Punch",

	Timeline = {
		{ BlockType = "Wait", Time = 0.1 },
		{ BlockType = "Hitbox", X = 0, Y = 0, Z = 4, SizeX = 6, SizeY = 6, SizeZ = 6, Damage = 10, Stun = 0.3 },
		{ BlockType = "HitCancel", Time = 0.5, Flip = true, Endlag = 0.2 },
		{ BlockType = "Wait", Time = 0.3 },
	},

	Conditions = {
		OnAir = false,
	},

	Properties = {
		DamageMultiplier = 1,
	},
}