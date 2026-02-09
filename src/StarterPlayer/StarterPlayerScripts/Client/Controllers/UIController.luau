--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)

local Trove = Packages.Trove
local Signal = Packages.Signal

local LocalPlayer = Players.LocalPlayer :: Player
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local UIController = {}

local ControllerTrove: typeof(Trove.new()) = nil :: any
local Screens: { [string]: ScreenGui } = {}
local ActiveScreens: { [string]: boolean } = {}

UIController.ScreenShown = Signal.new()
UIController.ScreenHidden = Signal.new()

function UIController.Init()
    ControllerTrove = Trove.new()
end

function UIController.Start()
    ControllerTrove:Connect(PlayerGui.ChildAdded, function(Child: Instance)
        if Child:IsA("ScreenGui") then
            UIController.RegisterScreen(Child.Name, Child)
        end
    end)

    ControllerTrove:Connect(PlayerGui.ChildRemoved, function(Child: Instance)
        if Child:IsA("ScreenGui") then
            UIController.UnregisterScreen(Child.Name)
        end
    end)

    for _, Child in PlayerGui:GetChildren() do
        if Child:IsA("ScreenGui") then
            UIController.RegisterScreen(Child.Name, Child)
        end
    end
end

function UIController.Stop()
    for Name in Screens do
        UIController.UnregisterScreen(Name)
    end
    ControllerTrove:Destroy()
end

function UIController.RegisterScreen(Name: string, Screen: ScreenGui)
    if Screens[Name] then
        warn(string.format("[UIController] Screen already registered: %s", Name))
        return
    end

    Screen.Name = Name
    Screen.Parent = PlayerGui
    Screens[Name] = Screen
    ControllerTrove:Add(Screen)
end

function UIController.UnregisterScreen(Name: string)
    local Screen = Screens[Name]
    if not Screen then
        return
    end

    ActiveScreens[Name] = nil
    Screens[Name] = nil
end

function UIController.ShowScreen(Name: string)
    local Screen = Screens[Name]
    if not Screen then
        warn(string.format("[UIController] Screen not found: %s", Name))
        return
    end

    if ActiveScreens[Name] then
        return
    end

    Screen.Enabled = true
    ActiveScreens[Name] = true
    UIController.ScreenShown:Fire(Name, Screen)
end

function UIController.HideScreen(Name: string)
    local Screen = Screens[Name]
    if not Screen then
        return
    end

    if not ActiveScreens[Name] then
        return
    end

    Screen.Enabled = false
    ActiveScreens[Name] = nil
    UIController.ScreenHidden:Fire(Name, Screen)
end

function UIController.ToggleScreen(Name: string)
    if ActiveScreens[Name] then
        UIController.HideScreen(Name)
    else
        UIController.ShowScreen(Name)
    end
end

function UIController.IsScreenVisible(Name: string): boolean
    return ActiveScreens[Name] == true
end

function UIController.GetScreen(Name: string): ScreenGui?
    return Screens[Name]
end

function UIController.GetAllScreens(): { [string]: ScreenGui }
    return table.clone(Screens)
end

function UIController.HideAllScreens()
    for Name in ActiveScreens do
        UIController.HideScreen(Name)
    end
end

return UIController