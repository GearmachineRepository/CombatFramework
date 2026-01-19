--!strict

--[[
    SpeedBoostHook

    Example hook that increases player walkspeed while active.

    Usage:
        local HookComponent = Entity:GetComponent("Hooks")
        HookComponent.Register("SpeedBoost")  -- Activates SpeedBoost
        HookComponent.Unregister("SpeedBoost") -- Deactivates SpeedBoost

    Hooks are temporary modifiers that can be toggled on/off.
    They're useful for buffs, debuffs, status effects, passives, talents etc.
]]

local ServerScriptService = game:GetService("ServerScriptService")
local EnsembleTypes = require(ServerScriptService.Server.Ensemble.Types)

type Entity = EnsembleTypes.Entity

local BOOST_MULTIPLIER = 1.5

local SpeedBoostHook = {}

SpeedBoostHook.HookName = "SpeedBoost"

function SpeedBoostHook.OnActivate(Entity: Entity): (() -> ())?
    local Humanoid = Entity.Humanoid
    if not Humanoid then
        return nil
    end

    local OriginalSpeed = Humanoid.WalkSpeed
    Humanoid.WalkSpeed = OriginalSpeed * BOOST_MULTIPLIER

    local function Cleanup()
        if Humanoid and Humanoid.Parent then
            Humanoid.WalkSpeed = OriginalSpeed
        end
    end

    return Cleanup
end

return SpeedBoostHook