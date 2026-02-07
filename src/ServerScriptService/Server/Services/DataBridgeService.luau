--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)

local Trove = Packages.Trove
local TableUtil = Packages.TableUtil

local PlayerDataService = require(Server.Services.PlayerDataService)

local DataBridgeService = {}

DataBridgeService.Dependencies = { "PlayerDataService" }

local ServiceTrove: typeof(Trove.new()) = nil :: any

local ALLOWED_KEYS: { [string]: boolean } = {
	Inventory = true,
	Currency = true,
	Stats = true,
}

local RATE_LIMIT_INTERVAL = 1
local MAX_REQUESTS_PER_INTERVAL = 10

local RequestCounts: { [Player]: { Count: number, ResetTime: number } } = {}

local function CheckRateLimit(Player: Player): boolean
	local CurrentTime = os.clock()
	local PlayerData = RequestCounts[Player]

	if not PlayerData or CurrentTime >= PlayerData.ResetTime then
		RequestCounts[Player] = {
			Count = 1,
			ResetTime = CurrentTime + RATE_LIMIT_INTERVAL,
		}
		return true
	end

	if PlayerData.Count >= MAX_REQUESTS_PER_INTERVAL then
		return false
	end

	PlayerData.Count = PlayerData.Count + 1
	return true
end

function DataBridgeService.Init()
	ServiceTrove = Trove.new()
end

function DataBridgeService.Start()
	ServiceTrove:Connect(Players.PlayerRemoving, function(Player: Player)
		RequestCounts[Player] = nil
	end)

	ServiceTrove:Add(Packets.FetchData.OnServerEvent:Connect(function(Player: Player, RequestId: any, Key: any)
		if typeof(RequestId) ~= "string" or typeof(Key) ~= "string" then
			return
		end

		if not CheckRateLimit(Player) then
			Packets.DataResponse:FireClient(Player, RequestId, false, nil)
			return
		end

		if not ALLOWED_KEYS[Key] then
			Packets.DataResponse:FireClient(Player, RequestId, false, nil)
			return
		end

		local Data = PlayerDataService.GetData(Player)
		if not Data then
			Packets.DataResponse:FireClient(Player, RequestId, false, nil)
			return
		end

		local Value = (Data :: any)[Key]
		if Value == nil then
			Packets.DataResponse:FireClient(Player, RequestId, false, nil)
			return
		end

		local SafeValue = Value
		if typeof(Value) == "table" then
			SafeValue = TableUtil.Copy(Value, true)
		end

		Packets.DataResponse:FireClient(Player, RequestId, true, SafeValue)
	end))
end

function DataBridgeService.Stop()
	ServiceTrove:Destroy()
	table.clear(RequestCounts)
end

function DataBridgeService.AddAllowedKey(Key: string)
	ALLOWED_KEYS[Key] = true
end

function DataBridgeService.RemoveAllowedKey(Key: string)
	ALLOWED_KEYS[Key] = nil
end

function DataBridgeService.IsKeyAllowed(Key: string): boolean
	return ALLOWED_KEYS[Key] == true
end

return DataBridgeService