--!strict

type EffectConfig = {
	Scale: number?,
	Duration: number?,
	Color: Color3?,
	Direction: Vector3?,
	QualityMultiplier: number?,
	[string]: any,
}

type PoolConfig = {
	Create: () -> Instance,
	Reset: (Object: Instance) -> (),
	InitialSize: number?,
	MaxSize: number?,
}

type EffectDefinition = {
	Create: ((Position: Vector3, Config: EffectConfig) -> Instance?)?,
	Configure: ((Object: Instance, Position: Vector3, Config: EffectConfig) -> ())?,
	Duration: number?,
	PoolConfig: PoolConfig?,
}

local EffectDefinitions: { [string]: EffectDefinition } = {}

EffectDefinitions.HitSpark = {
	Duration = 0.5,

	PoolConfig = {
		Create = function(): Instance
			local Part = Instance.new("Part")
			Part.Name = "HitSpark"
			Part.Size = Vector3.new(0.5, 0.5, 0.5)
			Part.Anchored = true
			Part.CanCollide = false
			Part.CanQuery = false
			Part.CanTouch = false
			Part.Material = Enum.Material.Neon
			Part.Color = Color3.fromRGB(255, 200, 100)
			return Part
		end,

		Reset = function(Object: Instance)
			local Part = Object :: BasePart
			Part.CFrame = CFrame.identity
			Part.Parent = nil
			Part.Transparency = 0
			Part.Size = Vector3.new(0.5, 0.5, 0.5)
			Part.Color = Color3.fromRGB(255, 200, 100)
		end,

		InitialSize = 10,
		MaxSize = 50,
	},

	Configure = function(Object: Instance, Position: Vector3, Config: EffectConfig)
		local Part = Object :: BasePart
		Part.Position = Position

		if Config.Color then
			Part.Color = Config.Color
		end

		if Config.Scale then
			Part.Size = Vector3.new(0.5, 0.5, 0.5) * Config.Scale
		end
	end,
}

EffectDefinitions.ImpactRing = {
	Duration = 1,

	Create = function(Position: Vector3, Config: EffectConfig): Instance?
		local QualityMultiplier = Config.QualityMultiplier or 1
		local Scale = Config.Scale or 1

		local SegmentCount = math.max(4, math.floor(12 * QualityMultiplier))

		local Container = Instance.new("Model")
		Container.Name = "ImpactRing"

		for Index = 1, SegmentCount do
			local Angle = (Index / SegmentCount) * math.pi * 2
			local Offset = Vector3.new(math.cos(Angle), 0, math.sin(Angle)) * Scale

			local Part = Instance.new("Part")
			Part.Size = Vector3.new(0.2, 0.1, 0.2)
			Part.Position = Position + Offset
			Part.Anchored = true
			Part.CanCollide = false
			Part.CanQuery = false
			Part.CanTouch = false
			Part.Material = Enum.Material.Neon
			Part.Color = Config.Color or Color3.fromRGB(100, 150, 255)
			Part.Parent = Container
		end

		Container.Parent = workspace
		return Container
	end,
}

EffectDefinitions.Bullet = {
	Duration = 5,

	PoolConfig = {
		Create = function(): Instance
			local Part = Instance.new("Part")
			Part.Name = "Bullet"
			Part.Size = Vector3.new(0.2, 0.2, 1)
			Part.Anchored = true
			Part.CanCollide = false
			Part.CanQuery = false
			Part.CanTouch = false
			Part.Material = Enum.Material.Neon
			Part.Color = Color3.fromRGB(255, 255, 100)
			return Part
		end,

		Reset = function(Object: Instance)
			local Part = Object :: BasePart
			Part.CFrame = CFrame.identity
			Part.Parent = nil
			Part.Transparency = 0
			Part.Color = Color3.fromRGB(255, 255, 100)
		end,

		InitialSize = 20,
		MaxSize = 100,
	},

	Configure = function(Object: Instance, Position: Vector3, Config: EffectConfig)
		local Part = Object :: BasePart
		Part.Position = Position

		if Config.Color then
			Part.Color = Config.Color
		end

		if Config.Direction then
			Part.CFrame = CFrame.lookAt(Position, Position + Config.Direction)
		end
	end,
}

EffectDefinitions.TrailAttachment = {
	Duration = 2,

	PoolConfig = {
		Create = function(): Instance
			local Attachment = Instance.new("Attachment")
			Attachment.Name = "TrailAttachment"
			return Attachment
		end,

		Reset = function(Object: Instance)
			local Attachment = Object :: Attachment
			Attachment.WorldPosition = Vector3.zero
			Attachment.Parent = nil
		end,

		InitialSize = 5,
		MaxSize = 20,
	},

	Configure = function(Object: Instance, Position: Vector3, _Config: EffectConfig)
		local Attachment = Object :: Attachment
		Attachment.WorldPosition = Position
	end,
}

return EffectDefinitions