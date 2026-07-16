local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local DataUtility = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility"):WaitForChild("DataUtility"))
local ConsumableToolService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("ConsumableToolService"))
local FarmingService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("FarmingService"))
local FarmingShopService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("FarmingShopService"))
local HorseMountService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseMountService"))
local HorseService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseService"))
local InventoryLoadoutService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("InventoryLoadoutService"))
local NpcShopService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("NpcShopService"))
local PlayerSettingsService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("PlayerSettingsService"))
local PersistentToolService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("PersistentToolService"))
local QuestService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("QuestService"))
local RaceService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("RaceService"))

local function safe_require_module(moduleScript: ModuleScript, moduleName: string)
	local success, result = pcall(require, moduleScript)
	if success then
		return result
	end

	warn(("[GameBootstrap] failed to require %s: %s"):format(moduleName, tostring(result)))
	return nil
end

local function safe_init_service(serviceName: string, service)
	if not service or type(service.Init) ~= "function" then
		return
	end

	local success, errorMessage = pcall(function()
		service.Init()
	end)

	if not success then
		warn(("[GameBootstrap] failed to initialize %s: %s"):format(serviceName, tostring(errorMessage)))
	end
end

local CookingService = safe_require_module(ServerStorage:WaitForChild("Modules"):WaitForChild("CookingService"), "CookingService")

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

		InventoryLoadoutService.SyncPlayerTools(player)
		update_login_data(player)
		HorseService.ensure_starter_horse(player)
		HorseService.refresh_horse_statuses(player)
		QuestService.EnsureDailyQuest(player)
		RaceService.SyncPlayer(player)
	end)
end

safe_init_service("CookingService", CookingService)
FarmingShopService.Init()
ConsumableToolService.Init()
FarmingService.Init()
PersistentToolService.Init()
InventoryLoadoutService.Init()
NpcShopService.Init()
PlayerSettingsService.Init()
QuestService.Init()
RaceService.Init()
HorseMountService.Init()
HorseService.start_status_decay_loop()

for _, player in Players:GetPlayers() do
	bootstrap_player(player)
end

Players.PlayerAdded:Connect(bootstrap_player)