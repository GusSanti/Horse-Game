local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local ShopCatalog = {}

ShopCatalog.Items = {
	soft_brush = {
		ItemId = "soft_brush",
		DisplayName = "Soft Brush",
		Description = "A starter grooming item for basic care actions.",
		Price = 45,
		InventoryPath = "Consumables.Grooming",
		ShopId = "OutdoorStore",
		Tags = { "Grooming", "Brush" },
		MaxStack = 99,
	},
	grooming_kit = {
		ItemId = "grooming_kit",
		DisplayName = "Grooming Kit",
		Description = "A better grooming bundle for repeated care loops.",
		Price = 65,
		InventoryPath = "Consumables.Grooming",
		ShopId = "OutdoorStore",
		Tags = { "Grooming", "Kit" },
		MaxStack = 99,
	},
	shine_kit = {
		ItemId = "shine_kit",
		DisplayName = "Shine Kit",
		Description = "A premium care item for horses that love extra polish.",
		Price = 80,
		InventoryPath = "Consumables.Grooming",
		ShopId = "OutdoorStore",
		Tags = { "Grooming", "Premium" },
		MaxStack = 99,
	},
	carrot_seed = {
		ItemId = "carrot_seed",
		DisplayName = "Carrot Seeds",
		Description = "Starter seeds for the farming patch.",
		Price = 20,
		InventoryPath = "Seeds",
		ShopId = "OutdoorStore",
		Tags = { "Seed", "Crop" },
		MaxStack = 99,
	},
	starter_bridle = {
		ItemId = "starter_bridle",
		DisplayName = "Starter Bridle",
		Description = "Simple tack for the first equipment set.",
		Price = 110,
		InventoryPath = "Tack",
		ShopId = "TackShop",
		Tags = { "Tack", "Bridle" },
		MaxStack = 1,
	},
	starter_saddle = {
		ItemId = "starter_saddle",
		DisplayName = "Starter Saddle",
		Description = "A basic saddle for your active horse.",
		Price = 140,
		InventoryPath = "Tack",
		ShopId = "TackShop",
		Tags = { "Tack", "Saddle" },
		MaxStack = 1,
	},
	rider_helmet_classic = {
		ItemId = "rider_helmet_classic",
		DisplayName = "Classic Rider Helmet",
		Description = "A starter player cosmetic for riding outfits.",
		Price = 90,
		InventoryPath = "Cosmetics",
		ShopId = "TackShop",
		Tags = { "Cosmetic", "Helmet" },
		MaxStack = 1,
	},
	daisy_banner = {
		ItemId = "daisy_banner",
		DisplayName = "Daisy Banner",
		Description = "Simple stable decor for the player's stall.",
		Price = 100,
		InventoryPath = "StableDecor",
		ShopId = "OutdoorStore",
		Tags = { "Decor", "Stable" },
		MaxStack = 10,
	},
}

for _, itemDefinition in ipairs(ToolItemCatalog.GetAllItems()) do
	ShopCatalog.Items[itemDefinition.ItemId] = itemDefinition
end

ShopCatalog.Shops = {
	TackShop = {
		ShopId = "TackShop",
		DisplayName = "Tack Shop",
		ItemIds = {
			"starter_bridle",
			"starter_saddle",
			"rider_helmet_classic",
		},
	},
	OutdoorStore = {
		ShopId = "OutdoorStore",
		DisplayName = "Outdoor Store",
		ItemIds = {
			"soft_brush",
			"grooming_kit",
			"shine_kit",
			"carrot_seed",
			"daisy_banner",
		},
	},
}

for _, itemDefinition in ipairs(ToolItemCatalog.GetAllItems()) do
	local shopDefinition = ShopCatalog.Shops[itemDefinition.ShopId]
	if shopDefinition then
		shopDefinition.ItemIds[#shopDefinition.ItemIds + 1] = itemDefinition.ItemId
	end
end

function ShopCatalog.GetItemDefinition(itemId)
	return ShopCatalog.Items[itemId]
end

function ShopCatalog.GetShopDefinition(shopId)
	return ShopCatalog.Shops[shopId]
end

function ShopCatalog.GetItemsForShop(shopId)
	local shopDefinition = ShopCatalog.GetShopDefinition(shopId)
	if not shopDefinition then
		return {}
	end

	local items = {}

	for _, itemId in ipairs(shopDefinition.ItemIds) do
		local itemDefinition = ShopCatalog.GetItemDefinition(itemId)
		if itemDefinition then
			items[#items + 1] = itemDefinition
		end
	end

	return items
end

return ShopCatalog
