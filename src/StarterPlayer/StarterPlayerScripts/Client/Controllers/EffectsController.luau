--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local ObjectPool = require(Shared.Utils.ObjectPool)

local Trove = Packages.Trove
local Signal = Packages.Signal

local SettingsController = require(script.Parent.SettingsController)

export type EffectConfig = {
    Scale: number?,
    Duration: number?,
    Color: Color3?,
    Direction: Vector3?,
    QualityMultiplier: number?,
    [string]: any,
}

export type PoolConfig = ObjectPool.PoolConfig<Instance>

export type EffectDefinition = {
    Create: ((Position: Vector3, Config: EffectConfig) -> Instance?)?,
    Configure: ((Object: Instance, Position: Vector3, Config: EffectConfig) -> ())?,
    Duration: number?,
    PoolConfig: PoolConfig?,
}

type EffectPool = ObjectPool.ObjectPool<Instance>

local EffectsController = {}

EffectsController.Dependencies = { "SettingsController" }

local ControllerTrove: typeof(Trove.new()) = nil :: any
local LocalPlayer = Players.LocalPlayer :: Player
local RegisteredEffects: { [string]: EffectDefinition } = {}
local EffectPools: { [string]: EffectPool } = {}

EffectsController.EffectSpawned = Signal.new()

local function GetVfxQuality(): number
    return SettingsController.GetSetting("VfxQuality") :: number
end

local function GetVfxRenderDistance(): number
    local Value = SettingsController.GetSetting("VfxRenderDistance") :: number
    return Value * 200
end

local function GetPlayerPosition(): Vector3?
    local Character = LocalPlayer.Character
    if not Character then
        return nil
    end

    local Root = Character:FindFirstChild("HumanoidRootPart") :: BasePart?
    return if Root then Root.Position else nil
end

local function IsWithinRenderDistance(Position: Vector3): boolean
    local PlayerPosition = GetPlayerPosition()
    if not PlayerPosition then
        return false
    end

    local Distance = (Position - PlayerPosition).Magnitude
    return Distance <= GetVfxRenderDistance()
end

local function BuildEffectConfig(Config: EffectConfig?, QualityMultiplier: number): EffectConfig
    local BaseConfig = Config or {} :: EffectConfig
    return {
        Scale = (BaseConfig.Scale or 1) * QualityMultiplier,
        Duration = BaseConfig.Duration,
        Color = BaseConfig.Color,
        Direction = BaseConfig.Direction,
        QualityMultiplier = QualityMultiplier,
    }
end

function EffectsController.Init()
    ControllerTrove = Trove.new()
end

function EffectsController.Start()
    ControllerTrove:Connect(Packets.SpawnEffect.OnClientEvent :: any, function(EffectName: string, Position: Vector3, Config: EffectConfig?)
        EffectsController.SpawnEffect(EffectName, Position, Config)
    end)
end

function EffectsController.Stop()
    for EffectName, Pool in EffectPools do
        Pool:Destroy()
        EffectPools[EffectName] = nil
    end

    table.clear(RegisteredEffects)
    ControllerTrove:Destroy()
end

function EffectsController.RegisterEffect(EffectName: string, Definition: EffectDefinition)
    if RegisteredEffects[EffectName] then
        warn(string.format("[EffectsController] Effect already registered: %s", EffectName))
        return
    end

    RegisteredEffects[EffectName] = Definition

    if Definition.PoolConfig then
        EffectPools[EffectName] = ObjectPool.new(Definition.PoolConfig)
    end
end

function EffectsController.UnregisterEffect(EffectName: string)
    RegisteredEffects[EffectName] = nil

    local Pool = EffectPools[EffectName]
    if Pool then
        Pool:Destroy()
        EffectPools[EffectName] = nil
    end
end

function EffectsController.SpawnEffect(EffectName: string, Position: Vector3, Config: EffectConfig?): Instance?
    if not IsWithinRenderDistance(Position) then
        return nil
    end

    local Definition = RegisteredEffects[EffectName]
    if not Definition then
        warn(string.format("[EffectsController] Unknown effect: %s", EffectName))
        return nil
    end

    local QualityMultiplier = GetVfxQuality()
    local AdjustedConfig = BuildEffectConfig(Config, QualityMultiplier)
    local Duration = (Config and Config.Duration) or Definition.Duration or 2

    local EffectInstance: Instance?
    local Pool = EffectPools[EffectName]

    if Pool and Definition.Configure then
        local PooledObject = Pool:Get()
        Definition.Configure(PooledObject, Position, AdjustedConfig)
        PooledObject.Parent = workspace
        EffectInstance = PooledObject

        EffectsController.EffectSpawned:Fire(EffectName, PooledObject, Position)

        task.delay(Duration, function()
            Pool:Return(PooledObject)
        end)
    elseif Definition.Create then
        EffectInstance = Definition.Create(Position, AdjustedConfig)

        if EffectInstance then
            EffectsController.EffectSpawned:Fire(EffectName, EffectInstance, Position)

            task.delay(Duration, function()
                if EffectInstance and EffectInstance.Parent then
                    EffectInstance:Destroy()
                end
            end)
        end
    end

    return EffectInstance
end

function EffectsController.GetPool(EffectName: string): EffectPool?
    return EffectPools[EffectName]
end

function EffectsController.HasEffect(EffectName: string): boolean
    return RegisteredEffects[EffectName] ~= nil
end

function EffectsController.GetQualityMultiplier(): number
    return GetVfxQuality()
end

function EffectsController.ApplyQualityToCount(BaseCount: number): number
    local Multiplier = GetVfxQuality()
    return math.max(1, math.floor(BaseCount * Multiplier))
end

function EffectsController.IsWithinRenderDistance(Position: Vector3): boolean
    return IsWithinRenderDistance(Position)
end

return EffectsController