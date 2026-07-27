local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local ServerModules = ServerStorage:WaitForChild("Modules")
local CookingModules = ServerModules:WaitForChild("Cooking")
local FarmingModules = ServerModules:WaitForChild("Farming")
local HorseModules = ServerModules:WaitForChild("Horse")
local InventoryModules = ServerModules:WaitForChild("Inventory")
local PlayerModules = ServerModules:WaitForChild("Player")
local QuestModules = ServerModules:WaitForChild("Quest")
local RaceModules = ServerModules:WaitForChild("Race")
local ShopModules = ServerModules:WaitForChild("Shop")

local DataUtility = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility"):WaitForChild("DataUtility"))
local ConsumableToolService = require(InventoryModules:WaitForChild("ConsumableToolService"))
local FarmingService = require(FarmingModules:WaitForChild("FarmingService"))
local FarmingShopService = require(FarmingModules:WaitForChild("FarmingShopService"))
local HorseIndexService = require(HorseModules:WaitForChild("HorseIndexService"))
local HorseMountService = require(HorseModules:WaitForChild("HorseMountService"))
local HorseService = require(HorseModules:WaitForChild("HorseService"))
local InventoryLoadoutService = require(InventoryModules:WaitForChild("InventoryLoadoutService"))
local NpcShopService = require(ShopModules:WaitForChild("NpcShopService"))
local PlayerSettingsService = require(PlayerModules:WaitForChild("PlayerSettingsService"))
local PersistentToolService = require(InventoryModules:WaitForChild("PersistentToolService"))
local QuestService = require(QuestModules:WaitForChild("QuestService"))
local RaceService = require(RaceModules:WaitForChild("RaceService"))

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

local CookingService = safe_require_module(CookingModules:WaitForChild("CookingService"), "CookingService")

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
		HorseService.EnsureStarterHorse(player)
		HorseService.RefreshHorseStatuses(player)
		QuestService.EnsureDailyQuest(player)
		RaceService.SyncPlayer(player)
	end)
end

safe_init_service("CookingService", CookingService)
FarmingShopService.Init()
HorseIndexService.Init()
ConsumableToolService.Init()
FarmingService.Init()
PersistentToolService.Init()
InventoryLoadoutService.Init()
NpcShopService.Init()
PlayerSettingsService.Init()
QuestService.Init()
RaceService.Init()
HorseMountService.Init()
HorseService.StartStatusDecayLoop()

for _, player in Players:GetPlayers() do
	bootstrap_player(player)
end

Players.PlayerAdded:Connect(bootstrap_player)
