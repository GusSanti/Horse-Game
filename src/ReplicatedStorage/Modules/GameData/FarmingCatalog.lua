local FarmingCatalog = {}

local function normalize_key(value): string?
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	local normalizedValue = string.lower(trimmedValue)
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function push_unique_string(list, value, seenLookup)
	if type(value) ~= "string" or value == "" then
		return
	end

	if seenLookup[value] then
		return
	end

	seenLookup[value] = true
	list[#list + 1] = value
end

local function build_seed_legacy_names(cropId: string, seedToolName: string, displayName: string, extraAliases)
	local names = {}
	local seen = {}

	for _, value in ipairs(extraAliases or {}) do
		push_unique_string(names, value, seen)
	end

	push_unique_string(names, seedToolName, seen)
	push_unique_string(names, ("Seed%s"):format(cropId), seen)
	push_unique_string(names, ("%sSeed"):format(cropId), seen)
	push_unique_string(names, ("%s Seed"):format(displayName), seen)
	push_unique_string(names, ("%s Seeds"):format(displayName), seen)

	return names
end

local function build_fruit_legacy_names(cropId: string, fruitToolName: string, displayName: string, extraAliases)
	local names = {}
	local seen = {}

	for _, value in ipairs(extraAliases or {}) do
		push_unique_string(names, value, seen)
	end

	push_unique_string(names, fruitToolName, seen)
	push_unique_string(names, displayName, seen)
	push_unique_string(names, ("Fruit%s"):format(cropId), seen)

	return names
end

local function build_stage_folder_aliases(cropId: string, explicitAliases)
	local aliases = {}
	local seen = {}

	push_unique_string(aliases, cropId, seen)

	for _, alias in ipairs(explicitAliases or {}) do
		push_unique_string(aliases, alias, seen)
	end

	return aliases
end

local function clamp_number(value: number, minValue: number, maxValue: number): number
	return math.max(minValue, math.min(maxValue, value))
end

local function build_crop_definition(config)
	local cropId = config.CropId
	local displayName = config.DisplayName or cropId
	local seedToolName = config.SeedToolName or ("%sSeed"):format(cropId)
	local fruitToolName = config.FruitToolName or cropId
	local stageFolderName = config.StageFolderName or cropId
	local stageAssetPrefix = config.StageAssetPrefix or ("SM_%s"):format(cropId)
	local maxStage = math.max(1, math.floor(tonumber(config.MaxStage) or 4))
	local waterIntervalSeconds = math.max(1, math.floor(tonumber(config.WaterIntervalSeconds) or 300))
	local initialWaterDelaySeconds = math.max(1, math.floor(tonumber(config.InitialWaterDelaySeconds) or waterIntervalSeconds))
	local stageAdvanceRatio = clamp_number(tonumber(config.StageAdvanceRatio) or 0.6, 0.1, 0.95)

	return {
		CropId = cropId,
		DisplayName = displayName,
		StageFolderName = stageFolderName,
		StageFolderAliases = build_stage_folder_aliases(cropId, config.StageFolderAliases),
		StageAssetPrefix = stageAssetPrefix,
		SortOrder = math.max(0, math.floor(tonumber(config.SortOrder) or 0)),
		MaxStage = maxStage,
		InitialWaterDelaySeconds = initialWaterDelaySeconds,
		WaterIntervalSeconds = waterIntervalSeconds,
		StageAdvanceRatio = stageAdvanceRatio,
		Seed = {
			ItemId = config.SeedItemId or ("%s_seed"):format(string.lower(cropId)),
			DisplayName = config.SeedDisplayName or ("%s Seed"):format(displayName),
			ToolName = seedToolName,
			InventoryPath = "Inventory.Seeds",
			Price = math.max(0, math.floor(tonumber(config.SeedPrice) or 0)),
			AssetPath = config.SeedAssetPath or { "Seeds", seedToolName },
			ViewportAssetPath = config.SeedViewportAssetPath or { "Seeds", seedToolName },
			LegacyToolNames = build_seed_legacy_names(
				cropId,
				seedToolName,
				displayName,
				config.LegacySeedToolNames
			),
		},
		Fruit = {
			ItemId = config.FruitItemId or ("%s_fruit"):format(string.lower(cropId)),
			DisplayName = config.FruitDisplayName or displayName,
			ToolName = fruitToolName,
			InventoryPath = "Inventory.Fruits",
			SellPrice = math.max(0, math.floor(tonumber(config.FruitSellPrice) or 0)),
			HarvestYield = math.max(1, math.floor(tonumber(config.HarvestYield) or 1)),
			AssetPath = config.FruitAssetPath or { "Fruits", fruitToolName },
			ViewportAssetPath = config.FruitViewportAssetPath or { "Fruits", fruitToolName },
			LegacyInventoryItems = config.LegacyInventoryItems or {},
			LegacyToolNames = build_fruit_legacy_names(
				cropId,
				fruitToolName,
				displayName,
				config.LegacyFruitToolNames
			),
		},
	}
end

local cropDefinitions = {
	build_crop_definition({
		CropId = "Beetroot",
		SortOrder = 10,
		SeedPrice = 1,
		FruitSellPrice = 5,
		WaterIntervalSeconds = 300,
	}),
	build_crop_definition({
		CropId = "Carrot",
		SortOrder = 20,
		SeedPrice = 1,
		FruitSellPrice = 5,
		WaterIntervalSeconds = 7,
		StageFolderAliases = { "CarrotStage" },
		LegacySeedToolNames = { "SeedCarrot", "Seed" },
		LegacyFruitToolNames = { "Carrot Bunch" },
		LegacyInventoryItems = { "carrot_bunch" },
	}),
	build_crop_definition({
		CropId = "Corn",
		SortOrder = 30,
		SeedPrice = 2,
		FruitSellPrice = 6,
		WaterIntervalSeconds = 420,
	}),
	build_crop_definition({
		CropId = "Eggplant",
		SortOrder = 40,
		SeedPrice = 2,
		FruitSellPrice = 7,
		WaterIntervalSeconds = 480,
	}),
	build_crop_definition({
		CropId = "Garlic",
		SortOrder = 50,
		SeedPrice = 2,
		FruitSellPrice = 7,
		WaterIntervalSeconds = 360,
	}),
	build_crop_definition({
		CropId = "Grape",
		SortOrder = 60,
		SeedPrice = 3,
		FruitSellPrice = 8,
		WaterIntervalSeconds = 600,
	}),
	build_crop_definition({
		CropId = "Lettuce",
		SortOrder = 70,
		SeedPrice = 1,
		FruitSellPrice = 4,
		WaterIntervalSeconds = 180,
	}),
	build_crop_definition({
		CropId = "Pepper",
		SortOrder = 80,
		SeedPrice = 3,
		FruitSellPrice = 8,
		WaterIntervalSeconds = 420,
	}),
	build_crop_definition({
		CropId = "Pineapple",
		SortOrder = 90,
		SeedPrice = 4,
		FruitSellPrice = 10,
		WaterIntervalSeconds = 720,
	}),
	build_crop_definition({
		CropId = "Potato",
		SortOrder = 100,
		SeedPrice = 2,
		FruitSellPrice = 6,
		WaterIntervalSeconds = 300,
	}),
	build_crop_definition({
		CropId = "Pumpkin",
		SortOrder = 110,
		SeedPrice = 4,
		FruitSellPrice = 10,
		WaterIntervalSeconds = 720,
	}),
	build_crop_definition({
		CropId = "Radish",
		SortOrder = 120,
		SeedPrice = 1,
		FruitSellPrice = 4,
		WaterIntervalSeconds = 150,
	}),
	build_crop_definition({
		CropId = "Strawberry",
		SortOrder = 130,
		SeedPrice = 3,
		FruitSellPrice = 9,
		WaterIntervalSeconds = 360,
	}),
	build_crop_definition({
		CropId = "Tomato",
		SortOrder = 140,
		SeedPrice = 2,
		FruitSellPrice = 7,
		WaterIntervalSeconds = 420,
	}),
	build_crop_definition({
		CropId = "Wheat",
		SortOrder = 150,
		SeedPrice = 1,
		FruitSellPrice = 4,
		WaterIntervalSeconds = 240,
	}),
}

local cropsById = {}
local itemsById = {}
local seedItems = {}
local fruitItems = {}

for _, cropDefinition in ipairs(cropDefinitions) do
	local normalizedCropId = normalize_key(cropDefinition.CropId)
	cropDefinition.NormalizedCropId = normalizedCropId
	cropsById[normalizedCropId] = cropDefinition

	for itemKind, itemDefinition in pairs({
		Seed = cropDefinition.Seed,
		Fruit = cropDefinition.Fruit,
	}) do
		itemDefinition.Kind = itemKind
		itemDefinition.CropId = cropDefinition.CropId
		itemDefinition.CropDisplayName = cropDefinition.DisplayName
		itemDefinition.StageFolderName = cropDefinition.StageFolderName
		itemDefinition.StageFolderAliases = cropDefinition.StageFolderAliases
		itemDefinition.StageAssetPrefix = cropDefinition.StageAssetPrefix
		itemDefinition.SortOrder = cropDefinition.SortOrder
		itemDefinition.MaxStage = cropDefinition.MaxStage

		local normalizedItemId = normalize_key(itemDefinition.ItemId)
		itemDefinition.NormalizedItemId = normalizedItemId
		itemsById[normalizedItemId] = itemDefinition

		if itemKind == "Seed" then
			seedItems[#seedItems + 1] = itemDefinition
		else
			fruitItems[#fruitItems + 1] = itemDefinition
		end
	end
end

table.sort(seedItems, function(left, right)
	return (left.SortOrder or 0) < (right.SortOrder or 0)
end)

table.sort(fruitItems, function(left, right)
	return (left.SortOrder or 0) < (right.SortOrder or 0)
end)

FarmingCatalog.Crops = cropDefinitions
FarmingCatalog.Seeds = seedItems
FarmingCatalog.Fruits = fruitItems
FarmingCatalog.Seed = seedItems[1]
FarmingCatalog.Fruit = fruitItems[1]

function FarmingCatalog.NormalizeKey(value): string?
	return normalize_key(value)
end

function FarmingCatalog.GetItemCount(bucket, itemId)
	if type(bucket) ~= "table" then
		return 0
	end

	return bucket[itemId] or 0
end

function FarmingCatalog.GetCrop(cropId)
	return cropsById[normalize_key(cropId)]
end

function FarmingCatalog.GetItem(itemId)
	return itemsById[normalize_key(itemId)]
end

function FarmingCatalog.GetSeedItems()
	return seedItems
end

function FarmingCatalog.GetFruitItems()
	return fruitItems
end

return FarmingCatalog
