local Shared = require(script.Parent:WaitForChild("Shared"))

return {
	Shared.CreateSeeds({
		ItemId = "carrot_seed",
		DisplayName = "Carrot Seeds",
		Description = "Starter seeds for the farming patch.",
		Price = 2,
		SortOrder = 10,
		EffectsSummary = "Plantable crop seed",
		Tags = { "Crop", "Starter" },
	}),
}
