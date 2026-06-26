local Shared = require(script.Parent:WaitForChild("Shared"))

return {
	Shared.CreateGrooming({
		ItemId = "soft_brush",
		DisplayName = "Soft Brush",
		Description = "A starter grooming brush for light cleaning and comfort.",
		Price = 2,
		SortOrder = 10,
		EffectsSummary = "Cleanliness +12 | Happiness +5",
		NeedsDelta = {
			Cleanliness = 12,
			Happiness = 5,
		},
		Tags = { "Brush", "Starter" },
	}),
	Shared.CreateGrooming({
		ItemId = "grooming_kit",
		DisplayName = "Grooming Kit",
		Description = "A more complete kit for repeated care and stable routines.",
		Price = 4,
		SortOrder = 20,
		EffectsSummary = "Cleanliness +18 | Happiness +8",
		NeedsDelta = {
			Cleanliness = 18,
			Happiness = 8,
		},
		Tags = { "Kit", "Care" },
	}),
	Shared.CreateGrooming({
		ItemId = "shine_kit",
		DisplayName = "Shine Kit",
		Description = "A premium polish set that makes horses feel extra pampered.",
		Price = 6,
		SortOrder = 30,
		EffectsSummary = "Cleanliness +14 | Happiness +12 | Premium grooming",
		NeedsDelta = {
			Cleanliness = 14,
			Happiness = 12,
		},
		Tags = { "Premium", "Polish" },
	}),
}
