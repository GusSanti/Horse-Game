local Shared = require(script.Parent:WaitForChild("Shared"))

return {
	Shared.CreateTack({
		ItemId = "starter_bridle",
		DisplayName = "Starter Bridle",
		Description = "Simple tack for the first equipment set.",
		Price = 7,
		SortOrder = 10,
		EffectsSummary = "Starter tack item",
		Tags = { "Bridle", "Starter" },
	}),
	Shared.CreateTack({
		ItemId = "starter_saddle",
		DisplayName = "Starter Saddle",
		Description = "A basic saddle for your active horse.",
		Price = 8,
		SortOrder = 20,
		EffectsSummary = "Starter tack item",
		Tags = { "Saddle", "Starter" },
	}),
}
