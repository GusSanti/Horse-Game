local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))
local InventoryLoadout = require(Utility:WaitForChild("InventoryLoadout"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"
local HUD_ROOT_NAME = "HUDFR"
local HOTBAR_NAME = "BottomFrameFR"
local TEMPLATE_NAME = "HotkeyBT"
local MONEY_TAB_NAME = "MoneyTabBG"
local MONEY_BG_NAME = "MoneyBG"
local MONEY_CONTAINER_NAME = "Money"
local CLICK_LAYER_NAME = "HotbarButton"
local MONEY_LABEL_NAMES = { "MoneyTX" }
local MONEY_SHADOW_LABEL_NAMES = { "MoneyShadowTX" }
local AMOUNT_LABEL_NAMES = { "AmountTX", "Quant" }
local AMOUNT_SHADOW_LABEL_NAMES = { "AmountShadowTX" }
local NAME_LABEL_NAMES = { "NameItem", "NameTX", "ItemName", "ItemNameTX" }
local BIND_INDICATOR_NAMES = { "Bind", "BindTX", "KeyBind", "KeyTX", "HotkeyTX" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }

local VIEWPORT_FIELD_OF_VIEW = 30
local VIEWPORT_RADIUS_SCALE = 0.42
local VIEWPORT_DISTANCE_MULTIPLIER = 1.55
local VIEWPORT_MIN_DISTANCE = 1.75
local VIEWPORT_FOCUS_Y_SCALE = 0.02
local VIEWPORT_CAMERA_OFFSET_SCALE = Vector3.new(0.08, 0.05, 1.15)
local MAX_HOTBAR_SLOTS = InventoryLoadout.MAX_HOTBAR_SLOTS or 9
local SELECTION_SCALE_NAME = "HotbarSelectionScale"
local SELECTED_SCALE = 1.1
local SELECTED_POP_SCALE = 1.22
local SELECTED_POP_TIME = 0.09
local SELECTED_SETTLE_TIME = 0.14
local DESELECT_TIME = 0.1

local KEYCODE_TO_SLOT_INDEX = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine] = 9,
}

local categoryOrderLookup = {}
for index, categoryId in ipairs(ToolItemCatalog.CategoryOrder or {}) do
	categoryOrderLookup[categoryId] = index
end

local uiRoot = nil
local hudRoot = nil
local hotbarFrame = nil
local hotbarTemplate = nil
local moneyLabel = nil
local moneyShadowLabel = nil
local slotInstances = {}
local slotTroves = {}
local orderedItemKeys = {}
local currentGroups = {}
local previewCache = {}
local refreshQueued = false
local stickySelectionKey = nil
local slotSelectionTweens = {}
local slotSelectionTokens = {}

local rootTrove = Trove.new()
local backpackTrove = Trove.new()
local characterTrove = Trove.new()
local uiTrove = Trove.new()

rootTrove:Add(backpackTrove)
rootTrove:Add(characterTrove)
rootTrove:Add(uiTrove)

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

local function get_string_attribute(instance: Instance, attributeName: string): string?
	local value = instance:GetAttribute(attributeName)
	if type(value) == "string" then
		return value
	end

	return nil
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

local function find_text_label(root: Instance?, aliases, recursive: boolean?): TextLabel?
	local instance = find_named_instance(root, aliases, "TextLabel", recursive)
	if instance then
		return instance :: TextLabel
	end

	return nil
end

local function find_gui_object(root: Instance?, aliases, recursive: boolean?): GuiObject?
	local instance = find_named_instance(root, aliases, "GuiObject", recursive)
	if instance then
		return instance :: GuiObject
	end

	return nil
end

local function format_amount(value): string
	return tostring(math.max(0, math.floor(tonumber(value) or 0)))
end

local function format_hotbar_quantity(value): string
	local amount = math.max(0, math.floor(tonumber(value) or 0))
	return string.format("%02d", amount)
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

local function get_bucket_item_count(bucket, itemId): number
	if type(bucket) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(bucket[itemId]) or 0))
end

local function get_inventory_quantity(itemId: string, inventoryPath: string?): number
	local normalizedInventoryPath = normalize_inventory_path(inventoryPath)
	if not normalizedInventoryPath then
		return 0
	end

	return get_bucket_item_count(DataUtility.client.get(normalizedInventoryPath), itemId)
end

local function disable_default_backpack()
	task.spawn(function()
		for _ = 1, 10 do
			local success = pcall(function()
				StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
			end)

			if success then
				return
			end

			task.wait(0.5)
		end
	end)
end

local function find_ui_root(): Instance?
	local directUi = playerGui:FindFirstChild(MAIN_UI_NAME)
	if directUi then
		return directUi
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant.Name == MAIN_UI_NAME then
			return descendant
		end
	end

	return nil
end

local function find_main_container(targetUiRoot: Instance?): Instance?
	if not targetUiRoot then
		return nil
	end

	local directMain = targetUiRoot:FindFirstChild(MAINFRAME_NAME)
	if directMain then
		return directMain
	end

	return targetUiRoot:FindFirstChild(MAINFRAME_NAME, true)
end

local function find_hud_container(mainContainer: Instance?): Instance?
	if not mainContainer then
		return nil
	end

	local directHud = mainContainer:FindFirstChild(HUD_ROOT_NAME)
	if directHud then
		return directHud
	end

	return mainContainer:FindFirstChild(HUD_ROOT_NAME, true)
end

local function find_hotbar_container(targetHudRoot: Instance?): Instance?
	if not targetHudRoot then
		return nil
	end

	local directHotbar = targetHudRoot:FindFirstChild(HOTBAR_NAME)
	if directHotbar then
		return directHotbar
	end

	return targetHudRoot:FindFirstChild(HOTBAR_NAME, true)
end

local function find_hotbar_template(targetHotbar: Instance?): GuiObject?
	return find_gui_object(targetHotbar, { TEMPLATE_NAME }, true)
end

local function find_money_labels(targetHudRoot: Instance?): (TextLabel?, TextLabel?)
	if not targetHudRoot then
		return nil, nil
	end

	local moneyTab = targetHudRoot:FindFirstChild(MONEY_TAB_NAME)
	if not moneyTab then
		moneyTab = targetHudRoot:FindFirstChild(MONEY_TAB_NAME, true)
	end

	local moneyRoot = moneyTab
	if moneyRoot then
		local moneyBackground = moneyRoot:FindFirstChild(MONEY_BG_NAME) or moneyRoot:FindFirstChild(MONEY_BG_NAME, true)
		if moneyBackground then
			moneyRoot = moneyBackground
		end

		local moneyContainer = moneyRoot:FindFirstChild(MONEY_CONTAINER_NAME) or moneyRoot:FindFirstChild(MONEY_CONTAINER_NAME, true)
		if moneyContainer then
			moneyRoot = moneyContainer
		end
	end

	local searchRoot = moneyRoot or targetHudRoot
	local primaryLabel = find_text_label(searchRoot, MONEY_LABEL_NAMES, true)
	local shadowLabel = find_text_label(searchRoot, MONEY_SHADOW_LABEL_NAMES, true)

	return primaryLabel, shadowLabel
end

local function update_money_display()
	local text = format_amount(DataUtility.client.get("Currencies.Horseshoes"))

	if moneyLabel and moneyLabel.Parent then
		moneyLabel.Text = text
	end

	if moneyShadowLabel and moneyShadowLabel.Parent then
		moneyShadowLabel.Text = text
	end
end

local function set_gui_visible(instance: Instance?, isVisible: boolean)
	if not instance then
		return
	end

	if instance:IsA("GuiObject") then
		instance.Visible = isVisible
	elseif instance:IsA("LayerCollector") then
		instance.Enabled = isVisible
	end
end

local function destroy_slot(itemKey: string)
	local slot = slotInstances[itemKey]
	if slot then
		local tween = slotSelectionTweens[slot]
		if tween then
			tween:Cancel()
		end

		slotSelectionTweens[slot] = nil
		slotSelectionTokens[slot] = nil
	end

	local slotTrove = slotTroves[itemKey]
	if slotTrove then
		slotTrove:Destroy()
		slotTroves[itemKey] = nil
	end

	slotInstances[itemKey] = nil
end

local function clear_slots()
	local keysToDestroy = {}
	for itemKey in pairs(slotInstances) do
		keysToDestroy[#keysToDestroy + 1] = itemKey
	end

	for _, itemKey in ipairs(keysToDestroy) do
		destroy_slot(itemKey)
	end

	table.clear(orderedItemKeys)
end

local function set_stroke_selected(stroke: UIStroke, isSelected: boolean)
	stroke.Color = isSelected and Color3.fromRGB(255, 230, 154) or Color3.fromRGB(255, 255, 255)
	stroke.Thickness = isSelected and 2.5 or 1
	stroke.Transparency = isSelected and 0 or 0.15
end

local function get_selection_scale(slot: GuiObject): UIScale
	local existingScale = slot:FindFirstChild(SELECTION_SCALE_NAME)
	if existingScale and existingScale:IsA("UIScale") then
		return existingScale
	end

	if existingScale then
		existingScale:Destroy()
	end

	local scale = Instance.new("UIScale")
	scale.Name = SELECTION_SCALE_NAME
	scale.Scale = 1
	scale.Parent = slot
	return scale
end

local function play_scale_tween(slot: GuiObject, scaleValue: number, duration: number, easingStyle, easingDirection)
	local scale = get_selection_scale(slot)
	local currentTween = slotSelectionTweens[slot]
	if currentTween then
		currentTween:Cancel()
	end

	local tween = TweenService:Create(
		scale,
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Quad, easingDirection or Enum.EasingDirection.Out),
		{ Scale = scaleValue }
	)

	slotSelectionTweens[slot] = tween
	tween.Completed:Connect(function()
		if slotSelectionTweens[slot] == tween then
			slotSelectionTweens[slot] = nil
		end
	end)
	tween:Play()
	return tween
end

local function set_slot_layer(slot: GuiObject, isSelected: boolean)
	local baseZIndex = slot:GetAttribute("HotbarBaseZIndex")
	if type(baseZIndex) ~= "number" then
		baseZIndex = slot.ZIndex
		slot:SetAttribute("HotbarBaseZIndex", baseZIndex)
	end

	slot.ZIndex = isSelected and baseZIndex + 10 or baseZIndex
end

local function animate_slot_selection(slot: GuiObject, isSelected: boolean)
	local wasSelected = slot:GetAttribute("HotbarSelected") == true
	local scale = get_selection_scale(slot)

	if wasSelected == isSelected then
		local targetScale = isSelected and SELECTED_SCALE or 1
		if not slotSelectionTweens[slot] and math.abs(scale.Scale - targetScale) > 0.02 then
			scale.Scale = targetScale
		end
		set_slot_layer(slot, isSelected)
		return
	end

	slot:SetAttribute("HotbarSelected", isSelected)
	slotSelectionTokens[slot] = (slotSelectionTokens[slot] or 0) + 1
	local token = slotSelectionTokens[slot]

	set_slot_layer(slot, isSelected)

	if not isSelected then
		play_scale_tween(slot, 1, DESELECT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		return
	end

	task.spawn(function()
		local popTween = play_scale_tween(slot, SELECTED_POP_SCALE, SELECTED_POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		popTween.Completed:Wait()

		if slotSelectionTokens[slot] ~= token or slot:GetAttribute("HotbarSelected") ~= true or not slot.Parent then
			return
		end

		play_scale_tween(slot, SELECTED_SCALE, SELECTED_SETTLE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end)
end

local function set_bind_indicator(slot: GuiObject, slotIndex: number)
	local bindText = tostring(slotIndex)

	for _, descendant in ipairs(slot:GetDescendants()) do
		if matches_alias(descendant, BIND_INDICATOR_NAMES) then
			if descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
				descendant.Text = bindText
			end

			if descendant:IsA("GuiObject") then
				descendant.Visible = true
			end
		end
	end
end

local function strip_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function get_item_search_names(itemDefinition): { string }
	local names = {}
	local seen = {}

	local function push(value)
		if type(value) ~= "string" or value == "" or seen[value] then
			return
		end

		seen[value] = true
		names[#names + 1] = value
	end

	push(itemDefinition.ToolName)
	push(itemDefinition.DisplayName)
	push(itemDefinition.ItemId)

	return names
end

local function find_first_named_asset(root: Instance?, itemDefinition): Instance?
	if not root then
		return nil
	end

	for _, name in ipairs(get_item_search_names(itemDefinition)) do
		local found = root:FindFirstChild(name, true)
		if found then
			return found
		end
	end

	return nil
end

local function get_assets_items_root(): Instance?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		return nil
	end

	return assetsFolder:FindFirstChild("Items")
end

local function get_catalog_render_source(itemDefinition): Instance?
	local itemsFolder = get_assets_items_root()
	if not itemsFolder then
		return nil
	end

	local categoryFolderName = ToolItemCatalog.GetCategoryFolderName(itemDefinition)
	local categoryFolder = itemsFolder:FindFirstChild(categoryFolderName)
	if categoryFolder and categoryFolder:IsA("Folder") then
		local categoryMatch = find_first_named_asset(categoryFolder, itemDefinition)
		if categoryMatch then
			return categoryMatch
		end
	end

	return find_first_named_asset(itemsFolder, itemDefinition)
end

local function get_farming_render_source(itemDefinition): Instance?
	return FarmingUtility.GetViewportAsset(itemDefinition) or FarmingUtility.GetItemAsset(itemDefinition)
end

local function get_tool_key(tool: Tool): string
	local farmingItemId = normalize_key(get_string_attribute(tool, FarmingUtility.FARMING_ITEM_ATTRIBUTE))
	if farmingItemId then
		return farmingItemId
	end

	local explicitItemId = normalize_key(get_string_attribute(tool, "ToolItemId"))
		or normalize_key(get_string_attribute(tool, "ItemId"))
	if explicitItemId then
		return explicitItemId
	end

	return normalize_key(tool.Name) or tool.Name
end

local function resolve_tool_metadata(tool: Tool)
	local farmingItemId = tool:GetAttribute(FarmingUtility.FARMING_ITEM_ATTRIBUTE)
	if type(farmingItemId) == "string" and farmingItemId ~= "" then
		local farmingDefinition = FarmingCatalog.GetItem(farmingItemId)
		if farmingDefinition then
			local quantity = get_inventory_quantity(farmingDefinition.ItemId, farmingDefinition.InventoryPath)
			return {
				Key = farmingDefinition.ItemId,
				DisplayName = farmingDefinition.DisplayName or tool.Name,
				SortCategory = farmingDefinition.Kind == "Seed"
					and (categoryOrderLookup.Seeds or math.huge)
					or (categoryOrderLookup.Food or math.huge),
				SortOrder = farmingDefinition.SortOrder or math.huge,
				RenderSource = get_farming_render_source(farmingDefinition) or tool,
				Quantity = math.max(quantity, 1),
				ShowsQuantity = quantity > 1,
			}
		end
	end

	local toolDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
	if toolDefinition then
		local quantity = get_inventory_quantity(toolDefinition.ItemId, toolDefinition.InventoryPath)
		local isDefaultItem = InventoryLoadout.IsDefaultItemId(toolDefinition.ItemId)
		return {
			Key = toolDefinition.ItemId,
			DisplayName = toolDefinition.DisplayName or tool.Name,
			SortCategory = categoryOrderLookup[toolDefinition.ToolCategory] or math.huge,
			SortOrder = toolDefinition.SortOrder or math.huge,
			RenderSource = get_catalog_render_source(toolDefinition) or tool,
			Quantity = math.max(quantity, 1),
			ShowsQuantity = not isDefaultItem and quantity > 1,
		}
	end

	return {
		Key = get_tool_key(tool),
		DisplayName = tool.Name,
		SortCategory = math.huge,
		SortOrder = math.huge,
		RenderSource = tool,
		Quantity = 1,
		ShowsQuantity = false,
	}
end

local function collect_render_parts(root: Instance): { BasePart }
	local baseParts = {}

	if root:IsA("BasePart") then
		baseParts[#baseParts + 1] = root
		return baseParts
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			baseParts[#baseParts + 1] = descendant
		end
	end

	return baseParts
end

local function create_fallback_preview_model(displayName: string): Model
	local model = Instance.new("Model")
	model.Name = ("%sPreview"):format(displayName)

	local part = Instance.new("Part")
	part.Name = "Preview"
	part.Size = Vector3.new(1.4, 1.4, 1.4)
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Color3.fromRGB(220, 220, 220)
	part.Parent = model

	return model
end

local function create_preview_model(source: Instance?, displayName: string): Model
	if not source then
		return create_fallback_preview_model(displayName)
	end

	local sourceClone = source:Clone()
	strip_scripts(sourceClone)

	local previewModel = nil

	if sourceClone:IsA("Model") then
		previewModel = sourceClone
	elseif sourceClone:IsA("Tool") or sourceClone:IsA("Folder") then
		previewModel = Instance.new("Model")
		previewModel.Name = sourceClone.Name

		for _, child in ipairs(sourceClone:GetChildren()) do
			child.Parent = previewModel
		end

		sourceClone:Destroy()
	elseif sourceClone:IsA("BasePart") then
		previewModel = Instance.new("Model")
		previewModel.Name = sourceClone.Name
		sourceClone.Parent = previewModel
	else
		sourceClone:Destroy()
		return create_fallback_preview_model(displayName)
	end

	local baseParts = collect_render_parts(previewModel)
	if #baseParts == 0 then
		previewModel:Destroy()
		return create_fallback_preview_model(displayName)
	end

	for _, basePart in ipairs(baseParts) do
		basePart.Anchored = true
		basePart.CanCollide = false
		basePart.CanTouch = false
		basePart.CanQuery = false
		basePart.CastShadow = false
	end

	previewModel:PivotTo(CFrame.new())

	return previewModel
end

local function get_preview_snapshot(itemKey: string, source: Instance?, displayName: string)
	local cachedPreview = previewCache[itemKey]
	if cachedPreview then
		return cachedPreview
	end

	local previewModel = create_preview_model(source, displayName)
	local boundingBoxCFrame, boundingBoxSize = previewModel:GetBoundingBox()
	local maxDimension = math.max(boundingBoxSize.X, boundingBoxSize.Y, boundingBoxSize.Z, 1)
	local focusPosition = boundingBoxCFrame.Position + Vector3.new(0, boundingBoxSize.Y * VIEWPORT_FOCUS_Y_SCALE, 0)
	local radius = maxDimension * VIEWPORT_RADIUS_SCALE
	local distance = math.max(
		VIEWPORT_MIN_DISTANCE,
		(radius / math.tan(math.rad(VIEWPORT_FIELD_OF_VIEW * 0.5))) * VIEWPORT_DISTANCE_MULTIPLIER
	)

	local cameraOffset = Vector3.new(
		distance * VIEWPORT_CAMERA_OFFSET_SCALE.X,
		distance * VIEWPORT_CAMERA_OFFSET_SCALE.Y,
		distance * VIEWPORT_CAMERA_OFFSET_SCALE.Z
	)

	cachedPreview = {
		ModelTemplate = previewModel,
		FieldOfView = VIEWPORT_FIELD_OF_VIEW,
		CameraCFrame = CFrame.lookAt(focusPosition + cameraOffset, focusPosition),
	}

	previewCache[itemKey] = cachedPreview
	return cachedPreview
end

local function render_viewport(viewportFrame: ViewportFrame, itemKey: string, source: Instance?, displayName: string)
	for _, child in ipairs(viewportFrame:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	local snapshot = get_preview_snapshot(itemKey, source, displayName)

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "HotbarWorldModel"
	worldModel.Parent = viewportFrame

	snapshot.ModelTemplate:Clone().Parent = worldModel

	local camera = Instance.new("Camera")
	camera.Name = "HotbarCamera"
	camera.FieldOfView = snapshot.FieldOfView
	camera.CFrame = snapshot.CameraCFrame
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera
end

local function create_click_target(slot: GuiObject): GuiButton
	if slot:IsA("GuiButton") then
		return slot
	end

	local existingButton = slot:FindFirstChild(CLICK_LAYER_NAME)
	if existingButton and existingButton:IsA("GuiButton") then
		return existingButton
	end

	local button = Instance.new("TextButton")
	button.Name = CLICK_LAYER_NAME
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromScale(1, 1)
	button.Position = UDim2.fromScale(0, 0)
	button.ZIndex = slot.ZIndex + 20
	button.Parent = slot

	return button
end

local function set_slot_selected(slot: GuiObject, isSelected: boolean)
	local stroke = slot:FindFirstChildWhichIsA("UIStroke", true)
	if stroke then
		set_stroke_selected(stroke, isSelected)
	end

	animate_slot_selection(slot, isSelected)
end

local function get_equipped_group_key(groups): string?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	for itemKey, group in pairs(groups) do
		if group.EquippedTool and group.EquippedTool.Parent == character then
			return itemKey
		end
	end

	return nil
end

local function build_groups()
	local groups = {}
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")
	local character = localPlayer.Character

	local function add_tool(tool: Tool)
		local metadata = resolve_tool_metadata(tool)
		local itemKey = metadata.Key
		if type(itemKey) ~= "string" or itemKey == "" then
			return
		end

		local existingGroup = groups[itemKey]
		if not existingGroup then
			existingGroup = {
				Key = itemKey,
				DisplayName = metadata.DisplayName,
				SortCategory = metadata.SortCategory,
				SortOrder = metadata.SortOrder,
				RenderSource = metadata.RenderSource or tool,
				Quantity = metadata.Quantity or 1,
				ShowsQuantity = metadata.ShowsQuantity == true,
				Tools = {},
				EquippedTool = nil,
			}
			groups[itemKey] = existingGroup
		end

		existingGroup.Quantity = math.max(existingGroup.Quantity or 1, metadata.Quantity or 1)
		existingGroup.ShowsQuantity = existingGroup.ShowsQuantity or metadata.ShowsQuantity == true

		existingGroup.Tools[#existingGroup.Tools + 1] = tool

		if character and tool.Parent == character then
			existingGroup.EquippedTool = tool
		end
	end

	if backpack then
		for _, child in ipairs(backpack:GetChildren()) do
			if child:IsA("Tool") then
				add_tool(child)
			end
		end
	end

	if character then
		for _, child in ipairs(character:GetChildren()) do
			if child:IsA("Tool") then
				add_tool(child)
			end
		end
	end

	return groups
end

local function compare_groups(left, right)
	local leftLoadoutOrder = left.LoadoutOrder or math.huge
	local rightLoadoutOrder = right.LoadoutOrder or math.huge

	if leftLoadoutOrder ~= rightLoadoutOrder then
		return leftLoadoutOrder < rightLoadoutOrder
	end

	if left.SortCategory ~= right.SortCategory then
		return left.SortCategory < right.SortCategory
	end

	if left.SortOrder ~= right.SortOrder then
		return left.SortOrder < right.SortOrder
	end

	return string.lower(left.DisplayName) < string.lower(right.DisplayName)
end

local function get_loadout_order_lookup()
	local lookup = {}
	local order = 1

	local function push(value)
		local normalizedValue = normalize_key(value)
		if not normalizedValue or lookup[normalizedValue] then
			return
		end

		lookup[normalizedValue] = order
		order += 1
	end

	for _, itemId in ipairs(DataUtility.client.get(InventoryLoadout.HOTBAR_ITEM_IDS_PATH) or {}) do
		push(itemId)
	end

	for _, toolName in ipairs(DataUtility.client.get(InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH) or {}) do
		push(toolName)
	end

	return lookup
end

local function get_group_array(groups): { any }
	local items = {}
	local loadoutOrderLookup = get_loadout_order_lookup()

	for _, group in pairs(groups) do
		local normalizedGroupKey = normalize_key(group.Key)
		group.LoadoutOrder = normalizedGroupKey and loadoutOrderLookup[normalizedGroupKey] or math.huge
		items[#items + 1] = group
	end

	table.sort(items, compare_groups)

	return items
end

local function equip_group(itemKey: string): boolean
	local group = currentGroups[itemKey]
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local backpack = localPlayer:FindFirstChildOfClass("Backpack")

	if not group or not humanoid or not backpack then
		return false
	end

	if group.EquippedTool and group.EquippedTool.Parent == character then
		return true
	end

	for _, tool in ipairs(group.Tools) do
		if tool.Parent == backpack then
			humanoid:EquipTool(tool)
			return true
		end
	end

	return false
end

local function toggle_group(itemKey: string)
	local group = currentGroups[itemKey]
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not group or not humanoid then
		return
	end

	if stickySelectionKey == itemKey and group.EquippedTool and group.EquippedTool.Parent == character then
		stickySelectionKey = nil
		humanoid:UnequipTools()
		return
	end

	stickySelectionKey = itemKey
	equip_group(itemKey)
end

local function update_slot(slot: GuiObject, group, slotIndex: number)
	slot.Name = group.Key
	slot.LayoutOrder = slotIndex
	set_gui_visible(slot, true)

	local nameLabel = find_text_label(slot, NAME_LABEL_NAMES, true)
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = group.DisplayName
	end

	set_bind_indicator(slot, slotIndex)

	local amountLabel = find_text_label(slot, AMOUNT_LABEL_NAMES, true)
	local showsQuantity = group.ShowsQuantity == true
	local amountText = showsQuantity and format_hotbar_quantity(group.Quantity or #group.Tools) or ""
	if amountLabel then
		amountLabel.Text = amountText
		amountLabel.Visible = showsQuantity
	end

	local amountShadowLabel = find_text_label(slot, AMOUNT_SHADOW_LABEL_NAMES, true)
	if amountShadowLabel then
		amountShadowLabel.Text = amountText
		amountShadowLabel.Visible = showsQuantity
	end

	local imageItem = find_named_instance(slot, { "ImageItem" }, nil, true)
	local viewportFrame = nil
	if imageItem then
		viewportFrame = find_named_instance(imageItem, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
	end

	if not viewportFrame then
		viewportFrame = find_named_instance(slot, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
	end

	if viewportFrame and slot:GetAttribute("HotbarPreviewReady") ~= true then
		render_viewport(viewportFrame :: ViewportFrame, group.Key, group.RenderSource, group.DisplayName)
		slot:SetAttribute("HotbarPreviewReady", true)
	end

	set_slot_selected(slot, stickySelectionKey == group.Key)
end

local function create_slot(group)
	local slot = hotbarTemplate:Clone()
	local slotTrove = Trove.new()

	slot:SetAttribute("HotbarPreviewReady", nil)
	slot.Parent = hotbarFrame
	slotInstances[group.Key] = slot
	slotTroves[group.Key] = slotTrove

	slotTrove:Add(slot)

	local clickTarget = create_click_target(slot)
	slotTrove:Connect(clickTarget.Activated, function()
		toggle_group(group.Key)
	end)

	return slot
end

local function rebuild_hotbar()
	refreshQueued = false
	currentGroups = build_groups()

	if not hotbarFrame or not hotbarTemplate or not hotbarTemplate.Parent then
		clear_slots()
		return
	end

	local groupArray = get_group_array(currentGroups)
	local equippedKey = get_equipped_group_key(currentGroups)

	if equippedKey then
		stickySelectionKey = equippedKey
	elseif stickySelectionKey and not currentGroups[stickySelectionKey] then
		stickySelectionKey = nil
	end

	table.clear(orderedItemKeys)

	local activeKeys = {}
	for index, group in ipairs(groupArray) do
		if index > MAX_HOTBAR_SLOTS then
			break
		end

		activeKeys[group.Key] = true
		orderedItemKeys[index] = group.Key

		local slot = slotInstances[group.Key]
		if not slot or not slot.Parent then
			slot = create_slot(group)
		end

		update_slot(slot, group, index)
	end

	local removedKeys = {}
	for itemKey in pairs(slotInstances) do
		if not activeKeys[itemKey] then
			removedKeys[#removedKeys + 1] = itemKey
		end
	end

	for _, itemKey in ipairs(removedKeys) do
		destroy_slot(itemKey)
	end

	if stickySelectionKey and currentGroups[stickySelectionKey] and not equippedKey then
		task.defer(function()
			equip_group(stickySelectionKey)
		end)
	end
end

local function queue_refresh()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(rebuild_hotbar)
end

local function bind_backpack()
	backpackTrove:Clean()

	local backpack = localPlayer:FindFirstChildOfClass("Backpack") or localPlayer:WaitForChild("Backpack")

	backpackTrove:Connect(backpack.ChildAdded, function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	backpackTrove:Connect(backpack.ChildRemoved, function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)
end

local function bind_character(character: Model)
	characterTrove:Clean()
	stickySelectionKey = nil

	characterTrove:Connect(character.ChildAdded, function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	characterTrove:Connect(character.ChildRemoved, function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	queue_refresh()
end

local function try_bind_hotbar()
	local nextUiRoot = find_ui_root()
	local nextMain = find_main_container(nextUiRoot)
	local nextHudRoot = find_hud_container(nextMain)
	local nextHotbar = find_hotbar_container(nextHudRoot)
	local nextTemplate = find_hotbar_template(nextHotbar)
	local nextMoneyLabel, nextMoneyShadowLabel = find_money_labels(nextHudRoot)
	local hotbarChanged = hudRoot ~= nextHudRoot or hotbarFrame ~= nextHotbar or hotbarTemplate ~= nextTemplate

	uiRoot = nextUiRoot
	hudRoot = nextHudRoot
	moneyLabel = nextMoneyLabel
	moneyShadowLabel = nextMoneyShadowLabel
	update_money_display()

	if not nextUiRoot or not nextHudRoot or not nextHotbar or not nextTemplate then
		if hotbarFrame then
			clear_slots()
		end

		hotbarFrame = nextHotbar
		hotbarTemplate = nextTemplate
		return
	end

	if hotbarChanged then
		clear_slots()
	end

	hotbarFrame = nextHotbar
	hotbarTemplate = nextTemplate

	set_gui_visible(hotbarTemplate, false)
	queue_refresh()
end

local function bind_ui_watchers()
	uiTrove:Clean()

	uiTrove:Connect(playerGui.DescendantAdded, function(instance)
		if instance.Name == MAIN_UI_NAME
			or instance.Name == MAINFRAME_NAME
			or instance.Name == HUD_ROOT_NAME
			or instance.Name == HOTBAR_NAME
			or instance.Name == TEMPLATE_NAME
			or instance.Name == MONEY_TAB_NAME
			or instance.Name == MONEY_BG_NAME
			or instance.Name == MONEY_CONTAINER_NAME
			or instance.Name == "MoneyTX"
			or instance.Name == "MoneyShadowTX"
		then
			try_bind_hotbar()
		end
	end)

	uiTrove:Connect(playerGui.DescendantRemoving, function(instance)
		if instance == uiRoot or instance == hudRoot or instance == hotbarFrame or instance == hotbarTemplate then
			task.defer(try_bind_hotbar)
			return
		end

		if instance.Name == MAIN_UI_NAME
			or instance.Name == MAINFRAME_NAME
			or instance.Name == HUD_ROOT_NAME
			or instance.Name == HOTBAR_NAME
			or instance.Name == TEMPLATE_NAME
			or instance.Name == MONEY_TAB_NAME
			or instance.Name == MONEY_BG_NAME
			or instance.Name == MONEY_CONTAINER_NAME
			or instance.Name == "MoneyTX"
			or instance.Name == "MoneyShadowTX"
		then
			task.defer(try_bind_hotbar)
		end
	end)
end

rootTrove:Connect(UserInputService.InputBegan, function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	local slotIndex = KEYCODE_TO_SLOT_INDEX[input.KeyCode]
	if not slotIndex then
		return
	end

	local itemKey = orderedItemKeys[slotIndex]
	if not itemKey then
		return
	end

	toggle_group(itemKey)
end)

rootTrove:Connect(localPlayer.CharacterAdded, function(character)
	disable_default_backpack()
	bind_character(character)
	task.defer(bind_backpack)
end)

rootTrove:Connect(localPlayer.CharacterRemoving, function()
	characterTrove:Clean()
	queue_refresh()
end)

disable_default_backpack()
bind_backpack()
bind_ui_watchers()
try_bind_hotbar()
rootTrove:Add(DataUtility.client.bind("Currencies.Horseshoes", update_money_display))
for _, inventoryPath in ipairs({
	"Inventory.Seeds",
	"Inventory.Fruits",
	"Inventory.Consumables.Food",
	"Inventory.Consumables.Water",
	"Inventory.Consumables.Grooming",
	"Inventory.Consumables.Misc",
	"Inventory.Consumables.Medical",
}) do
	rootTrove:Add(DataUtility.client.bind(inventoryPath, queue_refresh))
end

for _, loadoutPath in ipairs({
	InventoryLoadout.HOTBAR_ITEM_IDS_PATH,
	InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH,
	InventoryLoadout.HOTBAR_INITIALIZED_PATH,
}) do
	rootTrove:Add(DataUtility.client.bind(loadoutPath, queue_refresh))
end

if localPlayer.Character then
	bind_character(localPlayer.Character)
else
	queue_refresh()
end