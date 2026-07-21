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
local MAINFRAME_NAMES = { "MainframeFR", "MainFrameFR" }
local HUD_ROOT_NAME = "HUDFR"
local FRAMES_CONTAINER_NAMES = { "Frames" }
local SHOP_FRAME_NAMES = { "Shop" }
local HOTBAR_NAME = "BottomFrameFR"
local TEMPLATE_NAME = "HotkeyBT"
local MONEY_TAB_NAME = "MoneyTabBG"
local MONEY_BG_NAME = "MoneyBG"
local MONEY_CONTAINER_NAME = "Money"
local MONEY_ADD_BUTTON_NAMES = { "AddBT" }
local CLICK_LAYER_NAME = "HotbarButton"
local ITEM_HAND_LABEL_NAME = "ItemHandTX"
local GENERATED_VIEWPORT_NAME = "ViewportFrame"
local MONEY_LABEL_NAMES = { "MoneyTX" }
local MONEY_SHADOW_LABEL_NAMES = { "MoneyShadowTX" }
local AMOUNT_LABEL_NAMES = { "AmountTX", "Quant" }
local AMOUNT_SHADOW_LABEL_NAMES = { "AmountShadowTX" }
local NAME_LABEL_NAMES = { "NameItem", "NameTX", "ItemName", "ItemNameTX" }
local BIND_INDICATOR_NAMES = { "Bind", "BindTX", "KeyBind", "KeyTX", "HotkeyTX" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }
local IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE = "IgnoreAutoFrameButton"

local VIEWPORT_FIELD_OF_VIEW = 30
local VIEWPORT_RADIUS_SCALE = 0.42
local VIEWPORT_DISTANCE_MULTIPLIER = 1.55
local VIEWPORT_MIN_DISTANCE = 1.75
local VIEWPORT_FOCUS_Y_SCALE = 0.02
local VIEWPORT_CAMERA_OFFSET_SCALE = Vector3.new(0.08, 0.05, 1.15)
local SEED_VIEWPORT_RADIUS_SCALE = 0.78
local SEED_VIEWPORT_DISTANCE_MULTIPLIER = 1.05
local SEED_VIEWPORT_MIN_DISTANCE = 0.55
local SEED_VIEWPORT_FOCUS_Y_SCALE = 0.04
local SEED_VIEWPORT_CAMERA_OFFSET_SCALE = Vector3.new(0.06, 0.08, 1.05)
local SEED_PREVIEW_CACHE_VERSION = "seed-preview-v2"
local SEED_PACKET_COLOR = Color3.fromRGB(227, 197, 148)
local SEED_PACKET_EDGE_COLOR = Color3.fromRGB(117, 83, 52)
local SEED_PACKET_STRIPE_COLOR = Color3.fromRGB(248, 231, 190)
local SEED_PREVIEW_COLOR_RULES = {
	{ "beetroot", Color3.fromRGB(137, 47, 92) },
	{ "carrot", Color3.fromRGB(236, 121, 43) },
	{ "corn", Color3.fromRGB(240, 193, 58) },
	{ "eggplant", Color3.fromRGB(96, 63, 144) },
	{ "garlic", Color3.fromRGB(235, 226, 199) },
	{ "grape", Color3.fromRGB(110, 73, 173) },
	{ "lettuce", Color3.fromRGB(93, 178, 77) },
	{ "pepper", Color3.fromRGB(204, 62, 52) },
	{ "pineapple", Color3.fromRGB(226, 165, 54) },
	{ "potato", Color3.fromRGB(166, 117, 72) },
	{ "pumpkin", Color3.fromRGB(220, 117, 41) },
	{ "radish", Color3.fromRGB(220, 67, 94) },
	{ "strawberry", Color3.fromRGB(211, 55, 65) },
	{ "tomato", Color3.fromRGB(216, 62, 55) },
	{ "wheat", Color3.fromRGB(214, 171, 72) },
}
local SEED_PREVIEW_FALLBACK_COLORS = {
	Color3.fromRGB(93, 178, 77),
	Color3.fromRGB(236, 121, 43),
	Color3.fromRGB(214, 171, 72),
	Color3.fromRGB(204, 62, 52),
	Color3.fromRGB(110, 73, 173),
}
local MAX_HOTBAR_SLOTS = InventoryLoadout.MAX_HOTBAR_SLOTS or 9
local SELECTION_SCALE_NAME = "HotbarSelectionScale"
local SELECTED_SCALE = 1.1
local SELECTED_POP_SCALE = 1.22
local SELECTED_POP_TIME = 0.09
local SELECTED_SETTLE_TIME = 0.14
local DESELECT_TIME = 0.1
local ITEM_HAND_FADE_TIME = 0.12
local MONEY_CHANGE_LABEL_NAME = "MoneyChangeFX"
local MONEY_CHANGE_IN_TIME = 0.12
local MONEY_CHANGE_FLOAT_TIME = 0.62
local MONEY_CHANGE_START_OFFSET = 4
local MONEY_CHANGE_FLOAT_DISTANCE = 42
local MONEY_CHANGE_MIN_WIDTH = 92
local MONEY_CHANGE_HEIGHT = 30
local MONEY_GAIN_COLOR = Color3.fromRGB(94, 255, 139)
local MONEY_LOSS_COLOR = Color3.fromRGB(255, 105, 105)
local MONEY_CHANGE_STROKE_COLOR = Color3.fromRGB(39, 24, 18)
local MAX_MONEY_CHANGE_EFFECTS = 5

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
local hotbarTemplateSource = nil
local moneyTabFrame = nil
local moneyLabel = nil
local moneyShadowLabel = nil
local itemHandLabel = nil
local slotInstances = {}
local slotTroves = {}
local orderedItemKeys = {}
local currentGroups = {}
local previewCache = {}
local refreshQueued = false
local stickySelectionKey = nil
local slotSelectionTweens = {}
local slotSelectionTokens = {}
local itemHandTweens = {}
local itemHandToken = 0
local itemHandOriginals = nil
local itemHandTargetKey = nil
local lastMoneyAmount = nil
local moneyChangeEffects = {}

local rootTrove = Trove.new()
local backpackTrove = Trove.new()
local characterTrove = Trove.new()
local uiTrove = Trove.new()
local moneyButtonTrove = Trove.new()

rootTrove:Add(backpackTrove)
rootTrove:Add(characterTrove)
rootTrove:Add(uiTrove)
rootTrove:Add(moneyButtonTrove)

local strip_scripts

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

local function find_gui_button(root: Instance?, aliases, recursive: boolean?): GuiButton?
	local instance = find_named_instance(root, aliases, "GuiButton", recursive)
	if instance then
		return instance :: GuiButton
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

	return find_named_instance(targetUiRoot, MAINFRAME_NAMES, nil, true)
end

local function find_frames_container(targetUiRoot: Instance?): Instance?
	local mainContainer = find_main_container(targetUiRoot)
	if not mainContainer then
		return nil
	end

	return find_named_instance(mainContainer, FRAMES_CONTAINER_NAMES, nil, true)
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

local function find_item_hand_label(targetHudRoot: Instance?): TextLabel?
	return find_text_label(targetHudRoot, { ITEM_HAND_LABEL_NAME }, true)
end

local function find_money_tab(targetHudRoot: Instance?): GuiObject?
	return find_gui_object(targetHudRoot, { MONEY_TAB_NAME }, false)
		or find_gui_object(targetHudRoot, { MONEY_TAB_NAME }, true)
end

local function find_money_labels(targetHudRoot: Instance?): (TextLabel?, TextLabel?)
	if not targetHudRoot then
		return nil, nil
	end

	local moneyRoot = find_money_tab(targetHudRoot)
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

local function get_money_amount(value): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function is_visible_in_gui_hierarchy(instance: GuiObject?): boolean
	local current: Instance? = instance

	while current and current:IsA("GuiObject") do
		if not current.Visible then
			return false
		end

		current = current.Parent
	end

	local layerCollector = instance and instance:FindFirstAncestorWhichIsA("LayerCollector")
	if layerCollector and layerCollector.Enabled == false then
		return false
	end

	return instance ~= nil
end

local function remove_money_change_effect(label: TextLabel)
	for index, effect in ipairs(moneyChangeEffects) do
		if effect == label then
			table.remove(moneyChangeEffects, index)
			break
		end
	end
end

local function clear_old_money_change_effects()
	while #moneyChangeEffects >= MAX_MONEY_CHANGE_EFFECTS do
		local oldEffect = table.remove(moneyChangeEffects, 1)
		if oldEffect and oldEffect.Parent then
			oldEffect:Destroy()
		end
	end
end

local function format_money_change(delta: number): string
	local prefix = if delta > 0 then "+" else "-"
	return prefix .. format_amount(math.abs(delta))
end

local function show_money_change_effect(delta: number)
	if delta == 0 then
		return
	end

	if not hudRoot or not hudRoot:IsA("GuiObject") then
		return
	end

	if not moneyTabFrame or not moneyTabFrame.Parent or not is_visible_in_gui_hierarchy(moneyTabFrame) then
		return
	end

	local rootGui = hudRoot :: GuiObject
	local tabGui = moneyTabFrame :: GuiObject
	local rootSize = rootGui.AbsoluteSize
	local tabSize = tabGui.AbsoluteSize
	if rootSize.X <= 0 or rootSize.Y <= 0 or tabSize.X <= 0 or tabSize.Y <= 0 then
		return
	end

	clear_old_money_change_effects()

	local relativePosition = tabGui.AbsolutePosition - rootGui.AbsolutePosition
	local centerX = relativePosition.X + tabSize.X * 0.5
	local startY = relativePosition.Y - MONEY_CHANGE_START_OFFSET
	local width = math.max(MONEY_CHANGE_MIN_WIDTH, tabSize.X * 0.9)
	local textColor = if delta > 0 then MONEY_GAIN_COLOR else MONEY_LOSS_COLOR

	local label = Instance.new("TextLabel")
	label.Name = MONEY_CHANGE_LABEL_NAME
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(centerX, startY)
	label.Size = UDim2.fromOffset(width, MONEY_CHANGE_HEIGHT)
	label.Font = Enum.Font.GothamBold
	label.Text = format_money_change(delta)
	label.TextColor3 = textColor
	label.TextScaled = true
	label.TextTransparency = 1
	label.TextStrokeColor3 = MONEY_CHANGE_STROKE_COLOR
	label.TextStrokeTransparency = 1
	label.ZIndex = math.max(tabGui.ZIndex + 20, 20)
	label.Parent = rootGui

	local scale = Instance.new("UIScale")
	scale.Scale = 0.86
	scale.Parent = label

	local stroke = Instance.new("UIStroke")
	stroke.Color = MONEY_CHANGE_STROKE_COLOR
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = label

	moneyChangeEffects[#moneyChangeEffects + 1] = label

	local inPosition = UDim2.fromOffset(centerX, startY - 8)
	local outPosition = UDim2.fromOffset(centerX, startY - MONEY_CHANGE_FLOAT_DISTANCE)
	local inTween = TweenService:Create(label, TweenInfo.new(MONEY_CHANGE_IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = inPosition,
		TextTransparency = 0,
		TextStrokeTransparency = 0.2,
	})
	local strokeInTween = TweenService:Create(stroke, TweenInfo.new(MONEY_CHANGE_IN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 0.15,
	})
	local scaleInTween = TweenService:Create(scale, TweenInfo.new(MONEY_CHANGE_IN_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1.08,
	})

	inTween:Play()
	strokeInTween:Play()
	scaleInTween:Play()

	task.delay(MONEY_CHANGE_IN_TIME, function()
		if not label or not label.Parent then
			return
		end

		local floatTween = TweenService:Create(label, TweenInfo.new(MONEY_CHANGE_FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = outPosition,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		local strokeOutTween = TweenService:Create(stroke, TweenInfo.new(MONEY_CHANGE_FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		})
		local scaleOutTween = TweenService:Create(scale, TweenInfo.new(MONEY_CHANGE_FLOAT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Scale = 1,
		})

		floatTween.Completed:Connect(function()
			remove_money_change_effect(label)
			if label.Parent then
				label:Destroy()
			end
		end)

		floatTween:Play()
		strokeOutTween:Play()
		scaleOutTween:Play()
	end)
end

local function cancel_item_hand_tweens()
	for _, tween in ipairs(itemHandTweens) do
		pcall(function()
			tween:Cancel()
		end)
	end

	table.clear(itemHandTweens)
end

local function get_item_hand_originals(label: TextLabel)
	if itemHandOriginals and itemHandOriginals.Label == label then
		return itemHandOriginals
	end

	itemHandOriginals = {
		Label = label,
		BackgroundTransparency = label.BackgroundTransparency,
		TextTransparency = label.TextTransparency,
		TextStrokeTransparency = label.TextStrokeTransparency,
	}

	return itemHandOriginals
end

local function set_item_hand_properties(label: TextLabel, properties)
	pcall(function()
		label.BackgroundTransparency = properties.BackgroundTransparency
		label.TextTransparency = properties.TextTransparency
		label.TextStrokeTransparency = properties.TextStrokeTransparency
	end)
end

local function update_item_hand_display(itemKey: string?, displayName: string?)
	local label = itemHandLabel
	if not label or not label.Parent then
		itemHandTargetKey = itemKey
		return
	end

	local shouldShow = type(itemKey) == "string" and itemKey ~= "" and type(displayName) == "string" and displayName ~= ""
	if itemHandTargetKey == itemKey and label.Visible == shouldShow and (not shouldShow or label.Text == displayName) then
		return
	end

	itemHandTargetKey = itemKey
	itemHandToken += 1
	local token = itemHandToken
	local originals = get_item_hand_originals(label)
	cancel_item_hand_tweens()

	if shouldShow then
		label.Text = displayName
		label.Visible = true
		set_item_hand_properties(label, {
			BackgroundTransparency = 1,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
	end

	local targetProperties = if shouldShow then {
			BackgroundTransparency = originals.BackgroundTransparency,
			TextTransparency = originals.TextTransparency,
			TextStrokeTransparency = originals.TextStrokeTransparency,
		} else {
			BackgroundTransparency = 1,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		}
	local tween = TweenService:Create(
		label,
		TweenInfo.new(ITEM_HAND_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		targetProperties
	)

	itemHandTweens[1] = tween
	tween:Play()

	task.delay(ITEM_HAND_FADE_TIME, function()
		if itemHandToken ~= token or not label or not label.Parent then
			return
		end

		table.clear(itemHandTweens)

		if shouldShow then
			set_item_hand_properties(label, originals)
			return
		end

		set_item_hand_properties(label, {
			BackgroundTransparency = 1,
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		label.Text = ""
		label.Visible = false
	end)
end

local function update_money_display(value, animateChange: boolean?)
	local amount = get_money_amount(if value ~= nil then value else DataUtility.client.get("Currencies.Horseshoes"))
	local previousAmount = lastMoneyAmount
	local text = format_amount(amount)

	if moneyLabel and moneyLabel.Parent then
		moneyLabel.Text = text
	end

	if moneyShadowLabel and moneyShadowLabel.Parent then
		moneyShadowLabel.Text = text
	end

	lastMoneyAmount = amount

	if animateChange == false or previousAmount == nil or previousAmount == amount then
		return
	end

	show_money_change_effect(amount - previousAmount)
end

local function find_money_add_button(targetHudRoot: Instance?): GuiButton?
	if not targetHudRoot then
		return nil
	end

	local moneyTab = find_money_tab(targetHudRoot)
	return find_gui_button(moneyTab, MONEY_ADD_BUTTON_NAMES, true)
end

local function open_robux_coin_shop()
	local framesContainer = find_frames_container(find_ui_root())
	if not framesContainer then
		return
	end

	local shopFrame = find_gui_object(framesContainer, SHOP_FRAME_NAMES, false)
		or find_gui_object(framesContainer, SHOP_FRAME_NAMES, true)
	if not shopFrame then
		return
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if child ~= shopFrame and child:IsA("GuiObject") then
			child.Visible = false
		end
	end

	shopFrame.Visible = true
end

local function bind_money_add_button(targetHudRoot: Instance?)
	moneyButtonTrove:Clean()

	local addButton = find_money_add_button(targetHudRoot)
	if not addButton then
		return
	end

	addButton:SetAttribute(IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE, true)
	moneyButtonTrove:Connect(addButton.Activated, open_robux_coin_shop)
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

local function find_direct_child_by_name(parent: Instance, childName: string): Instance?
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == childName then
			return child
		end
	end

	return nil
end

local function build_relative_path(root: Instance, target: Instance): { string }
	local segments = {}
	local current = target

	while current and current ~= root do
		table.insert(segments, 1, current.Name)
		current = current.Parent
	end

	return segments
end

local function find_by_relative_path(root: Instance, pathSegments: { string }): Instance?
	local current = root

	for _, segment in ipairs(pathSegments) do
		local nextNode = find_direct_child_by_name(current, segment)
		if not nextNode then
			return nil
		end

		current = nextNode
	end

	return current
end

local function copy_instance_property(source: Instance, target: Instance, propertyName: string)
	pcall(function()
		target[propertyName] = source[propertyName]
	end)
end

local function restore_template_gui_state(sourceRoot: Instance?, targetRoot: Instance?)
	if not sourceRoot or not targetRoot then
		return
	end

	local function restore_pair(sourceInstance: Instance, targetInstance: Instance)
		if sourceInstance:IsA("GuiObject") and targetInstance:IsA("GuiObject") then
			for _, propertyName in ipairs({
				"AnchorPoint",
				"AutomaticSize",
				"BackgroundColor3",
				"BackgroundTransparency",
				"BorderColor3",
				"BorderSizePixel",
				"ClipsDescendants",
				"Position",
				"Rotation",
				"Size",
				"Visible",
				"ZIndex",
			}) do
				copy_instance_property(sourceInstance, targetInstance, propertyName)
			end
		end

		if sourceInstance:IsA("ImageLabel") or sourceInstance:IsA("ImageButton") then
			for _, propertyName in ipairs({
				"Image",
				"ImageColor3",
				"ImageRectOffset",
				"ImageRectSize",
				"ImageTransparency",
				"ScaleType",
				"SliceCenter",
				"SliceScale",
			}) do
				copy_instance_property(sourceInstance, targetInstance, propertyName)
			end
		end

		if sourceInstance:IsA("TextLabel")
			or sourceInstance:IsA("TextButton")
			or sourceInstance:IsA("TextBox")
		then
			for _, propertyName in ipairs({
				"Font",
				"TextColor3",
				"TextScaled",
				"TextSize",
				"TextStrokeColor3",
				"TextStrokeTransparency",
				"TextTransparency",
				"TextWrapped",
			}) do
				copy_instance_property(sourceInstance, targetInstance, propertyName)
			end
		end

		if sourceInstance:IsA("UIStroke") and targetInstance:IsA("UIStroke") then
			for _, propertyName in ipairs({
				"ApplyStrokeMode",
				"Color",
				"Enabled",
				"LineJoinMode",
				"Thickness",
				"Transparency",
			}) do
				copy_instance_property(sourceInstance, targetInstance, propertyName)
			end
		end

		if sourceInstance:IsA("UIScale") and targetInstance:IsA("UIScale") then
			copy_instance_property(sourceInstance, targetInstance, "Scale")
		end
	end

	restore_pair(sourceRoot, targetRoot)

	for _, sourceDescendant in ipairs(sourceRoot:GetDescendants()) do
		local targetDescendant = find_by_relative_path(targetRoot, build_relative_path(sourceRoot, sourceDescendant))
		if targetDescendant then
			restore_pair(sourceDescendant, targetDescendant)
		end
	end
end

local function make_template_source(template: GuiObject): GuiObject
	local source = template:Clone()
	source.Visible = true
	strip_scripts(source)
	set_gui_visible(template, false)
	return source
end

local function destroy_hotbar_template_source()
	if hotbarTemplateSource then
		hotbarTemplateSource:Destroy()
		hotbarTemplateSource = nil
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

strip_scripts = function(root: Instance)
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
				IsSeed = farmingDefinition.Kind == "Seed",
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
			IsSeed = false,
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
		IsSeed = false,
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

local function get_seed_preview_color(itemKey: string?, displayName: string?): Color3
	local normalizedKey = normalize_key(itemKey)
	local normalizedDisplayName = normalize_key(displayName)

	for _, rule in ipairs(SEED_PREVIEW_COLOR_RULES) do
		local token = rule[1]
		if (normalizedKey and string.find(normalizedKey, token, 1, true))
			or (normalizedDisplayName and string.find(normalizedDisplayName, token, 1, true))
		then
			return rule[2]
		end
	end

	local source = normalizedKey or normalizedDisplayName or "seed"
	local hash = 0
	for index = 1, #source do
		hash += string.byte(source, index) or 0
	end

	return SEED_PREVIEW_FALLBACK_COLORS[(hash % #SEED_PREVIEW_FALLBACK_COLORS) + 1]
end

local function configure_preview_part(part: BasePart, color: Color3, material)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = material or Enum.Material.SmoothPlastic
	part.Color = color
end

local function create_preview_part(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	configure_preview_part(part, color, material)
	part.Parent = parent
	return part
end

local function create_seed_disc(
	parent: Instance,
	name: string,
	position: Vector3,
	scale: Vector3,
	color: Color3
): Part
	local part = create_preview_part(parent, name, Vector3.new(1, 1, 1), CFrame.new(position), color, Enum.Material.SmoothPlastic)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = scale
	mesh.Parent = part
	return part
end

local function create_seed_preview_model(displayName: string, itemKey: string?): Model
	local model = Instance.new("Model")
	model.Name = ("%sSeedPreview"):format(displayName or "Seed")

	local cropColor = get_seed_preview_color(itemKey, displayName)
	create_preview_part(model, "Packet", Vector3.new(1.28, 1.54, 0.12), CFrame.new(0, 0, 0), SEED_PACKET_COLOR, Enum.Material.SmoothPlastic)
	create_preview_part(model, "TopStripe", Vector3.new(1.12, 0.22, 0.14), CFrame.new(0, 0.54, 0.05), SEED_PACKET_STRIPE_COLOR, Enum.Material.SmoothPlastic)
	create_preview_part(model, "BottomStripe", Vector3.new(1.12, 0.16, 0.14), CFrame.new(0, -0.55, 0.05), SEED_PACKET_EDGE_COLOR, Enum.Material.SmoothPlastic)
	create_preview_part(model, "ColorPatch", Vector3.new(0.66, 0.54, 0.16), CFrame.new(0, -0.03, 0.1), cropColor, Enum.Material.SmoothPlastic)

	create_seed_disc(model, "SeedA", Vector3.new(-0.16, 0.02, 0.23), Vector3.new(0.22, 0.31, 0.06), Color3.fromRGB(65, 56, 37))
	create_seed_disc(model, "SeedB", Vector3.new(0.13, -0.09, 0.23), Vector3.new(0.2, 0.29, 0.06), Color3.fromRGB(83, 66, 38))
	create_seed_disc(model, "Highlight", Vector3.new(-0.08, 0.24, 0.24), Vector3.new(0.22, 0.08, 0.02), Color3.fromRGB(255, 245, 202))

	model:PivotTo(CFrame.new())
	return model
end

local function create_preview_model(source: Instance?, displayName: string, isSeed: boolean?, itemKey: string?): Model
	if isSeed then
		return create_seed_preview_model(displayName, itemKey)
	end

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
		configure_preview_part(basePart, basePart.Color, basePart.Material)
	end

	previewModel:PivotTo(CFrame.new())

	return previewModel
end

local function get_preview_cache_key(itemKey: string, source: Instance?, isSeed: boolean): string
	local sourceKey = "fallback"

	if isSeed then
		sourceKey = SEED_PREVIEW_CACHE_VERSION
	elseif source then
		local success, fullName = pcall(function()
			return source:GetFullName()
		end)

		sourceKey = if success and type(fullName) == "string" then fullName else source.Name
	end

	return table.concat({
		itemKey,
		sourceKey,
		if isSeed then "seed" else "item",
	}, "|")
end

local function get_preview_snapshot(itemKey: string, source: Instance?, displayName: string, isSeed: boolean)
	local previewKey = get_preview_cache_key(itemKey, source, isSeed)
	local cachedPreview = previewCache[previewKey]
	if cachedPreview then
		return cachedPreview
	end

	local previewModel = create_preview_model(source, displayName, isSeed, itemKey)
	local boundingBoxCFrame, boundingBoxSize = previewModel:GetBoundingBox()
	local maxDimension = math.max(boundingBoxSize.X, boundingBoxSize.Y, boundingBoxSize.Z, if isSeed then 0.2 else 1)
	local focusYOffsetScale = if isSeed then SEED_VIEWPORT_FOCUS_Y_SCALE else VIEWPORT_FOCUS_Y_SCALE
	local radiusScale = if isSeed then SEED_VIEWPORT_RADIUS_SCALE else VIEWPORT_RADIUS_SCALE
	local distanceMultiplier = if isSeed then SEED_VIEWPORT_DISTANCE_MULTIPLIER else VIEWPORT_DISTANCE_MULTIPLIER
	local minDistance = if isSeed then SEED_VIEWPORT_MIN_DISTANCE else VIEWPORT_MIN_DISTANCE
	local cameraOffsetScale = if isSeed then SEED_VIEWPORT_CAMERA_OFFSET_SCALE else VIEWPORT_CAMERA_OFFSET_SCALE
	local focusPosition = boundingBoxCFrame.Position + Vector3.new(0, boundingBoxSize.Y * focusYOffsetScale, 0)
	local radius = maxDimension * radiusScale
	local distance = math.max(
		minDistance,
		(radius / math.tan(math.rad(VIEWPORT_FIELD_OF_VIEW * 0.5))) * distanceMultiplier
	)

	local cameraOffset = Vector3.new(
		distance * cameraOffsetScale.X,
		distance * cameraOffsetScale.Y,
		distance * cameraOffsetScale.Z
	)

	cachedPreview = {
		ModelTemplate = previewModel,
		FieldOfView = VIEWPORT_FIELD_OF_VIEW,
		CameraCFrame = CFrame.lookAt(focusPosition + cameraOffset, focusPosition),
	}

	previewCache[previewKey] = cachedPreview
	return cachedPreview
end

local function render_viewport(viewportFrame: ViewportFrame, itemKey: string, source: Instance?, displayName: string, isSeed: boolean)
	for _, child in ipairs(viewportFrame:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	local snapshot = get_preview_snapshot(itemKey, source, displayName, isSeed)

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
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.Ambient = Color3.fromRGB(220, 220, 220)
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
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
				IsSeed = metadata.IsSeed == true,
				Tools = {},
				EquippedTool = nil,
			}
			groups[itemKey] = existingGroup
		end

		existingGroup.Quantity = math.max(existingGroup.Quantity or 1, metadata.Quantity or 1)
		existingGroup.ShowsQuantity = existingGroup.ShowsQuantity or metadata.ShowsQuantity == true
		existingGroup.IsSeed = existingGroup.IsSeed or metadata.IsSeed == true

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

local function create_generated_viewport(parent: GuiObject): ViewportFrame
	local viewportFrame = Instance.new("ViewportFrame")
	viewportFrame.Name = GENERATED_VIEWPORT_NAME
	viewportFrame.AnchorPoint = Vector2.new(0, 0)
	viewportFrame.Position = UDim2.fromScale(0, 0)
	viewportFrame.Size = UDim2.fromScale(1, 1)
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.BorderSizePixel = 0
	viewportFrame.ZIndex = parent.ZIndex + 1
	viewportFrame.Parent = parent
	return viewportFrame
end

local function get_slot_viewport(slot: GuiObject): ViewportFrame
	local imageItem = find_named_instance(slot, { "ImageItem" }, nil, true)
	if imageItem and imageItem:IsA("ViewportFrame") then
		return imageItem :: ViewportFrame
	end

	if imageItem then
		local nestedViewport = find_named_instance(imageItem, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
		if nestedViewport then
			return nestedViewport :: ViewportFrame
		end
	end

	local viewportFrame = find_named_instance(slot, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
	if viewportFrame then
		return viewportFrame :: ViewportFrame
	end

	if imageItem and imageItem:IsA("GuiObject") then
		return create_generated_viewport(imageItem)
	end

	return create_generated_viewport(slot)
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

	local viewportFrame = get_slot_viewport(slot)
	local previewKey = get_preview_cache_key(group.Key, group.RenderSource, group.IsSeed == true)
	if slot:GetAttribute("HotbarPreviewReady") ~= true or slot:GetAttribute("HotbarPreviewKey") ~= previewKey then
		render_viewport(viewportFrame, group.Key, group.RenderSource, group.DisplayName, group.IsSeed == true)
		slot:SetAttribute("HotbarPreviewReady", true)
		slot:SetAttribute("HotbarPreviewKey", previewKey)
	end

	set_slot_selected(slot, stickySelectionKey == group.Key)
end

local function create_slot(group)
	local slot = hotbarTemplateSource:Clone()
	local slotTrove = Trove.new()

	slot:SetAttribute("HotbarPreviewReady", nil)
	slot:SetAttribute("HotbarPreviewKey", nil)
	restore_template_gui_state(hotbarTemplateSource, slot)
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
	local equippedKey = get_equipped_group_key(currentGroups)
	local equippedGroup = equippedKey and currentGroups[equippedKey] or nil
	update_item_hand_display(equippedKey, equippedGroup and equippedGroup.DisplayName or nil)

	if not hotbarFrame or not hotbarTemplateSource then
		clear_slots()
		return
	end

	local groupArray = get_group_array(currentGroups)

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

		restore_template_gui_state(hotbarTemplateSource, slot)
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
	local nextMoneyTab = find_money_tab(nextHudRoot)
	local nextMoneyLabel, nextMoneyShadowLabel = find_money_labels(nextHudRoot)
	local nextItemHandLabel = find_item_hand_label(nextHudRoot)
	local hotbarChanged = hudRoot ~= nextHudRoot or hotbarFrame ~= nextHotbar or hotbarTemplate ~= nextTemplate
	local itemHandLabelChanged = itemHandLabel ~= nextItemHandLabel

	uiRoot = nextUiRoot
	hudRoot = nextHudRoot
	moneyTabFrame = nextMoneyTab
	moneyLabel = nextMoneyLabel
	moneyShadowLabel = nextMoneyShadowLabel
	itemHandLabel = nextItemHandLabel

	if itemHandLabelChanged then
		cancel_item_hand_tweens()
		itemHandOriginals = nil
		itemHandTargetKey = nil
	end

	update_money_display(nil, false)
	bind_money_add_button(nextHudRoot)

	if not nextUiRoot or not nextHudRoot or not nextHotbar or not nextTemplate then
		if hotbarFrame then
			clear_slots()
		end

		destroy_hotbar_template_source()
		hotbarFrame = nextHotbar
		hotbarTemplate = nextTemplate
		return
	end

	if hotbarChanged then
		clear_slots()
		destroy_hotbar_template_source()
	end

	hotbarFrame = nextHotbar
	hotbarTemplate = nextTemplate
	hotbarTemplateSource = hotbarTemplateSource or make_template_source(hotbarTemplate)

	set_gui_visible(hotbarTemplate, false)
	queue_refresh()
end

local function bind_ui_watchers()
	uiTrove:Clean()

	uiTrove:Connect(playerGui.DescendantAdded, function(instance)
		if instance.Name == MAIN_UI_NAME
			or matches_alias(instance, MAINFRAME_NAMES)
			or instance.Name == HUD_ROOT_NAME
			or instance.Name == HOTBAR_NAME
			or instance.Name == TEMPLATE_NAME
			or instance.Name == MONEY_TAB_NAME
			or instance.Name == MONEY_BG_NAME
			or instance.Name == MONEY_CONTAINER_NAME
			or instance.Name == ITEM_HAND_LABEL_NAME
			or matches_alias(instance, MONEY_ADD_BUTTON_NAMES)
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
			or matches_alias(instance, MAINFRAME_NAMES)
			or instance.Name == HUD_ROOT_NAME
			or instance.Name == HOTBAR_NAME
			or instance.Name == TEMPLATE_NAME
			or instance.Name == MONEY_TAB_NAME
			or instance.Name == MONEY_BG_NAME
			or instance.Name == MONEY_CONTAINER_NAME
			or instance.Name == ITEM_HAND_LABEL_NAME
			or matches_alias(instance, MONEY_ADD_BUTTON_NAMES)
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
	update_item_hand_display(nil, nil)
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
