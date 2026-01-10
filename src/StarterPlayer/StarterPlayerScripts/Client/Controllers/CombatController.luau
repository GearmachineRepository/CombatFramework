--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local Enums = require(Shared.Enums)
local Combat = require(Shared.Combat)
local EventBus = require(Shared.Utils.EventBus)

local Trove = Packages.Trove
local Signal = Packages.Signal

local SkillExecutor = Combat.SkillExecutor
local SkillRegistry = Combat.SkillRegistry
local ToolRegistry = Combat.ToolRegistry

local LocalPlayer = Players.LocalPlayer :: Player

local CombatController = {}

CombatController.Dependencies = { "ToolbarController" }

CombatController.SkillActivated = Signal.new()
CombatController.SkillCompleted = Signal.new()
CombatController.SkillCanceled = Signal.new()
CombatController.SkillRejected = Signal.new()
CombatController.HitConfirmed = Signal.new()

local ControllerTrove: typeof(Trove.new()) = nil :: any
local LocalEventBus: typeof(EventBus.new()) = nil :: any
local Cooldowns: { [string]: number } = {}
local ActiveContext: any = nil

function CombatController.Init()
    ControllerTrove = Trove.new()
    LocalEventBus = EventBus.new()

    local SkillsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Skills")
    if SkillsFolder then
        SkillRegistry.LoadFolder(SkillsFolder)
    end

    local ToolsFolder = Shared:FindFirstChild("Data") and Shared.Data:FindFirstChild("Tools")
    if ToolsFolder then
        ToolRegistry.LoadFolder(ToolsFolder)
    end
end

function CombatController.Start()
    ControllerTrove:Connect(Packets.SkillRejected.OnClientEvent :: any, function(SkillId: string, Reason: string)
        CombatController.OnSkillRejected(SkillId, Reason)
    end)

    ControllerTrove:Connect(Packets.SkillSync.OnClientEvent :: any, function(SkillId: string, Branch: string, Canceled: boolean)
        CombatController.OnSkillSync(SkillId, Branch, Canceled)
    end)

    ControllerTrove:Connect(Packets.CooldownStarted.OnClientEvent :: any, function(SkillId: string, Duration: number)
        CombatController.OnCooldownStarted(SkillId, Duration)
    end)

    ControllerTrove:Connect(Packets.HitConfirmed.OnClientEvent :: any, function(Attacker: Instance?, Target: Instance?, Damage: number, Position: Vector3, AttackType: string)
        CombatController.OnHitConfirmed(Attacker, Target, Damage, Position, AttackType)
    end)

    ControllerTrove:Add(LocalEventBus:Subscribe(Enums.Combat.Connect.SignalSent, function(Data: any)
        Packets.ConnectSignal:Fire(Data.Signal, Data.Position, Data.Range, Data.Duration)
    end))
end

function CombatController.Stop()
    ControllerTrove:Destroy()

    if LocalEventBus then
        LocalEventBus:Destroy()
    end

    table.clear(Cooldowns)
    ActiveContext = nil
end

function CombatController.IsOnCooldown(SkillId: string): boolean
    local CooldownEnd = Cooldowns[SkillId]
    if not CooldownEnd then
        return false
    end
    return tick() < CooldownEnd
end

function CombatController.GetCooldownRemaining(SkillId: string): number
    local CooldownEnd = Cooldowns[SkillId]
    if not CooldownEnd then
        return 0
    end
    return math.max(0, CooldownEnd - tick())
end

function CombatController.CanActivate(SkillId: string): (boolean, string?)
    if CombatController.IsOnCooldown(SkillId) then
        return false, "OnCooldown"
    end

    if ActiveContext then
        return false, "SkillActive"
    end

    local Character = LocalPlayer.Character
    if not Character then
        return false, "NoCharacter"
    end

    local Humanoid = Character:FindFirstChildOfClass("Humanoid")
    if not Humanoid or Humanoid.Health <= 0 then
        return false, "Dead"
    end

    local SkillDef = SkillRegistry.Get(SkillId)
    if not SkillDef then
        return false, "UnknownSkill"
    end

    if SkillDef.Conditions then
        if SkillDef.Conditions.OnAir == false then
            if Humanoid.FloorMaterial == Enum.Material.Air then
                return false, "NotGrounded"
            end
        elseif SkillDef.Conditions.OnAir == true then
            if Humanoid.FloorMaterial ~= Enum.Material.Air then
                return false, "NotAirborne"
            end
        end
    end

    return true, nil
end

function CombatController.ActivateSkill(SkillId: string): boolean
    local CanUse, Reason = CombatController.CanActivate(SkillId)

    if not CanUse then
        CombatController.SkillRejected:Fire(SkillId, Reason)
        return false
    end

    local SkillDef = SkillRegistry.Get(SkillId)
    if not SkillDef then
        return false
    end

    local Character = LocalPlayer.Character :: Model

    local Entity = {
        Character = Character,
        Humanoid = Character:FindFirstChildOfClass("Humanoid"),
        IsPlayer = true,
        Player = LocalPlayer,
    }

    Packets.SkillActivate:Fire(SkillId, tick())

    task.spawn(function()
        ActiveContext = SkillExecutor.Execute(Entity, SkillDef, LocalEventBus)

        CombatController.SkillActivated:Fire(SkillId)

        while ActiveContext and not ActiveContext.Canceled do
            if ActiveContext.GetElapsedTime() > 30 then
                ActiveContext.Cancel()
                break
            end
            task.wait()
        end

        local WasCanceled = ActiveContext and ActiveContext.Canceled
        ActiveContext = nil

        if WasCanceled then
            CombatController.SkillCanceled:Fire(SkillId)
        else
            CombatController.SkillCompleted:Fire(SkillId)
        end
    end)

    return true
end

function CombatController.CancelSkill()
    if ActiveContext then
        local SkillId = ActiveContext.SkillDefinition.SkillId
        SkillExecutor.Cancel(ActiveContext)
        Packets.SkillCancel:Fire(SkillId)
    end
end

function CombatController.OnSkillRejected(SkillId: string, Reason: string)
    if ActiveContext and ActiveContext.SkillDefinition.SkillId == SkillId then
        SkillExecutor.Cancel(ActiveContext)
    end

    CombatController.SkillRejected:Fire(SkillId, Reason)
end

function CombatController.OnSkillSync(SkillId: string, _Branch: string, Canceled: boolean)
    if Canceled and ActiveContext then
        if ActiveContext.SkillDefinition.SkillId == SkillId then
            SkillExecutor.Cancel(ActiveContext)
        end
    end
end

function CombatController.OnCooldownStarted(SkillId: string, Duration: number)
    Cooldowns[SkillId] = tick() + Duration
end

function CombatController.OnHitConfirmed(Attacker: Instance?, Target: Instance?, Damage: number, Position: Vector3, AttackType: string)
    CombatController.HitConfirmed:Fire({
        Attacker = Attacker,
        Target = Target,
        Damage = Damage,
        Position = Position,
        AttackType = AttackType,
    })

    LocalEventBus:Publish(Enums.Combat.Hitbox.Hit, {
        Attacker = Attacker,
        Target = Target,
        Damage = Damage,
        Position = Position,
        AttackType = AttackType,
    })
end

function CombatController.IsSkillActive(): boolean
    return ActiveContext ~= nil
end

function CombatController.GetActiveSkillId(): string?
    if ActiveContext then
        return ActiveContext.SkillDefinition.SkillId
    end
    return nil
end

function CombatController.GetEventBus(): typeof(EventBus.new())
    return LocalEventBus
end

return CombatController