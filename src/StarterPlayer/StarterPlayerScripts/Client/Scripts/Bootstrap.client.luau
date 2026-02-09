--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer :: Player

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Client = LocalPlayer.PlayerScripts:WaitForChild("Client")

local ServiceLoader = require(Shared.Utils.ServiceLoader)

ServiceLoader.LoadServices(Client.Controllers)
ServiceLoader.InitAll()
ServiceLoader.StartAll()