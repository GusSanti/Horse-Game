local Shared = require(script.Parent:WaitForChild("Shared"))

return {
	Shared.CreateMisc({
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
}
