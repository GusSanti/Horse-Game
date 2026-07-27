local Shared = require(script.Parent:WaitForChild("Shared"))

local function push_unique(list, seen, value)
	if type(value) ~= "string" or value == "" or seen[value] then
		return
	end

	seen[value] = true
	list[#list + 1] = value
end

local function build_legacy_names(cropId: string, toolName: string, displayName: string, extraNames)
	local names = {}
	local seen = {}

	for _, name in ipairs(extraNames or {}) do
		push_unique(names, seen, name)
	end

	push_unique(names, seen, toolName)
	push_unique(names, seen, ("Seed%s"):format(cropId))
	push_unique(names, seen, ("%sSeed"):format(cropId))
	push_unique(names, seen, ("%s Seed"):format(displayName))
	push_unique(names, seen, ("%s Seeds"):format(displayName))

	return names
end

local function create_seed(config)
	local cropId = config.CropId
	local displayName = config.DisplayName or cropId
	local toolName = config.ToolName or ("%sSeed"):format(cropId)
	local itemId = config.ItemId or ("%s_seed"):format(string.lower(cropId))

	return Shared.CreateSeeds({
		ItemId = itemId,
		CropId = cropId,
		CropDisplayName = displayName,
		DisplayName = config.SeedDisplayName or ("%s Seed"):format(displayName),
		ToolName = toolName,
		Description = config.Description or ("Plant this seed in the farming soil to grow %s."):format(string.lower(displayName)),
		Price = config.Price or 0,
		PriceLabel = config.PriceLabel or ("%d horseshoes"):format(config.Price or 0),
		SortOrder = config.SortOrder or 0,
		EffectsSummary = "Plantable crop seed",
		AssetPath = config.AssetPath or { "Seeds", toolName },
		ViewportAssetPath = config.ViewportAssetPath or { "Seeds", toolName },
		LegacyToolNames = build_legacy_names(cropId, toolName, displayName, config.LegacyToolNames),
		Tags = config.Tags or { "Crop", "Farming" },
	})
end

return {
	create_seed({
		ItemId = "beetroot_seed",
		CropId = "Beetroot",
		SortOrder = 10,
		Price = 1,
	}),
	create_seed({
		ItemId = "carrot_seed",
		CropId = "Carrot",
		SortOrder = 20,
		Price = 1,
		ToolName = "SeedCarrot",
		LegacyToolNames = { "Seed" },
	}),
	create_seed({
		ItemId = "corn_seed",
		CropId = "Corn",
		SortOrder = 30,
		Price = 2,
	}),
	create_seed({
		ItemId = "eggplant_seed",
		CropId = "Eggplant",
		SortOrder = 40,
		Price = 2,
	}),
	create_seed({
		ItemId = "garlic_seed",
		CropId = "Garlic",
		SortOrder = 50,
		Price = 2,
	}),
	create_seed({
		ItemId = "grape_seed",
		CropId = "Grape",
		SortOrder = 60,
		Price = 3,
	}),
	create_seed({
		ItemId = "lettuce_seed",
		CropId = "Lettuce",
		SortOrder = 70,
		Price = 1,
	}),
	create_seed({
		ItemId = "pepper_seed",
		CropId = "Pepper",
		SortOrder = 80,
		Price = 3,
	}),
	create_seed({
		ItemId = "pineapple_seed",
		CropId = "Pineapple",
		SortOrder = 90,
		Price = 4,
	}),
	create_seed({
		ItemId = "potato_seed",
		CropId = "Potato",
		SortOrder = 100,
		Price = 2,
	}),
	create_seed({
		ItemId = "pumpkin_seed",
		CropId = "Pumpkin",
		SortOrder = 110,
		Price = 4,
	}),
	create_seed({
		ItemId = "radish_seed",
		CropId = "Radish",
		SortOrder = 120,
		Price = 1,
	}),
	create_seed({
		ItemId = "strawberry_seed",
		CropId = "Strawberry",
		SortOrder = 130,
		Price = 3,
	}),
	create_seed({
		ItemId = "tomato_seed",
		CropId = "Tomato",
		SortOrder = 140,
		Price = 2,
	}),
	create_seed({
		ItemId = "wheat_seed",
		CropId = "Wheat",
		SortOrder = 150,
		Price = 1,
	}),
}
