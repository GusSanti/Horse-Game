local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utility = Modules:WaitForChild("Utility")

local TableUtility = require(Utility:WaitForChild("TableUtility"))

local HorseCatalog = {}

local SHARED_BONDING = {
	MaxFriendship = 100,
	StartingFriendship = 15,
	MaxBondLevel = 10,
	CareBonus = {
		Feed = 4,
		Water = 4,
		Groom = 4,
		Clean = 4,
		Quest = 12,
	},
}

local SHARED_DEPENDENCIES = {
	FavoriteFoods = { "hay_bale", "apple_treat" },
	FavoriteGroomingItems = { "soft_brush", "grooming_kit" },
	FavoriteActivities = { "DailyCare", "ArenaSprint" },
	StableNeeds = { "WaterBucket", "CleanStall" },
}

local SHARED_NEEDS = {
	Max = {
		Happiness = 100,
		Hunger = 100,
		Thirst = 100,
		Cleanliness = 100,
		Health = 100,
	},
	Starting = {
		Happiness = 88,
		Hunger = 92,
		Thirst = 92,
		Cleanliness = 90,
		Health = 100,
	},
	DecayPerHour = {
		Happiness = 2.8,
		Hunger = 2.9,
		Thirst = 2.9,
		Cleanliness = 2.8,
		Health = 3.1,
	},
}

local function create_definition(definition)
	return {
		CatalogId = definition.CatalogId,
		DisplayName = definition.DisplayName,
		ShortName = definition.ShortName or definition.DisplayName,
		Tier = definition.Tier or "Starter",
		Rarity = definition.Rarity or "Common",
		LaunchGroup = definition.LaunchGroup or "Launch",
		PlaceholderModelKey = definition.PlaceholderModelKey or definition.DisplayName,
		Image = definition.Image or "",
		Description = definition.Description or "",
		Bonding = TableUtility.DeepCopy(definition.Bonding or SHARED_BONDING),
		Dependencies = TableUtility.DeepCopy(definition.Dependencies or SHARED_DEPENDENCIES),
		Movement = TableUtility.DeepCopy(definition.Movement or {}),
		Temperament = TableUtility.DeepCopy(definition.Temperament or {}),
		Needs = TableUtility.DeepCopy(definition.Needs or SHARED_NEEDS),
	}
end

HorseCatalog.RoulettePrice = 500

HorseCatalog.RoulettePool = {
	{ CatalogId = "quarter_horse", Weight = 38 },
	{ CatalogId = "american_paint_horse", Weight = 28 },
	{ CatalogId = "andalusian", Weight = 16 },
	{ CatalogId = "american_saddlebred", Weight = 10 },
	{ CatalogId = "lipizzaner", Weight = 6 },
	{ CatalogId = "friesian", Weight = 2 },
}

HorseCatalog.StarterPool = HorseCatalog.RoulettePool

HorseCatalog.Definitions = {
	Default = create_definition({
		CatalogId = "Default",
		DisplayName = "Default",
		ShortName = "Default",
		Tier = "Starter",
		Rarity = "Common",
		PlaceholderModelKey = "Default",
		Description = "Fallback horse definition used when a specific catalog id is unavailable.",
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
			Gentleness = 82,
			Energy = 68,
			Bravery = 74,
			Focus = 78,
			Sociability = 80,
		},
	}),
	american_paint_horse = create_definition({
		CatalogId = "american_paint_horse",
		DisplayName = "American Paint Horse",
		ShortName = "Paint",
		Tier = "Starter",
		Rarity = "Common",
		PlaceholderModelKey = "American Paint Horse",
		Image = "rbxassetid://131074427513576",
		Description = "A balanced all-rounder with a calm presence and reliable pace.",
		Movement = {
			WalkSpeed = 14,
			TrotSpeed = 19,
			CanterSpeed = 23,
			SprintSpeed = 27,
			Acceleration = 0.86,
			TurnRate = 0.8,
			Stamina = 100,
			Jump = 0.8,
			RaceAffinity = 0.72,
		},
		Temperament = {
			Gentleness = 86,
			Energy = 72,
			Bravery = 72,
			Focus = 76,
			Sociability = 86,
		},
	}),
	andalusian = create_definition({
		CatalogId = "andalusian",
		DisplayName = "Andalusian",
		ShortName = "Andalusian",
		Tier = "Sport",
		Rarity = "Uncommon",
		PlaceholderModelKey = "Andalusian",
		Image = "rbxassetid://101594609020877",
		Description = "A focused endurance horse built for steady runs and composed handling.",
		Movement = {
			WalkSpeed = 13,
			TrotSpeed = 18,
			CanterSpeed = 22,
			SprintSpeed = 26,
			Acceleration = 0.8,
			TurnRate = 0.77,
			Stamina = 110,
			Jump = 0.76,
			RaceAffinity = 0.68,
		},
		Temperament = {
			Gentleness = 78,
			Energy = 64,
			Bravery = 84,
			Focus = 88,
			Sociability = 68,
		},
	}),
	friesian = create_definition({
		CatalogId = "friesian",
		DisplayName = "Friesian",
		ShortName = "Friesian",
		Tier = "Elite",
		Rarity = "Legendary",
		PlaceholderModelKey = "Friesian",
		Image = "rbxassetid://131573941244089",
		Description = "A striking powerhouse with deep stamina and an unmistakable silhouette.",
		Movement = {
			WalkSpeed = 13,
			TrotSpeed = 17,
			CanterSpeed = 21,
			SprintSpeed = 24,
			Acceleration = 0.74,
			TurnRate = 0.73,
			Stamina = 116,
			Jump = 0.72,
			RaceAffinity = 0.6,
		},
		Temperament = {
			Gentleness = 72,
			Energy = 56,
			Bravery = 88,
			Focus = 82,
			Sociability = 60,
		},
	}),
	lipizzaner = create_definition({
		CatalogId = "lipizzaner",
		DisplayName = "Lipizzaner",
		ShortName = "Lipizzaner",
		Tier = "Elite",
		Rarity = "Epic",
		PlaceholderModelKey = "Lipizzaner",
		Image = "rbxassetid://134974544197868",
		Description = "A poised specialist with high focus, elegant movement, and precise jumps.",
		Movement = {
			WalkSpeed = 13,
			TrotSpeed = 18,
			CanterSpeed = 22,
			SprintSpeed = 25,
			Acceleration = 0.78,
			TurnRate = 0.79,
			Stamina = 104,
			Jump = 0.9,
			RaceAffinity = 0.64,
		},
		Temperament = {
			Gentleness = 76,
			Energy = 60,
			Bravery = 80,
			Focus = 92,
			Sociability = 64,
		},
	}),
	quarter_horse = create_definition({
		CatalogId = "quarter_horse",
		DisplayName = "Quarter Horse",
		ShortName = "Quarter",
		Tier = "Starter",
		Rarity = "Common",
		PlaceholderModelKey = "Quarter Horse",
		Image = "rbxassetid://99406170486621",
		Description = "An explosive sprinter with quick acceleration and strong race instincts.",
		Movement = {
			WalkSpeed = 14,
			TrotSpeed = 20,
			CanterSpeed = 24,
			SprintSpeed = 29,
			Acceleration = 0.92,
			TurnRate = 0.82,
			Stamina = 96,
			Jump = 0.78,
			RaceAffinity = 0.8,
		},
		Temperament = {
			Gentleness = 80,
			Energy = 84,
			Bravery = 74,
			Focus = 78,
			Sociability = 76,
		},
	}),
	american_saddlebred = create_definition({
		CatalogId = "american_saddlebred",
		DisplayName = "American Saddlebred",
		ShortName = "Saddlebred",
		Tier = "Show",
		Rarity = "Rare",
		PlaceholderModelKey = "American Saddlebred",
		Image = "rbxassetid://117520239878803",
		Description = "A stylish control horse that keeps rhythm well and handles cleanly at speed.",
		Movement = {
			WalkSpeed = 14,
			TrotSpeed = 20,
			CanterSpeed = 24,
			SprintSpeed = 28,
			Acceleration = 0.88,
			TurnRate = 0.84,
			Stamina = 98,
			Jump = 0.82,
			RaceAffinity = 0.75,
		},
		Temperament = {
			Gentleness = 82,
			Energy = 80,
			Bravery = 70,
			Focus = 80,
			Sociability = 78,
		},
	}),
}

local function get_roulette_entry(catalogId)
	for _, entry in ipairs(HorseCatalog.RoulettePool) do
		if entry.CatalogId == catalogId then
			return entry
		end
	end

	return nil
end

local function roll_weighted_catalog_id(pool)
	local totalWeight = 0

	for _, entry in ipairs(pool) do
		totalWeight += math.max(0, tonumber(entry.Weight) or 0)
	end

	if totalWeight <= 0 then
		return "Default"
	end

	local roll = math.random(1, totalWeight)
	local runningTotal = 0

	for _, entry in ipairs(pool) do
		runningTotal += math.max(0, tonumber(entry.Weight) or 0)
		if roll <= runningTotal then
			return entry.CatalogId
		end
	end

	return pool[#pool] and pool[#pool].CatalogId or "Default"
end

function HorseCatalog.GetDefinition(catalogId)
	return HorseCatalog.Definitions[catalogId]
end

function HorseCatalog.GetStarterPool()
	return HorseCatalog.StarterPool
end

function HorseCatalog.GetRoulettePool()
	return HorseCatalog.RoulettePool
end

function HorseCatalog.GetRouletteEntry(catalogId)
	return get_roulette_entry(catalogId)
end

function HorseCatalog.GetRouletteHorseOptions()
	local options = {}

	for _, entry in ipairs(HorseCatalog.RoulettePool) do
		local definition = HorseCatalog.GetDefinition(entry.CatalogId)
		if definition then
			options[#options + 1] = {
				CatalogId = definition.CatalogId,
				DisplayName = definition.DisplayName,
				Rarity = definition.Rarity,
				Weight = entry.Weight,
				ModelKey = definition.PlaceholderModelKey,
				Image = definition.Image,
			}
		end
	end

	return options
end

function HorseCatalog.RollRouletteHorseId()
	return roll_weighted_catalog_id(HorseCatalog.RoulettePool)
end

function HorseCatalog.GetStarterHorseIdForPlayer(_userId)
	return HorseCatalog.RollRouletteHorseId()
end

return HorseCatalog
