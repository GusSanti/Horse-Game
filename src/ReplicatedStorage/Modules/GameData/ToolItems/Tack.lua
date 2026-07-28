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
		Description = "A basic reusable saddle that gives a small speed bonus.",
		Price = 8,
		SortOrder = 20,
		EquipmentType = "Saddle",
		SaddleBonuses = {
			SprintSpeedAdd = 0.75,
		},
		EffectsSummary = "Sprint Speed +0.75",
		Tags = { "Saddle", "Starter" },
	}),
	Shared.CreateTack({
		ItemId = "western_saddle",
		DisplayName = "Western Saddle",
		Description = "A sturdy reusable saddle with a balanced mounted speed bonus.",
		Price = 40,
		SortOrder = 30,
		EquipmentType = "Saddle",
		SaddleBonuses = {
			CanterSpeedAdd = 0.75,
			SprintSpeedAdd = 1.5,
			AccelerationAdd = 0.02,
		},
		EffectsSummary = "Canter +0.75 | Sprint +1.5 | Acceleration +0.02",
		Tags = { "Saddle", "Western" },
	}),
	Shared.CreateTack({
		ItemId = "english_saddle",
		DisplayName = "English Saddle",
		Description = "A light reusable saddle tuned for fast riding and racing.",
		Price = 75,
		SortOrder = 40,
		EquipmentType = "Saddle",
		SaddleBonuses = {
			CanterSpeedAdd = 1,
			SprintSpeedAdd = 2.5,
			AccelerationAdd = 0.05,
			RaceAffinityAdd = 0.03,
		},
		EffectsSummary = "Canter +1 | Sprint +2.5 | Acceleration +0.05 | Race +0.03",
		Tags = { "Saddle", "English", "Race" },
	}),
}
