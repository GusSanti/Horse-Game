--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network: any = require(ReplicatedStorage.Modules.Network)

local EXPECTED_EVENTS: { string } = {
	"AcknowledgeReveal",
	"AreaUnlocked",
	"DataUtilityChanged",
	"HorseBrushAnimation",
	"HorseFeedAnimation",
	"HorseIndexStateChanged",
	"HorseMountInput",
	"HorseMountState",
	"PlayGameSFX",
	"RaceState",
	"TeleportToStable",
}

local EXPECTED_FUNCTIONS: { string } = {
	"BeginRobuxGiftPurchase",
	"BuyNpcShopItem",
	"BuySeed",
	"CancelRobuxGiftPurchase",
	"ClaimDailyQuest",
	"CleanStableDirt",
	"ConfirmRobuxGiftPurchase",
	"CookingAction",
	"DataUtilityGet",
	"FarmingShopAction",
	"FillStableWaterTank",
	"GetHorseRouletteState",
	"GetItemCatalog",
	"GetRobuxShopCatalog",
	"HorseIndexGetState",
	"HorseMountAction",
	"PlaceStableHayBale",
	"PlantSeed",
	"RaceAction",
	"RequestItemTool",
	"RestoreEquippedHorseNeeds",
	"RollHorseRoulette",
	"SellFruit",
	"StableSlotAction",
	"TeleportToArea",
	"UpdateInventoryLoadout",
	"UpdatePlayerSetting",
	"UpgradeStable",
	"UseHorseTool",
	"WellWaterAction",
	"WaterPlant",
}

return function(t: any): ()
	t.test("creates every declared remote from code", function(): ()
		Network.Init()
		local Root: Folder = ReplicatedStorage:WaitForChild("Net") :: Folder
		local Events: Folder = Root:WaitForChild("Events") :: Folder
		local Functions: Folder = Root:WaitForChild("Functions") :: Folder

		for _Index: number, Name: string in EXPECTED_EVENTS do
			local Remote: Instance? = Events:FindFirstChild(Name)
			t.expect.truthy(Remote ~= nil and Remote:IsA("RemoteEvent"))
		end
		for _Index: number, Name: string in EXPECTED_FUNCTIONS do
			local Remote: Instance? = Functions:FindFirstChild(Name)
			t.expect.truthy(Remote ~= nil and Remote:IsA("RemoteFunction"))
		end
	end)

	t.test("exposes stable domain aliases", function(): ()
	t.expect.equal(Network.Admin.GetItemCatalog, Network.Functions.AdminGetItemCatalog)
	t.expect.equal(Network.Horse.UseTool, Network.Functions.UseHorseTool)
	t.expect.equal(Network.Horse.BrushAnimation, Network.Events.HorseBrushAnimation)
	t.expect.equal(Network.Horse.FeedAnimation, Network.Events.HorseFeedAnimation)
	t.expect.equal(Network.Horse.AcknowledgeReveal, Network.Events.HorseRevealAcknowledged)
	end)
end
