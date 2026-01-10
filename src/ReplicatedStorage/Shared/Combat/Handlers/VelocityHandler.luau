--!strict

local TweenService = game:GetService("TweenService")

local VelocityHandler = {}

function VelocityHandler.Execute(Block: any, Context: any): any?
    local VelX = Block.X or 0
    local VelY = Block.Y or 0
    local VelZ = Block.Z or 0
    local Time = Block.Time or 0.1
    local Fade = Block.Fade or false
    local Track = Block.Track ~= false
    local LastHit = Block.LastHit or -1
    local _Ragdoll = Block.Ragdoll or 0

    local Target
    if LastHit >= 0 then
        Target = Context.GetLastHitTarget()
        if not Target then
            return nil
        end
    else
        Target = Context.Entity.Character
    end

    local RootPart = Target:FindFirstChild("HumanoidRootPart") :: BasePart?
    if not RootPart then
        return nil
    end

    local Velocity = Vector3.new(VelX, VelY, VelZ)

    if Track then
        Velocity = RootPart.CFrame:VectorToWorldSpace(Velocity)
    end

    local BodyVelocity = Instance.new("BodyVelocity")
    BodyVelocity.MaxForce = Vector3.new(1, 1, 1) * math.huge
    BodyVelocity.Velocity = Velocity
    BodyVelocity.Parent = RootPart

    if Fade then
        local Tween = TweenService:Create(BodyVelocity, TweenInfo.new(Time), {
            Velocity = Vector3.zero,
        })
        Tween:Play()
        Tween.Completed:Wait()
        BodyVelocity:Destroy()
    else
        task.delay(Time, function()
            BodyVelocity:Destroy()
        end)
        task.wait(Time)
    end

    return nil
end

return VelocityHandler