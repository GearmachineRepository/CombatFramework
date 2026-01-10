--!strict

local RunService = game:GetService("RunService")

local IsServer = RunService:IsServer()

local AnimationHandler = {}

function AnimationHandler.Execute(Block: any, Context: any): any?
    if IsServer then
        return nil
    end

    local AnimationId = Block.AnimationId
    local Speed = Block.Speed or 1
    local Loop = Block.Loop or false
    local LastHit = Block.LastHit or -1

    local Target
    if LastHit >= 0 then
        Target = Context.GetLastHitTarget()
        if not Target then
            return nil
        end
    else
        Target = Context.Entity.Character
    end

    local Humanoid = Target:FindFirstChildOfClass("Humanoid")
    if not Humanoid then
        return nil
    end

    local Animator = Humanoid:FindFirstChildOfClass("Animator")
    if not Animator then
        return nil
    end

    local Animation = Instance.new("Animation")
    Animation.AnimationId = AnimationId

    local Track = Animator:LoadAnimation(Animation)
    Track.Looped = Loop
    Track:Play()
    Track:AdjustSpeed(Speed)

    if not Loop then
        Track.Stopped:Wait()
    end

    Animation:Destroy()

    return nil
end

return AnimationHandler