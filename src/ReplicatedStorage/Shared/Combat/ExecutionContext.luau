--!strict

local ExecutionContext = {}

local DEFAULT_PROPERTIES = {
    DamageMultiplier = 1,
    KnockbackMultiplier = 1,
    Invincible = false,
}

function ExecutionContext.Create(Entity: any, SkillDefinition: any, EventBus: any): any
    local StartTime = tick()

    local Properties = table.clone(DEFAULT_PROPERTIES)
    if SkillDefinition.Properties then
        for Key, Value in SkillDefinition.Properties do
            Properties[Key] = Value
        end
    end

    local Context = {
        Entity = Entity,
        SkillDefinition = SkillDefinition,
        EventBus = EventBus,
        StartTime = StartTime,
        Canceled = false,
        Properties = Properties,
        HitRecords = {},
        LastHitTarget = nil,
    }

    function Context.GetElapsedTime(): number
        return tick() - StartTime
    end

    function Context.Cancel()
        Context.Canceled = true
    end

    function Context.RecordHit(Target: Model, Damage: number)
        table.insert(Context.HitRecords, {
            Target = Target,
            Timestamp = tick(),
            Damage = Damage,
        })
        Context.LastHitTarget = Target :: any
    end

    function Context.HadHitInWindow(WindowSeconds: number): boolean
        local CutoffTime = tick() - WindowSeconds
        for _, Record in Context.HitRecords do
            if Record.Timestamp >= CutoffTime then
                return true
            end
        end
        return false
    end

    function Context.GetLastHitTarget(): Model?
        return Context.LastHitTarget
    end

    return Context
end

return ExecutionContext