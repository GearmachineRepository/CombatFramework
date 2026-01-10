--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Packages = require(Shared.Packages)

local Trove = Packages.Trove

local EntityService = require(script.Parent.EntityService)

local PlayerService = {}

local PlayerTroves: { [Player]: typeof(Trove.new()) } = {}

local function OnCharacterAdded(Player: Player, Character: Model)
	if EntityService.GetEntity(Character) then
		return
	end

	local Humanoid = Character:WaitForChild("Humanoid", 5) :: Humanoid?
	if not Humanoid then
		warn("[PlayerService] No Humanoid for", Player.Name)
		return
	end

	EntityService.CreateEntity(Character, {
		Player = Player,
	})
end

local function OnCharacterRemoving(Character: Model)
	EntityService.DestroyEntity(Character)
end

local function OnPlayerAdded(Player: Player)
	local PlayerTrove = Trove.new()
	PlayerTroves[Player] = PlayerTrove

	PlayerTrove:Connect(Player.CharacterAdded, function(Character)
		OnCharacterAdded(Player, Character)
	end)

	PlayerTrove:Connect(Player.CharacterRemoving, OnCharacterRemoving)

	if Player.Character then
		OnCharacterAdded(Player, Player.Character)
	end
end

local function OnPlayerRemoving(Player: Player)
	local PlayerTrove = PlayerTroves[Player]
	if PlayerTrove then
		PlayerTrove:Destroy()
		PlayerTroves[Player] = nil
	end

	if Player.Character then
		EntityService.DestroyEntity(Player.Character)
	end
end

function PlayerService.Start()
	for _, Player in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, Player)
	end

	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

function PlayerService.GetTrove(Player: Player): typeof(Trove.new())?
	return PlayerTroves[Player]
end

return PlayerService