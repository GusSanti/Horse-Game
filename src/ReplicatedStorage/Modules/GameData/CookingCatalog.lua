local ToolItemCatalog = require(script.Parent:WaitForChild("ToolItemCatalog"))

local CookingCatalog = {}

local function normalize_key(value): string?
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function normalize_inventory_path(path: string?): string?
	if type(path) ~= "string" then
		return nil
	end

	local trimmedPath = string.gsub(path, "^%s*(.-)%s*$", "%1")
	if trimmedPath == "" then
		return nil
	end

	if string.sub(trimmedPath, 1, #"Inventory.") == "Inventory." then
		return trimmedPath
	end

	return ("Inventory.%s"):format(trimmedPath)
end

local function shallow_copy_array(values)
	local copy = {}

	for index, value in ipairs(values or {}) do
		copy[index] = value
	end

	return copy
end

local function resolve_item_definition(itemId)
	return ToolItemCatalog.GetItemDefinition(itemId)
end

local rawRecipes = {
	{
		RecipeId = "hay_bale",
		FoodItemId = "hay_bale",
		SortOrder = 10,
		CookDurationSeconds = 6,
		ResultAmount = 1,
		Description = "A simple stable staple bundled from fresh wheat.",
		Ingredients = {
			{ ItemId = "wheat_fruit", Amount = 3 },
		},
	},
	{
		RecipeId = "bread",
		FoodItemId = "bread",
		SortOrder = 20,
		CookDurationSeconds = 8,
		ResultAmount = 2,
		Description = "Warm bread baked only from wheat.",
		Ingredients = {
			{ ItemId = "wheat_fruit", Amount = 4 },
		},
	},
	{
		RecipeId = "beet_pellets",
		FoodItemId = "beet_pellets",
		SortOrder = 30,
		CookDurationSeconds = 10,
		ResultAmount = 1,
		Description = "Dense pellets mixed from root crops and grain.",
		Ingredients = {
			{ ItemId = "beetroot_fruit", Amount = 3 },
			{ ItemId = "wheat_fruit", Amount = 2 },
		},
	},
	{
		RecipeId = "berry_mash",
		FoodItemId = "berry_mash",
		SortOrder = 40,
		CookDurationSeconds = 12,
		ResultAmount = 1,
		Description = "Sweet mash made with vineyard fruit and berries.",
		Ingredients = {
			{ ItemId = "strawberry_fruit", Amount = 3 },
			{ ItemId = "grape_fruit", Amount = 2 },
			{ ItemId = "wheat_fruit", Amount = 1 },
		},
	},
	{
		RecipeId = "root_salad",
		FoodItemId = "root_salad",
		SortOrder = 50,
		CookDurationSeconds = 14,
		ResultAmount = 1,
		Description = "A crisp salad using several fresh vegetables from the farm.",
		Ingredients = {
			{ ItemId = "lettuce_fruit", Amount = 2 },
			{ ItemId = "carrot_fruit", Amount = 2 },
			{ ItemId = "beetroot_fruit", Amount = 1 },
			{ ItemId = "radish_fruit", Amount = 1 },
			{ ItemId = "tomato_fruit", Amount = 1 },
		},
	},
	{
		RecipeId = "garden_soup",
		FoodItemId = "garden_soup",
		SortOrder = 60,
		CookDurationSeconds = 16,
		ResultAmount = 1,
		Description = "A warm vegetable soup for steady hunger and health recovery.",
		Ingredients = {
			{ ItemId = "potato_fruit", Amount = 2 },
			{ ItemId = "corn_fruit", Amount = 2 },
			{ ItemId = "tomato_fruit", Amount = 2 },
			{ ItemId = "garlic_fruit", Amount = 1 },
		},
	},
	{
		RecipeId = "stuffed_pumpkin",
		FoodItemId = "stuffed_pumpkin",
		SortOrder = 70,
		CookDurationSeconds = 18,
		ResultAmount = 1,
		Description = "A hearty pumpkin packed with grains and bright vegetables.",
		Ingredients = {
			{ ItemId = "pumpkin_fruit", Amount = 1 },
			{ ItemId = "corn_fruit", Amount = 2 },
			{ ItemId = "pepper_fruit", Amount = 1 },
			{ ItemId = "garlic_fruit", Amount = 1 },
			{ ItemId = "wheat_fruit", Amount = 1 },
		},
	},
	{
		RecipeId = "harvest_skewers",
		FoodItemId = "harvest_skewers",
		SortOrder = 80,
		CookDurationSeconds = 15,
		ResultAmount = 1,
		Description = "Roasted farm vegetables served in quick bite-sized pieces.",
		Ingredients = {
			{ ItemId = "pepper_fruit", Amount = 2 },
			{ ItemId = "corn_fruit", Amount = 1 },
			{ ItemId = "eggplant_fruit", Amount = 1 },
			{ ItemId = "potato_fruit", Amount = 1 },
		},
	},
	{
		RecipeId = "golden_salad",
		FoodItemId = "golden_salad",
		SortOrder = 90,
		CookDurationSeconds = 30,
		ResultAmount = 1,
		Description = "A rare salad that can only be made with Gold harvests.",
		Ingredients = {
			{ ItemId = "carrot_fruit_gold", Amount = 1 },
			{ ItemId = "lettuce_fruit_gold", Amount = 1 },
			{ ItemId = "tomato_fruit_gold", Amount = 1 },
			{ ItemId = "radish_fruit_gold", Amount = 1 },
		},
	},
	{
		RecipeId = "golden_grain_loaf",
		FoodItemId = "golden_grain_loaf",
		SortOrder = 100,
		CookDurationSeconds = 36,
		ResultAmount = 1,
		Description = "A rare loaf baked only from Gold grain and vegetables.",
		Ingredients = {
			{ ItemId = "wheat_fruit_gold", Amount = 3 },
			{ ItemId = "corn_fruit_gold", Amount = 1 },
			{ ItemId = "pumpkin_fruit_gold", Amount = 1 },
		},
	},
	{
		RecipeId = "diamond_root_feast",
		FoodItemId = "diamond_root_feast",
		SortOrder = 110,
		CookDurationSeconds = 50,
		ResultAmount = 1,
		Description = "An extremely rare root feast that requires only Diamond harvests.",
		Ingredients = {
			{ ItemId = "carrot_fruit_diamond", Amount = 1 },
			{ ItemId = "beetroot_fruit_diamond", Amount = 1 },
			{ ItemId = "radish_fruit_diamond", Amount = 1 },
			{ ItemId = "potato_fruit_diamond", Amount = 1 },
		},
	},
	{
		RecipeId = "diamond_champion_bowl",
		FoodItemId = "diamond_champion_bowl",
		SortOrder = 120,
		CookDurationSeconds = 60,
		ResultAmount = 1,
		Description = "The rarest champion meal, crafted entirely from Diamond harvests.",
		Ingredients = {
			{ ItemId = "lettuce_fruit_diamond", Amount = 1 },
			{ ItemId = "tomato_fruit_diamond", Amount = 1 },
			{ ItemId = "pepper_fruit_diamond", Amount = 1 },
			{ ItemId = "garlic_fruit_diamond", Amount = 1 },
			{ ItemId = "wheat_fruit_diamond", Amount = 1 },
		},
	},
}

local orderedRecipes = {}
local recipesById = {}

for _, recipeConfig in ipairs(rawRecipes) do
	local recipeId = normalize_key(recipeConfig.RecipeId or recipeConfig.FoodItemId)
	if recipeId == nil then
		warn("[CookingCatalog] skipped recipe with missing RecipeId/FoodItemId")
		continue
	end

	local foodDefinition = ToolItemCatalog.GetItemDefinition(recipeConfig.FoodItemId)
	if foodDefinition == nil then
		warn(("[CookingCatalog] skipped recipe '%s' because food '%s' was not found"):format(
			recipeId,
			tostring(recipeConfig.FoodItemId)
		))
		continue
	end

	local ingredients = {}
	local hasInvalidIngredient = false

	for _, ingredientConfig in ipairs(recipeConfig.Ingredients or {}) do
		local ingredientDefinition = resolve_item_definition(ingredientConfig.ItemId)
		if ingredientDefinition == nil then
			hasInvalidIngredient = true
			warn(("[CookingCatalog] skipped recipe '%s' because ingredient '%s' was not found"):format(
				recipeId,
				tostring(ingredientConfig.ItemId)
			))
			break
		end

		local ingredientAmount = math.max(1, math.floor(tonumber(ingredientConfig.Amount) or 1))

		ingredients[#ingredients + 1] = {
			ItemId = ingredientDefinition.ItemId,
			DisplayName = ingredientDefinition.DisplayName or ingredientDefinition.ItemId,
			ToolName = ingredientDefinition.ToolName or ingredientDefinition.DisplayName or ingredientDefinition.ItemId,
			Amount = ingredientAmount,
			InventoryPath = normalize_inventory_path(ingredientDefinition.InventoryPath),
			Definition = ingredientDefinition,
		}
	end

	if hasInvalidIngredient then
		continue
	end

	table.sort(ingredients, function(left, right)
		if left.Amount ~= right.Amount then
			return left.Amount > right.Amount
		end

		return left.DisplayName < right.DisplayName
	end)

	local recipe = {
		RecipeId = recipeId,
		DisplayName = foodDefinition.DisplayName or recipeId,
		Description = recipeConfig.Description or foodDefinition.Description or "",
		FoodItemId = foodDefinition.ItemId,
		FoodDefinition = foodDefinition,
		CookDurationSeconds = math.max(1, math.floor(tonumber(recipeConfig.CookDurationSeconds) or 6)),
		ResultAmount = math.max(1, math.floor(tonumber(recipeConfig.ResultAmount) or 1)),
		SortOrder = math.max(0, math.floor(tonumber(recipeConfig.SortOrder) or 0)),
		Ingredients = ingredients,
	}

	orderedRecipes[#orderedRecipes + 1] = recipe
	recipesById[recipeId] = recipe
end

table.sort(orderedRecipes, function(left, right)
	if left.SortOrder ~= right.SortOrder then
		return left.SortOrder < right.SortOrder
	end

	return left.DisplayName < right.DisplayName
end)

function CookingCatalog.NormalizeKey(value): string?
	return normalize_key(value)
end

function CookingCatalog.GetRecipe(recipeId)
	local normalizedRecipeId = normalize_key(recipeId)
	if not normalizedRecipeId then
		return nil
	end

	return recipesById[normalizedRecipeId]
end

function CookingCatalog.GetRecipes()
	return shallow_copy_array(orderedRecipes)
end

return CookingCatalog
