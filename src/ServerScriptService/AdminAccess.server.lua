local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local AdminAccessService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("AdminAccessService"))

AdminAccessService.RefreshAllPlayers()

Players.PlayerAdded:Connect(function(player)
	task.spawn(AdminAccessService.ApplyAccessAttributes, player)
end)
