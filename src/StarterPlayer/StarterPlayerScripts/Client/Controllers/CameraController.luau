--!strict

--[=[
	@class CameraController

	Camera shake management.

	Wraps the Shake package to provide keyed camera shakes that respect
	the player's screen shake setting. Shakes are automatically cleaned
	up when completed or when the setting is toggled off.
]=]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)

local Shake = Packages.Shake
local Trove = Packages.Trove

local SettingsController = require(script.Parent.SettingsController)

local CameraController = {}

CameraController.Dependencies = { "SettingsController" }

local ControllerTrove: typeof(Trove.new()) = nil :: any
local Camera = Workspace.CurrentCamera
local ActiveShakes: { [string]: typeof(Shake.new()) } = {}

local function IsScreenShakeEnabled(): boolean
    return SettingsController.IsScreenShakeEnabled()
end

--[=[
	Creates the controller Trove for connection cleanup.
]=]
function CameraController.Init()
    ControllerTrove = Trove.new()
end

--[=[
	Subscribes to screen shake setting changes and stops all shakes if disabled.
]=]
function CameraController.Start()
    ControllerTrove:Connect(SettingsController.SettingChanged :: any, function(Key: string, Value: any)
        if Key == "ScreenShakeEnabled" and Value == false then
            CameraController.StopAllShakes()
        end
    end)
end

--[=[
	Stops all active shakes and destroys the controller Trove.
]=]
function CameraController.Stop()
    CameraController.StopAllShakes()
    ControllerTrove:Destroy()
end

--[=[
	Sets the camera mode. "Default" restores Roblox camera control,
	"Locked" switches to scriptable mode aimed at the given Target.

	@param Mode string -- "Default" or "Locked"
	@param Target Instance? -- Target instance for locked mode
]=]
function CameraController.SetMode(Mode: string, Target: Instance?)
    if not Camera then
        Camera = Workspace.CurrentCamera
    end

    if not Camera then
        return
    end

    if Mode == "Default" then
        Camera.CameraType = Enum.CameraType.Custom
    elseif Mode == "Locked" and Target then
        Camera.CameraType = Enum.CameraType.Scriptable
    end
end

--[=[
	Starts a camera shake with the given key. If a shake with the same key
	is already active, it is stopped first. Respects the screen shake setting.

	@param Key string -- Unique identifier for this shake
	@param Amplitude number -- Strength of the shake
	@param Duration number -- Total duration in seconds
]=]
function CameraController.Shake(Key: string, Amplitude: number, Duration: number)
    if not IsScreenShakeEnabled() then
        return
    end

    if not Camera then
        Camera = Workspace.CurrentCamera
    end

    local ExistingShake = ActiveShakes[Key]
    if ExistingShake then
        ExistingShake:Stop()
    end

    local NewShake = Shake.new()
    NewShake.FadeInTime = 0
    NewShake.FadeOutTime = Duration * 0.3
    NewShake.SustainTime = Duration * 0.7
    NewShake.Frequency = 0.1
    NewShake.Amplitude = Amplitude
    NewShake.PositionInfluence = Vector3.new(0.1, 0.1, 0.1)
    NewShake.RotationInfluence = Vector3.new(0.02, 0.02, 0.02)

    ActiveShakes[Key] = NewShake
    NewShake:Start()

    NewShake:OnSignal(RunService.RenderStepped, function(Position: Vector3, Rotation: Vector3, Done: boolean)
        if not Camera then
            return
        end
        Camera.CFrame *= CFrame.new(Position) * CFrame.Angles(Rotation.X, Rotation.Y, Rotation.Z)
        if Done then
            ActiveShakes[Key] = nil
        end
    end)
end

--[=[
	Stops a specific active shake by key.

	@param Key string -- The shake key to stop
]=]
function CameraController.StopShake(Key: string)
    local ExistingShake = ActiveShakes[Key]
    if ExistingShake then
        ExistingShake:Stop()
        ActiveShakes[Key] = nil
    end
end

--[=[
	Stops all active camera shakes.
]=]
function CameraController.StopAllShakes()
    for Key, ShakeInstance in ActiveShakes do
        ShakeInstance:Stop()
        ActiveShakes[Key] = nil
    end
end

--[=[
	Returns the current workspace Camera, fetching it if needed.

	@return Camera? -- The current camera, or nil
]=]
function CameraController.GetCamera(): Camera?
    if not Camera then
        Camera = Workspace.CurrentCamera
    end
    return Camera
end

return CameraController