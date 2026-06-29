local HorseCatalog = {}

HorseCatalog.StarterPool = {
	"Default",
}

HorseCatalog.Definitions = {
	Default = {
		CatalogId = "Default",
		DisplayName = "Default",
		ShortName = "Default",
		Tier = "Starter",
		Rarity = "Common",
		LaunchGroup = "Launch",
		PlaceholderModelKey = "Default",
		Description = "The default horse every player starts with.",
		Bonding = {
			MaxFriendship = 100,
			StartingFriendship = 15,
			MaxBondLevel = 10,
			CareBonus = {
				Feed = 4,
				Water = 4,
				Groom = 4,
				Clean = 4,
				Quest = 10,
			},
		},
		Dependencies = {
			FavoriteFoods = { "hay_bale" },
			FavoriteGroomingItems = { "soft_brush" },
			FavoriteActivities = { "DailyCare" },
			StableNeeds = { "WaterBucket" },
		},
		Movement = {
			WalkSpeed = 14,
			TrotSpeed = 18,
			CanterSpeed = 22,
			SprintSpeed = 26,
			Acceleration = 0.8,
			TurnRate = 0.78,
			Stamina = 100,
			Jump = 0.76,
			RaceAffinity = 0.66,
		},
		Temperament = {
			Gentleness = 85,
			Energy = 68,
			Bravery = 72,
			Focus = 78,
			Sociability = 80,
		},
		Needs = {
			Max = {
				Happiness = 100,
				Hunger = 100,
				Thirst = 100,
				Cleanliness = 100,
				Health = 100,
			},
			Starting = {
				Happiness = 80,
				Hunger = 85,
				Thirst = 85,
				Cleanliness = 90,
				Health = 100,
			},
			DecayPerHour = {
				Happiness = 2.9,
				Hunger = 5.8,
				Thirst = 5.8,
				Cleanliness = 4.35,
				Health = 1.45,
			},
		},
	},
	starter_meadow_bay = {
		CatalogId = "starter_meadow_bay",
		DisplayName = "Meadow Bay",
		ShortName = "Meadow",
		Tier = "Starter",
		Rarity = "Common",
		LaunchGroup = "Launch",
		PlaceholderModelKey = "Horse_MeadowBay",
		Description = "A calm starter horse with balanced bond growth and steady movement.",
		Bonding = {
			MaxFriendship = 100,
			StartingFriendship = 15,
			MaxBondLevel = 10,
			CareBonus = {
				Feed = 4,
				Water = 3,
				Groom = 5,
				Clean = 3,
				Quest = 12,
			},
		},
		Dependencies = {
			FavoriteFoods = { "hay_bale", "apple_treat" },
			FavoriteGroomingItems = { "soft_brush", "grooming_kit" },
			FavoriteActivities = { "DailyCare", "ArenaSprint" },
			StableNeeds = { "WaterBucket", "CleanStall" },
		},
		Movement = {
			WalkSpeed = 14,
			TrotSpeed = 18,
			CanterSpeed = 22,
			SprintSpeed = 26,
			Acceleration = 0.82,
			TurnRate = 0.78,
			Stamina = 100,
			Jump = 0.75,
			RaceAffinity = 0.65,
		},
		Temperament = {
			Gentleness = 88,
			Energy = 62,
			Bravery = 70,
			Focus = 78,
			Sociability = 82,
		},
		Needs = {
			Max = {
				Happiness = 100,
				Hunger = 100,
				Thirst = 100,
				Cleanliness = 100,
				Health = 100,
			},
			Starting = {
				Happiness = 78,
				Hunger = 86,
				Thirst = 84,
				Cleanliness = 90,
				Health = 100,
			},
			DecayPerHour = {
				Happiness = 2.9,
				Hunger = 5.8,
				Thirst = 7.25,
				Cleanliness = 4.35,
				Health = 1.45,
			},
		},
	},
	starter_dusty_chestnut = {
		CatalogId = "starter_dusty_chestnut",
		DisplayName = "Dusty Chestnut",
		ShortName = "Dusty",
		Tier = "Starter",
		Rarity = "Common",
		LaunchGroup = "Launch",
		PlaceholderModelKey = "Horse_DustyChestnut",
		Description = "A friendly horse that bonds quickly and keeps good pace in simple races.",
		Bonding = {
			MaxFriendship = 100,
			StartingFriendship = 18,
			MaxBondLevel = 10,
			CareBonus = {
				Feed = 3,
				Water = 3,
				Groom = 6,
				Clean = 4,
				Quest = 10,
			},
		},
		Dependencies = {
			FavoriteFoods = { "apple_treat", "carrot_bunch" },
			FavoriteGroomingItems = { "soft_brush", "shine_kit" },
			FavoriteActivities = { "DailyCare", "StablePhoto" },
			StableNeeds = { "CleanStall", "FreshHay" },
		},
		Movement = {
			WalkSpeed = 14,
			TrotSpeed = 19,
			CanterSpeed = 23,
			SprintSpeed = 27,
			Acceleration = 0.86,
			TurnRate = 0.8,
			Stamina = 96,
			Jump = 0.8,
			RaceAffinity = 0.72,
		},
		Temperament = {
			Gentleness = 84,
			Energy = 72,
			Bravery = 76,
			Focus = 74,
			Sociability = 88,
		},
		Needs = {
			Max = {
				Happiness = 100,
				Hunger = 100,
				Thirst = 100,
				Cleanliness = 100,
				Health = 100,
			},
			Starting = {
				Happiness = 82,
				Hunger = 84,
				Thirst = 82,
				Cleanliness = 88,
				Health = 100,
			},
			DecayPerHour = {
				Happiness = 2.9,
				Hunger = 5.8,
				Thirst = 7.25,
				Cleanliness = 5.8,
				Health = 1.45,
			},
		},
	},
	starter_moon_gray = {
		CatalogId = "starter_moon_gray",
		DisplayName = "Moon Gray",
		ShortName = "Moon",
		Tier = "Starter",
		Rarity = "Common",
		LaunchGroup = "Launch",
		PlaceholderModelKey = "Horse_MoonGray",
		Description = "A focused and reliable horse with strong stamina for longer activities.",
		Bonding = {
			MaxFriendship = 100,
			StartingFriendship = 12,
			MaxBondLevel = 10,
			CareBonus = {
				Feed = 4,
				Water = 4,
				Groom = 4,
				Clean = 3,
				Quest = 14,
			},
		},
		Dependencies = {
			FavoriteFoods = { "hay_bale", "mint_treat" },
			FavoriteGroomingItems = { "grooming_kit", "shine_kit" },
			FavoriteActivities = { "ArenaSprint", "TrailWalk" },
			StableNeeds = { "WaterBucket", "QuietCorner" },
		},
		Movement = {
			WalkSpeed = 13,
			TrotSpeed = 18,
			CanterSpeed = 22,
			SprintSpeed = 25,
			Acceleration = 0.78,
			TurnRate = 0.76,
			Stamina = 112,
			Jump = 0.74,
			RaceAffinity = 0.68,
		},
		Temperament = {
			Gentleness = 80,
			Energy = 58,
			Bravery = 82,
			Focus = 90,
			Sociability = 68,
		},
		Needs = {
			Max = {
				Happiness = 100,
				Hunger = 100,
				Thirst = 100,
				Cleanliness = 100,
				Health = 100,
			},
			Starting = {
				Happiness = 74,
				Hunger = 88,
				Thirst = 86,
				Cleanliness = 89,
				Health = 100,
			},
			DecayPerHour = {
				Happiness = 2.9,
				Hunger = 4.35,
				Thirst = 5.8,
				Cleanliness = 4.35,
				Health = 1.45,
			},
		},
	},
	starter_midnight_black = {
		CatalogId = "starter_midnight_black",
		DisplayName = "Midnight Black",
		ShortName = "Midnight",
		Tier = "Starter",
		Rarity = "Common",
		LaunchGroup = "Launch",
		PlaceholderModelKey = "Horse_MidnightBlack",
		Description = "A fast, energetic horse with higher race potential and slightly fussier care needs.",
		Bonding = {
			MaxFriendship = 100,
			StartingFriendship = 10,
			MaxBondLevel = 10,
			CareBonus = {
				Feed = 3,
				Water = 3,
				Groom = 5,
				Clean = 5,
				Quest = 15,
			},
		},
		Dependencies = {
			FavoriteFoods = { "carrot_bunch", "mint_treat" },
			FavoriteGroomingItems = { "soft_brush", "shine_kit" },
			FavoriteActivities = { "ArenaSprint", "JumpPractice" },
			StableNeeds = { "FreshHay", "CleanStall" },
		},
		Movement = {
			WalkSpeed = 14,
			TrotSpeed = 20,
			CanterSpeed = 24,
			SprintSpeed = 29,
			Acceleration = 0.92,
			TurnRate = 0.84,
			Stamina = 94,
			Jump = 0.82,
			RaceAffinity = 0.82,
		},
		Temperament = {
			Gentleness = 72,
			Energy = 88,
			Bravery = 80,
			Focus = 76,
			Sociability = 66,
		},
		Needs = {
			Max = {
				Happiness = 100,
				Hunger = 100,
				Thirst = 100,
				Cleanliness = 100,
				Health = 100,
			},
			Starting = {
				Happiness = 76,
				Hunger = 82,
				Thirst = 80,
				Cleanliness = 86,
				Health = 100,
			},
			DecayPerHour = {
				Happiness = 4.35,
				Hunger = 7.25,
				Thirst = 7.25,
				Cleanliness = 5.8,
				Health = 1.45,
			},
		},
	},
}

function HorseCatalog.GetDefinition(catalogId)
	return HorseCatalog.Definitions[catalogId]
end

function HorseCatalog.GetStarterPool()
	return HorseCatalog.StarterPool
end

function HorseCatalog.GetStarterHorseIdForPlayer(userId)
	local pool = HorseCatalog.GetStarterPool()
	local index = (math.abs(userId) % #pool) + 1
	return pool[index]
end

return HorseCatalog
