------------------//SERVICES
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------//CONSTANTS
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")

local StableDictionary = require(Dictionary:WaitForChild("StableDictionary"))
local HorseFactory = require(GameData:WaitForChild("HorseFactory"))

------------------//VARIABLES
local defaultHorse = HorseFactory.Create("Default", 0, {
	HorseId = "Default",
	Nickname = "Default",
	Source = "ProfileTemplate",
	IsStarterGrant = true,
	ObtainedAt = 0,
})

local defaultHorseSlots = StableDictionary.get_default_horse_slots()
defaultHorseSlots.Slot1 = defaultHorse.Id

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
		FirstHorseGranted = true,
		UnlockedFeatures = {
			Stable = true,
			TackShop = false,
			OutdoorStore = false,
			Farming = false,
			Arena = false,
		},
	},

	Horses = {
		EquippedHorseId = defaultHorse.Id,
		NextHorseInstanceId = 0,
		OrderedIds = { defaultHorse.Id },
		Owned = {
			[defaultHorse.Id] = defaultHorse,
		},
	},

	Inventory = {
		Tack = {},
		Cosmetics = {},
		StableDecor = {},
		Consumables = {
			Food = {},
			Water = {},
			Grooming = {},
			Medical = {},
			Misc = {},
		},
		Seeds = {},
		Trophies = {},
	},

	Stable = {
		Level = 1,
		OwnedStalls = StableDictionary.DefaultOwnedStalls,
		HorseSlots = defaultHorseSlots,
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

	Race = {
		RacesEntered = 0,
		RacesWon = 0,
		BestRaceTimeMs = 0,
		LastRaceAt = 0,
		TotalRewardsEarned = 0,
	},

	Collection = {
		DiscoveredHorseIds = { defaultHorse.CatalogId },
		OwnedHorseCatalogIds = { defaultHorse.CatalogId },
		UnlockedCosmeticIds = {},
	},

	Stats = {
		TotalCareActions = 0,
		TotalFeedActions = 0,
		TotalWaterActions = 0,
		TotalMedicalActions = 0,
		TotalGroomActions = 0,
		TotalCleanActions = 0,
		TotalBondPointsEarned = 0,
		TotalQuestsCompleted = 0,
		TotalArenaRuns = 0,
		TotalCropsHarvested = 0,
		TotalHorsesOwned = 1,
		TotalRacesEntered = 0,
		TotalRaceWins = 0,
	},

	LiveOps = {
		ClaimedRewards = {},
		SeenAnnouncements = {},
	},
}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
return ProfileTemplate
