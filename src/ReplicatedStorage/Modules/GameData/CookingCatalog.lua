local FarmingCatalog = require(script.Parent:WaitForChild("FarmingCatalog"))
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
	return ToolItemCatalog.GetItemDefinition(itemId) or FarmingCatalog.GetItem(itemId)
end

local rawRecipes = {
	{
		RecipeId = "apple_treat",
		FoodItemId = "apple_treat",
		SortOrder = 10,
		CookDurationSeconds = 8,
		ResultAmount = 1,
		Description = "Example crafted treat using crops already available in the farm.",
		Ingredients = {
			{ ItemId = "carrot_fruit", Amount = 2 },
			{ ItemId = "wheat_fruit", Amount = 1 },
			{ ItemId = "grape_fruit", Amount = 1 },
		},
	},
	{
		RecipeId = "beet_pellets",
		FoodItemId = "beet_pellets",
		SortOrder = 20,
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
		SortOrder = 30,
		CookDurationSeconds = 12,
		ResultAmount = 1,
		Description = "Sweet mash recipe made with the current berry-like harvests.",
		Ingredients = {
			{ ItemId = "strawberry_fruit", Amount = 3 },
			{ ItemId = "grape_fruit", Amount = 2 },
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
	return recipesById[normalize_key(recipeId)]
end

function CookingCatalog.GetRecipes()
	return shallow_copy_array(orderedRecipes)
end

function CookingCatalog.GetFoodDefinition(recipeOrId)
	local recipe = recipeOrId

	if type(recipeOrId) ~= "table" then
		recipe = CookingCatalog.GetRecipe(recipeOrId)
	end

	return recipe and recipe.FoodDefinition or nil
end

function CookingCatalog.GetIngredientDefinition(itemId)
	return resolve_item_definition(itemId)
end

return CookingCatalog