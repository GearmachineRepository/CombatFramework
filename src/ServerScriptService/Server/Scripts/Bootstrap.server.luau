--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Server = ServerScriptService:WaitForChild("Server")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local ServiceLoader = require(Shared.Utils.ServiceLoader)
local Ensemble = require(Server.Ensemble)
local HookLoader = require(Server.HookUtil.HookLoader)

HookLoader.Configure(Server.Hooks)

Ensemble.Init({
    Components = Server.Components,
    Archetypes = {
        Player = { "Stats", "States", "Modifiers", "Inventory" },
        Enemy = { "Stats", "States", "Modifiers" },
    },
})

ServiceLoader.LoadServices(Server.Services)
ServiceLoader.InitAll()
ServiceLoader.StartAll()

print("[Server] Bootstrap complete")
print("[Server] Load order:", table.concat(ServiceLoader.GetLoadOrder(), " -> "))