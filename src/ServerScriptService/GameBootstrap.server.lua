local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local DataUtility = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility"):WaitForChild("DataUtility"))
local FarmingService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("FarmingService"))
local FarmingShopService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("FarmingShopService"))
local HorseService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseService"))
local QuestService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("QuestService"))
local RaceService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("RaceService"))

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

		FarmingShopService.SyncSeedTools(player)
		update_login_data(player)
		HorseService.ensure_starter_horse(player)
		HorseService.refresh_horse_statuses(player)
		QuestService.EnsureDailyQuest(player)
		RaceService.SyncPlayer(player)
	end)
end

FarmingShopService.Init()
FarmingService.Init()
QuestService.Init()
RaceService.Init()
HorseService.start_status_decay_loop()

for _, player in Players:GetPlayers() do
	bootstrap_player(player)
end

Players.PlayerAdded:Connect(bootstrap_player)
