local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")

local serverModules = ServerStorage:WaitForChild("Modules")
local adminModules = serverModules:WaitForChild("Admin")
local AdminAccessService = require(adminModules:WaitForChild("AdminAccessService"))

AdminAccessService.RefreshAllPlayers()

Players.PlayerAdded:Connect(function(player)
	task.spawn(AdminAccessService.ApplyAccessAttributes, player)
end)
