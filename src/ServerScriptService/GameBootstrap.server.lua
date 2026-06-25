------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//VARIABLES
local DataUtility = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility"):WaitForChild("DataUtility"))
local HorseService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseService"))
local QuestService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("QuestService"))

------------------//FUNCTIONS
local function update_login_data(player: Player): ()
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

local function bootstrap_player(player: Player): ()
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

------------------//MAIN FUNCTIONS
QuestService.Init()

------------------//INIT
for _, player in Players:GetPlayers() do
	bootstrap_player(player)
end

Players.PlayerAdded:Connect(bootstrap_player)
