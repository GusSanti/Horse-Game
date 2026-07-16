local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local CookingCatalog = require(GameData:WaitForChild("CookingCatalog"))
local Trove = require(Libraries:WaitForChild("Trove"))
local Net = require(Libraries:WaitForChild("Net"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local COOKING_ACTION_REMOTE_NAME = "CookingAction"
local NET_ROOT_FOLDER_NAME = "Net"
local NET_FUNCTIONS_FOLDER_NAME = "Functions"

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainFrameFR", "MainframeFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local COOKING_ROOT_NAMES = { "Cooking" }
local MAIN_LEFT_NAMES = { "MainLeft" }
local LIST_SCROLLING_FRAME_NAMES = { "ListScrollingFrame" }
local TEMPLATE_CARD_NAMES = { "TemplateCraft" }
local CARD_BUTTON_NAMES = { "PurchaseBT" }
local CARD_NAME_NAMES = { "ItemNameTX" }
local CARD_STOCK_NAMES = { "StockCountTX" }
local CARD_BUTTON_TEXT_NAMES = { "BTTX" }
local IMAGE_ROOT_NAMES = { "ImageLabel", "HorseImage", "ImageItem", "Icon" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }
local FOOD_ROOT_NAMES = { "Food" }
local FOOD_NAME_NAMES = { "FoodNameTX" }
local COOKING_LABEL_NAMES = { "Cooking" }
local COOK_BUTTON_NAMES = { "CookBT" }
local BAR_BG_NAMES = { "BarBG" }
local BAR_FILL_NAMES = { "ToggleBT" }
local INGREDIENT_CONTAINER_NAMES = { "Frame" }
local INGREDIENT_TEMPLATE_NAMES = { "Ingredient" }
local INGREDIENT_STOCK_NAMES = { "StockCountTX" }
local TEXT_OBJECT_CLASSES = {
	"TextLabel",
	"TextButton",
	"TextBox",
}

local WARNING_INTERVAL = 20
local UI_DISCOVERY_INTERVAL = 0.5

local VIEWPORT_CONFIG = {
	FieldOfView = 33,
	RadiusScale = 0.5,
	CameraXScale = 0.36,
	CameraYScale = 0.18,
	FocusYOffsetScale = 0.05,
}

local INSUFFICIENT_COLOR = Color3.fromRGB(229, 85, 85)

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()
local ingredientTrove = Trove.new()

local currentUi = nil
local cardEntries = {}
local selectedRecipeId = nil
local requestInFlight = false
local try_bind_ui

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

local function format_count(amount: number): string
	return string.format("%02d", math.max(0, math.floor(tonumber(amount) or 0)))
end

local function matches_alias(instance: Instance, aliases): boolean
	local normalizedName = normalize_key(instance.Name)
	if not normalizedName then
		return false
	end

	for _, alias in ipairs(aliases or {}) do
		if normalize_key(alias) == normalizedName then
			return true
		end
	end

	return false
end

local function find_named_instance(root: Instance?, aliases, className: string?, recursive: boolean?): Instance?
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if matches_alias(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	if recursive == false then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if matches_alias(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function find_gui_object(root: Instance?, aliases, recursive: boolean?): GuiObject?
	local instance = find_named_instance(root, aliases, "GuiObject", recursive)
	return if instance then instance :: GuiObject else nil
end

local function find_gui_button(root: Instance?, aliases, recursive: boolean?): GuiButton?
	local instance = find_named_instance(root, aliases, "GuiButton", recursive)
	return if instance then instance :: GuiButton else nil
end

local function is_text_object(instance: Instance?): boolean
	if not instance then
		return false
	end

	for _, className in ipairs(TEXT_OBJECT_CLASSES) do
		if instance:IsA(className) then
			return true
		end
	end

	return false
end

local function find_text_object(root: Instance?, aliases, recursive: boolean?): Instance?
	if not root then
		return nil
	end

	for _, className in ipairs(TEXT_OBJECT_CLASSES) do
		local instance = find_named_instance(root, aliases, className, recursive)
		if instance then
			return instance
		end
	end

	return nil
end

local function set_text(instance: Instance?, text: string)
	if not is_text_object(instance) then
		return
	end

	(instance :: any).Text = text
end

local function set_text_color(instance: Instance?, color: Color3)
	if not is_text_object(instance) then
		return
	end

	(instance :: any).TextColor3 = color
end

local function get_text_color(instance: Instance?, fallback: Color3): Color3
	if not is_text_object(instance) then
		return fallback
	end

	return (instance :: any).TextColor3
end

local function find_direct_child(parent: Instance?, aliases, className: string?): Instance?
	if not parent then
		return nil
	end

	for _, child in ipairs(parent:GetChildren()) do
		if matches_alias(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	return nil
end

local function find_viewport_frame(root: Instance?): ViewportFrame?
	if not root then
		return nil
	end

	if root:IsA("ViewportFrame") then
		return root :: ViewportFrame
	end

	local instance = find_named_instance(root, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
	return if instance then instance :: ViewportFrame else nil
end

local function is_ui_visible(instance: Instance?): boolean
	local current = instance

	while current do
		if current:IsA("GuiObject") and current.Visible ~= true then
			return false
		end

		if current:IsA("LayerCollector") and current.Enabled ~= true then
			return false
		end

		current = current.Parent
	end

	return true
end

local function strip_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function make_template_source(template: GuiObject): GuiObject
	local source = template:Clone()
	source.Visible = true
	strip_scripts(source)
	template.Visible = false
	return source
end

local function set_button_enabled(button: GuiButton?, isEnabled: boolean)
	if not button then
		return
	end

	button.Active = isEnabled
	button.Selectable = isEnabled
	button.AutoButtonColor = isEnabled
end

local function set_selected_visual(card: GuiObject, isSelected: boolean)
	local stroke = card:FindFirstChildWhichIsA("UIStroke", true)
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
	end

	stroke.Thickness = isSelected and 2.5 or 1
	stroke.Transparency = isSelected and 0 or 0.25
	stroke.Color = isSelected and Color3.fromRGB(255, 222, 129) or Color3.fromRGB(255, 255, 255)
end

local function update_canvas_size(scrollingFrame: ScrollingFrame?)
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
		scrollingFrame.ScrollingDirection = Enum.ScrollingDirection.XY
	end
end

local function clear_viewport(viewportFrame: ViewportFrame?)
	if not viewportFrame then
		return
	end

	for _, child in ipairs(viewportFrame:GetChildren()) do
		child:Destroy()
	end

	viewportFrame.CurrentCamera = nil
end

local function get_cooking_remote(): RemoteFunction?
	local netRoot = ReplicatedStorage:FindFirstChild(NET_ROOT_FOLDER_NAME)
	if not netRoot then
		return nil
	end

	local functionsFolder = netRoot:FindFirstChild(NET_FUNCTIONS_FOLDER_NAME)
	if not functionsFolder then
		return nil
	end

	local remote = functionsFolder:FindFirstChild(COOKING_ACTION_REMOTE_NAME)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end

	return nil
end

local function is_cooking_remote_available(): boolean
	return get_cooking_remote() ~= nil
end

local function collect_base_parts(root: Instance): { BasePart }
	local baseParts = {}

	if root:IsA("BasePart") then
		baseParts[#baseParts + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			baseParts[#baseParts + 1] = descendant
		end
	end

	return baseParts
end

local function create_placeholder_preview_model(displayName: string): Model
	local model = Instance.new("Model")
	model.Name = ("%sPreview"):format(displayName)

	local part = Instance.new("Part")
	part.Name = "Preview"
	part.Size = Vector3.new(1.25, 1.25, 1.25)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(214, 214, 214)
	part.Parent = model

	return model
end

local function create_preview_root(asset: Instance?, displayName: string): Model
	local previewRoot = nil

	if asset then
		local success, cloneOrError = pcall(function()
			return asset:Clone()
		end)
		if not success then
			warn(("[Cooking] failed to clone preview asset for %s: %s"):format(displayName, tostring(cloneOrError)))
			return create_placeholder_preview_model(displayName)
		end

		local clone = cloneOrError
		strip_scripts(clone)

		if clone:IsA("Model") then
			previewRoot = clone
		else
			previewRoot = Instance.new("Model")
			previewRoot.Name = clone.Name

			local parentSuccess, parentError = pcall(function()
				clone.Parent = previewRoot
			end)
			if not parentSuccess then
				warn(("[Cooking] failed to parent preview asset for %s: %s"):format(displayName, tostring(parentError)))
				previewRoot:Destroy()
				return create_placeholder_preview_model(displayName)
			end
		end
	else
		previewRoot = create_placeholder_preview_model(displayName)
	end

	local baseParts = collect_base_parts(previewRoot)
	if #baseParts == 0 then
		previewRoot:Destroy()
		previewRoot = create_placeholder_preview_model(displayName)
		baseParts = collect_base_parts(previewRoot)
	end

	for _, basePart in ipairs(baseParts) do
		basePart.Anchored = true
		basePart.CanCollide = false
		basePart.CanTouch = false
		basePart.CanQuery = false
		basePart.CastShadow = false
	end

	local pivotSuccess, pivotError = pcall(function()
		previewRoot:PivotTo(CFrame.new())
	end)
	if not pivotSuccess then
		warn(("[Cooking] failed to pivot preview asset for %s: %s"):format(displayName, tostring(pivotError)))
	end

	return previewRoot
end

local function render_definition_viewport(viewportFrame: ViewportFrame?, definition)
	if not viewportFrame then
		return
	end

	clear_viewport(viewportFrame)

	local asset = nil
	if definition then
		asset = FarmingUtility.GetViewportAsset(definition) or FarmingUtility.GetItemAsset(definition)
	end

	local displayName = definition and (definition.DisplayName or definition.ItemId) or "Food"
	local previewRoot = create_preview_root(asset, displayName)
	local renderSuccess, renderError = pcall(function()
		local boxCFrame, boxSize = previewRoot:GetBoundingBox()
		if not boxCFrame or not boxSize then
			error("missing preview bounds")
		end

		local worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewportFrame
		previewRoot.Parent = worldModel

		local camera = Instance.new("Camera")
		camera.FieldOfView = VIEWPORT_CONFIG.FieldOfView
		camera.Parent = viewportFrame

		viewportFrame.BackgroundTransparency = 1
		viewportFrame.Ambient = Color3.fromRGB(220, 220, 220)
		viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
		viewportFrame.CurrentCamera = camera

		local focusPoint = boxCFrame.Position + Vector3.new(0, boxSize.Y * VIEWPORT_CONFIG.FocusYOffsetScale, 0)
		local radius = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1) * VIEWPORT_CONFIG.RadiusScale
		local distance = math.max(1.75, radius / math.tan(math.rad(camera.FieldOfView * 0.5)))
		local offset = Vector3.new(
			distance * VIEWPORT_CONFIG.CameraXScale,
			distance * VIEWPORT_CONFIG.CameraYScale,
			distance * 1.08
		)

		camera.CFrame = CFrame.lookAt(focusPoint + offset, focusPoint)
	end)

	if renderSuccess then
		return
	end

	warn(("[Cooking] failed to render viewport for %s: %s"):format(displayName, tostring(renderError)))
	clear_viewport(viewportFrame)
	previewRoot:Destroy()

	local fallbackPreview = create_placeholder_preview_model(displayName)
	local fallbackSuccess = pcall(function()
		local boxCFrame, boxSize = fallbackPreview:GetBoundingBox()
		local worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewportFrame
		fallbackPreview.Parent = worldModel

		local camera = Instance.new("Camera")
		camera.FieldOfView = VIEWPORT_CONFIG.FieldOfView
		camera.Parent = viewportFrame

		viewportFrame.BackgroundTransparency = 1
		viewportFrame.Ambient = Color3.fromRGB(220, 220, 220)
		viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
		viewportFrame.CurrentCamera = camera

		local focusPoint = boxCFrame.Position + Vector3.new(0, boxSize.Y * VIEWPORT_CONFIG.FocusYOffsetScale, 0)
		local radius = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1) * VIEWPORT_CONFIG.RadiusScale
		local distance = math.max(1.75, radius / math.tan(math.rad(camera.FieldOfView * 0.5)))
		local offset = Vector3.new(
			distance * VIEWPORT_CONFIG.CameraXScale,
			distance * VIEWPORT_CONFIG.CameraYScale,
			distance * 1.08
		)

		camera.CFrame = CFrame.lookAt(focusPoint + offset, focusPoint)
	end)

	if not fallbackSuccess then
		clear_viewport(viewportFrame)
	end
end

local function get_definition_count(definition): number
	if not definition then
		return 0
	end

	local inventoryPath = normalize_inventory_path(definition.InventoryPath)
	if not inventoryPath then
		return 0
	end

	local bucket = DataUtility.client.get(inventoryPath)
	if type(bucket) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(bucket[definition.ItemId]) or 0))
end

local function get_cooking_state()
	local rawState = DataUtility.client.get("Cooking")

	return {
		ActiveRecipeId = normalize_key(type(rawState) == "table" and rawState.ActiveRecipeId or nil) or "",
		StartedAt = math.max(0, math.floor(tonumber(type(rawState) == "table" and rawState.StartedAt or 0) or 0)),
		ReadyAt = math.max(0, math.floor(tonumber(type(rawState) == "table" and rawState.ReadyAt or 0) or 0)),
		ResultAmount = math.max(0, math.floor(tonumber(type(rawState) == "table" and rawState.ResultAmount or 0) or 0)),
	}
end

local function has_active_job(state): boolean
	return type(state.ActiveRecipeId) == "string" and state.ActiveRecipeId ~= ""
end

local function is_job_ready(state): boolean
	return has_active_job(state) and state.ReadyAt > 0 and state.ReadyAt <= os.time()
end

local function get_progress_alpha(state): number
	if not has_active_job(state) then
		return 0
	end

	local totalDuration = math.max(1, state.ReadyAt - state.StartedAt)
	local elapsed = math.clamp(os.time() - state.StartedAt, 0, totalDuration)
	return math.clamp(elapsed / totalDuration, 0, 1)
end

local function get_selected_recipe()
	return selectedRecipeId and CookingCatalog.GetRecipe(selectedRecipeId) or nil
end

local function get_active_recipe(state)
	return has_active_job(state) and CookingCatalog.GetRecipe(state.ActiveRecipeId) or nil
end

local function has_recipe_ingredients(recipe): boolean
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

local function destroy_ingredient_rows()
	ingredientTrove:Clean()
end

local function refresh_dynamic_ui()
	if not currentUi or not currentUi.Root or not currentUi.Root.Parent then
		return
	end

	if not is_ui_visible(currentUi.Root) then
		return
	end

	local state = get_cooking_state()
	local selectedRecipe = get_selected_recipe()
	local activeRecipe = get_active_recipe(state)
	local isSelectedActiveRecipe = selectedRecipe and activeRecipe and selectedRecipe.RecipeId == activeRecipe.RecipeId

	local progressAlpha = if isSelectedActiveRecipe then get_progress_alpha(state) else 0
	if currentUi.BarFill then
		currentUi.BarFill.Size = UDim2.new(
			progressAlpha,
			0,
			currentUi.BarFillYScale,
			currentUi.BarFillYOffset
		)
	end

	if currentUi.CookingLabel then
		if isSelectedActiveRecipe and not is_job_ready(state) then
			local dotCount = (math.floor(os.clock() * 2.5) % 3) + 1
			set_text(currentUi.CookingLabel, "Cooking" .. string.rep(".", dotCount))
		elseif isSelectedActiveRecipe and is_job_ready(state) then
			set_text(currentUi.CookingLabel, "Ready")
		else
			set_text(currentUi.CookingLabel, "")
		end
	end

	local actionMode = nil
	if selectedRecipe then
		if isSelectedActiveRecipe then
			actionMode = if is_job_ready(state) then "Collect" else "Cooking"
		elseif not activeRecipe and has_recipe_ingredients(selectedRecipe) then
			actionMode = "Cook"
		end
	end

	local showCookButton = selectedRecipe ~= nil and (actionMode ~= nil or requestInFlight)
	if currentUi.CookButton then
		currentUi.CookButton.Visible = showCookButton
	end

	if currentUi.CookButtonText then
		if actionMode == "Collect" then
			set_text(currentUi.CookButtonText, "Purchase")
		elseif actionMode == "Cooking" or requestInFlight then
			set_text(currentUi.CookButtonText, "Cooking")
		else
			set_text(currentUi.CookButtonText, "Cook")
		end
	end

	set_button_enabled(
		currentUi.CookButton,
		is_cooking_remote_available() and not requestInFlight and (actionMode == "Cook" or actionMode == "Collect")
	)
end

local function refresh_recipe_cards()
	if not currentUi then
		return
	end

	local state = get_cooking_state()
	local activeRecipe = get_active_recipe(state)
	local activeRecipeId = activeRecipe and activeRecipe.RecipeId or nil

	for _, entry in ipairs(cardEntries) do
		local foodCount = get_definition_count(entry.Recipe.FoodDefinition)
		if entry.StockCountLabel then
			set_text(entry.StockCountLabel, format_count(foodCount))
		end

		local isSelected = selectedRecipeId == entry.Recipe.RecipeId
		local canSelect = not requestInFlight and (activeRecipeId == nil or activeRecipeId == entry.Recipe.RecipeId)

		set_selected_visual(entry.Card, isSelected)
		set_button_enabled(entry.Button, canSelect)

		if entry.ButtonText then
			if activeRecipeId == entry.Recipe.RecipeId then
				set_text(entry.ButtonText, if is_job_ready(state) then "Ready" else "Cooking")
			elseif isSelected then
				set_text(entry.ButtonText, "Selected")
			else
				set_text(entry.ButtonText, "Select")
			end
		end
	end
end

local function render_selected_recipe_panel()
	if not currentUi then
		return
	end

	destroy_ingredient_rows()
	sync_selected_recipe()

	local selectedRecipe = get_selected_recipe()

	if not selectedRecipe then
		set_text(currentUi.FoodNameLabel, "")
		clear_viewport(currentUi.FoodViewport)
		refresh_dynamic_ui()
		return
	end

	set_text(currentUi.FoodNameLabel, selectedRecipe.DisplayName)

	render_definition_viewport(currentUi.FoodViewport, selectedRecipe.FoodDefinition)

	for index, ingredient in ipairs(selectedRecipe.Ingredients) do
		local row = currentUi.IngredientTemplateSource:Clone()
		row.Name = ingredient.ItemId
		row.Visible = true
		row.LayoutOrder = index
		row.Parent = currentUi.IngredientContainer
		ingredientTrove:Add(row)

		local stockCountLabel = find_text_object(row, INGREDIENT_STOCK_NAMES, true)
		local ingredientImageRoot = find_gui_object(row, IMAGE_ROOT_NAMES, true) or row
		local ingredientViewport = find_viewport_frame(ingredientImageRoot)
		local playerAmount = get_definition_count(ingredient.Definition)
		local hasEnough = playerAmount >= ingredient.Amount

		set_text(stockCountLabel, string.format("%s/%s", format_count(playerAmount), format_count(ingredient.Amount)))
		set_text_color(stockCountLabel, if hasEnough then currentUi.DefaultIngredientTextColor else INSUFFICIENT_COLOR)

		render_definition_viewport(ingredientViewport, ingredient.Definition)
	end

	refresh_dynamic_ui()
end

local function refresh_all_static()
	if not currentUi then
		return
	end

	sync_selected_recipe()
	refresh_recipe_cards()
	render_selected_recipe_panel()
end

local function set_selected_recipe(recipeId)
	local recipe = CookingCatalog.GetRecipe(recipeId)
	if not recipe then
		return
	end

	local state = get_cooking_state()
	local activeRecipe = get_active_recipe(state)
	if activeRecipe and activeRecipe.RecipeId ~= recipe.RecipeId then
		return
	end

	selectedRecipeId = recipe.RecipeId
	refresh_all_static()
end

local function build_recipe_cards()
	if not currentUi then
		return
	end

	local ui = currentUi
	cardTrove:Clean()
	table.clear(cardEntries)

	for index, recipe in ipairs(CookingCatalog.GetRecipes()) do
		local card = ui.CardTemplateSource:Clone()
		card.Name = recipe.RecipeId
		card.Visible = true
		card.LayoutOrder = index
		card.Parent = ui.ListScrollingFrame
		cardTrove:Add(card)

		local purchaseButton = find_gui_button(card, CARD_BUTTON_NAMES, true)
		local buttonText = find_text_object(purchaseButton, CARD_BUTTON_TEXT_NAMES, true)
		local nameLabel = find_text_object(card, CARD_NAME_NAMES, true)
		local stockCountLabel = find_text_object(card, CARD_STOCK_NAMES, true)
		local imageRoot = find_gui_object(card, IMAGE_ROOT_NAMES, true) or card
		local viewportFrame = find_viewport_frame(imageRoot)

		set_text(nameLabel, recipe.DisplayName)
		set_text(buttonText, "Select")

		render_definition_viewport(viewportFrame, recipe.FoodDefinition)

		local entry = {
			Recipe = recipe,
			Card = card,
			Button = purchaseButton,
			ButtonText = buttonText,
			StockCountLabel = stockCountLabel,
		}

		cardEntries[#cardEntries + 1] = entry

		if purchaseButton then
			cardTrove:Connect(purchaseButton.Activated, function()
				set_selected_recipe(recipe.RecipeId)
			end)
		end

		if index == 1 or index % 3 == 0 then
			update_canvas_size(ui.ListScrollingFrame)
		end
	end

	update_canvas_size(ui.ListScrollingFrame)
	refresh_all_static()
end

local function submit_cooking_action(actionName: string)
	local selectedRecipe = get_selected_recipe()
	if not selectedRecipe or requestInFlight then
		return
	end

	if not is_cooking_remote_available() then
		warn("[Cooking] cooking remote is unavailable; the service did not initialize yet")
		refresh_dynamic_ui()
		return
	end

	requestInFlight = true
	refresh_dynamic_ui()
	refresh_recipe_cards()

	task.spawn(function()
		local success, result = pcall(function()
			return Net.Function[COOKING_ACTION_REMOTE_NAME]:Call({
				Action = actionName,
				RecipeId = selectedRecipe.RecipeId,
			})
		end)

		requestInFlight = false

		if not success then
			warn("[Cooking] failed to send action: " .. tostring(result))
		end

		refresh_all_static()
	end)
end

local function get_relevant_data_paths()
	local paths = { "Cooking" }
	local seen = {
		Cooking = true,
	}

	local function push(path)
		path = normalize_inventory_path(path)
		if not path or seen[path] then
			return
		end

		seen[path] = true
		paths[#paths + 1] = path
	end

	for _, recipe in ipairs(CookingCatalog.GetRecipes()) do
		push(recipe.FoodDefinition and recipe.FoodDefinition.InventoryPath)

		for _, ingredient in ipairs(recipe.Ingredients) do
			push(ingredient.InventoryPath)
		end
	end

	return paths
end

local function destroy_ui_binding()
	cardTrove:Clean()
	ingredientTrove:Clean()
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = nil
	table.clear(cardEntries)
end

local function bind_ui(ui)
	if currentUi and currentUi.Root == ui.Root then
		return
	end

	destroy_ui_binding()

	currentUi = ui
	ui.CardTemplateSource = make_template_source(ui.CardTemplate)
	ui.IngredientTemplateSource = make_template_source(ui.IngredientTemplate)
	ui.DefaultIngredientTextColor = get_text_color(ui.IngredientLabel, Color3.fromRGB(255, 255, 255))
	ui.BarFillYScale = ui.BarFill and ui.BarFill.Size.Y.Scale or 1
	ui.BarFillYOffset = ui.BarFill and ui.BarFill.Size.Y.Offset or 0

	uiTrove:Add(ui.CardTemplateSource)
	uiTrove:Add(ui.IngredientTemplateSource)

	if ui.ListScrollingFrame then
		ui.ListScrollingFrame.Active = true
		ui.ListScrollingFrame.ScrollingEnabled = true
		ui.ListScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
		ui.ListScrollingFrame.CanvasSize = UDim2.fromOffset(0, 0)
		ui.ListScrollingFrame.CanvasPosition = Vector2.zero

		local layout = ui.ListScrollingFrame:FindFirstChildOfClass("UIListLayout")
			or ui.ListScrollingFrame:FindFirstChildWhichIsA("UIListLayout", true)
		if layout then
			uiTrove:Connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
				update_canvas_size(ui.ListScrollingFrame)
			end)
		end

		uiTrove:Connect(ui.ListScrollingFrame:GetPropertyChangedSignal("AbsoluteSize"), function()
			update_canvas_size(ui.ListScrollingFrame)
		end)

		update_canvas_size(ui.ListScrollingFrame)
	end

	if ui.CookButton then
		uiTrove:Connect(ui.CookButton.Activated, function()
			local state = get_cooking_state()
			local selectedRecipe = get_selected_recipe()
			local activeRecipe = get_active_recipe(state)

			if not selectedRecipe then
				return
			end

			if activeRecipe and activeRecipe.RecipeId == selectedRecipe.RecipeId and is_job_ready(state) then
				submit_cooking_action("Collect")
			else
				submit_cooking_action("Start")
			end
		end)
	end

	for _, dataPath in ipairs(get_relevant_data_paths()) do
		uiTrove:Add(DataUtility.client.bind(dataPath, refresh_all_static))
	end

	if ui.Root:IsA("GuiObject") then
		uiTrove:Connect(ui.Root:GetPropertyChangedSignal("Visible"), function()
			if ui.Root.Visible then
				refresh_all_static()
			end
		end)
	end

	uiTrove:Connect(ui.Root.AncestryChanged, function(_, parent)
		if parent then
			return
		end

		local boundUi = currentUi
		if boundUi and boundUi.Root == ui.Root then
			destroy_ui_binding()
			task.defer(try_bind_ui)
		end
	end)

	build_recipe_cards()
	refresh_dynamic_ui()
end

local function get_cooking_ui(root: Instance)
	local mainLeft = find_gui_object(root, MAIN_LEFT_NAMES, true)
	local listScrollingFrame = find_named_instance(root, LIST_SCROLLING_FRAME_NAMES, "ScrollingFrame", true)
	local cardTemplate = listScrollingFrame and (find_direct_child(listScrollingFrame, TEMPLATE_CARD_NAMES, "GuiObject")
		or find_gui_object(listScrollingFrame, TEMPLATE_CARD_NAMES, true))
	local ingredientContainer = mainLeft and (find_direct_child(mainLeft, INGREDIENT_CONTAINER_NAMES, "GuiObject")
		or find_gui_object(mainLeft, INGREDIENT_CONTAINER_NAMES, true))
	local ingredientTemplate = ingredientContainer and (find_direct_child(ingredientContainer, INGREDIENT_TEMPLATE_NAMES, "GuiObject")
		or find_gui_object(ingredientContainer, INGREDIENT_TEMPLATE_NAMES, true))
	local foodRoot = mainLeft and (find_direct_child(mainLeft, FOOD_ROOT_NAMES, "GuiObject")
		or find_gui_object(mainLeft, FOOD_ROOT_NAMES, true))
	local foodViewport = find_viewport_frame(foodRoot)
	local foodNameLabel = mainLeft and find_text_object(mainLeft, FOOD_NAME_NAMES, true)
	local cookingLabel = mainLeft and find_text_object(mainLeft, COOKING_LABEL_NAMES, true)
	local cookButton = mainLeft and find_gui_button(mainLeft, COOK_BUTTON_NAMES, true)
	local cookButtonText = cookButton and find_text_object(cookButton, CARD_BUTTON_TEXT_NAMES, true)
	local barBackground = mainLeft and find_gui_object(mainLeft, BAR_BG_NAMES, true)
	local barFill = barBackground and find_gui_object(barBackground, BAR_FILL_NAMES, true)
	local ingredientLabel = ingredientTemplate and find_text_object(ingredientTemplate, INGREDIENT_STOCK_NAMES, true)

	if not mainLeft or not listScrollingFrame or not cardTemplate or not ingredientContainer or not ingredientTemplate then
		return nil
	end

	if not foodRoot or not foodViewport then
		return nil
	end

	return {
		Root = root,
		MainLeft = mainLeft,
		ListScrollingFrame = listScrollingFrame,
		CardTemplate = cardTemplate,
		IngredientContainer = ingredientContainer,
		IngredientTemplate = ingredientTemplate,
		IngredientLabel = ingredientLabel,
		FoodViewport = foodViewport,
		FoodNameLabel = foodNameLabel,
		CookingLabel = cookingLabel,
		CookButton = cookButton,
		CookButtonText = cookButtonText,
		BarFill = barFill,
	}
end

local function find_cooking_ui()
	local mainUi = find_named_instance(playerGui, MAIN_UI_NAMES, nil, true)
	if not mainUi then
		return nil
	end

	local mainframe = find_named_instance(mainUi, MAINFRAME_NAMES, nil, true)
	if not mainframe then
		return nil
	end

	local framesContainer = find_named_instance(mainframe, FRAMES_CONTAINER_NAMES, nil, true)
	if not framesContainer then
		return nil
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if child:IsA("GuiObject") and matches_alias(child, COOKING_ROOT_NAMES) then
			local ui = get_cooking_ui(child)
			if ui then
				return ui
			end
		end
	end

	for _, descendant in ipairs(framesContainer:GetDescendants()) do
		if descendant:IsA("GuiObject") and matches_alias(descendant, COOKING_ROOT_NAMES) then
			local ui = get_cooking_ui(descendant)
			if ui then
				return ui
			end
		end
	end

	return nil
end

try_bind_ui = function()
	local ui = find_cooking_ui()
	if not ui then
		destroy_ui_binding()
		return
	end

	bind_ui(ui)
end

local function is_cooking_ui_related(instance: Instance): boolean
	return matches_alias(instance, MAIN_UI_NAMES)
		or matches_alias(instance, MAINFRAME_NAMES)
		or matches_alias(instance, FRAMES_CONTAINER_NAMES)
		or matches_alias(instance, COOKING_ROOT_NAMES)
		or matches_alias(instance, MAIN_LEFT_NAMES)
		or matches_alias(instance, LIST_SCROLLING_FRAME_NAMES)
		or matches_alias(instance, TEMPLATE_CARD_NAMES)
		or matches_alias(instance, INGREDIENT_TEMPLATE_NAMES)
		or matches_alias(instance, FOOD_ROOT_NAMES)
		or matches_alias(instance, COOK_BUTTON_NAMES)
		or matches_alias(instance, BAR_BG_NAMES)
		or matches_alias(instance, VIEWPORT_FRAME_NAMES)
end

local function initialize()
	DataUtility.client.ensure_remotes()
	sync_selected_recipe()

	rootTrove:Connect(playerGui.DescendantAdded, function(instance)
		if instance:IsA("LayerCollector") or is_cooking_ui_related(instance) then
			try_bind_ui()
		end
	end)

	rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
		if currentUi and (instance == currentUi.Root or instance:IsDescendantOf(currentUi.Root)) then
			task.defer(try_bind_ui)
		elseif is_cooking_ui_related(instance) then
			task.defer(try_bind_ui)
		end
	end)

	rootTrove:Connect(RunService.Heartbeat, function()
		refresh_dynamic_ui()
	end)

	local attempts = 0
	while true do
		attempts += 1
		local ui = find_cooking_ui()
		if ui then
			bind_ui(ui)
			return
		end

		if attempts % WARNING_INTERVAL == 0 then
			warn("[Cooking] waiting for Cooking UI in PlayerGui...")
		end

		task.wait(UI_DISCOVERY_INTERVAL)
	end
end

task.defer(function()
	local success, errorMessage = pcall(initialize)
	if not success then
		warn("[Cooking] initialization failed: " .. tostring(errorMessage))
	end
end)