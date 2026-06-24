local QuestCatalog = {}

QuestCatalog.DailyPool = {
	"daily_feed_horse",
	"daily_groom_horse",
	"daily_clean_stable",
	"daily_care_combo",
	"daily_harvest_crop",
	"daily_arena_run",
}

QuestCatalog.Definitions = {
	daily_feed_horse = {
		Id = "daily_feed_horse",
		DisplayName = "Breakfast Time",
		Description = "Feed your horse 3 times.",
		Category = "Daily",
		EstimatedMinutes = 5,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalFeedActions",
			Target = 3,
		},
		Rewards = {
			Horseshoes = 60,
			Items = {
				{ ItemId = "apple_treat", Amount = 1 },
			},
		},
	},
	daily_groom_horse = {
		Id = "daily_groom_horse",
		DisplayName = "Brush And Shine",
		Description = "Groom your horse 2 times.",
		Category = "Daily",
		EstimatedMinutes = 5,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalGroomActions",
			Target = 2,
		},
		Rewards = {
			Horseshoes = 55,
			Items = {
				{ ItemId = "soft_brush", Amount = 1 },
			},
		},
	},
	daily_clean_stable = {
		Id = "daily_clean_stable",
		DisplayName = "Fresh Stall",
		Description = "Clean your horse or stall 2 times.",
		Category = "Daily",
		EstimatedMinutes = 5,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalCleanActions",
			Target = 2,
		},
		Rewards = {
			Horseshoes = 55,
			Items = {
				{ ItemId = "grooming_kit", Amount = 1 },
			},
		},
	},
	daily_care_combo = {
		Id = "daily_care_combo",
		DisplayName = "Care Routine",
		Description = "Perform 5 total care actions.",
		Category = "Daily",
		EstimatedMinutes = 8,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalCareActions",
			Target = 5,
		},
		Rewards = {
			Horseshoes = 80,
			Items = {
				{ ItemId = "hay_bale", Amount = 1 },
			},
		},
	},
	daily_harvest_crop = {
		Id = "daily_harvest_crop",
		DisplayName = "Garden Routine",
		Description = "Harvest 1 crop.",
		Category = "Daily",
		EstimatedMinutes = 6,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalCropsHarvested",
			Target = 1,
		},
		Rewards = {
			Horseshoes = 70,
			Items = {
				{ ItemId = "carrot_seed", Amount = 2 },
			},
		},
	},
	daily_arena_run = {
		Id = "daily_arena_run",
		DisplayName = "Track Warmup",
		Description = "Complete 1 arena run.",
		Category = "Daily",
		EstimatedMinutes = 7,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalArenaRuns",
			Target = 1,
		},
		Rewards = {
			Horseshoes = 90,
			Items = {
				{ ItemId = "mint_treat", Amount = 1 },
			},
		},
	},
}

function QuestCatalog.GetDefinition(questId)
	return QuestCatalog.Definitions[questId]
end

function QuestCatalog.GetDailyQuestIds()
	return QuestCatalog.DailyPool
end

function QuestCatalog.GetDailyQuestIdForPlayer(userId, timestamp)
	local pool = QuestCatalog.GetDailyQuestIds()
	local dayToken = math.floor(timestamp / 86400)
	local index = ((dayToken + math.abs(userId)) % #pool) + 1
	return pool[index]
end

return QuestCatalog
