local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local CookingCatalog = require(GameData:WaitForChild("CookingCatalog"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local HudAnim = require(Libraries:WaitForChild("HudAnim"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local FoodHoverTooltip = {}
do
	local tooltipGui = nil
	local tooltipFrame = nil
	local titleLabel = nil
	local bodyLabel = nil
	local activeTarget = nil
	local positionConnection = nil

	local function format_number(value)
		local numberValue = tonumber(value) or 0
		if math.abs(numberValue - math.floor(numberValue + 0.5)) < 0.001 then
			return tostring(math.floor(numberValue + 0.5))
		end

		return string.format("%.1f", numberValue)
	end

	local function format_signed(value)
		local numberValue = tonumber(value) or 0
		return numberValue >= 0 and ("+" .. format_number(numberValue)) or format_number(numberValue)
	end

	local function ensure_tooltip()
		if tooltipGui and tooltipGui.Parent and tooltipFrame and tooltipFrame.Parent then
			return tooltipFrame
		end

		tooltipGui = playerGui:FindFirstChild("FoodHoverTooltipGui")
		if not tooltipGui then
			tooltipGui = Instance.new("ScreenGui")
			tooltipGui.Name = "FoodHoverTooltipGui"
			tooltipGui.IgnoreGuiInset = true
			tooltipGui.ResetOnSpawn = false
			tooltipGui.DisplayOrder = 10000
			tooltipGui.Parent = playerGui
		end

		tooltipFrame = tooltipGui:FindFirstChild("Tooltip")
		if not tooltipFrame then
			tooltipFrame = Instance.new("Frame")
			tooltipFrame.Name = "Tooltip"
			tooltipFrame.BackgroundColor3 = Color3.fromRGB(24, 22, 20)
			tooltipFrame.BackgroundTransparency = 0.08
			tooltipFrame.BorderSizePixel = 0
			tooltipFrame.AutomaticSize = Enum.AutomaticSize.Y
			tooltipFrame.Size = UDim2.fromOffset(238, 0)
			tooltipFrame.Visible = false
			tooltipFrame.ZIndex = 10000
			tooltipFrame.Parent = tooltipGui

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 6)
			corner.Parent = tooltipFrame

			local stroke = Instance.new("UIStroke")
			stroke.Color = Color3.fromRGB(255, 225, 170)
			stroke.Transparency = 0.28
			stroke.Thickness = 1
			stroke.Parent = tooltipFrame

			local padding = Instance.new("UIPadding")
			padding.PaddingLeft = UDim.new(0, 10)
			padding.PaddingRight = UDim.new(0, 10)
			padding.PaddingTop = UDim.new(0, 10)
			padding.PaddingBottom = UDim.new(0, 10)
			padding.Parent = tooltipFrame

			local layout = Instance.new("UIListLayout")
			layout.FillDirection = Enum.FillDirection.Vertical
			layout.SortOrder = Enum.SortOrder.LayoutOrder
			layout.Padding = UDim.new(0, 5)
			layout.Parent = tooltipFrame

			titleLabel = Instance.new("TextLabel")
			titleLabel.Name = "Title"
			titleLabel.BackgroundTransparency = 1
			titleLabel.Font = Enum.Font.GothamBold
			titleLabel.TextColor3 = Color3.fromRGB(255, 236, 192)
			titleLabel.TextSize = 15
			titleLabel.TextXAlignment = Enum.TextXAlignment.Left
			titleLabel.TextWrapped = true
			titleLabel.AutomaticSize = Enum.AutomaticSize.Y
			titleLabel.Size = UDim2.fromScale(1, 0)
			titleLabel.LayoutOrder = 1
			titleLabel.ZIndex = 10001
			titleLabel.Parent = tooltipFrame

			bodyLabel = Instance.new("TextLabel")
			bodyLabel.Name = "Body"
			bodyLabel.BackgroundTransparency = 1
			bodyLabel.Font = Enum.Font.Gotham
			bodyLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
			bodyLabel.TextSize = 13
			bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
			bodyLabel.TextWrapped = true
			bodyLabel.AutomaticSize = Enum.AutomaticSize.Y
			bodyLabel.Size = UDim2.fromScale(1, 0)
			bodyLabel.LayoutOrder = 2
			bodyLabel.ZIndex = 10001
			bodyLabel.Parent = tooltipFrame
		else
			titleLabel = tooltipFrame:FindFirstChild("Title")
			bodyLabel = tooltipFrame:FindFirstChild("Body")
		end

		return tooltipFrame
	end

	local function is_target_visible(target)
		local current = target

		while current do
			if current:IsA("GuiObject") and not current.Visible then
				return false
			end

			if current:IsA("LayerCollector") and not current.Enabled then
				return false
			end

			current = current.Parent
		end

		return target ~= nil and target.Parent ~= nil
	end

	local function update_position()
		if not tooltipFrame or not tooltipFrame.Visible then
			return
		end

		if activeTarget and not is_target_visible(activeTarget) then
			FoodHoverTooltip.Hide(activeTarget)
			return
		end

		local mousePosition = UserInputService:GetMouseLocation()
		local viewportSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		local frameSize = tooltipFrame.AbsoluteSize
		local x = mousePosition.X + 16
		local y = mousePosition.Y + 18

		if x + frameSize.X + 10 > viewportSize.X then
			x = mousePosition.X - frameSize.X - 16
		end

		if y + frameSize.Y + 10 > viewportSize.Y then
			y = mousePosition.Y - frameSize.Y - 18
		end

		tooltipFrame.Position = UDim2.fromOffset(math.max(10, x), math.max(10, y))
	end

	local function build_effect_lines(itemDefinition)
		local effects = itemDefinition and itemDefinition.Effects or {}
		local lines = {}

		if itemDefinition and itemDefinition.NeedKey == "Hunger" and effects.NeedGain ~= nil then
			lines[#lines + 1] = "Hunger: +" .. format_number(effects.NeedGain)
		elseif itemDefinition and itemDefinition.NeedKey and effects.NeedGain ~= nil then
			lines[#lines + 1] = tostring(itemDefinition.NeedKey) .. ": +" .. format_number(effects.NeedGain)
		end

		if effects.HealthGain ~= nil then
			lines[#lines + 1] = "Health: " .. format_signed(effects.HealthGain)
		end

		if effects.HappinessGain ~= nil then
			lines[#lines + 1] = "Happiness: " .. format_signed(effects.HappinessGain)
		end

		if effects.FriendshipGain ~= nil then
			lines[#lines + 1] = "Friendship: " .. format_signed(effects.FriendshipGain)
		end

		local decayBuff = effects.DecayBuff
		if type(decayBuff) == "table" and tonumber(decayBuff.Multiplier) then
			local multiplier = tonumber(decayBuff.Multiplier)
			if multiplier and multiplier < 1 then
				local percent = math.max(0, math.floor((1 - multiplier) * 100 + 0.5))
				local duration = tonumber(decayBuff.DurationMinutes)
				local suffix = duration and duration > 0 and (" for " .. format_number(duration) .. " min") or ""
				lines[#lines + 1] = "Hunger decay: -" .. percent .. "%" .. suffix
			end
		end

		if effects.MoodText ~= nil and tostring(effects.MoodText) ~= "" then
			lines[#lines + 1] = "Mood: " .. tostring(effects.MoodText)
		end

		if #lines == 0 and type(itemDefinition.Description) == "string" and itemDefinition.Description ~= "" then
			lines[#lines + 1] = itemDefinition.Description
		end

		return lines
	end

	function FoodHoverTooltip.HasTooltip(itemDefinition)
		return type(itemDefinition) == "table" and #build_effect_lines(itemDefinition) > 0
	end

	function FoodHoverTooltip.Show(source, target)
		local itemDefinition = type(source) == "function" and source() or source
		if not FoodHoverTooltip.HasTooltip(itemDefinition) then
			return
		end

		local frame = ensure_tooltip()
		if not frame or not titleLabel or not bodyLabel then
			return
		end

		activeTarget = target
		titleLabel.Text = itemDefinition.DisplayName or itemDefinition.ToolName or itemDefinition.ItemId or "Food"
		bodyLabel.Text = table.concat(build_effect_lines(itemDefinition), "\n")
		frame.Visible = true
		update_position()

		if not positionConnection then
			positionConnection = RunService.RenderStepped:Connect(update_position)
		end
	end

	function FoodHoverTooltip.Hide(target)
		if target and activeTarget ~= target then
			return
		end

		activeTarget = nil
		if tooltipFrame then
			tooltipFrame.Visible = false
		end

		if positionConnection then
			positionConnection:Disconnect()
			positionConnection = nil
		end
	end

	function FoodHoverTooltip.Bind(target, source, trove)
		if not target or not target:IsA("GuiObject") then
			return
		end

		trove:Connect(target.MouseEnter, function()
			FoodHoverTooltip.Show(source, target)
		end)
		trove:Connect(target.MouseLeave, function()
			FoodHoverTooltip.Hide(target)
		end)
		trove:Connect(target.AncestryChanged, function(_, parent)
			if not parent then
				FoodHoverTooltip.Hide(target)
			end
		end)
	end
end

local COOKING_ACTION_REMOTE_NAME = "CookingAction"
local UI_RETRY_SECONDS = 0.5
local UI_WARNING_INTERVAL = 20
local DYNAMIC_REFRESH_SECONDS = 0.1
local LOAD_STEP_SECONDS = 0.03
local IGNORE_HUD_ANIM_ATTRIBUTE = "IgnoreHudAnim"

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainframeFR", "MainFrameFR" }
local FRAMES_NAMES = { "Frames" }
local COOKING_NAMES = { "Cooking" }

local INSUFFICIENT_COLOR = Color3.fromRGB(229, 85, 85)
local DEFAULT_TEXT_COLOR = Color3.fromRGB(255, 255, 255)

local VIEWPORT_CONFIG = {
	FieldOfView = 33,
	RadiusScale = 0.58,
	CameraOffset = Vector3.new(0.35, 0.18, 1.1),
	FocusYOffsetScale = 0.05,
}

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()
local ingredientTrove = Trove.new()

local currentUi = nil
local cardEntries = {}
local selectedRecipeId = nil
local requestInFlight = false
local dataReady = false
local dataBindingsReady = false
local refreshQueued = false
local retryScheduled = false
local uiSearchAttempts = 0
local dynamicAccumulator = 0
local loadToken = 0
local panelToken = 0
local cardsBuilt = false
local cardsLoading = false
local refreshPending = false
local renderedPanelRecipeId = nil
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

local function strip_scripts(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function create_template_source(template)
	local source = template:Clone()
	source.Visible = true
	source.Parent = nil
	strip_scripts(source)
	template.Visible = false
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

local function clear_viewport(viewport)
	if not viewport or not viewport:IsA("ViewportFrame") then
		return
	end

	for _, child in ipairs(viewport:GetChildren()) do
		if not child:IsA("UIAspectRatioConstraint") and not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end

	viewport.CurrentCamera = nil
end

local function collect_base_parts(root)
	local parts = {}

	if root:IsA("BasePart") then
		parts[#parts + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts[#parts + 1] = descendant
		end
	end

	return parts
end

local function create_placeholder_model(displayName)
	local model = Instance.new("Model")
	model.Name = ("%sPreview"):format(displayName or "Food")

	local part = Instance.new("Part")
	part.Name = "Preview"
	part.Size = Vector3.new(1.25, 1.25, 1.25)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(214, 214, 214)
	part.Parent = model

	return model
end

local function prepare_preview_model(source, displayName)
	local model

	if source then
		local ok, clone = pcall(function()
			return source:Clone()
		end)

		if ok and clone then
			strip_scripts(clone)

			if clone:IsA("Model") then
				model = clone
			else
				model = Instance.new("Model")
				model.Name = clone.Name
				clone.Parent = model
			end
		end
	end

	if not model then
		model = create_placeholder_model(displayName)
	end

	local parts = collect_base_parts(model)
	if #parts == 0 then
		model:Destroy()
		model = create_placeholder_model(displayName)
		parts = collect_base_parts(model)
	end

	for _, part in ipairs(parts) do
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
	end

	pcall(function()
		model:PivotTo(CFrame.new())
	end)

	return model
end

local function push_unique(list, value)
	if type(value) ~= "string" or value == "" then
		return
	end

	for _, existing in ipairs(list) do
		if existing == value then
			return
		end
	end

	list[#list + 1] = value
end

local function get_search_names(definition)
	local names = {}

	push_unique(names, definition and definition.ToolName)
	push_unique(names, definition and definition.DisplayName)
	push_unique(names, definition and definition.ItemId)
	push_unique(names, definition and definition.CropId)
	push_unique(names, definition and definition.CropDisplayName)

	for _, legacyName in ipairs(type(definition and definition.LegacyToolNames) == "table" and definition.LegacyToolNames or {}) do
		push_unique(names, legacyName)
	end

	return names
end

local function get_category_folder_name(definition)
	if not definition then
		return nil
	end

	if type(definition.ToolCategory) == "string" and definition.ToolCategory ~= "" then
		local ok, folderName = pcall(function()
			return ToolItemCatalog.GetCategoryFolderName(definition)
		end)

		if ok and type(folderName) == "string" and folderName ~= "" then
			return folderName
		end
	end

	if definition.Kind == "Seed" then
		return "Seeds"
	end

	if definition.Kind == "Fruit" then
		return "Fruits"
	end

	local inventoryPath = normalize_inventory_path(definition.InventoryPath)
	if inventoryPath == "Inventory.Consumables.Food" then
		return "Food"
	end

	return nil
end

local function find_named_asset(root, definition)
	if not root then
		return nil
	end

	for _, name in ipairs(get_search_names(definition)) do
		local asset = root:FindFirstChild(name, true)
		if asset then
			return asset
		end
	end

	return nil
end

local function resolve_asset(definition)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets or not definition then
		return nil
	end

	local items = assets:FindFirstChild("Items")
	local categoryName = get_category_folder_name(definition)
	local roots = {}

	local function add_root(root)
		if not root then
			return
		end

		for _, existing in ipairs(roots) do
			if existing == root then
				return
			end
		end

		roots[#roots + 1] = root
	end

	if type(definition.ViewportAssetPath) == "table" then
		add_root(find_path(assets, definition.ViewportAssetPath))
	end

	if type(definition.AssetPath) == "table" then
		add_root(find_path(assets, definition.AssetPath))
	end

	if categoryName then
		add_root(items and items:FindFirstChild(categoryName))
		add_root(assets:FindFirstChild(categoryName))
	end

	add_root(items and items:FindFirstChild("Food"))
	add_root(items and items:FindFirstChild("Fruits"))
	add_root(items and items:FindFirstChild("Seeds"))
	add_root(items)
	add_root(assets)

	for _, root in ipairs(roots) do
		if root == assets or root == items or root:IsA("Folder") then
			local asset = find_named_asset(root, definition)
			if asset then
				return asset
			end
		else
			return root
		end
	end

	return nil
end

local function render_viewport(viewport, definition)
	if not viewport or not viewport:IsA("ViewportFrame") then
		return
	end

	clear_viewport(viewport)

	local displayName = definition and (definition.DisplayName or definition.ItemId) or "Food"
	local model = prepare_preview_model(resolve_asset(definition), displayName)

	local ok = pcall(function()
		local boxCFrame, boxSize = model:GetBoundingBox()
		local worldModel = Instance.new("WorldModel")
		worldModel.Parent = viewport
		model.Parent = worldModel

		local camera = Instance.new("Camera")
		camera.FieldOfView = VIEWPORT_CONFIG.FieldOfView
		camera.Parent = viewport

		local focus = boxCFrame.Position + Vector3.new(0, boxSize.Y * VIEWPORT_CONFIG.FocusYOffsetScale, 0)
		local largest = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1)
		local radius = largest * VIEWPORT_CONFIG.RadiusScale
		local distance = math.max(2, radius / math.tan(math.rad(camera.FieldOfView * 0.5)))
		local offset = Vector3.new(
			distance * VIEWPORT_CONFIG.CameraOffset.X,
			distance * VIEWPORT_CONFIG.CameraOffset.Y,
			distance * VIEWPORT_CONFIG.CameraOffset.Z
		)

		camera.CFrame = CFrame.lookAt(focus + offset, focus)
		viewport.BackgroundTransparency = 1
		viewport.Ambient = Color3.fromRGB(220, 220, 220)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		viewport.CurrentCamera = camera
	end)

	if not ok then
		clear_viewport(viewport)
		model:Destroy()
	end
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
	local stroke = card:FindFirstChildWhichIsA("UIStroke", true)
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
	end

	stroke.Thickness = selected and 2.5 or 1
	stroke.Transparency = selected and 0 or 0.25
	stroke.Color = selected and Color3.fromRGB(255, 222, 129) or Color3.fromRGB(255, 255, 255)
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

local function refresh_ingredient_counts(recipe)
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

local function render_ingredients_lazy(recipe, token)
	if not currentUi or not currentUi.IngredientContainer then
		return
	end

	local ui = currentUi
	if token ~= panelToken or not is_ui_visible(ui.Root) or not ensure_template_sources(ui) then
		return
	end

	task.spawn(function()
		local pendingRows = {}
		local pendingEntries = {}

		local function destroy_pending_rows()
			for _, pending in ipairs(pendingRows) do
				if pending.Row and not pending.Row.Parent then
					pending.Row:Destroy()
				end
			end
		end

		for index, ingredient in ipairs(recipe.Ingredients) do
			if token ~= panelToken or currentUi ~= ui or not is_ui_visible(ui.Root) then
				destroy_pending_rows()
				return
			end

			local row = ui.IngredientTemplateSource:Clone()
			row.Name = ingredient.ItemId
			disable_hud_anim_tree(row)
			row.Visible = true
			row.LayoutOrder = index

			local nameLabel = find_text(row, { "IngredientName", "ItemNameTX", "ItemName" })
			local stockLabel = find_text(row, { "StockCountTX", "StockCount" })
			local viewport = find_path(row, { "HorseImage", "ViewportFrame" })
				or find_descendant(row, { "ViewportFrame", "ViewPortFrame", "Viewport" }, "ViewportFrame")
			local owned = get_definition_count(ingredient.Definition)
			local hasEnough = owned >= ingredient.Amount

			pendingEntries[#pendingEntries + 1] = {
				Ingredient = ingredient,
				StockLabel = stockLabel,
			}

			pendingRows[#pendingRows + 1] = {
				Row = row,
				Viewport = viewport,
				Definition = ingredient.Definition,
			}

			set_text(nameLabel, ingredient.DisplayName or ingredient.ToolName or ingredient.ItemId)
			set_text(stockLabel, ("%s/%s"):format(format_count(owned), format_count(ingredient.Amount)))
			set_text_color(stockLabel, hasEnough and ui.DefaultIngredientTextColor or INSUFFICIENT_COLOR)
		end

		if token ~= panelToken or currentUi ~= ui or not is_ui_visible(ui.Root) then
			destroy_pending_rows()
			return
		end

		ingredientTrove:Clean()
		ui.IngredientEntries = pendingEntries

		for _, pending in ipairs(pendingRows) do
			pending.Row.Parent = ui.IngredientContainer
			ingredientTrove:Add(pending.Row)
		end

		for _, pending in ipairs(pendingRows) do
			task.wait(LOAD_STEP_SECONDS)

			if token ~= panelToken or currentUi ~= ui or not is_ui_visible(ui.Root) then
				return
			end

			render_viewport(pending.Viewport, pending.Definition)
			task.wait(LOAD_STEP_SECONDS)
		end
	end)
end

local function refresh_selected_panel()
	if not currentUi then
		return
	end

	sync_selected_recipe()

	local recipe = get_selected_recipe()
	if not recipe then
		set_text(currentUi.FoodNameLabel, "")
		clear_viewport(currentUi.FoodViewport)
		ingredientTrove:Clean()
		currentUi.IngredientEntries = {}
		renderedPanelRecipeId = nil
		refresh_dynamic_ui()
		return
	end

	set_text(currentUi.FoodNameLabel, recipe.DisplayName)

	if renderedPanelRecipeId == recipe.RecipeId then
		refresh_ingredient_counts(recipe)
	else
		renderedPanelRecipeId = recipe.RecipeId
		panelToken += 1
		local token = panelToken
		local ui = currentUi

		clear_viewport(ui.FoodViewport)
		task.spawn(function()
			task.wait(LOAD_STEP_SECONDS)
			if token ~= panelToken or currentUi ~= ui or not is_ui_visible(ui.Root) then
				return
			end

			render_viewport(ui.FoodViewport, recipe.FoodDefinition)
		end)

		render_ingredients_lazy(recipe, token)
	end

	refresh_dynamic_ui()
end

local function refresh_all()
	if not currentUi then
		return
	end

	if not is_ui_visible(currentUi.Root) or not cardsBuilt then
		refreshPending = true
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

	local state = get_cooking_state()
	local activeRecipe = get_active_recipe(state)
	if activeRecipe and activeRecipe.RecipeId ~= recipe.RecipeId then
		return
	end

	selectedRecipeId = recipe.RecipeId
	refresh_all()
end

local function build_recipe_cards()
	if not currentUi then
		return
	end

	if cardsLoading then
		return
	end

	loadToken += 1
	local token = loadToken
	local ui = currentUi

	if not is_ui_visible(ui.Root) or not ensure_template_sources(ui) then
		refreshPending = true
		return
	end

	cardsLoading = true
	cardsBuilt = false
	cardTrove:Clean()
	table.clear(cardEntries)

	task.spawn(function()
		for index, recipe in ipairs(CookingCatalog.GetRecipes()) do
			if token ~= loadToken or currentUi ~= ui or not is_ui_visible(ui.Root) then
				if token == loadToken and currentUi == ui then
					cardsLoading = false
				end
				return
			end

			local card = ui.CardTemplateSource:Clone()
			card.Name = recipe.RecipeId
			disable_hud_anim_tree(card)
			card.Visible = true
			card.LayoutOrder = index
			card.Parent = ui.ListScrollingFrame
			cardTrove:Add(card)

			local button = find_descendant(card, { "PurchaseBT" }, "GuiButton")
			local buttonText = button and find_text(button, { "BTTX" }) or nil
			local nameLabel = find_text(card, { "ItemNameTX", "ItemName" })
			local stockLabel = find_text(card, { "StockCountTX", "StockCount" })
			local viewport = find_path(card, { "ImageLabel", "ViewportFrame" })
				or find_descendant(card, { "ViewportFrame", "ViewPortFrame", "Viewport" }, "ViewportFrame")

			set_text(nameLabel, recipe.DisplayName)
			set_text(buttonText, "Select")
			set_text(stockLabel, format_count(get_definition_count(recipe.FoodDefinition)))

			local entry = {
				Recipe = recipe,
				Card = card,
				Button = button,
				ButtonText = buttonText,
				StockLabel = stockLabel,
			}

			cardEntries[#cardEntries + 1] = entry
			FoodHoverTooltip.Bind(card, recipe.FoodDefinition, cardTrove)

			if button then
				cardTrove:Connect(button.Activated, function()
					select_recipe(recipe.RecipeId)
				end)
			end

			update_canvas_size(ui.ListScrollingFrame)
			task.wait(LOAD_STEP_SECONDS)

			if token ~= loadToken or currentUi ~= ui or not is_ui_visible(ui.Root) then
				if token == loadToken and currentUi == ui then
					cardsLoading = false
				end
				return
			end

			render_viewport(viewport, recipe.FoodDefinition)
			task.wait(LOAD_STEP_SECONDS)
		end

		if token ~= loadToken or currentUi ~= ui then
			if token == loadToken and currentUi == ui then
				cardsLoading = false
			end
			return
		end

		cardsLoading = false
		cardsBuilt = true
		update_canvas_size(ui.ListScrollingFrame)
		refreshPending = false
		refresh_all()
	end)
end

ensure_open_ui_loaded = function()
	if not currentUi then
		return
	end

	if not is_ui_visible(currentUi.Root) then
		refreshPending = true
		return
	end

	bind_data_paths()
	sync_selected_recipe()

	if not cardsBuilt then
		build_recipe_cards()
		return
	end

	if refreshPending then
		refreshPending = false
	end

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

local function cancel_deferred_loads()
	loadToken += 1
	panelToken += 1
	cardsLoading = false
end

local function destroy_ui_binding()
	cancel_deferred_loads()
	cardTrove:Clean()
	ingredientTrove:Clean()
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = nil
	dataBindingsReady = false
	cardsBuilt = false
	cardsLoading = false
	refreshPending = false
	renderedPanelRecipeId = nil
	uiWasVisible = false
	table.clear(cardEntries)
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

	local foodViewport = foodRoot and (find_path(foodRoot, { "HorseImage", "ViewportFrame" })
		or find_descendant(foodRoot, { "ViewportFrame", "ViewPortFrame", "Viewport" }, "ViewportFrame")) or nil
	if foodViewport and not foodViewport:IsA("ViewportFrame") then
		foodViewport = nil
	end

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
		FoodViewport = foodViewport,
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

	disable_hud_anim_tree(ui.ListScrollingFrame)
	disable_hud_anim_tree(ui.IngredientContainer)
	disable_hud_anim_tree(ui.CardTemplate)
	disable_hud_anim_tree(ui.IngredientTemplate)
	bind_open_hud_anim(ui.Root)
	ui.CardTemplate.Visible = false
	ui.IngredientTemplate.Visible = false

	if ui.FoodRoot then
		FoodHoverTooltip.Bind(ui.FoodRoot, function()
			local recipe = get_selected_recipe()
			return recipe and recipe.FoodDefinition or nil
		end, uiTrove)
	end

	ui.ListScrollingFrame.Active = true
	ui.ListScrollingFrame.ScrollingEnabled = true
	ui.ListScrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	ui.ListScrollingFrame.CanvasSize = UDim2.fromOffset(0, 0)

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
				cancel_deferred_loads()
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
	else
		refreshPending = true
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
		else
			refreshPending = true
		end

		queue_refresh_all()
	end)
end

initialize_data()
sync_selected_recipe()
try_bind_ui()

rootTrove:Connect(playerGui.DescendantAdded, function(instance)
	if matches_name(instance, MAIN_UI_NAMES)
		or matches_name(instance, MAINFRAME_NAMES)
		or matches_name(instance, FRAMES_NAMES)
		or matches_name(instance, COOKING_NAMES)
		or instance.Name == "TemplateCraft"
		or instance.Name == "Ingredient"
	then
		task.defer(try_bind_ui)
	end
end)

rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
	if currentUi and (instance == currentUi.Root or instance:IsDescendantOf(currentUi.Root)) then
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
			cancel_deferred_loads()
		end

		uiWasVisible = isVisible
	end

	refresh_dynamic_ui()
end)
