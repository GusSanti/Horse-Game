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

local cropDefinitions = {
	{
		CropId = "Carrot",
		DisplayName = "Carrot",
		StageFolderName = "CarrotStage",
		SortOrder = 10,
		MaxStage = 5,
		Seed = {
			ItemId = "carrot_seed",
			DisplayName = "Carrot Seed",
			ToolName = "SeedCarrot",
			InventoryPath = "Inventory.Seeds",
			Price = 1,
			AssetPath = { "Seeds", "SeedCarrot" },
			ViewportAssetPath = { "Seeds", "SeedCarrot" },
			LegacyToolNames = {
				"Seed",
				"SeedCarrot",
				"Carrot Seed",
				"Carrot Seeds",
			},
		},
		Fruit = {
			ItemId = "carrot_fruit",
			DisplayName = "Carrot",
			ToolName = "Carrot",
			InventoryPath = "Inventory.Fruits",
			SellPrice = 5,
			HarvestYield = 1,
			AssetPath = { "Fruits", "Carrot" },
			ViewportAssetPath = { "Fruits", "Carrot" },
			LegacyInventoryItems = {
				"carrot_bunch",
			},
			LegacyToolNames = {
				"Carrot",
				"Carrot Bunch",
				"Fruit",
			},
		},
	},
	{
		CropId = "Apple",
		DisplayName = "Apple",
		StageFolderName = "AppleStage",
		SortOrder = 20,
		MaxStage = 5,
		Seed = {
			ItemId = "apple_seed",
			DisplayName = "Apple Seed",
			ToolName = "SeedApple",
			InventoryPath = "Inventory.Seeds",
			Price = 2,
			AssetPath = { "Seeds", "SeedApple" },
			ViewportAssetPath = { "Seeds", "SeedApple" },
			LegacyToolNames = {
				"SeedApple",
				"Apple Seed",
				"Apple Seeds",
			},
		},
		Fruit = {
			ItemId = "apple_fruit",
			DisplayName = "Apple",
			ToolName = "Apple",
			InventoryPath = "Inventory.Fruits",
			SellPrice = 8,
			HarvestYield = 1,
			AssetPath = { "Fruits", "Apple" },
			ViewportAssetPath = { "Fruits", "Apple" },
			LegacyToolNames = {
				"Apple",
				"FruitApple",
			},
		},
	},
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
