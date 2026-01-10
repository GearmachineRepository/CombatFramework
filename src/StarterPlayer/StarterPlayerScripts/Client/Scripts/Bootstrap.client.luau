--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = Players.LocalPlayer.PlayerScripts:WaitForChild("Client")

local ServiceLoader = require(Shared.Utils.ServiceLoader)

ServiceLoader.LoadServices(Client.Controllers)
ServiceLoader.InitAll()
ServiceLoader.StartAll()

print("[Client] Bootstrap complete")
print("[Client] Load order:", table.concat(ServiceLoader.GetLoadOrder(), " -> "))