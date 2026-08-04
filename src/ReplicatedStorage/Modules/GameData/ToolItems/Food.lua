local Shared = require(script.Parent:WaitForChild("Shared"))

local FOOD_IMAGE_IDS = {
	hay_bale = "",
	bread = "",
	beet_pellets = "",
	berry_mash = "",
	root_salad = "",
	garden_soup = "",
	stuffed_pumpkin = "",
	harvest_skewers = "",
	pineapple_pie = "",
}

local function crafted_food(config)
	config.IdImage = config.IdImage or FOOD_IMAGE_IDS[config.ItemId] or ""
	config.ShopId = false
	config.Price = config.Price or 0
	config.PriceLabel = config.PriceLabel or "Crafted"
	config.EquipOnPurchase = false
	return Shared.CreateFood(config)
end

return {
	crafted_food({
		ItemId = "hay_bale",
		DisplayName = "Hay Bale",
		ToolName = "HaybaleTool",
		Description = "Basic bundled wheat that fills the stomach well, but keeps excitement low.",
		SortOrder = 10,
		Effects = {
			NeedGain = 22,
			HappinessGain = 3,
			HealthGain = 0,
			FriendshipGain = 2,
			OverflowYield = 0.24,
			OverflowHealthPenalty = 0.18,
			OverflowHappinessFactor = 0.25,
			DecayBuff = {
				Multiplier = 0.92,
				DurationMinutes = 12,
			},
			MoodText = "Satisfied",
		},
		Tags = { "Hay", "Starter", "Crafted" },
	}),
	crafted_food({
		ItemId = "bread",
		DisplayName = "Bread",
		Description = "Warm wheat bread that gives reliable food and a small comfort boost.",
		SortOrder = 20,
		Effects = {
			NeedGain = 24,
			HappinessGain = 5,
			HealthGain = 1,
			FriendshipGain = 3,
			OverflowYield = 0.26,
			OverflowHealthPenalty = 0.14,
			OverflowHappinessFactor = 0.3,
			DecayBuff = {
				Multiplier = 0.88,
				DurationMinutes = 15,
			},
			MoodText = "Comforted",
		},
		Tags = { "Bread", "Wheat", "Crafted" },
	}),
	crafted_food({
		ItemId = "beet_pellets",
		DisplayName = "Beet Pellets",
		Description = "Dense pellets that feed well and give a small health top-up.",
		SortOrder = 30,
		Effects = {
			NeedGain = 21,
			HappinessGain = 4,
			HealthGain = 3,
			FriendshipGain = 3,
			OverflowYield = 0.22,
			OverflowHealthPenalty = 0.16,
			OverflowHappinessFactor = 0.24,
			DecayBuff = {
				Multiplier = 0.86,
				DurationMinutes = 18,
			},
			MoodText = "Restored",
		},
		Tags = { "Pellets", "Root", "Crafted" },
	}),
	crafted_food({
		ItemId = "berry_mash",
		DisplayName = "Berry Mash",
		Description = "Soft mash that fills lightly, but gives a strong happiness boost.",
		SortOrder = 40,
		Effects = {
			NeedGain = 14,
			HappinessGain = 14,
			HealthGain = 1,
			FriendshipGain = 7,
			OverflowYield = 0.4,
			OverflowHealthPenalty = 0.1,
			OverflowHappinessFactor = 0.5,
			DecayBuff = {
				Multiplier = 0.93,
				DurationMinutes = 8,
			},
			MoodText = "Delighted",
		},
		Tags = { "Mash", "Sweet", "Crafted" },
	}),
	crafted_food({
		ItemId = "root_salad",
		DisplayName = "Root Salad",
		Description = "A crisp salad using several fresh vegetables from the farm.",
		SortOrder = 50,
		Effects = {
			NeedGain = 18,
			HappinessGain = 10,
			HealthGain = 2,
			FriendshipGain = 5,
			OverflowYield = 0.34,
			OverflowHealthPenalty = 0.11,
			OverflowHappinessFactor = 0.42,
			DecayBuff = {
				Multiplier = 0.84,
				DurationMinutes = 16,
			},
			MoodText = "Fresh",
		},
		Tags = { "Salad", "Vegetable", "Crafted" },
	}),
	crafted_food({
		ItemId = "garden_soup",
		DisplayName = "Garden Soup",
		Description = "A warm vegetable soup for steady hunger and health recovery.",
		SortOrder = 60,
		Effects = {
			NeedGain = 26,
			HappinessGain = 7,
			HealthGain = 3,
			FriendshipGain = 5,
			OverflowYield = 0.27,
			OverflowHealthPenalty = 0.13,
			OverflowHappinessFactor = 0.34,
			DecayBuff = {
				Multiplier = 0.82,
				DurationMinutes = 20,
			},
			MoodText = "Warmed",
		},
		Tags = { "Soup", "Vegetable", "Crafted" },
	}),
	crafted_food({
		ItemId = "stuffed_pumpkin",
		DisplayName = "Stuffed Pumpkin",
		Description = "A hearty pumpkin packed with grains and bright vegetables.",
		SortOrder = 70,
		Effects = {
			NeedGain = 30,
			HappinessGain = 6,
			HealthGain = 4,
			FriendshipGain = 5,
			OverflowYield = 0.23,
			OverflowHealthPenalty = 0.15,
			OverflowHappinessFactor = 0.3,
			DecayBuff = {
				Multiplier = 0.8,
				DurationMinutes = 24,
			},
			MoodText = "Hearty",
		},
		Tags = { "Pumpkin", "LargeMeal", "Crafted" },
	}),
	crafted_food({
		ItemId = "harvest_skewers",
		DisplayName = "Harvest Skewers",
		Description = "Roasted farm vegetables served in quick bite-sized pieces.",
		SortOrder = 80,
		Effects = {
			NeedGain = 20,
			HappinessGain = 9,
			HealthGain = 2,
			FriendshipGain = 4,
			OverflowYield = 0.31,
			OverflowHealthPenalty = 0.12,
			OverflowHappinessFactor = 0.4,
			DecayBuff = {
				Multiplier = 0.83,
				DurationMinutes = 18,
			},
			MoodText = "Focused",
		},
		Tags = { "Roasted", "Vegetable", "Crafted" },
	}),
	crafted_food({
		ItemId = "pineapple_pie",
		DisplayName = "Pineapple Pie",
		ToolGrip = CFrame.new(0, -0.08, -0.5)
			* CFrame.Angles(math.rad(-15), math.rad(10), 0),
		Description = "A sweet pineapple pie baked with fresh fruit and wheat.",
		SortOrder = 90,
		Effects = {
			NeedGain = 28,
			HappinessGain = 13,
			HealthGain = 2,
			FriendshipGain = 7,
			OverflowYield = 0.38,
			OverflowHealthPenalty = 0.09,
			OverflowHappinessFactor = 0.5,
			DecayBuff = {
				Multiplier = 0.78,
				DurationMinutes = 22,
			},
			MoodText = "Sweetened",
		},
		Tags = { "Pie", "Pineapple", "Sweet", "Crafted" },
	}),
}
