local ShopCatalog = {}

ShopCatalog.Items = {
	hay_bale = {
		ItemId = "hay_bale",
		DisplayName = "Hay Bale",
		Description = "Basic food for daily horse care.",
		Price = 25,
		InventoryPath = "Consumables.Food",
		ShopId = "OutdoorStore",
		Tags = { "Food", "Hay" },
		MaxStack = 99,
	},
	apple_treat = {
		ItemId = "apple_treat",
		DisplayName = "Apple Treat",
		Description = "A simple reward snack that many horses enjoy.",
		Price = 30,
		InventoryPath = "Consumables.Food",
		ShopId = "OutdoorStore",
		Tags = { "Food", "Treat" },
		MaxStack = 99,
	},
	carrot_bunch = {
		ItemId = "carrot_bunch",
		DisplayName = "Carrot Bunch",
		Description = "A favorite snack for more energetic horses.",
		Price = 35,
		InventoryPath = "Consumables.Food",
		ShopId = "OutdoorStore",
		Tags = { "Food", "Treat" },
		MaxStack = 99,
	},
	mint_treat = {
		ItemId = "mint_treat",
		DisplayName = "Mint Treat",
		Description = "A refreshing snack used in quests and bonding rewards.",
		Price = 40,
		InventoryPath = "Consumables.Food",
		ShopId = "OutdoorStore",
		Tags = { "Food", "Treat" },
		MaxStack = 99,
	},
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
			"hay_bale",
			"apple_treat",
			"carrot_bunch",
			"mint_treat",
			"soft_brush",
			"grooming_kit",
			"shine_kit",
			"carrot_seed",
			"daisy_banner",
		},
	},
}

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
