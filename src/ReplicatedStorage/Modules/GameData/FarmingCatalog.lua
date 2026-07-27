local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local FarmingCatalog = {}

local rarityDefinitions = {
	Diamond = {
		Name = "Diamond",
		Chance = 1,
	},
	Gold = {
		Name = "Gold",
		Chance = 0.05,
	},
}

local rarityRollOrder = {
	rarityDefinitions.Diamond,
	rarityDefinitions.Gold,
}

local rarityRandom = Random.new()

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
	if type(value) ~= "string" or value == "" or seenLookup[value] then
		return
	end

	seenLookup[value] = true
	list[#list + 1] = value
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

local function resolve_linked_item(cropId: string, itemId: string, expectedKind: string)
	local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
	assert(itemDefinition ~= nil, ("Farming crop '%s' references missing item '%s'"):format(cropId, tostring(itemId)))
	assert(
		itemDefinition.Kind == expectedKind,
		("Farming crop '%s' item '%s' must be kind '%s'"):format(cropId, tostring(itemId), expectedKind)
	)
	assert(
		normalize_key(itemDefinition.CropId) == normalize_key(cropId),
		("Farming crop '%s' item '%s' is linked to crop '%s'"):format(
			cropId,
			tostring(itemId),
			tostring(itemDefinition.CropId)
		)
	)

	return itemDefinition
end

local function build_crop_definition(config)
	local cropId = config.CropId
	local seedItemId = config.SeedItemId or ("%s_seed"):format(string.lower(cropId))
	local fruitItemId = config.FruitItemId or ("%s_fruit"):format(string.lower(cropId))
	local seedItem = resolve_linked_item(cropId, seedItemId, "Seed")
	local fruitItem = resolve_linked_item(cropId, fruitItemId, "Fruit")
	local rareFruits = {}

	for rarityName, rareItemId in pairs(fruitItem.RareItemIds or {}) do
		local rareFruit = resolve_linked_item(cropId, rareItemId, "Fruit")
		assert(
			rareFruit.Rarity == rarityName,
			("Farming crop '%s' rare item '%s' must use rarity '%s'"):format(cropId, rareItemId, rarityName)
		)
		rareFruits[rarityName] = rareFruit
	end

	local displayName = config.DisplayName or fruitItem.CropDisplayName or fruitItem.DisplayName or cropId
	local stageFolderName = config.StageFolderName or cropId
	local stageAssetPrefix = config.StageAssetPrefix or ("SM_%s"):format(cropId)
	local maxStage = math.max(1, math.floor(tonumber(config.MaxStage) or 4))
	local waterIntervalSeconds = math.max(1, math.floor(tonumber(config.WaterIntervalSeconds) or 300))
	local initialWaterDelaySeconds = math.max(1, math.floor(tonumber(config.InitialWaterDelaySeconds) or waterIntervalSeconds))
	local stageAdvanceRatio = clamp_number(tonumber(config.StageAdvanceRatio) or 0.6, 0.1, 0.95)

	return {
		CropId = cropId,
		NormalizedCropId = normalize_key(cropId),
		DisplayName = displayName,
		SeedItemId = seedItem.ItemId,
		FruitItemId = fruitItem.ItemId,
		Seed = seedItem,
		Fruit = fruitItem,
		RareFruits = rareFruits,
		StageFolderName = stageFolderName,
		StageFolderAliases = build_stage_folder_aliases(cropId, config.StageFolderAliases),
		StageAssetPrefix = stageAssetPrefix,
		SortOrder = math.max(0, math.floor(tonumber(config.SortOrder or seedItem.SortOrder or fruitItem.SortOrder) or 0)),
		MaxStage = maxStage,
		InitialWaterDelaySeconds = initialWaterDelaySeconds,
		WaterIntervalSeconds = waterIntervalSeconds,
		StageAdvanceRatio = stageAdvanceRatio,
	}
end

local cropDefinitions = {
	build_crop_definition({
		CropId = "Beetroot",
		SeedItemId = "beetroot_seed",
		FruitItemId = "beetroot_fruit",
		SortOrder = 10,
		WaterIntervalSeconds = 300,
	}),
	build_crop_definition({
		CropId = "Carrot",
		SeedItemId = "carrot_seed",
		FruitItemId = "carrot_fruit",
		SortOrder = 20,
		WaterIntervalSeconds = 7,
		StageFolderAliases = { "CarrotStage" },
	}),
	build_crop_definition({
		CropId = "Corn",
		SeedItemId = "corn_seed",
		FruitItemId = "corn_fruit",
		SortOrder = 30,
		WaterIntervalSeconds = 420,
	}),
	build_crop_definition({
		CropId = "Eggplant",
		SeedItemId = "eggplant_seed",
		FruitItemId = "eggplant_fruit",
		SortOrder = 40,
		WaterIntervalSeconds = 480,
	}),
	build_crop_definition({
		CropId = "Garlic",
		SeedItemId = "garlic_seed",
		FruitItemId = "garlic_fruit",
		SortOrder = 50,
		WaterIntervalSeconds = 360,
	}),
	build_crop_definition({
		CropId = "Grape",
		SeedItemId = "grape_seed",
		FruitItemId = "grape_fruit",
		SortOrder = 60,
		WaterIntervalSeconds = 600,
	}),
	build_crop_definition({
		CropId = "Lettuce",
		SeedItemId = "lettuce_seed",
		FruitItemId = "lettuce_fruit",
		SortOrder = 70,
		WaterIntervalSeconds = 180,
	}),
	build_crop_definition({
		CropId = "Pepper",
		SeedItemId = "pepper_seed",
		FruitItemId = "pepper_fruit",
		SortOrder = 80,
		WaterIntervalSeconds = 420,
	}),
	build_crop_definition({
		CropId = "Pineapple",
		SeedItemId = "pineapple_seed",
		FruitItemId = "pineapple_fruit",
		SortOrder = 90,
		WaterIntervalSeconds = 720,
	}),
	build_crop_definition({
		CropId = "Potato",
		SeedItemId = "potato_seed",
		FruitItemId = "potato_fruit",
		SortOrder = 100,
		WaterIntervalSeconds = 300,
	}),
	build_crop_definition({
		CropId = "Pumpkin",
		SeedItemId = "pumpkin_seed",
		FruitItemId = "pumpkin_fruit",
		SortOrder = 110,
		WaterIntervalSeconds = 720,
	}),
	build_crop_definition({
		CropId = "Radish",
		SeedItemId = "radish_seed",
		FruitItemId = "radish_fruit",
		SortOrder = 120,
		WaterIntervalSeconds = 150,
	}),
	build_crop_definition({
		CropId = "Strawberry",
		SeedItemId = "strawberry_seed",
		FruitItemId = "strawberry_fruit",
		SortOrder = 130,
		WaterIntervalSeconds = 360,
	}),
	build_crop_definition({
		CropId = "Tomato",
		SeedItemId = "tomato_seed",
		FruitItemId = "tomato_fruit",
		SortOrder = 140,
		WaterIntervalSeconds = 420,
	}),
	build_crop_definition({
		CropId = "Wheat",
		SeedItemId = "wheat_seed",
		FruitItemId = "wheat_fruit",
		SortOrder = 150,
		WaterIntervalSeconds = 240,
	}),
}

local cropsById = {}
local seedItems = {}
local seedItemsById = {}

for _, cropDefinition in ipairs(cropDefinitions) do
	cropsById[cropDefinition.NormalizedCropId] = cropDefinition

	seedItems[#seedItems + 1] = cropDefinition.Seed
	seedItemsById[normalize_key(cropDefinition.Seed.ItemId)] = cropDefinition.Seed
end

table.sort(seedItems, function(left, right)
	return (left.SortOrder or 0) < (right.SortOrder or 0)
end)

FarmingCatalog.Crops = cropDefinitions
FarmingCatalog.RarityDefinitions = rarityDefinitions

function FarmingCatalog.NormalizeKey(value): string?
	return normalize_key(value)
end

function FarmingCatalog.GetCrop(cropId)
	return cropsById[normalize_key(cropId)]
end

function FarmingCatalog.GetSeedItem(itemId)
	return seedItemsById[normalize_key(itemId)]
end

function FarmingCatalog.GetSeedItems()
	return seedItems
end

function FarmingCatalog.GetRarityDefinition(rarityName)
	if type(rarityName) ~= "string" then
		return nil
	end

	for name, rarityDefinition in pairs(rarityDefinitions) do
		if normalize_key(name) == normalize_key(rarityName) then
			return rarityDefinition
		end
	end

	return nil
end

function FarmingCatalog.RollHarvestRarity(randomGenerator)
	local roll = if randomGenerator then randomGenerator:NextNumber() else rarityRandom:NextNumber()
	local cumulativeChance = 0

	for _, rarityDefinition in ipairs(rarityRollOrder) do
		cumulativeChance += rarityDefinition.Chance
		if roll < cumulativeChance then
			return rarityDefinition.Name
		end
	end

	return nil
end

function FarmingCatalog.GetHarvestItem(cropDefinitionOrId, rarityName)
	local cropDefinition = if type(cropDefinitionOrId) == "table"
		then cropDefinitionOrId
		else FarmingCatalog.GetCrop(cropDefinitionOrId)
	if not cropDefinition then
		return nil
	end

	local rarityDefinition = FarmingCatalog.GetRarityDefinition(rarityName)
	if rarityDefinition then
		return cropDefinition.RareFruits[rarityDefinition.Name] or cropDefinition.Fruit
	end

	return cropDefinition.Fruit
end

return FarmingCatalog
