local Shared = require(script.Parent:WaitForChild("Shared"))

return {
	Shared.CreateSeeds({
		ItemId = "carrot_seed",
		DisplayName = "Carrot Seed",
		ToolName = "SeedCarrot",
		Description = "Plant this seed in the farming soil to grow a carrot crop.",
		Price = 1,
		SortOrder = 10,
		EffectsSummary = "Plantable crop seed",
		ShopId = false,
		Tags = { "Crop", "Farming" },
	}),
	Shared.CreateSeeds({
		ItemId = "apple_seed",
		DisplayName = "Apple Seed",
		ToolName = "SeedApple",
		Description = "Plant this seed in the farming soil to grow an apple crop.",
		Price = 2,
		SortOrder = 20,
		EffectsSummary = "Plantable crop seed",
		ShopId = false,
		Tags = { "Crop", "Farming" },
	}),
}
