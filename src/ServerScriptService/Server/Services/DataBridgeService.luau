--!strict

--[=[
	@class DataBridgeService

	Rate-limited bridge for client data requests.

	Allows clients to request whitelisted slices of their player data
	via a request/response packet pattern. Rate limits are enforced
	per-player using the shared RateLimiter utility.
]=]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Server = ServerScriptService:WaitForChild("Server")

local Packages = require(Shared.Packages)
local Packets = require(Shared.Network.Packets)
local RateLimiter = require(Shared.Utils.RateLimiter)

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

local RequestLimiter = RateLimiter.Create({
	MaxTokens = 10,
	RefillRate = 10,
	RefillInterval = 1,
})

local function GetPlayerRateKey(Player: Player): string
	return tostring(Player.UserId)
end

function DataBridgeService.Init()
	ServiceTrove = Trove.new()
end

function DataBridgeService.Start()
	ServiceTrove:Connect(Players.PlayerRemoving, function(Player: Player)
		RequestLimiter.Reset(GetPlayerRateKey(Player))
	end)

	ServiceTrove:Connect(Packets.FetchData.OnServerEvent :: any, function(Player: Player, RequestId: any, Key: any)
		if typeof(RequestId) ~= "string" or typeof(Key) ~= "string" then
			return
		end

		if not RequestLimiter.Consume(GetPlayerRateKey(Player)) then
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
	end)
end

function DataBridgeService.Stop()
	ServiceTrove:Destroy()
	RequestLimiter.Destroy()
end

--[=[
	Adds a key to the whitelist of requestable data keys.

	@param Key string -- The data key to allow
]=]
function DataBridgeService.AddAllowedKey(Key: string)
	ALLOWED_KEYS[Key] = true
end

--[=[
	Removes a key from the whitelist of requestable data keys.

	@param Key string -- The data key to disallow
]=]
function DataBridgeService.RemoveAllowedKey(Key: string)
	ALLOWED_KEYS[Key] = nil
end

--[=[
	Returns whether a data key is currently whitelisted.

	@param Key string -- The data key to check
	@return boolean -- True if the key is allowed
]=]
function DataBridgeService.IsKeyAllowed(Key: string): boolean
	return ALLOWED_KEYS[Key] == true
end

return DataBridgeService