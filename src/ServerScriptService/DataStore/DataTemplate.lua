local ProfileTemplate = {
	ProfileVersion = 1,
	TimePlayed = 0,

	Settings = {
		Music = true,
		NoShadows = false,
	},

	Login = {
		FirstJoinAt = 0,
		LastJoinAt = 0,
		LastDailyResetAt = 0,
		LoginCount = 0,
	},

	Currencies = {
		Horseshoes = 0,
	},

	Progression = {
		TutorialCompleted = false,
		TutorialStep = "NotStarted",
		FirstHorseGranted = false,
		UnlockedFeatures = {
			Stable = true,
			TackShop = false,
			OutdoorStore = false,
			Farming = false,
			Arena = false,
		},
	},

	Horses = {
		EquippedHorseId = "",
		NextHorseInstanceId = 0,
		OrderedIds = {},
		Owned = {},
	},

	Inventory = {
		Tack = {},
		Cosmetics = {},
		StableDecor = {},
		Consumables = {
			Food = {},
			Grooming = {},
			Medical = {},
		},
		Seeds = {},
		Trophies = {},
	},

	Stable = {
		Level = 1,
		OwnedStalls = 1,
		ActiveStyleId = "Default",
		Upgrades = {},
		PlacedDecor = {},
		DisplaySlots = {
			Trophies = {},
		},
	},

	Quests = {
		Daily = {
			QuestId = "",
			AssignedAt = 0,
			ExpiresAt = 0,
			StartValue = 0,
			Progress = 0,
			Goal = 0,
			Completed = false,
			Claimed = false,
		},
		History = {
			LastCompletedQuestId = "",
			LastCompletedAt = 0,
			CompletedCount = 0,
			CurrentStreak = 0,
			BestStreak = 0,
		},
	},

	Farming = {
		UnlockedPlots = 1,
		Plots = {
			{
				PlotId = 1,
				CropId = "",
				State = "Empty",
				PlantedAt = 0,
				HarvestAt = 0,
				LastWateredAt = 0,
			},
		},
	},

	Arena = {
		RunsPlayed = 0,
		RunsCompleted = 0,
		FastestRunMs = 0,
		LastPlayedAt = 0,
		TotalRewardsEarned = 0,
	},

	Collection = {
		DiscoveredHorseIds = {},
		OwnedHorseCatalogIds = {},
		UnlockedCosmeticIds = {},
	},

	Stats = {
		TotalCareActions = 0,
		TotalFeedActions = 0,
		TotalWaterActions = 0,
		TotalGroomActions = 0,
		TotalCleanActions = 0,
		TotalBondPointsEarned = 0,
		TotalQuestsCompleted = 0,
		TotalArenaRuns = 0,
		TotalCropsHarvested = 0,
		TotalHorsesOwned = 0,
	},

	LiveOps = {
		ClaimedRewards = {},
		SeenAnnouncements = {},
	},
}

return ProfileTemplate
