------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------//VARIABLES
local localPlayer: Player = Players.LocalPlayer
local playerScripts: PlayerScripts = localPlayer:WaitForChild("PlayerScripts")
local sourceFolder: Folder = ReplicatedStorage:WaitForChild("PlayerScripts")

------------------//MAIN FUNCTIONS
for _, scriptObj in sourceFolder:GetDescendants() do
	if scriptObj:IsA("LocalScript") then
		scriptObj.Parent = playerScripts
	end
end