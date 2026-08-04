local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local CookingCatalog = require(GameData:WaitForChild("CookingCatalog"))
local HudAnim = require(Libraries:WaitForChild("HudAnim"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local COOKING_ACTION_REMOTE_NAME = "CookingAction"
local UI_RETRY_SECONDS = 0.5
local UI_WARNING_INTERVAL = 20
local DYNAMIC_REFRESH_SECONDS = 0.1
local IGNORE_HUD_ANIM_ATTRIBUTE = "IgnoreHudAnim"
local INGREDIENT_INTRO_STAGGER_SECONDS = 0.035
local DEBUG_COOKING = false

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainframeFR", "MainFrameFR" }
local FRAMES_NAMES = { "Frames" }
local COOKING_NAMES = { "Cooking" }
local IMAGE_OBJECT_NAMES = { "HorseImage", "FoodImage", "ItemImage", "ImageItem", "ImageLabel", "Icon" }

local INSUFFICIENT_COLOR = Color3.fromRGB(229, 85, 85)
local DEFAULT_TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local RARITY_ICON_IMAGE_BY_KEY = {
	diamond = "rbxassetid://71853979751019",
	gold = "rbxassetid://125720194935690",
}
local RARITY_ICON_COLOR_BY_KEY = {
	diamond = Color3.fromRGB(73, 191, 255),
	gold = Color3.fromRGB(255, 211, 64),
}
local FOOD_STAT_NAME_NAMES = { "StatTX", "StatsTX" }
local FOOD_STAT_AMOUNT_NAMES = { "StatAmountTX" }
local FOOD_STAT_BAR_NAMES = { "BarBG" }
local FOOD_STAT_INSIDE_BAR_NAMES = { "InsideBarBG" }

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()
local ingredientTrove = Trove.new()
local foodStatsTrove = Trove.new()

local currentUi = nil
local cardEntries = {}
local ingredientRows = {}
local foodStatRows = {}
local preloadedImages = {}
local selectedRecipeId = nil
local requestInFlight = false
local dataReady = false
local dataBindingsReady = false
local refreshQueued = false
local retryScheduled = false
local uiSearchAttempts = 0
local dynamicAccumulator = 0
local panelToken = 0
local cardsBuilt = false
local uiWasVisible = false

local try_bind_ui
local ensure_open_ui_loaded
local bind_data_paths

local function normalize_key(value)
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function normalize_inventory_path(path)
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

local function format_count(amount)
	return string.format("%02d", math.max(0, math.floor(tonumber(amount) or 0)))
end

local function matches_name(instance, names)
	local normalizedName = normalize_key(instance and instance.Name)
	if not normalizedName then
		return false
	end

	for _, name in ipairs(names or {}) do
		if normalize_key(name) == normalizedName then
			return true
		end
	end

	return false
end

local function find_child(parent, names, className)
	if not parent then
		return nil
	end

	for _, child in ipairs(parent:GetChildren()) do
		if matches_name(child, names) and (not className or child:IsA(className)) then
			return child
		end
	end

	return nil
end

local function find_descendant(root, names, className)
	if not root then
		return nil
	end

	local direct = find_child(root, names, className)
	if direct then
		return direct
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if matches_name(descendant, names) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function find_path(root, path)
	local current = root

	for _, segment in ipairs(path) do
		if not current then
			return nil
		end

		current = current:FindFirstChild(segment)
	end

	return current
end

local function find_text(root, names)
	local instance = find_descendant(root, names, nil)
	if instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
		return instance
	end

	return nil
end

local function find_gui_object(root, names)
	local instance = find_descendant(root, names, "GuiObject")
	if instance and instance:IsA("GuiObject") then
		return instance
	end

	return nil
end

local function is_image_object(instance)
	return instance and (instance:IsA("ImageLabel") or instance:IsA("ImageButton"))
end

local function is_rarity_icon(instance)
	local key = normalize_key(instance and instance.Name)
	return key == "rarity" or key == "rarityicon" or key == "rarityimage"
end

local function find_image_object(root, preferredPaths)
	if not root then
		return nil
	end

	for _, path in ipairs(preferredPaths or {}) do
		local instance = find_path(root, path)
		if is_image_object(instance) then
			return instance
		end
	end

	if is_image_object(root) and not is_rarity_icon(root) then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if is_image_object(descendant)
			and matches_name(descendant, IMAGE_OBJECT_NAMES)
			and not is_rarity_icon(descendant)
		then
			return descendant
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ImageLabel") and not is_rarity_icon(descendant) then
			return descendant
		end
	end

	return nil
end

local function set_text(instance, text)
	if instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
		instance.Text = text
	end
end

local function set_text_color(instance, color)
	if instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
		instance.TextColor3 = color
	end
end

local function get_text_color(instance)
	if instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
		return instance.TextColor3
	end

	return DEFAULT_TEXT_COLOR
end

local function set_button_enabled(button, enabled)
	if not button then
		return
	end

	button.Active = enabled
	button.Selectable = enabled
	button.AutoButtonColor = enabled
end

local function disable_hud_anim(instance)
	if instance then
		instance:SetAttribute(IGNORE_HUD_ANIM_ATTRIBUTE, true)

		if instance:IsA("GuiObject") then
			instance:SetAttribute("UIAnim", false)
			instance:SetAttribute("UIOpen", false)
			instance:SetAttribute("hover_scale", 0)
			instance:SetAttribute("click_scale", 0)
			instance:SetAttribute("rotate_hover_deg", 0)
			instance:SetAttribute("pulse", false)
		end
	end
end

local function allow_hud_anim(instance)
	if instance then
		instance:SetAttribute(IGNORE_HUD_ANIM_ATTRIBUTE, nil)
	end
end

local function bind_open_hud_anim(root)
	if not root then
		return
	end

	allow_hud_anim(root)
	root:SetAttribute("UIOpen", true)

	pcall(function()
		if root:IsA("GuiObject") then
			HudAnim.bind(root)
		end

		HudAnim.apply_defaults_to_buttons(root)
		HudAnim.bind_all(root)
	end)
end

local function disable_hud_anim_tree(root)
	if not root then
		return
	end

	disable_hud_anim(root)

	for _, descendant in ipairs(root:GetDescendants()) do
		disable_hud_anim(descendant)
	end

	pcall(function()
		if root:IsA("GuiObject") then
			HudAnim.unbind(root)
		end

		HudAnim.unbind_all(root)
	end)
end

local function is_ui_visible(instance)
	if not instance then
		return false
	end

	local current = instance

	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end

		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end

		current = current.Parent
	end

	return true
end

local function get_debug_path(instance)
	if not instance then
		return "nil"
	end

	local ok, fullName = pcall(function()
		return instance:GetFullName()
	end)

	return if ok then fullName else instance.Name
end

local function debug_print(eventName, ...)
	if not DEBUG_COOKING then
		return
	end

	local parts = {}
	for index = 1, select("#", ...) do
		local value = select(index, ...)
		parts[#parts + 1] = tostring(value)
	end

	print(("[CookingDebug %.3f] %s %s"):format(os.clock(), eventName, table.concat(parts, " ")))
end

local function strip_scripts(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function disable_viewport_previews(root)
	if not root then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ViewportFrame") then
			descendant.Visible = false
			descendant.CurrentCamera = nil

			for _, child in ipairs(descendant:GetChildren()) do
				if child:IsA("WorldModel") or child:IsA("Camera") then
					child:Destroy()
				end
			end
		end
	end
end

local function create_template_source(template)
	local source = template:Clone()
	source.Visible = true
	source.Parent = nil
	strip_scripts(source)
	disable_viewport_previews(source)
	template.Visible = false
	disable_viewport_previews(template)
	return source
end

local function ensure_template_sources(ui)
	if not ui or not ui.CardTemplate or not ui.IngredientTemplate then
		return false
	end

	if not ui.CardTemplateSource then
		ui.CardTemplateSource = create_template_source(ui.CardTemplate)
		uiTrove:Add(ui.CardTemplateSource)
	end

	if not ui.IngredientTemplateSource then
		ui.IngredientTemplateSource = create_template_source(ui.IngredientTemplate)
		uiTrove:Add(ui.IngredientTemplateSource)
	end

	return true
end

local function normalize_image_id(value)
	if type(value) == "number" then
		return "rbxassetid://" .. tostring(math.floor(value))
	end

	if type(value) ~= "string" then
		return ""
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	if trimmedValue == "" then
		return ""
	end

	if string.find(trimmedValue, "://", 1, true) then
		return trimmedValue
	end

	if tonumber(trimmedValue) then
		return "rbxassetid://" .. trimmedValue
	end

	return trimmedValue
end

local function get_definition_image(definition)
	if type(definition) ~= "table" then
		return ""
	end

	return normalize_image_id(definition.IdImage or definition.ImageId or definition.IconImage)
end

local function preload_image(imageId)
	if imageId == "" or preloadedImages[imageId] then
		return
	end

	preloadedImages[imageId] = true
	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ imageId })
		end)
	end)
end

local function set_item_image(imageObject, definition)
	if not is_image_object(imageObject) then
		return
	end

	local imageId = get_definition_image(definition)
	imageObject.Image = imageId
	imageObject.ImageTransparency = imageId == "" and 1 or 0
	imageObject.Visible = true
	imageObject.ScaleType = Enum.ScaleType.Fit
	preload_image(imageId)
	disable_viewport_previews(imageObject)
end

local function round_number(value)
	if type(value) ~= "number" then
		return 0
	end

	return math.floor(value + 0.5)
end

local function format_seconds(seconds)
	local value = math.max(0, math.floor(tonumber(seconds) or 0))
	return ("%ds"):format(value)
end

local function format_signed_percent(value)
	local rounded = round_number(value)
	if rounded >= 0 then
		return ("+%d%%"):format(rounded)
	end

	return ("%d%%"):format(rounded)
end

local function format_unsigned_percent(value)
	return ("%d%%"):format(math.max(0, round_number(value)))
end

local function get_tagged_rarity(definition)
	for _, tag in ipairs(type(definition and definition.Tags) == "table" and definition.Tags or {}) do
		local tagKey = normalize_key(tag)
		if tagKey == "diamond" then
			return "Diamond"
		elseif tagKey == "gold" then
			return "Gold"
		end
	end

	return nil
end

local function get_food_rarity(recipe)
	local foodDefinition = recipe and recipe.FoodDefinition
	local explicitRarity = normalize_key(foodDefinition and foodDefinition.Rarity)
	if explicitRarity == "diamond" then
		return "Diamond"
	elseif explicitRarity == "gold" then
		return "Gold"
	end

	local taggedRarity = get_tagged_rarity(foodDefinition)
	if taggedRarity then
		return taggedRarity
	end

	local detectedRarity = nil
	for _, ingredient in ipairs(recipe and recipe.Ingredients or {}) do
		local definition = ingredient.Definition
		local rarityKey = normalize_key(definition and definition.Rarity)
		local itemId = normalize_key(ingredient.ItemId or definition and definition.ItemId)

		if rarityKey == "diamond" or (itemId and string.find(itemId, "_diamond", 1, true)) then
			return "Diamond"
		elseif rarityKey == "gold" or (itemId and string.find(itemId, "_gold", 1, true)) then
			detectedRarity = "Gold"
		end
	end

	local recipeId = normalize_key(recipe and recipe.RecipeId)
	local foodItemId = normalize_key(recipe and recipe.FoodItemId)
	if (recipeId and string.find(recipeId, "diamond", 1, true))
		or (foodItemId and string.find(foodItemId, "diamond", 1, true))
	then
		return "Diamond"
	end

	if (recipeId and string.find(recipeId, "gold", 1, true))
		or (foodItemId and string.find(foodItemId, "gold", 1, true))
	then
		return "Gold"
	end

	return detectedRarity
end

local function set_rarity_icon(icon, rarity)
	if not icon or not icon:IsA("GuiObject") then
		return
	end

	local rarityKey = normalize_key(rarity)
	local image = rarityKey and RARITY_ICON_IMAGE_BY_KEY[rarityKey] or nil
	icon.Visible = image ~= nil

	if icon:IsA("ImageLabel") or icon:IsA("ImageButton") then
		icon.Image = image or ""
		icon.ImageColor3 = (rarityKey and RARITY_ICON_COLOR_BY_KEY[rarityKey]) or Color3.fromRGB(255, 255, 255)
	end
end

local function build_ingredient_summary(recipe)
	local pieces = {}

	for _, ingredient in ipairs(recipe and recipe.Ingredients or {}) do
		pieces[#pieces + 1] = ("%s x%d"):format(
			ingredient.DisplayName or ingredient.ToolName or ingredient.ItemId,
			math.max(1, math.floor(tonumber(ingredient.Amount) or 1))
		)
	end

	return table.concat(pieces, ", ")
end

local function build_food_details_text(recipe)
	if not recipe then
		return ""
	end

	local foodDefinition = recipe.FoodDefinition or {}
	local lines = {}
	local description = recipe.Description or foodDefinition.Description
	local effects = foodDefinition.Effects or {}
	local rarity = get_food_rarity(recipe)
	local ingredients = build_ingredient_summary(recipe)

	if type(description) == "string" and description ~= "" then
		lines[#lines + 1] = description
	end

	lines[#lines + 1] = ("Cook time: %s | Result: x%d"):format(
		format_seconds(recipe.CookDurationSeconds),
		math.max(1, math.floor(tonumber(recipe.ResultAmount) or 1))
	)

	if rarity then
		lines[#lines + 1] = ("Rarity: %s"):format(rarity)
	end

	local passiveDetails = {}
	local decayBuff = effects.DecayBuff
	if type(decayBuff) == "table" then
		local multiplier = tonumber(decayBuff.Multiplier)
		local duration = tonumber(decayBuff.DurationMinutes)
		if multiplier and multiplier < 1 then
			local reduction = math.max(0, (1 - multiplier) * 100)
			local suffix = duration and duration > 0 and (" for %d min"):format(math.floor(duration + 0.5)) or ""
			passiveDetails[#passiveDetails + 1] = ("Hunger decay -%s%s"):format(format_unsigned_percent(reduction), suffix)
		end
	end

	local healthRegen = effects.HealthRegen
	if type(healthRegen) == "table" and tonumber(healthRegen.TotalGain) then
		local totalGain = tonumber(healthRegen.TotalGain) or 0
		local duration = tonumber(healthRegen.DurationMinutes)
		if totalGain > 0 then
			local suffix = duration and duration > 0 and (" over %d min"):format(math.floor(duration + 0.5)) or ""
			passiveDetails[#passiveDetails + 1] = ("Health regen +%s%s"):format(format_unsigned_percent(totalGain), suffix)
		end
	end

	if #passiveDetails > 0 then
		lines[#lines + 1] = "Passives: " .. table.concat(passiveDetails, ", ")
	end

	if ingredients ~= "" then
		lines[#lines + 1] = "Ingredients: " .. ingredients
	end

	return table.concat(lines, "\n")
end

local function add_food_stat(descriptors, key, label, percentValue, alphaOverride, amountTextOverride)
	local numericPercent = tonumber(percentValue)
	if not numericPercent or math.abs(numericPercent) < 0.001 then
		return
	end

	descriptors[#descriptors + 1] = {
		Key = key,
		Label = label,
		AmountText = amountTextOverride or format_signed_percent(numericPercent),
		Alpha = math.clamp(alphaOverride or (math.abs(numericPercent) / 100), 0, 1),
	}
end

local function build_food_stat_descriptors(recipe)
	local definition = recipe and recipe.FoodDefinition
	local effects = definition and definition.Effects or {}
	local descriptors = {}
	local needKey = definition and definition.NeedKey or "Hunger"

	add_food_stat(descriptors, needKey, needKey, effects.NeedGain)
	add_food_stat(descriptors, "Happiness", "Happiness", effects.HappinessGain)
	add_food_stat(descriptors, "Health", "Health", effects.HealthGain)
	add_food_stat(descriptors, "Friendship", "Friendship", effects.FriendshipGain)

	local secondaryNeedOrder = { "Thirst", "Cleanliness", "Hunger", "Happiness", "Health" }
	local alreadyShown = {
		[needKey] = effects.NeedGain ~= nil,
		Happiness = effects.HappinessGain ~= nil,
		Health = effects.HealthGain ~= nil,
	}

	if type(effects.SecondaryNeedAdjustments) == "table" then
		for _, secondaryNeed in ipairs(secondaryNeedOrder) do
			if not alreadyShown[secondaryNeed] then
				add_food_stat(descriptors, secondaryNeed, secondaryNeed, effects.SecondaryNeedAdjustments[secondaryNeed])
			end
		end
	end

	local healthRegen = effects.HealthRegen
	if type(healthRegen) == "table" then
		add_food_stat(descriptors, "HealthRegen", "Health Regen", healthRegen.TotalGain)
	end

	local decayBuff = effects.DecayBuff
	if type(decayBuff) == "table" then
		local multiplier = tonumber(decayBuff.Multiplier)
		if multiplier and multiplier < 1 then
			local reduction = math.max(0, (1 - multiplier) * 100)
			add_food_stat(descriptors, "HungerDecay", "Hunger Decay", reduction, reduction / 100, "-" .. format_unsigned_percent(reduction))
		end
	end

	return descriptors
end

local ensure_food_stat_row

local function update_food_stats(ui, recipe)
	if not ui or not ui.FoodStatsContainer or not ui.FoodStatTemplate then
		return
	end

	local descriptors = build_food_stat_descriptors(recipe)
	ui.FoodStatTemplate.Visible = false
	ui.FoodStatsContainer.Visible = #descriptors > 0

	for index, descriptor in ipairs(descriptors) do
		local rowRecord = ensure_food_stat_row(ui, index)
		if not rowRecord then
			continue
		end

		local row = rowRecord.Row
		row.Name = descriptor.Key
		row.Visible = true
		row.LayoutOrder = index

		set_text(rowRecord.NameLabel, descriptor.Label)
		set_text(rowRecord.AmountLabel, descriptor.AmountText)

		if rowRecord.BarFill then
			local currentSize = rowRecord.BarFill.Size
			rowRecord.BarFill.Size = UDim2.new(
				math.clamp(descriptor.Alpha, 0, 1),
				0,
				currentSize.Y.Scale,
				currentSize.Y.Offset
			)
		end
	end

	for index = #descriptors + 1, #foodStatRows do
		foodStatRows[index].Row.Visible = false
	end
end

ensure_food_stat_row = function(ui, index)
	if not ui or not ui.FoodStatsContainer or not ui.FoodStatTemplate then
		return nil
	end

	local rowRecord = foodStatRows[index]
	if rowRecord then
		return rowRecord
	end

	local row = ui.FoodStatTemplate:Clone()
	disable_hud_anim_tree(row)
	row.Visible = false
	row.LayoutOrder = index
	row.Parent = ui.FoodStatsContainer
	foodStatsTrove:Add(row)

	rowRecord = {
		Row = row,
		NameLabel = find_text(row, FOOD_STAT_NAME_NAMES),
		AmountLabel = find_text(row, FOOD_STAT_AMOUNT_NAMES),
	}

	local barBackground = find_gui_object(row, FOOD_STAT_BAR_NAMES)
	rowRecord.BarFill = find_gui_object(barBackground, FOOD_STAT_INSIDE_BAR_NAMES)
		or find_gui_object(row, FOOD_STAT_INSIDE_BAR_NAMES)
	foodStatRows[index] = rowRecord

	return rowRecord
end

local function refresh_food_template_panel(recipe)
	local ui = currentUi
	if not ui or not ui.FoodTemplate then
		return
	end

	if not recipe then
		ui.FoodTemplate.Visible = false
		set_text(ui.FoodTemplateNameLabel, "")
		set_text(ui.FoodTemplateDetailsLabel, "")
		set_item_image(ui.FoodTemplateImage, nil)
		set_rarity_icon(ui.FoodTemplateRarityIcon, nil)
		for _, rowRecord in ipairs(foodStatRows) do
			rowRecord.Row.Visible = false
		end
		return
	end

	ui.FoodTemplate.Visible = true
	set_text(ui.FoodTemplateNameLabel, recipe.DisplayName)
	set_text(ui.FoodTemplateDetailsLabel, build_food_details_text(recipe))
	set_item_image(ui.FoodTemplateImage, recipe.FoodDefinition)
	set_rarity_icon(ui.FoodTemplateRarityIcon, get_food_rarity(recipe))
	update_food_stats(ui, recipe)
end

local function get_cooking_remote()
	local net = ReplicatedStorage:FindFirstChild("Net")
	local functions = net and net:FindFirstChild("Functions")
	local remote = functions and functions:FindFirstChild(COOKING_ACTION_REMOTE_NAME)

	if remote and remote:IsA("RemoteFunction") then
		return remote
	end

	return nil
end

local function get_client_data(path)
	if not dataReady then
		return nil
	end

	local ok, value = pcall(function()
		return DataUtility.client.get(path)
	end)

	if ok then
		return value
	end

	return nil
end

local function get_definition_count(definition)
	local inventoryPath = normalize_inventory_path(definition and definition.InventoryPath)
	if not inventoryPath then
		return 0
	end

	local bucket = get_client_data(inventoryPath)
	if type(bucket) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(bucket[definition.ItemId]) or 0))
end

local function get_cooking_state()
	local rawState = get_client_data("Cooking")

	if type(rawState) ~= "table" then
		return {
			ActiveRecipeId = "",
			StartedAt = 0,
			ReadyAt = 0,
			ResultAmount = 0,
		}
	end

	return {
		ActiveRecipeId = normalize_key(rawState.ActiveRecipeId) or "",
		StartedAt = math.max(0, math.floor(tonumber(rawState.StartedAt) or 0)),
		ReadyAt = math.max(0, math.floor(tonumber(rawState.ReadyAt) or 0)),
		ResultAmount = math.max(0, math.floor(tonumber(rawState.ResultAmount) or 0)),
	}
end

local function has_active_job(state)
	return type(state.ActiveRecipeId) == "string" and state.ActiveRecipeId ~= ""
end

local function is_job_ready(state)
	return has_active_job(state) and state.ReadyAt > 0 and state.ReadyAt <= os.time()
end

local function get_progress_alpha(state)
	if not has_active_job(state) then
		return 0
	end

	local duration = math.max(1, state.ReadyAt - state.StartedAt)
	local elapsed = math.clamp(os.time() - state.StartedAt, 0, duration)
	return math.clamp(elapsed / duration, 0, 1)
end

local function get_selected_recipe()
	if not selectedRecipeId then
		return nil
	end

	return CookingCatalog.GetRecipe(selectedRecipeId)
end

local function get_active_recipe(state)
	if not has_active_job(state) then
		return nil
	end

	return CookingCatalog.GetRecipe(state.ActiveRecipeId)
end

local function has_recipe_ingredients(recipe)
	if not dataReady or not recipe then
		return false
	end

	for _, ingredient in ipairs(recipe.Ingredients) do
		if get_definition_count(ingredient.Definition) < ingredient.Amount then
			return false
		end
	end

	return true
end

local function sync_selected_recipe()
	local recipes = CookingCatalog.GetRecipes()
	local state = get_cooking_state()
	local activeRecipe = get_active_recipe(state)

	if activeRecipe then
		selectedRecipeId = activeRecipe.RecipeId
		return
	end

	if selectedRecipeId and CookingCatalog.GetRecipe(selectedRecipeId) then
		return
	end

	selectedRecipeId = recipes[1] and recipes[1].RecipeId or nil
end

local function update_canvas_size(scrollingFrame)
	if not scrollingFrame then
		return
	end

	local layout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
		or scrollingFrame:FindFirstChildWhichIsA("UIListLayout", true)

	if layout then
		scrollingFrame.CanvasSize = UDim2.fromOffset(
			math.max(0, layout.AbsoluteContentSize.X),
			math.max(0, layout.AbsoluteContentSize.Y)
		)
	end
end

local function set_selected_visual(card, selected)
	if card then
		card:SetAttribute("CookingSelected", selected == true)
	end
end

local function get_action_mode()
	local state = get_cooking_state()
	local selectedRecipe = get_selected_recipe()
	local activeRecipe = get_active_recipe(state)

	if not selectedRecipe then
		return nil, state, selectedRecipe, activeRecipe
	end

	if activeRecipe and selectedRecipe.RecipeId == activeRecipe.RecipeId then
		return is_job_ready(state) and "Purchase" or "Cooking", state, selectedRecipe, activeRecipe
	end

	if activeRecipe then
		return nil, state, selectedRecipe, activeRecipe
	end

	if has_recipe_ingredients(selectedRecipe) then
		return "Cook", state, selectedRecipe, activeRecipe
	end

	return nil, state, selectedRecipe, activeRecipe
end

local function refresh_dynamic_ui()
	if not currentUi or not currentUi.Root or not currentUi.Root.Parent then
		return
	end

	if not is_ui_visible(currentUi.Root) then
		return
	end

	local actionMode, state = get_action_mode()
	local progress = 0
	if actionMode == "Cooking" or actionMode == "Purchase" then
		progress = get_progress_alpha(state)
	end

	if currentUi.BarFill then
		currentUi.BarFill.Size = UDim2.new(
			progress,
			0,
			currentUi.BarFillBaseSize.Y.Scale,
			currentUi.BarFillBaseSize.Y.Offset
		)
	end

	if currentUi.CookingLabel then
		if actionMode == "Cooking" then
			local dots = (math.floor(os.clock() * 2.5) % 3) + 1
			set_text(currentUi.CookingLabel, "Cooking" .. string.rep(".", dots))
		elseif actionMode == "Purchase" then
			set_text(currentUi.CookingLabel, "Ready")
		else
			set_text(currentUi.CookingLabel, "")
		end
	end

	if currentUi.CookButton then
		currentUi.CookButton.Visible = actionMode == "Cook" or actionMode == "Cooking" or actionMode == "Purchase" or requestInFlight
		set_button_enabled(
			currentUi.CookButton,
			not requestInFlight and get_cooking_remote() ~= nil and (actionMode == "Cook" or actionMode == "Purchase")
		)
	end

	if currentUi.CookButtonText then
		if requestInFlight or actionMode == "Cooking" then
			set_text(currentUi.CookButtonText, "Cooking")
		elseif actionMode == "Purchase" then
			set_text(currentUi.CookButtonText, "Purchase")
		else
			set_text(currentUi.CookButtonText, "Cook")
		end
	end
end

local function refresh_recipe_cards()
	if not currentUi then
		return
	end

	local state = get_cooking_state()
	local activeRecipe = get_active_recipe(state)
	local activeRecipeId = activeRecipe and activeRecipe.RecipeId or nil

	for _, entry in ipairs(cardEntries) do
		local isSelected = selectedRecipeId == entry.Recipe.RecipeId
		local canSelect = not requestInFlight and (not activeRecipeId or activeRecipeId == entry.Recipe.RecipeId)
		local foodCount = get_definition_count(entry.Recipe.FoodDefinition)

		set_selected_visual(entry.Card, isSelected)
		set_button_enabled(entry.Button, canSelect)
		set_text(entry.StockLabel, format_count(foodCount))

		if activeRecipeId == entry.Recipe.RecipeId then
			set_text(entry.ButtonText, is_job_ready(state) and "Ready" or "Cooking")
		elseif isSelected then
			set_text(entry.ButtonText, "Selected")
		else
			set_text(entry.ButtonText, "Select")
		end
	end
end

local function refresh_ingredient_counts()
	if not currentUi or not currentUi.IngredientEntries then
		return
	end

	for _, entry in ipairs(currentUi.IngredientEntries) do
		local owned = get_definition_count(entry.Ingredient.Definition)
		local hasEnough = owned >= entry.Ingredient.Amount

		set_text(entry.StockLabel, ("%s/%s"):format(format_count(owned), format_count(entry.Ingredient.Amount)))
		set_text_color(entry.StockLabel, hasEnough and currentUi.DefaultIngredientTextColor or INSUFFICIENT_COLOR)
	end
end

local function ensure_ingredient_row(ui, index)
	if not ui or not ui.IngredientTemplateSource or not ui.IngredientContainer then
		return nil
	end

	local rowRecord = ingredientRows[index]
	if rowRecord then
		return rowRecord
	end

	local row = ui.IngredientTemplateSource:Clone()
	disable_hud_anim_tree(row)
	disable_viewport_previews(row)
	row.Visible = false
	row.LayoutOrder = index
	row.Parent = ui.IngredientContainer
	ingredientTrove:Add(row)

	rowRecord = {
		Row = row,
		NameLabel = find_text(row, { "IngredientName", "ItemNameTX", "ItemName" }),
		StockLabel = find_text(row, { "StockCountTX", "StockCount" }),
		Image = find_image_object(row, { { "HorseImage" }, { "ItemImage" }, { "ImageLabel" } }),
	}
	ingredientRows[index] = rowRecord

	return rowRecord
end

local function hide_ingredient_row(rowRecord)
	if rowRecord and rowRecord.Row then
		rowRecord.Row.Visible = false
	end
end

local function play_ingredient_intro(rowRecord, index, token, ui)
	if not rowRecord or not rowRecord.Row then
		return
	end

	local row = rowRecord.Row
	row.Visible = false

	task.delay((index - 1) * INGREDIENT_INTRO_STAGGER_SECONDS, function()
		if token ~= panelToken or currentUi ~= ui or not ui.Root or not is_ui_visible(ui.Root) then
			return
		end

		row.Visible = true
	end)
end

local function prewarm_dynamic_rows(ui)
	if not ui or not ensure_template_sources(ui) then
		return
	end

	local maxIngredientRows = 0
	local maxFoodStatRows = 0
	for _, recipe in ipairs(CookingCatalog.GetRecipes()) do
		maxIngredientRows = math.max(maxIngredientRows, #recipe.Ingredients)
		maxFoodStatRows = math.max(maxFoodStatRows, #build_food_stat_descriptors(recipe))
	end

	for index = 1, maxIngredientRows do
		local rowRecord = ensure_ingredient_row(ui, index)
		if rowRecord then
			rowRecord.Row.Visible = false
		end
	end

	for index = 1, maxFoodStatRows do
		local rowRecord = ensure_food_stat_row(ui, index)
		if rowRecord then
			rowRecord.Row.Visible = false
		end
	end

	ui.IngredientEntries = {}
end

local function render_ingredients(recipe, token)
	if not currentUi or not currentUi.IngredientContainer then
		return
	end

	local ui = currentUi
	if token ~= panelToken or not is_ui_visible(ui.Root) or not ensure_template_sources(ui) then
		return
	end

	local activeEntries = {}

	for index, ingredient in ipairs(recipe.Ingredients) do
		local rowRecord = ensure_ingredient_row(ui, index)
		if not rowRecord then
			continue
		end

		local owned = get_definition_count(ingredient.Definition)
		local hasEnough = owned >= ingredient.Amount

		rowRecord.Row.Name = ingredient.ItemId or ("Ingredient%d"):format(index)
		rowRecord.Row.LayoutOrder = index
		set_text(rowRecord.NameLabel, ingredient.DisplayName or ingredient.ToolName or ingredient.ItemId)
		set_text(rowRecord.StockLabel, ("%s/%s"):format(format_count(owned), format_count(ingredient.Amount)))
		set_text_color(rowRecord.StockLabel, hasEnough and ui.DefaultIngredientTextColor or INSUFFICIENT_COLOR)
		set_item_image(rowRecord.Image, ingredient.Definition)

		activeEntries[#activeEntries + 1] = {
			Ingredient = ingredient,
			StockLabel = rowRecord.StockLabel,
		}

		play_ingredient_intro(rowRecord, index, token, ui)
	end

	for index = #recipe.Ingredients + 1, #ingredientRows do
		hide_ingredient_row(ingredientRows[index])
	end

	ui.IngredientEntries = activeEntries
end

local function refresh_selected_panel()
	if not currentUi then
		return
	end

	sync_selected_recipe()

	local recipe = get_selected_recipe()
	panelToken += 1
	local token = panelToken

	if not recipe then
		set_text(currentUi.FoodNameLabel, "")
		set_item_image(currentUi.FoodImage, nil)
		set_rarity_icon(currentUi.FoodRarityIcon, nil)
		refresh_food_template_panel(nil)
		for _, rowRecord in ipairs(ingredientRows) do
			hide_ingredient_row(rowRecord)
		end
		currentUi.IngredientEntries = {}
		refresh_dynamic_ui()
		return
	end

	set_text(currentUi.FoodNameLabel, recipe.DisplayName)
	set_item_image(currentUi.FoodImage, recipe.FoodDefinition)
	set_rarity_icon(currentUi.FoodRarityIcon, get_food_rarity(recipe))
	refresh_food_template_panel(recipe)
	render_ingredients(recipe, token)
	refresh_dynamic_ui()
end

local function refresh_all()
	if not currentUi then
		return
	end

	if not is_ui_visible(currentUi.Root) or not cardsBuilt then
		return
	end

	sync_selected_recipe()
	refresh_recipe_cards()
	refresh_selected_panel()
	update_canvas_size(currentUi.ListScrollingFrame)
end

local function queue_refresh_all()
	if refreshQueued then
		return
	end

	refreshQueued = true

	task.defer(function()
		refreshQueued = false
		refresh_all()
	end)
end

local function select_recipe(recipeId)
	local recipe = CookingCatalog.GetRecipe(recipeId)
	if not recipe then
		return
	end

	if selectedRecipeId == recipe.RecipeId then
		return
	end

	local state = get_cooking_state()
	local activeRecipe = get_active_recipe(state)
	if activeRecipe and activeRecipe.RecipeId ~= recipe.RecipeId then
		debug_print("select_recipe_blocked_active_job", "requested=" .. tostring(recipe.RecipeId), "active=" .. tostring(activeRecipe.RecipeId))
		return
	end

	selectedRecipeId = recipe.RecipeId
	refresh_all()
end

local function build_recipe_cards()
	if not currentUi or cardsBuilt then
		return
	end

	local ui = currentUi
	if not ensure_template_sources(ui) then
		return
	end

	cardTrove:Clean()
	table.clear(cardEntries)
	ui.CardTemplate.Visible = false

	for index, recipe in ipairs(CookingCatalog.GetRecipes()) do
		local card = ui.CardTemplateSource:Clone()
		card.Name = recipe.RecipeId
		card.Visible = true
		card.LayoutOrder = index
		card.Parent = ui.ListScrollingFrame
		disable_hud_anim_tree(card)
		disable_viewport_previews(card)
		cardTrove:Add(card)

		local button = find_descendant(card, { "PurchaseBT" }, "GuiButton")
		local buttonText = button and find_text(button, { "BTTX" }) or nil
		local nameLabel = find_text(card, { "ItemNameTX", "ItemName" })
		local stockLabel = find_text(card, { "StockCountTX", "StockCount" })
		local image = find_image_object(card, { { "ImageLabel" }, { "HorseImage" }, { "ItemImage" } })
		local rarityIcon = find_descendant(card, { "rarity", "Rarity" }, "ImageLabel")
			or find_descendant(card, { "rarity", "Rarity" }, "ImageButton")
			or find_gui_object(card, { "rarity", "Rarity" })

		set_text(nameLabel, recipe.DisplayName)
		set_text(buttonText, "Select")
		set_text(stockLabel, format_count(get_definition_count(recipe.FoodDefinition)))
		set_item_image(image, recipe.FoodDefinition)
		set_rarity_icon(rarityIcon, get_food_rarity(recipe))

		cardEntries[#cardEntries + 1] = {
			Recipe = recipe,
			Card = card,
			Button = button,
			ButtonText = buttonText,
			StockLabel = stockLabel,
		}

		if button then
			cardTrove:Connect(button.Activated, function()
				select_recipe(recipe.RecipeId)
			end)
		end
	end

	cardsBuilt = true
	update_canvas_size(ui.ListScrollingFrame)
	refresh_recipe_cards()
end

ensure_open_ui_loaded = function()
	if not currentUi then
		return
	end

	if not is_ui_visible(currentUi.Root) then
		return
	end

	bind_data_paths()
	sync_selected_recipe()
	build_recipe_cards()
	refresh_all()
end

local function submit_action(actionName)
	local recipe = get_selected_recipe()
	local remote = get_cooking_remote()

	if not recipe or not remote or requestInFlight then
		refresh_dynamic_ui()
		return
	end

	requestInFlight = true
	refresh_dynamic_ui()
	refresh_recipe_cards()

	task.spawn(function()
		local ok, response = pcall(function()
			return remote:InvokeServer({
				Action = actionName,
				RecipeId = recipe.RecipeId,
			})
		end)

		requestInFlight = false

		if not ok then
			warn("[Cooking] failed to send cooking action: " .. tostring(response))
		elseif type(response) == "table" and response.Success == false then
			warn("[Cooking] cooking action rejected: " .. tostring(response.Code))
		end

		queue_refresh_all()
	end)
end

bind_data_paths = function()
	if not currentUi or dataBindingsReady or not dataReady then
		return
	end

	local paths = { "Cooking" }
	local seen = { Cooking = true }

	local function add_path(path)
		local normalizedPath = normalize_inventory_path(path)
		if normalizedPath and not seen[normalizedPath] then
			seen[normalizedPath] = true
			paths[#paths + 1] = normalizedPath
		end
	end

	for _, recipe in ipairs(CookingCatalog.GetRecipes()) do
		add_path(recipe.FoodDefinition and recipe.FoodDefinition.InventoryPath)

		for _, ingredient in ipairs(recipe.Ingredients) do
			add_path(ingredient.InventoryPath)
		end
	end

	for _, path in ipairs(paths) do
		local ok, connection = pcall(function()
			return DataUtility.client.bind(path, queue_refresh_all)
		end)

		if ok and connection then
			uiTrove:Add(connection)
		elseif not ok then
			warn("[Cooking] failed to bind data path " .. tostring(path) .. ": " .. tostring(connection))
		end
	end

	dataBindingsReady = true
end

local function reset_runtime_state()
	panelToken += 1
	requestInFlight = false
end

local function destroy_ui_binding()
	reset_runtime_state()
	cardTrove:Clean()
	ingredientTrove:Clean()
	foodStatsTrove:Clean()
	table.clear(cardEntries)
	table.clear(ingredientRows)
	table.clear(foodStatRows)
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = nil
	dataBindingsReady = false
	cardsBuilt = false
	uiWasVisible = false
end

local function get_cooking_ui(root)
	local mainLeft = root:FindFirstChild("MainLeft")
	local ingredientContainer = mainLeft and mainLeft:FindFirstChild("Frame")
	local ingredientTemplate = ingredientContainer and ingredientContainer:FindFirstChild("Ingredient")
	local foodRoot = mainLeft and mainLeft:FindFirstChild("Food")
	local listScrollingFrame = root:FindFirstChild("ListScrollingFrame")
	local cardTemplate = listScrollingFrame and listScrollingFrame:FindFirstChild("TemplateCraft")
	local cookButton = mainLeft and mainLeft:FindFirstChild("CookBT")
	local barBackground = mainLeft and mainLeft:FindFirstChild("BarBG")
	local foodTemplate = root:FindFirstChild("FoodTemplate") or find_descendant(root, { "FoodTemplate" }, "GuiObject")

	if not mainLeft or not ingredientContainer or not ingredientTemplate or not listScrollingFrame or not cardTemplate then
		return nil
	end

	if not mainLeft:IsA("GuiObject")
		or not ingredientContainer:IsA("GuiObject")
		or not ingredientTemplate:IsA("GuiObject")
		or not listScrollingFrame:IsA("ScrollingFrame")
		or not cardTemplate:IsA("GuiObject")
	then
		return nil
	end

	local barFill = barBackground and barBackground:FindFirstChild("ToggleBT") or nil
	if barFill and not barFill:IsA("GuiObject") then
		barFill = nil
	end

	local foodRarityIcon = foodRoot and (
		find_descendant(foodRoot, { "rarity", "Rarity" }, "ImageLabel")
			or find_descendant(foodRoot, { "rarity", "Rarity" }, "ImageButton")
			or find_gui_object(foodRoot, { "rarity", "Rarity" })
	) or nil

	if foodTemplate and not foodTemplate:IsA("GuiObject") then
		foodTemplate = nil
	end

	local foodStatsContainer = foodTemplate and find_gui_object(foodTemplate, { "StatsFR" }) or nil
	local foodStatTemplate = foodStatsContainer and (
		foodStatsContainer:FindFirstChild("StatFR") or find_descendant(foodStatsContainer, { "StatFR" }, "GuiObject")
	) or nil
	if foodStatTemplate and not foodStatTemplate:IsA("GuiObject") then
		foodStatTemplate = nil
	end

	local foodTemplateRarityIcon = foodTemplate and (
		find_descendant(foodTemplate, { "rarity", "Rarity" }, "ImageLabel")
			or find_descendant(foodTemplate, { "rarity", "Rarity" }, "ImageButton")
			or find_gui_object(foodTemplate, { "rarity", "Rarity" })
	) or nil

	local ui = {
		Root = root,
		MainLeft = mainLeft,
		IngredientContainer = ingredientContainer,
		IngredientTemplate = ingredientTemplate,
		ListScrollingFrame = listScrollingFrame,
		CardTemplate = cardTemplate,
		FoodRoot = foodRoot and foodRoot:IsA("GuiObject") and foodRoot or nil,
		CookButton = cookButton and cookButton:IsA("GuiButton") and cookButton or nil,
		CookButtonText = cookButton and find_text(cookButton, { "BTTX" }) or nil,
		BarFill = barFill,
		CookingLabel = mainLeft and find_text(mainLeft, { "Cooking" }) or nil,
		FoodNameLabel = mainLeft and find_text(mainLeft, { "FoodNameTX" }) or nil,
		FoodImage = foodRoot and find_image_object(foodRoot, { { "HorseImage" }, { "FoodImage" }, { "ImageLabel" } }) or nil,
		FoodRarityIcon = foodRarityIcon,
		FoodTemplate = foodTemplate,
		FoodTemplateNameLabel = foodTemplate and find_text(foodTemplate, { "FoodNameTX" }) or nil,
		FoodTemplateDetailsLabel = foodTemplate and find_text(foodTemplate, { "DetailsTX" }) or nil,
		FoodTemplateImage = foodTemplate and find_image_object(foodTemplate, {
			{ "ItemDisplayBG", "HorseImage" },
			{ "HorseImage" },
			{ "FoodImage" },
			{ "ImageLabel" },
		}) or nil,
		FoodTemplateRarityIcon = foodTemplateRarityIcon,
		FoodStatsContainer = foodStatsContainer,
		FoodStatTemplate = foodStatTemplate,
		IngredientLabel = find_text(ingredientTemplate, { "StockCountTX", "StockCount" }),
	}

	ui.DefaultIngredientTextColor = get_text_color(ui.IngredientLabel)
	ui.BarFillBaseSize = ui.BarFill and ui.BarFill.Size or UDim2.fromScale(1, 1)

	return ui
end

local function find_cooking_ui()
	local mainUi = find_descendant(playerGui, MAIN_UI_NAMES, nil)
	local mainframe = find_descendant(mainUi, MAINFRAME_NAMES, nil)
	local frames = find_descendant(mainframe, FRAMES_NAMES, nil)
	local cooking = find_child(frames, COOKING_NAMES, "GuiObject") or find_descendant(frames, COOKING_NAMES, "GuiObject")

	if cooking then
		return get_cooking_ui(cooking)
	end

	return nil
end

local function bind_ui(ui)
	if currentUi and currentUi.Root == ui.Root then
		return
	end

	destroy_ui_binding()
	currentUi = ui
	debug_print("bind_ui", "root=" .. get_debug_path(ui.Root), "visible=" .. tostring(ui.Root.Visible))

	disable_hud_anim_tree(ui.ListScrollingFrame)
	disable_hud_anim_tree(ui.IngredientContainer)
	disable_hud_anim_tree(ui.CardTemplate)
	disable_hud_anim_tree(ui.IngredientTemplate)
	disable_hud_anim_tree(ui.FoodTemplate)
	disable_viewport_previews(ui.Root)
	bind_open_hud_anim(ui.Root)

	ui.CardTemplate.Visible = false
	ui.IngredientTemplate.Visible = false
	if ui.FoodTemplate then
		ui.FoodTemplate.Visible = false
	end
	if ui.FoodStatTemplate then
		ui.FoodStatTemplate.Visible = false
	end

	prewarm_dynamic_rows(ui)

	ui.ListScrollingFrame.Active = true
	ui.ListScrollingFrame.ScrollingEnabled = true
	ui.ListScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	ui.ListScrollingFrame.CanvasSize = UDim2.fromOffset(0, 0)
	build_recipe_cards()

	local layout = ui.ListScrollingFrame:FindFirstChildOfClass("UIListLayout")
	if layout then
		uiTrove:Connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
			update_canvas_size(ui.ListScrollingFrame)
		end)
	end

	uiTrove:Connect(ui.ListScrollingFrame:GetPropertyChangedSignal("AbsoluteSize"), function()
		update_canvas_size(ui.ListScrollingFrame)
	end)

	if ui.CookButton then
		uiTrove:Connect(ui.CookButton.Activated, function()
			local actionMode = get_action_mode()

			if actionMode == "Cook" then
				submit_action("Start")
			elseif actionMode == "Purchase" then
				submit_action("Collect")
			else
				refresh_dynamic_ui()
			end
		end)
	end

	if ui.Root:IsA("GuiObject") then
		uiTrove:Connect(ui.Root:GetPropertyChangedSignal("Visible"), function()
			local isVisible = is_ui_visible(ui.Root)
			uiWasVisible = isVisible

			if isVisible then
				ensure_open_ui_loaded()
			else
				reset_runtime_state()
			end
		end)
	end

	uiTrove:Connect(ui.Root.AncestryChanged, function(_, parent)
		if parent then
			return
		end

		if currentUi and currentUi.Root == ui.Root then
			destroy_ui_binding()
			task.defer(try_bind_ui)
		end
	end)

	uiWasVisible = is_ui_visible(ui.Root)
	if uiWasVisible then
		ensure_open_ui_loaded()
	end
	refresh_dynamic_ui()
end

local function schedule_retry()
	if retryScheduled then
		return
	end

	retryScheduled = true

	task.delay(UI_RETRY_SECONDS, function()
		retryScheduled = false

		if currentUi and currentUi.Root and currentUi.Root.Parent then
			return
		end

		uiSearchAttempts += 1
		try_bind_ui()

		if not currentUi then
			if uiSearchAttempts % UI_WARNING_INTERVAL == 0 then
				warn("[Cooking] waiting for Cooking UI in PlayerGui.MainUI.MainframeFR.Frames.Cooking")
			end

			schedule_retry()
		end
	end)
end

try_bind_ui = function()
	local ui = find_cooking_ui()
	if not ui then
		if currentUi then
			destroy_ui_binding()
		end

		schedule_retry()
		return
	end

	uiSearchAttempts = 0
	bind_ui(ui)
end

local function initialize_data()
	task.spawn(function()
		local ok, err = pcall(function()
			DataUtility.client.ensure_remotes()
		end)

		if not ok then
			warn("[Cooking] failed to initialize player data: " .. tostring(err))
		end

		dataReady = true
		if currentUi and is_ui_visible(currentUi.Root) then
			ensure_open_ui_loaded()
		end

		queue_refresh_all()
	end)
end

initialize_data()
sync_selected_recipe()
try_bind_ui()

local function is_cooking_structure_instance(instance)
	return matches_name(instance, MAIN_UI_NAMES)
		or matches_name(instance, MAINFRAME_NAMES)
		or matches_name(instance, FRAMES_NAMES)
		or matches_name(instance, COOKING_NAMES)
		or instance.Name == "MainLeft"
		or instance.Name == "ListScrollingFrame"
		or instance.Name == "TemplateCraft"
		or instance.Name == "Ingredient"
		or instance.Name == "FoodTemplate"
		or instance.Name == "StatsFR"
		or instance.Name == "StatFR"
end

local function is_current_bound_structure_instance(instance)
	if not currentUi then
		return false
	end

	return instance == currentUi.Root
		or instance == currentUi.MainLeft
		or instance == currentUi.IngredientContainer
		or instance == currentUi.IngredientTemplate
		or instance == currentUi.ListScrollingFrame
		or instance == currentUi.CardTemplate
		or instance == currentUi.FoodTemplate
		or instance == currentUi.FoodStatsContainer
		or instance == currentUi.FoodStatTemplate
end

local function should_rebind_for_added_instance(instance)
	if not is_cooking_structure_instance(instance) then
		return false
	end

	if currentUi and currentUi.Root and instance:IsDescendantOf(currentUi.Root) then
		return is_current_bound_structure_instance(instance)
	end

	return true
end

rootTrove:Connect(playerGui.DescendantAdded, function(instance)
	if should_rebind_for_added_instance(instance) then
		debug_print("structure_added", "instance=" .. get_debug_path(instance))
		task.defer(try_bind_ui)
	end
end)

rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
	if currentUi and (
		instance == currentUi.Root
		or instance == currentUi.MainLeft
		or instance == currentUi.IngredientContainer
		or instance == currentUi.IngredientTemplate
		or instance == currentUi.ListScrollingFrame
		or instance == currentUi.CardTemplate
	) then
		debug_print("structure_removing", "instance=" .. get_debug_path(instance))
		task.defer(try_bind_ui)
	end
end)

rootTrove:Connect(RunService.Heartbeat, function(deltaTime)
	dynamicAccumulator += deltaTime
	if dynamicAccumulator < DYNAMIC_REFRESH_SECONDS then
		return
	end

	dynamicAccumulator = 0

	if currentUi and currentUi.Root and currentUi.Root.Parent then
		local isVisible = is_ui_visible(currentUi.Root)

		if isVisible and not uiWasVisible then
			ensure_open_ui_loaded()
		elseif not isVisible and uiWasVisible then
			reset_runtime_state()
		end

		uiWasVisible = isVisible
	end

	refresh_dynamic_ui()
end)

script:SetAttribute("RuntimeReady", true)
