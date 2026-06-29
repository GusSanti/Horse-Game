local Shared = require(script.Parent:WaitForChild("Shared"))

return {
	Shared.CreateCosmetic({
		ItemId = "rider_helmet_classic",
		DisplayName = "Classic Rider Helmet",
		Description = "A starter player cosmetic for riding outfits.",
		Price = 5,
		SortOrder = 10,
		EffectsSummary = "Starter cosmetic",
		Tags = { "Helmet", "Starter" },
	}),
}
