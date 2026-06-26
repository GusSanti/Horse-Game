local Shared = require(script.Parent:WaitForChild("Shared"))

return {
	Shared.CreateStableDecor({
		ItemId = "daisy_banner",
		DisplayName = "Daisy Banner",
		Description = "Simple stable decor for the player's stall.",
		Price = 4,
		SortOrder = 10,
		EffectsSummary = "Stable decor item",
		Tags = { "Banner", "Flower" },
	}),
}
