local Shared = require(script.Parent:WaitForChild("Shared"))

return {
	Shared.CreateMisc({
		ShopId = "Cowboy",
		ItemId = "soap",
		DisplayName = "Soap",
		Description = "Basic soap used to wash your horse and restore cleanliness.",
		Price = 2,
		PriceLabel = "2 coin",
		SortOrder = 10,
		Effects = {
			CleanlinessGain = 100,
			HappinessGain = 2,
			FriendshipGain = 2,
			MoodText = "Fresh",
		},
		PromptActionText = "Wash",
		PromptObjectText = "Your horse",
		ResponseCode = "Cleaned",
		Tags = { "Cleaning", "Soap" },
	}),
	Shared.CreateMisc({
		ShopId = "Cowboy",
		ItemId = "horse_brush",
		DisplayName = "Horse Brush",
		Description = "A soft brush used to calm your horse and make it feel cared for.",
		Price = 3,
		PriceLabel = "3 coin",
		SortOrder = 20,
		Effects = {
			HappinessGain = 5,
			MoodText = "Pampered",
		},
		EffectsSummary = "Happiness +5",
		PromptActionText = "Brush",
		PromptObjectText = "Your horse",
		ResponseCode = "Brushed",
		Tags = { "Grooming", "Brush" },
	}),
}
