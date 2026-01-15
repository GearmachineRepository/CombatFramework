--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local Packages = require(Shared.Packages)
local Combat = require(Shared.Combat)

local Trove = Packages.Trove
local Signal = Packages.Signal

local ToolRegistry = Combat.ToolRegistry

local ToolService = {}

ToolService.Dependencies = {}

ToolService.LoadoutChanged = Signal.new()

local ServiceTrove: typeof(Trove.new()) = nil :: any
local PlayerLoadouts: { [Player]: { [number]: string } } = {}

function ToolService.Init()
    ServiceTrove = Trove.new()
end

function ToolService.Start()
    ServiceTrove:Connect(Players.PlayerAdded, function(Player: Player)
        ToolService.OnPlayerAdded(Player)
    end)

    ServiceTrove:Connect(Players.PlayerRemoving, function(Player: Player)
        PlayerLoadouts[Player] = nil
    end)

    for _, Player in Players:GetPlayers() do
        task.spawn(ToolService.OnPlayerAdded, Player)
    end
end

function ToolService.Stop()
    ServiceTrove:Destroy()
    table.clear(PlayerLoadouts)
end

function ToolService.OnPlayerAdded(Player: Player)
    local DefaultLoadout = ToolService.GetDefaultLoadout()
    PlayerLoadouts[Player] = DefaultLoadout

    Player.CharacterAdded:Connect(function(Character: Model)
        ToolService.GiveTools(Player, Character)
    end)

    if Player.Character then
        ToolService.GiveTools(Player, Player.Character)
    end
end

function ToolService.GetDefaultLoadout(): { [number]: string }
    local Loadout: { [number]: string } = {}

    for ToolId, ToolDef in ToolRegistry.GetAll() do
        if ToolDef.Slot then
            Loadout[ToolDef.Slot] = ToolId
        end
    end

    return Loadout
end

function ToolService.GiveTools(Player: Player, _Character: Model)
    local Backpack = Player:FindFirstChild("Backpack")
    if not Backpack then
        return
    end

    local Loadout = PlayerLoadouts[Player]
    if not Loadout then
        return
    end

    local ToolsFolder = ServerStorage:FindFirstChild("Tools")

    for Slot, ToolId in Loadout do
        local ToolDef = ToolRegistry.Get(ToolId)
        if not ToolDef then
            continue
        end

        local Tool: Tool? = nil

        if ToolsFolder then
            local Template = ToolsFolder:FindFirstChild(ToolId)
            if Template and Template:IsA("Tool") then
                Tool = Template:Clone()
            end
        end

        if not Tool then
            local NewTool = Instance.new("Tool")
            NewTool.Name = ToolDef.DisplayName or ToolId
            NewTool.RequiresHandle = false
            Tool = NewTool
        end

        if not Tool then return end

        Tool:SetAttribute("ToolId", ToolId)
        Tool:SetAttribute("ActionId", ToolDef.ActionId)
        Tool:SetAttribute("Slot", Slot)
        Tool.Parent = Backpack
    end
end

function ToolService.SetLoadout(Player: Player, Loadout: { [number]: string })
    PlayerLoadouts[Player] = table.clone(Loadout)
    ToolService.LoadoutChanged:Fire(Player, Loadout)

    if Player.Character then
        local Backpack = Player:FindFirstChild("Backpack")
        if Backpack then
            for _, Child in Backpack:GetChildren() do
                if Child:IsA("Tool") then
                    Child:Destroy()
                end
            end
        end

        ToolService.GiveTools(Player, Player.Character)
    end
end

function ToolService.GetLoadout(Player: Player): { [number]: string }?
    local Loadout = PlayerLoadouts[Player]
    if Loadout then
        return table.clone(Loadout)
    end
    return nil
end

function ToolService.SetSlot(Player: Player, Slot: number, ToolId: string?)
    if not PlayerLoadouts[Player] then
        PlayerLoadouts[Player] = {}
    end

    if not ToolId then return end

    PlayerLoadouts[Player][Slot] = ToolId
    ToolService.LoadoutChanged:Fire(Player, PlayerLoadouts[Player])
end

return ToolService