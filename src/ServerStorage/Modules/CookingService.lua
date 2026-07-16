local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local CookingCatalog = require(GameData:WaitForChild("CookingCatalog"))
local Net = require(Libraries:WaitForChild("Net"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local InventoryService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("InventoryServer"))

local CookingService = {}

local initialized = false

local COOKING_ACTION_FUNCTION_NAME = "CookingAction"
local COOKING_STATE_PATH = "Cooking"

local function build_idle_state()
	return {
		ActiveRecipeId = "",
		StartedAt = 0,
		ReadyAt = 0,
		ResultAmount = 0,
	}
end

local function normalize_key(value): string?
	return CookingCatalog.NormalizeKey(value)
end

local function normalize_cooking_state(rawState)
	local state = build_idle_state()

	if type(rawState) ~= "table" then
		return state
	end

	state.ActiveRecipeId = normalize_key(rawState.ActiveRecipeId) or ""
	state.StartedAt = math.max(0, math.floor(tonumber(rawState.StartedAt) or 0))
	state.ReadyAt = math.max(0, math.floor(tonumber(rawState.ReadyAt) or 0))
	state.ResultAmount = math.max(0, math.floor(tonumber(rawState.ResultAmount) or 0))

	return state
end

local function get_profile_data(player: Player)
	return DataUtility.server.get(player)
end

local function get_cooking_state(player: Player, profileDataOverride)
	local profileData = profileDataOverride or get_profile_data(player)
	local rawState = type(profileData) == "table" and profileData.Cooking or nil
	return normalize_cooking_state(rawState)
end

local function has_active_job(state): boolean
	return type(state.ActiveRecipeId) == "string" and state.ActiveRecipeId ~= ""
end

local function is_job_ready(state, nowTimestamp: number): boolean
	return has_active_job(state) and state.ReadyAt > 0 and state.ReadyAt <= nowTimestamp
end

local function serialize_state(state, nowTimestamp: number)
	local normalizedState = normalize_cooking_state(state)

	return {
		ActiveRecipeId = normalizedState.ActiveRecipeId,
		StartedAt = normalizedState.StartedAt,
		ReadyAt = normalizedState.ReadyAt,
		ResultAmount = normalizedState.ResultAmount,
		IsActive = has_active_job(normalizedState),
		IsReady = is_job_ready(normalizedState, nowTimestamp or os.time()),
	}
end

local function build_response(player: Player, success: boolean, code: string, recipe, stateOverride)
	local state = serialize_state(stateOverride or get_cooking_state(player), os.time())

	return {
		Success = success,
		Code = code,
		RecipeId = recipe and recipe.RecipeId or state.ActiveRecipeId,
		CookingState = state,
	}
end

local function count_ingredient(player: Player, ingredient)
	return InventoryService.GetItemCount(player, ingredient.Definition)
end

local function has_enough_ingredients(player: Player, recipe)
	for _, ingredient in ipairs(recipe.Ingredients) do
		if count_ingredient(player, ingredient) < ingredient.Amount then
			return false
		end
	end

	return true
end

local function consume_ingredients(player: Player, recipe)
	for _, ingredient in ipairs(recipe.Ingredients) do
		local currentCount = InventoryService.GetItemCount(player, ingredient.Definition)
		InventoryService.SetItemCount(player, ingredient.Definition, currentCount - ingredient.Amount)
	end
end

local function write_cooking_state(player: Player, state)
	DataUtility.server.set(player, COOKING_STATE_PATH, normalize_cooking_state(state))
end

function CookingService.GetState(player: Player)
	return serialize_state(get_cooking_state(player), os.time())
end

function CookingService.StartCooking(player: Player, recipeId)
	local recipe = CookingCatalog.GetRecipe(recipeId)
	if not recipe then
		return build_response(player, false, "UnknownRecipe", nil)
	end

	local profileData = get_profile_data(player)
	if not profileData then
		return build_response(player, false, "ProfileUnavailable", recipe)
	end

	local currentState = get_cooking_state(player, profileData)
	if has_active_job(currentState) then
		local activeRecipe = CookingCatalog.GetRecipe(currentState.ActiveRecipeId)
		if not activeRecipe then
			currentState = build_idle_state()
			write_cooking_state(player, currentState)
		else
			return build_response(player, false, "CookingAlreadyActive", activeRecipe or recipe, currentState)
		end
	end

	if not has_enough_ingredients(player, recipe) then
		return build_response(player, false, "MissingIngredients", recipe, currentState)
	end

	local nowTimestamp = os.time()
	local nextState = {
		ActiveRecipeId = recipe.RecipeId,
		StartedAt = nowTimestamp,
		ReadyAt = nowTimestamp + recipe.CookDurationSeconds,
		ResultAmount = recipe.ResultAmount,
	}

	DataUtility.server.begin_batch(player)
	consume_ingredients(player, recipe)
	write_cooking_state(player, nextState)
	DataUtility.server.end_batch(player)

	return build_response(player, true, "CookingStarted", recipe, nextState)
end

function CookingService.CollectCookedFood(player: Player, recipeId)
	local profileData = get_profile_data(player)
	if not profileData then
		return build_response(player, false, "ProfileUnavailable", nil)
	end

	local currentState = get_cooking_state(player, profileData)
	if not has_active_job(currentState) then
		return build_response(player, false, "NoCookingActive", nil, currentState)
	end

	local activeRecipe = CookingCatalog.GetRecipe(currentState.ActiveRecipeId)
	if not activeRecipe then
		local clearedState = build_idle_state()
		write_cooking_state(player, clearedState)
		return build_response(player, false, "InvalidCookingRecipe", nil, clearedState)
	end

	local requestedRecipeId = normalize_key(recipeId)
	if requestedRecipeId and requestedRecipeId ~= activeRecipe.RecipeId then
		return build_response(player, false, "RecipeMismatch", activeRecipe, currentState)
	end

	local nowTimestamp = os.time()
	if not is_job_ready(currentState, nowTimestamp) then
		return build_response(player, false, "CookingNotReady", activeRecipe, currentState)
	end

	local rewardAmount = math.max(1, currentState.ResultAmount > 0 and currentState.ResultAmount or activeRecipe.ResultAmount)
	local clearedState = build_idle_state()

	DataUtility.server.begin_batch(player)
	InventoryService.AddItemCount(player, activeRecipe.FoodDefinition, rewardAmount)
	write_cooking_state(player, clearedState)
	DataUtility.server.end_batch(player)

	return build_response(player, true, "CookingCollected", activeRecipe, clearedState)
end

function CookingService.HandleAction(player: Player, payload)
	local actionName = payload
	local recipeId = nil

	if type(payload) == "table" then
		actionName = payload.Action or payload.Type
		recipeId = payload.RecipeId
	end

	if actionName == "Start" or actionName == "Cook" or actionName == "StartCooking" then
		return CookingService.StartCooking(player, recipeId)
	end

	if actionName == "Collect" or actionName == "Purchase" or actionName == "CollectCookedFood" then
		return CookingService.CollectCookedFood(player, recipeId)
	end

	return build_response(player, false, "UnknownAction", nil)
end

function CookingService.Init()
	if initialized then
		return
	end

	Net.Function[COOKING_ACTION_FUNCTION_NAME]:Respond(function(player, payload)
		return CookingService.HandleAction(player, payload)
	end)

	initialized = true
end

return CookingService