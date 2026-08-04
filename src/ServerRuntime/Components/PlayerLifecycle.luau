--!strict

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))

local PlayerLifecycle = {
	Name = "PlayerLifecycle",
	Trove = nil :: any,
	PlayerTroves = {} :: { [Player]: any },
}

function PlayerLifecycle:_TrackPlayer(Player: Player): ()
	if self.PlayerTroves[Player] then
		return
	end

	local PlayerTrove: any = Trove.new()
	self.PlayerTroves[Player] = PlayerTrove
	PlayerTrove:Connect(Player.CharacterAdded, function(Character: Model): ()
		Framework.RuntimeEvents.CharacterAdded:Fire(Player, Character)
	end)
	PlayerTrove:Connect(Player.CharacterRemoving, function(Character: Model): ()
		Framework.RuntimeEvents.CharacterRemoving:Fire(Player, Character)
	end)

	Framework.RuntimeEvents.PlayerAdded:Fire(Player)
	if Player.Character then
		Framework.RuntimeEvents.CharacterAdded:Fire(Player, Player.Character)
	end
end

function PlayerLifecycle:_UntrackPlayer(Player: Player): ()
	Framework.RuntimeEvents.PlayerRemoving:Fire(Player)

	local PlayerTrove: any = self.PlayerTroves[Player]
	if PlayerTrove then
		PlayerTrove:Destroy()
		self.PlayerTroves[Player] = nil
	end
end

function PlayerLifecycle:Init(): ()
	if self.Trove then
		return
	end

	self.Trove = Trove.new()
	self.Trove:Connect(Players.PlayerAdded, function(Player: Player): ()
		self:_TrackPlayer(Player)
	end)
	self.Trove:Connect(Players.PlayerRemoving, function(Player: Player): ()
		self:_UntrackPlayer(Player)
	end)
end

function PlayerLifecycle:Start(): ()
	for _Index: number, Player: Player in Players:GetPlayers() do
		self:_TrackPlayer(Player)
	end
end

function PlayerLifecycle:Destroy(): ()
	if not self.Trove then
		return
	end

	for Player: Player in table.clone(self.PlayerTroves) do
		self:_UntrackPlayer(Player)
	end
	self.Trove:Destroy()
	self.Trove = nil
end

return PlayerLifecycle
