--!strict

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))
local DataUtility: any = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))

local ServerModules: Folder = ServerStorage:WaitForChild("Modules") :: Folder
local CookingModules: Folder = ServerModules:WaitForChild("Cooking") :: Folder
local FarmingModules: Folder = ServerModules:WaitForChild("Farming") :: Folder
local HorseModules: Folder = ServerModules:WaitForChild("Horse") :: Folder
local InventoryModules: Folder = ServerModules:WaitForChild("Inventory") :: Folder
local PlayerModules: Folder = ServerModules:WaitForChild("Player") :: Folder
local QuestModules: Folder = ServerModules:WaitForChild("Quest") :: Folder
local RaceModules: Folder = ServerModules:WaitForChild("Race") :: Folder
local ShopModules: Folder = ServerModules:WaitForChild("Shop") :: Folder

local ConsumableToolService: any = require(InventoryModules:WaitForChild("ConsumableToolService"))
local FarmingService: any = require(FarmingModules:WaitForChild("FarmingService"))
local FarmingShopService: any = require(FarmingModules:WaitForChild("FarmingShopService"))
local HayBaleService: any = require(HorseModules:WaitForChild("HayBaleService"))
local HorseIndexService: any = require(HorseModules:WaitForChild("HorseIndexService"))
local HorseMountService: any = require(HorseModules:WaitForChild("HorseMountService"))
local HorseRoamingService: any = require(HorseModules:WaitForChild("HorseRoamingService"))
local HorseSaddleAssetService: any = require(HorseModules:WaitForChild("HorseSaddleAssetService"))
local HorseService: any = require(HorseModules:WaitForChild("HorseService"))
local StableCleaningService: any = require(HorseModules:WaitForChild("StableCleaningService"))
local WaterTankService: any = require(HorseModules:WaitForChild("WaterTankService"))
local WellWaterService: any = require(HorseModules:WaitForChild("WellWaterService"))
local InventoryLoadoutService: any = require(InventoryModules:WaitForChild("InventoryLoadoutService"))
local NpcShopService: any = require(ShopModules:WaitForChild("NpcShopService"))
local PersistentToolService: any = require(InventoryModules:WaitForChild("PersistentToolService"))
local PlayerSettingsService: any = require(PlayerModules:WaitForChild("PlayerSettingsService"))
local QuestService: any = require(QuestModules:WaitForChild("QuestService"))
local RaceService: any = require(RaceModules:WaitForChild("RaceService"))

type ServiceDefinition = {
	Name: string,
	Service: any,
	AllowFailure: boolean?,
}

local GameplayRuntime = {
	Name = "GameplayRuntime",
	Trove = nil :: any,
	Started = false,
	PendingPlayers = {} :: { [Player]: boolean },
	StartedServices = {} :: { ServiceDefinition },
}

local function SafeRequire(ModuleValue: ModuleScript, ModuleName: string): any
	local Success: boolean, Result: any = pcall(require, ModuleValue)
	if Success then
		return Result
	end
	warn(`[GameplayRuntime] Failed to require {ModuleName}: {tostring(Result)}`)
	return nil
end

local CookingService: any = SafeRequire(CookingModules:WaitForChild("CookingService") :: ModuleScript, "CookingService")

local SERVICES: { ServiceDefinition } = {
	{ Name = "HorseSaddleAssetService", Service = HorseSaddleAssetService, AllowFailure = true },
	{ Name = "HorseService", Service = HorseService, AllowFailure = true },
	{ Name = "CookingService", Service = CookingService, AllowFailure = true },
	{ Name = "FarmingShopService", Service = FarmingShopService },
	{ Name = "HorseIndexService", Service = HorseIndexService },
	{ Name = "ConsumableToolService", Service = ConsumableToolService },
	{ Name = "FarmingService", Service = FarmingService },
	{ Name = "PersistentToolService", Service = PersistentToolService },
	{ Name = "InventoryLoadoutService", Service = InventoryLoadoutService },
	{ Name = "NpcShopService", Service = NpcShopService },
	{ Name = "PlayerSettingsService", Service = PlayerSettingsService },
	{ Name = "QuestService", Service = QuestService },
	{ Name = "RaceService", Service = RaceService },
	{ Name = "HorseRoamingService", Service = HorseRoamingService },
	{ Name = "HorseMountService", Service = HorseMountService },
	{ Name = "HayBaleService", Service = HayBaleService },
	{ Name = "WaterTankService", Service = WaterTankService },
	{ Name = "WellWaterService", Service = WellWaterService },
	{ Name = "StableCleaningService", Service = StableCleaningService },
}

local function UpdateLoginData(Player: Player): ()
	local Login: any = DataUtility.server.get(Player, "Login")
	if not Login then
		return
	end

	local Now: number = os.time()
	if (Login.FirstJoinAt or 0) <= 0 then
		Login.FirstJoinAt = Now
	end
	Login.LastJoinAt = Now
	Login.LoginCount = (Login.LoginCount or 0) + 1
	DataUtility.server.set(Player, "Login", Login)
end

function GameplayRuntime:_BootstrapPlayer(Player: Player): ()
	local RuntimeTrove: any = self.Trove
	if not RuntimeTrove then
		return
	end

	RuntimeTrove:Add(task.spawn(function(): ()
		local Profile: any = DataUtility.server.get(Player)
		if not self.Started or Player.Parent ~= Players or not Profile then
			return
		end

		InventoryLoadoutService.SyncPlayerTools(Player)
		UpdateLoginData(Player)
		HorseService.EnsureStarterHorse(Player)
		HorseService.RefreshHorseStatuses(Player)
		FarmingService.PlayerReady(Player)
		HayBaleService.PlayerReady(Player)
		WaterTankService.PlayerReady(Player)
		StableCleaningService.PlayerReady(Player)
		QuestService.EnsureDailyQuest(Player)
		RaceService.SyncPlayer(Player)
	end))
end

function GameplayRuntime:Init(): ()
	if self.Trove then
		return
	end

	self.Trove = Trove.new()
	self.Trove:Connect(Framework.RuntimeEvents.PlayerAdded, function(Player: Player): ()
		if self.Started then
			self:_BootstrapPlayer(Player)
		else
			self.PendingPlayers[Player] = true
		end
	end)
	self.Trove:Connect(Framework.RuntimeEvents.PlayerRemoving, function(Player: Player): ()
		self.PendingPlayers[Player] = nil
	end)
end

function GameplayRuntime:Start(): ()
	if self.Started then
		return
	end

	for _Index: number, Definition: ServiceDefinition in SERVICES do
		local Service: any = Definition.Service
		if Service and type(Service.Init) == "function" then
			local Success: boolean, ErrorValue: any = pcall(Service.Init)
			if not Success then
				if Definition.AllowFailure then
					warn(`[GameplayRuntime] Failed to initialize {Definition.Name}: {tostring(ErrorValue)}`)
					continue
				end
				error(`Required service {Definition.Name} failed to initialize: {tostring(ErrorValue)}`, 0)
			end
		end
		table.insert(self.StartedServices, Definition)
	end

	HorseService.StartStatusDecayLoop()
	self.Started = true
	for Player: Player in table.clone(self.PendingPlayers) do
		self.PendingPlayers[Player] = nil
		self:_BootstrapPlayer(Player)
	end
end

function GameplayRuntime:Destroy(): ()
	self.Started = false
	table.clear(self.PendingPlayers)

	for Index: number = #self.StartedServices, 1, -1 do
		local Definition: ServiceDefinition = self.StartedServices[Index]
		if type(Definition.Service.Destroy) == "function" then
			local Success: boolean, ErrorValue: any = pcall(Definition.Service.Destroy)
			if not Success then
				warn(`[GameplayRuntime] Failed to destroy {Definition.Name}: {tostring(ErrorValue)}`)
			end
		end
	end
	table.clear(self.StartedServices)

	if self.Trove then
		self.Trove:Destroy()
		self.Trove = nil
	end
end

return GameplayRuntime
