local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local DataUtility = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility"):WaitForChild("DataUtility"))
local HorseService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseService"))
local QuestService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("QuestService"))

local function update_login_data(player)
	local login = DataUtility.server.get(player, "Login")
	if not login then
		return
	end

	local now = os.time()

	if (login.FirstJoinAt or 0) <= 0 then
		login.FirstJoinAt = now
	end

	login.LastJoinAt = now
	login.LoginCount = (login.LoginCount or 0) + 1

	DataUtility.server.set(player, "Login", login)
end

local function bootstrap_player(player)
	task.spawn(function()
		local profile = DataUtility.server.get(player)
		if not profile then
			return
		end

		update_login_data(player)
		HorseService.ensure_starter_horse(player)
		QuestService.EnsureDailyQuest(player)
	end)
end

QuestService.Init()

for _, player in ipairs(Players:GetPlayers()) do
	bootstrap_player(player)
end

Players.PlayerAdded:Connect(bootstrap_player)
