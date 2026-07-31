local Shared = require(script.Parent:WaitForChild("Shared"))

local FRUIT_IMAGE_IDS = {
	beetroot_fruit = "rbxassetid://136673913026027",
	carrot_fruit = "rbxassetid://78452739054701",
	corn_fruit = "rbxassetid://129860183380571",
	eggplant_fruit = "rbxassetid://88479108383566",
	garlic_fruit = "rbxassetid://106412346747593",
	grape_fruit = "rbxassetid://114455612544610",
	lettuce_fruit = "rbxassetid://126947296393285",
	pepper_fruit = "rbxassetid://90548924696388",
	pineapple_fruit = "rbxassetid://76176951210606",
	potato_fruit = "rbxassetid://97456292530893",
	pumpkin_fruit = "rbxassetid://77922108770901",
	radish_fruit = "rbxassetid://135353218234234",
	strawberry_fruit = "rbxassetid://96751196625233",
	tomato_fruit = "rbxassetid://133781086648596",
	wheat_fruit = "rbxassetid://86382292626844",
}

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
	push_unique(names, seen, displayName)
	push_unique(names, seen, ("Fruit%s"):format(cropId))

	return names
end

local function create_fruit(config)
	local cropId = config.CropId
	local displayName = config.DisplayName or cropId
	local toolName = config.ToolName or cropId
	local itemId = config.ItemId or ("%s_fruit"):format(string.lower(cropId))

	return Shared.CreateFruit({
		ItemId = itemId,
		CropId = cropId,
		CropDisplayName = displayName,
		DisplayName = config.FruitDisplayName or displayName,
		ToolName = toolName,
		IdImage = config.IdImage or FRUIT_IMAGE_IDS[itemId] or "",
		Description = config.Description or ("Freshly harvested %s from the farm."):format(string.lower(displayName)),
		SellPrice = config.SellPrice or 0,
		SortOrder = config.SortOrder or 0,
		HarvestYield = config.HarvestYield or 1,
		EffectsSummary = "Harvested farming produce",
		AssetPath = config.AssetPath or { "Fruits", toolName },
		ViewportAssetPath = config.ViewportAssetPath or { "Fruits", toolName },
		LegacyInventoryItems = config.LegacyInventoryItems or {},
		LegacyToolNames = build_legacy_names(cropId, toolName, displayName, config.LegacyToolNames),
		Tags = config.Tags or { "Crop", "Farming", "Produce" },
	})
end

local baseFruits = {
	create_fruit({
		ItemId = "beetroot_fruit",
		CropId = "Beetroot",
		SortOrder = 10,
		SellPrice = 5,
	}),
	create_fruit({
		ItemId = "carrot_fruit",
		CropId = "Carrot",
		SortOrder = 20,
		SellPrice = 5,
		LegacyInventoryItems = { "carrot_bunch" },
		LegacyToolNames = { "Carrot Bunch" },
	}),
	create_fruit({
		ItemId = "corn_fruit",
		CropId = "Corn",
		SortOrder = 30,
		SellPrice = 6,
	}),
	create_fruit({
		ItemId = "eggplant_fruit",
		CropId = "Eggplant",
		SortOrder = 40,
		SellPrice = 7,
	}),
	create_fruit({
		ItemId = "garlic_fruit",
		CropId = "Garlic",
		SortOrder = 50,
		SellPrice = 7,
	}),
	create_fruit({
		ItemId = "grape_fruit",
		CropId = "Grape",
		SortOrder = 60,
		SellPrice = 8,
	}),
	create_fruit({
		ItemId = "lettuce_fruit",
		CropId = "Lettuce",
		SortOrder = 70,
		SellPrice = 4,
	}),
	create_fruit({
		ItemId = "pepper_fruit",
		CropId = "Pepper",
		SortOrder = 80,
		SellPrice = 8,
	}),
	create_fruit({
		ItemId = "pineapple_fruit",
		CropId = "Pineapple",
		SortOrder = 90,
		SellPrice = 10,
	}),
	create_fruit({
		ItemId = "potato_fruit",
		CropId = "Potato",
		SortOrder = 100,
		SellPrice = 6,
	}),
	create_fruit({
		ItemId = "pumpkin_fruit",
		CropId = "Pumpkin",
		SortOrder = 110,
		SellPrice = 10,
	}),
	create_fruit({
		ItemId = "radish_fruit",
		CropId = "Radish",
		SortOrder = 120,
		SellPrice = 4,
	}),
	create_fruit({
		ItemId = "strawberry_fruit",
		CropId = "Strawberry",
		SortOrder = 130,
		SellPrice = 9,
	}),
	create_fruit({
		ItemId = "tomato_fruit",
		CropId = "Tomato",
		SortOrder = 140,
		SellPrice = 7,
	}),
	create_fruit({
		ItemId = "wheat_fruit",
		CropId = "Wheat",
		SortOrder = 150,
		SellPrice = 4,
	}),
}

local fruits = {}

for _, baseFruit in ipairs(baseFruits) do
	fruits[#fruits + 1] = baseFruit
	baseFruit.RareItemIds = {}
end

return fruits
