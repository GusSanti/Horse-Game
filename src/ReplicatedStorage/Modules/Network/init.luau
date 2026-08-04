--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Net: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Net"))

local Events = table.freeze({
	DataChanged = Net.Event.DataUtilityChanged,
	HorseIndexStateChanged = Net.Event.HorseIndexStateChanged,
	HorseMountInput = Net.Event.HorseMountInput,
	HorseMountState = Net.Event.HorseMountState,
	HorseRevealAcknowledged = Net.Event.AcknowledgeReveal,
	PlayGameSFX = Net.Event.PlayGameSFX,
	RaceState = Net.Event.RaceState,
	TeleportToStable = Net.Event.TeleportToStable,
})

local Functions = table.freeze({
	AdminGetItemCatalog = Net.Function.GetItemCatalog,
	AdminGetHorseRouletteState = Net.Function.GetHorseRouletteState,
	AdminRequestItemTool = Net.Function.RequestItemTool,
	AdminRestoreEquippedHorseNeeds = Net.Function.RestoreEquippedHorseNeeds,
	AdminRollHorseRoulette = Net.Function.RollHorseRoulette,
	BeginRobuxGiftPurchase = Net.Function.BeginRobuxGiftPurchase,
	BuyNpcShopItem = Net.Function.BuyNpcShopItem,
	BuySeed = Net.Function.BuySeed,
	CancelRobuxGiftPurchase = Net.Function.CancelRobuxGiftPurchase,
	ClaimDailyQuest = Net.Function.ClaimDailyQuest,
	CleanStableDirt = Net.Function.CleanStableDirt,
	ConfirmRobuxGiftPurchase = Net.Function.ConfirmRobuxGiftPurchase,
	CookingAction = Net.Function.CookingAction,
	DataGet = Net.Function.DataUtilityGet,
	FarmingShopAction = Net.Function.FarmingShopAction,
	FillStableWaterTank = Net.Function.FillStableWaterTank,
	GetRobuxShopCatalog = Net.Function.GetRobuxShopCatalog,
	HorseIndexGetState = Net.Function.HorseIndexGetState,
	HorseMountAction = Net.Function.HorseMountAction,
	PlaceStableHayBale = Net.Function.PlaceStableHayBale,
	PlantSeed = Net.Function.PlantSeed,
	RaceAction = Net.Function.RaceAction,
	SellFruit = Net.Function.SellFruit,
	UpdateInventoryLoadout = Net.Function.UpdateInventoryLoadout,
	UpdatePlayerSetting = Net.Function.UpdatePlayerSetting,
	UseHorseTool = Net.Function.UseHorseTool,
	WellWaterAction = Net.Function.WellWaterAction,
	WaterPlant = Net.Function.WaterPlant,
})

local Network = {
	Events = Events,
	Functions = Functions,
	Admin = table.freeze({
		GetItemCatalog = Functions.AdminGetItemCatalog,
		GetHorseRouletteState = Functions.AdminGetHorseRouletteState,
		RequestItemTool = Functions.AdminRequestItemTool,
		RestoreEquippedHorseNeeds = Functions.AdminRestoreEquippedHorseNeeds,
		RollHorseRoulette = Functions.AdminRollHorseRoulette,
	}),
	Horse = table.freeze({
		AcknowledgeReveal = Events.HorseRevealAcknowledged,
		CleanStableDirt = Functions.CleanStableDirt,
		UseTool = Functions.UseHorseTool,
	}),
}

function Network.Init(): ()
	Net.Init()
end

return table.freeze(Network)
