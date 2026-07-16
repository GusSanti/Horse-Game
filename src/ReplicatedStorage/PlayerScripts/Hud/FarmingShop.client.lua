local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))
local FarmingShopViewportCache = require(ClientModules:WaitForChild("Hud"):WaitForChild("FarmingShopViewportCache"))
local HudAnim = require(Libraries:WaitForChild("HudAnim"))
local Net = require(Libraries:WaitForChild("Net"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PRELOAD_READY_ATTRIBUTE = "ClientUiPreloadComplete"
local PRELOAD_SKIPPED_ATTRIBUTE = "ClientUiPreloadSkipped"
local SHOP_ACTION_REMOTE_NAME = "FarmingShopAction"
local MAX_PRELOAD_WAIT_SECONDS = 3
local SHOP_UI_DISCOVERY_INTERVAL = 0.5
local SHOP_UI_WARNING_INTERVAL = 20
local CARD_BUILD_INTERVAL_SECONDS = 0.03
local SECONDARY_TAB_PRELOAD_DELAY_SECONDS = 0.2

local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"
local FRAMES_CONTAINER_NAME = "Frames"
local SEED_SHOP_FRAME_NAME = "SeedShop"
local FRUIT_SHOP_FRAME_NAME = "FruitShop"
local TABS_CONTAINER_NAME = "BuySellSeedsFR"
local SCROLLING_FRAME_NAME = "ListScrollingFrame"
local SEED_TEMPLATE_NAME = "SeedListBG"
local FRUIT_TEMPLATE_NAME = "FruitListBG"
local SEED_TAB_NAME = "Seeds"
local FRUIT_TAB_NAME = "Fruits"
local IGNORE_HUD_ANIM_ATTRIBUTE = "IgnoreHudAnim"
local IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE = "IgnoreAutoFrameButton"

local CLOSE_BUTTON_NAMES = { "CloseBT", "ExitBT" }
local RESTOCK_BUTTON_NAMES = { "RestyockBT", "RestockBT", "ReestockBT" }
local PURCHASE_BUTTON_NAMES = { "PurchaseBT" }
local BUTTON_TEXT_NAMES = { "BTTX" }
local NAME_LABEL_NAMES = { "ItemNameTX" }
local STOCK_COUNT_LABEL_NAMES = { "StockCountTX" }
local VALUE_LABEL_NAMES = { "ValueTX" }
local OUT_OF_STOCK_LABEL_NAMES = { "StockTX" }
local IMAGE_CONTAINER_NAMES = { "ImageLabel", "ImageItem", "ItemImage", "Icon" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }
local SHOP_BACKGROUND_NAMES = { "SeedShopBG", "FruitShopBG", "ShopBG" }
local SHALLOW_SEARCH_DEPTH = 3

type ShopCardTemplateMap = {
	PurchaseButtonPath: { string }?,
	StockCountLabelPath: { string }?,
	ValueLabelPath: { string }?,
	OutOfStockLabelPath: { string }?,
	ButtonTextPath: { string }?,
	NameLabelPath: { string }?,
	ViewportFramePath: { string }?,
}

type ShopCardEntry = {
	Card: GuiObject,
	ItemDefinition: any,
	PurchaseButton: GuiButton?,
	StockCountLabel: TextLabel?,
	ValueLabel: TextLabel?,
	OutOfStockLabel: TextLabel?,
	ButtonText: TextLabel?,
	ViewportFrame: ViewportFrame?,
	WorldModel: WorldModel?,
	Camera: Camera?,
	ButtonConnection: RBXScriptConnection?,
}

type ShopPanel = {
	Kind: string,
	Root: GuiObject,
	ScrollingFrame: ScrollingFrame,
	Template: GuiObject,
	TemplateMap: ShopCardTemplateMap?,
	SeedsButton: GuiButton,
	FruitsButton: GuiButton,
	CloseButton: GuiButton?,
	RestockButton: GuiButton?,
	Entries: { ShopCardEntry },
	BuildToken: number,
	BuildStarted: boolean,
	BuildCompleted: boolean,
}

type ShopUi = {
	SeedPanel: ShopPanel,
	FruitPanel: ShopPanel,
}

local currentUi: ShopUi? = nil
local currentUiConnections = {}
local activeTab = "Seed"
local requestInFlight = false

local seedItems = if type(FarmingCatalog.GetSeedItems) == "function" then (FarmingCatalog.GetSeedItems() or {}) else (type(FarmingCatalog.Seeds) == "table" and FarmingCatalog.Seeds or {})
local fruitItems = if type(FarmingCatalog.GetFruitItems) == "function" then (FarmingCatalog.GetFruitItems() or {}) else (type(FarmingCatalog.Fruits) == "table" and FarmingCatalog.Fruits or {})
local itemDefinitionsByKind = {
	Seed = seedItems,
	Fruit = fruitItems,
}

local function wait_for_preload_ready()
	local startedAt = os.clock()

	while player:GetAttribute(PRELOAD_READY_ATTRIBUTE) ~= true
		and player:GetAttribute(PRELOAD_SKIPPED_ATTRIBUTE) ~= true
		and os.clock() - startedAt < MAX_PRELOAD_WAIT_SECONDS
	do
		task.wait()
	end
end

local function disconnect_connection(connection)
	if connection and type(connection.Disconnect) == "function" then
		connection:Disconnect()
	end
end

local function disconnect_connections(connections)
	for index = #connections, 1, -1 do
		disconnect_connection(connections[index])
		connections[index] = nil
	end
end

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

local function matches_alias(instance: Instance, aliases): boolean
	local normalizedName = normalize_key(instance.Name)
	if not normalizedName then
		return false
	end

	for _, alias in ipairs(aliases) do
		if normalize_key(alias) == normalizedName then
			return true
		end
	end

	return false
end

local function find_direct_child(parent: Instance?, aliases, className: string?): Instance?
	if not parent then
		return nil
	end

	for _, alias in ipairs(aliases) do
		local child = parent:FindFirstChild(alias)
		if child and (not className or child:IsA(className)) then
			return child
		end
	end

	return nil
end

local function find_shallow_named_descendant(root: Instance?, aliases, className: string?, maxDepth: number): Instance?
	if not root then
		return nil
	end

	local queue = { { Node = root, Depth = 0 } }
	local cursor = 1

	while cursor <= #queue do
		local current = queue[cursor]
		cursor += 1

		if current.Depth >= maxDepth then
			continue
		end

		for _, child in ipairs(current.Node:GetChildren()) do
			if matches_alias(child, aliases) and (not className or child:IsA(className)) then
				return child
			end

			queue[#queue + 1] = {
				Node = child,
				Depth = current.Depth + 1,
			}
		end
	end

	return nil
end

local function find_text_label(root: Instance?, aliases): TextLabel?
	local instance = find_shallow_named_descendant(root, aliases, "TextLabel", SHALLOW_SEARCH_DEPTH)
	return if instance then instance :: TextLabel else nil
end

local function find_gui_button(root: Instance?, aliases, maxDepth: number?): GuiButton?
	local instance = find_shallow_named_descendant(root, aliases, "GuiButton", maxDepth or SHALLOW_SEARCH_DEPTH)
	return if instance then instance :: GuiButton else nil
end

local function find_viewport_frame(root: Instance?): ViewportFrame?
	local imageContainer = find_shallow_named_descendant(root, IMAGE_CONTAINER_NAMES, nil, 2)
	local viewport = find_direct_child(imageContainer, VIEWPORT_FRAME_NAMES, "ViewportFrame")
	if viewport then
		return viewport :: ViewportFrame
	end

	local fallback = find_shallow_named_descendant(root, VIEWPORT_FRAME_NAMES, "ViewportFrame", SHALLOW_SEARCH_DEPTH)
	return if fallback then fallback :: ViewportFrame else nil
end

local function strip_local_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function format_count(amount: number): string
	return string.format("%02d", math.max(0, math.floor(tonumber(amount) or 0)))
end

local function format_value(itemDefinition): string
	if itemDefinition.Kind == "Seed" then
		return ("$%d"):format(math.max(0, math.floor(tonumber(itemDefinition.Price) or 0)))
	end

	return ("$%d"):format(math.max(0, math.floor(tonumber(itemDefinition.SellPrice) or 0)))
end

local function get_horseshoes_amount(): number
	return math.max(0, math.floor(tonumber(DataUtility.client.get("Currencies.Horseshoes")) or 0))
end

local function get_inventory_path(kind: string): string
	return if kind == "Seed" then "Inventory.Seeds" else "Inventory.Fruits"
end

local function get_item_count(bucket, itemId): number
	if type(FarmingCatalog.GetItemCount) == "function" then
		return FarmingCatalog.GetItemCount(bucket, itemId)
	end

	if type(bucket) ~= "table" then
		return 0
	end

	return bucket[itemId] or 0
end

local function set_button_enabled(button: GuiButton?, isEnabled: boolean)
	if not button then
		return
	end

	button.Active = isEnabled
	button.Selectable = isEnabled

	if button:IsA("TextButton") or button:IsA("ImageButton") then
		button.AutoButtonColor = isEnabled
	end
end

local function update_canvas_size(scrollingFrame: ScrollingFrame?)
	if not scrollingFrame then
		return
	end

	local layout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if layout then
		scrollingFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
	end
end

local function clear_world_model(worldModel: WorldModel?)
	if not worldModel then
		return
	end

	for _, child in ipairs(worldModel:GetChildren()) do
		child:Destroy()
	end
end

local function ensure_viewport_state(entry: ShopCardEntry)
	if entry.WorldModel and entry.Camera and entry.ViewportFrame then
		return
	end

	local viewportFrame = entry.ViewportFrame
	if not viewportFrame then
		return
	end

	clear_world_model(viewportFrame:FindFirstChildOfClass("WorldModel"))

	local camera = viewportFrame:FindFirstChildOfClass("Camera")
	if camera then
		camera:Destroy()
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = "PooledWorldModel"
	worldModel.Parent = viewportFrame

	camera = Instance.new("Camera")
	camera.Name = "PooledCamera"
	camera.Parent = viewportFrame

	viewportFrame.BackgroundTransparency = 1
	viewportFrame.Ambient = Color3.fromRGB(220, 220, 220)
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
	viewportFrame.CurrentCamera = camera

	entry.WorldModel = worldModel
	entry.Camera = camera
end

local function get_relative_child_path(root: Instance, descendant: Instance?): { string }?
	if not descendant or descendant == root then
		return nil
	end

	local path = {}
	local current = descendant

	while current and current ~= root do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end

	if current ~= root then
		return nil
	end

	return path
end

local function resolve_child_by_path(root: Instance?, path: { string }?, className: string?): Instance?
	if not root or not path then
		return nil
	end

	local current = root

	for _, segment in ipairs(path) do
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end

	if className and not current:IsA(className) then
		return nil
	end

	return current
end

local function create_template_map(template: GuiObject): ShopCardTemplateMap
	local purchaseButton = find_gui_button(template, PURCHASE_BUTTON_NAMES)
	local stockCountLabel = find_text_label(template, STOCK_COUNT_LABEL_NAMES)
	local valueLabel = find_text_label(template, VALUE_LABEL_NAMES)
	local outOfStockLabel = find_text_label(template, OUT_OF_STOCK_LABEL_NAMES)
	local buttonText = find_text_label(template, BUTTON_TEXT_NAMES)
	local nameLabel = find_text_label(template, NAME_LABEL_NAMES)
	local viewportFrame = find_viewport_frame(template)

	return {
		PurchaseButtonPath = get_relative_child_path(template, purchaseButton),
		StockCountLabelPath = get_relative_child_path(template, stockCountLabel),
		ValueLabelPath = get_relative_child_path(template, valueLabel),
		OutOfStockLabelPath = get_relative_child_path(template, outOfStockLabel),
		ButtonTextPath = get_relative_child_path(template, buttonText),
		NameLabelPath = get_relative_child_path(template, nameLabel),
		ViewportFramePath = get_relative_child_path(template, viewportFrame),
	}
end

local function apply_cached_viewport(entry: ShopCardEntry)
	local viewportFrame = entry.ViewportFrame
	if not viewportFrame then
		return
	end

	local cachedViewport = FarmingShopViewportCache.Get(entry.ItemDefinition)
	if not cachedViewport then
		return
	end

	ensure_viewport_state(entry)
	clear_world_model(entry.WorldModel)

	cachedViewport.Template:Clone().Parent = entry.WorldModel
	entry.Camera.FieldOfView = cachedViewport.FieldOfView
	entry.Camera.CFrame = cachedViewport.CameraCFrame
	entry.ViewportFrame.CurrentCamera = entry.Camera
end

local function get_panel(ui: ShopUi?, kind: string): ShopPanel?
	if not ui then
		return nil
	end

	return if kind == "Seed" then ui.SeedPanel else ui.FruitPanel
end

local function clear_panel_entries(panel: ShopPanel)
	for _, entry in ipairs(panel.Entries) do
		disconnect_connection(entry.ButtonConnection)
		entry.ButtonConnection = nil
		entry.Card:Destroy()
	end

	panel.Entries = {}
end

local function cancel_panel_build(panel: ShopPanel)
	panel.BuildToken += 1
	panel.BuildStarted = false
	panel.BuildCompleted = false
end

local function reset_panel(panel: ShopPanel)
	cancel_panel_build(panel)
	clear_panel_entries(panel)
end

local function refresh_card(entry: ShopCardEntry, inventoryBucket, horseshoes: number)
	local itemDefinition = entry.ItemDefinition
	local amount = get_item_count(inventoryBucket, itemDefinition.ItemId)

	if entry.StockCountLabel then
		entry.StockCountLabel.Text = format_count(amount)
	end

	if entry.OutOfStockLabel then
		entry.OutOfStockLabel.Visible = itemDefinition.Kind == "Seed" and amount <= 0
	end

	if itemDefinition.Kind == "Seed" then
		set_button_enabled(entry.PurchaseButton, (not requestInFlight) and horseshoes >= (itemDefinition.Price or 0))
	else
		set_button_enabled(entry.PurchaseButton, (not requestInFlight) and amount > 0)
	end
end

local function refresh_kind(kind: string)
	local panel = get_panel(currentUi, kind)
	if not panel then
		return
	end

	local inventoryBucket = DataUtility.client.get(get_inventory_path(kind)) or {}
	local horseshoes = get_horseshoes_amount()

	for _, entry in ipairs(panel.Entries) do
		refresh_card(entry, inventoryBucket, horseshoes)
	end
end

local function refresh_all()
	refresh_kind("Seed")
	refresh_kind("Fruit")
end

local function disable_hud_anim(instance)
	if not instance then
		return
	end

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

local function bind_panel_open_anim(panel: ShopPanel)
	panel.Root:SetAttribute(IGNORE_HUD_ANIM_ATTRIBUTE, nil)
	panel.Root:SetAttribute(IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE, true)
	panel.Root:SetAttribute("UIOpen", true)

	pcall(function()
		HudAnim.bind(panel.Root)
		HudAnim.apply_defaults_to_buttons(panel.Root)
		HudAnim.bind_all(panel.Root)
	end)
end

local function set_panel_visible(panel: ShopPanel, isVisible: boolean, skipAnimation: boolean?)
	local wasVisible = panel.Root.Visible

	if not skipAnimation then
		panel.Root:SetAttribute("skip_open", nil)
		panel.Root:SetAttribute("skip_close", nil)
	elseif isVisible and not wasVisible then
		panel.Root:SetAttribute("skip_open", true)
	elseif not isVisible and wasVisible then
		panel.Root:SetAttribute("skip_close", true)
	elseif isVisible and wasVisible then
		panel.Root:SetAttribute("skip_open", nil)
		panel.Root:SetAttribute("skip_close", nil)
	elseif not isVisible and not wasVisible then
		panel.Root:SetAttribute("skip_close", nil)
	end

	panel.Root.Visible = isVisible
end

local function create_card_entry(panel: ShopPanel, itemDefinition): ShopCardEntry
	local templateMap = panel.TemplateMap or create_template_map(panel.Template)
	panel.TemplateMap = templateMap

	local card = panel.Template:Clone()
	card.Name = itemDefinition.ItemId
	disable_hud_anim_tree(card)
	card.Visible = true
	card.LayoutOrder = itemDefinition.SortOrder or 0

	strip_local_scripts(card)

	local entry: ShopCardEntry = {
		Card = card,
		ItemDefinition = itemDefinition,
		PurchaseButton = resolve_child_by_path(card, templateMap.PurchaseButtonPath, "GuiButton") :: GuiButton?,
		StockCountLabel = resolve_child_by_path(card, templateMap.StockCountLabelPath, "TextLabel") :: TextLabel?,
		ValueLabel = resolve_child_by_path(card, templateMap.ValueLabelPath, "TextLabel") :: TextLabel?,
		OutOfStockLabel = resolve_child_by_path(card, templateMap.OutOfStockLabelPath, "TextLabel") :: TextLabel?,
		ButtonText = resolve_child_by_path(card, templateMap.ButtonTextPath, "TextLabel") :: TextLabel?,
		ViewportFrame = resolve_child_by_path(card, templateMap.ViewportFramePath, "ViewportFrame") :: ViewportFrame?,
		WorldModel = nil,
		Camera = nil,
		ButtonConnection = nil,
	}

	local nameLabel = resolve_child_by_path(card, templateMap.NameLabelPath, "TextLabel") :: TextLabel?
	if nameLabel then
		nameLabel.Text = itemDefinition.DisplayName
	end

	if entry.ValueLabel then
		entry.ValueLabel.Text = format_value(itemDefinition)
	end

	if entry.ButtonText then
		entry.ButtonText.Text = if panel.Kind == "Seed" then "Buy" else "Sell"
	end

	apply_cached_viewport(entry)

	if entry.PurchaseButton then
		entry.ButtonConnection = entry.PurchaseButton.Activated:Connect(function()
			if requestInFlight then
				return
			end

			requestInFlight = true
			refresh_all()

			task.spawn(function()
				pcall(function()
					Net.Function[SHOP_ACTION_REMOTE_NAME]:Call({
						Action = if panel.Kind == "Seed" then "BuySeed" else "SellFruit",
						ItemId = itemDefinition.ItemId,
					})
				end)

				requestInFlight = false
				refresh_all()
			end)
		end)
	end

	return entry
end

local function apply_manual_shop_control(panel: ShopPanel)
	bind_panel_open_anim(panel)
	disable_hud_anim_tree(panel.ScrollingFrame)
	disable_hud_anim_tree(panel.Template)
	panel.Template.Visible = false
end

local function start_panel_build(panel: ShopPanel)
	local itemDefinitions = itemDefinitionsByKind[panel.Kind]
	if not itemDefinitions or panel.BuildStarted or panel.BuildCompleted then
		return
	end

	panel.TemplateMap = panel.TemplateMap or create_template_map(panel.Template)
	panel.BuildToken += 1
	panel.BuildStarted = true

	local buildToken = panel.BuildToken

	task.spawn(function()
		for index, itemDefinition in ipairs(itemDefinitions) do
			if not currentUi or get_panel(currentUi, panel.Kind) ~= panel or panel.BuildToken ~= buildToken then
				return
			end

			local entry = create_card_entry(panel, itemDefinition)
			entry.Card.Parent = panel.ScrollingFrame
			panel.Entries[#panel.Entries + 1] = entry

			local inventoryBucket = DataUtility.client.get(get_inventory_path(panel.Kind)) or {}
			refresh_card(entry, inventoryBucket, get_horseshoes_amount())

			if index == 1 or index % 4 == 0 or index == #itemDefinitions then
				update_canvas_size(panel.ScrollingFrame)
			end

			task.wait(CARD_BUILD_INTERVAL_SECONDS)
		end

		if panel.BuildToken ~= buildToken then
			return
		end

		panel.BuildStarted = false
		panel.BuildCompleted = true
		update_canvas_size(panel.ScrollingFrame)
		task.defer(function()
			update_canvas_size(panel.ScrollingFrame)
		end)
	end)
end

local function show_tab(kind: string)
	if not currentUi then
		return
	end

	activeTab = kind

	set_panel_visible(currentUi.SeedPanel, kind == "Seed", true)
	set_panel_visible(currentUi.FruitPanel, kind == "Fruit", true)

	if currentUi.SeedPanel.RestockButton then
		currentUi.SeedPanel.RestockButton.Visible = false
	end

	if currentUi.FruitPanel.RestockButton then
		currentUi.FruitPanel.RestockButton.Visible = kind == "Fruit"
	end

	local panel = get_panel(currentUi, kind)
	if not panel then
		return
	end

	start_panel_build(panel)
	refresh_kind(kind)
	update_canvas_size(panel.ScrollingFrame)
	task.defer(function()
		update_canvas_size(panel.ScrollingFrame)
	end)
end

local function hide_shop()
	if not currentUi then
		return
	end

	set_panel_visible(currentUi.SeedPanel, false, false)
	set_panel_visible(currentUi.FruitPanel, false, false)
end

local function find_shop_root(framesContainer: Instance?, frameName: string): GuiObject?
	if not framesContainer then
		return nil
	end

	local root = framesContainer:FindFirstChild(frameName)
	if root and root:IsA("GuiObject") then
		return root :: GuiObject
	end

	local nestedRoot = framesContainer:FindFirstChild(frameName, true)
	return if nestedRoot and nestedRoot:IsA("GuiObject") then nestedRoot :: GuiObject else nil
end

local function find_scrolling_frame(shopRoot: GuiObject): ScrollingFrame?
	local directScrollingFrame = find_direct_child(shopRoot, { SCROLLING_FRAME_NAME }, "ScrollingFrame")
	if directScrollingFrame then
		return directScrollingFrame :: ScrollingFrame
	end

	for _, backgroundName in ipairs(SHOP_BACKGROUND_NAMES) do
		local background = find_shallow_named_descendant(shopRoot, { backgroundName }, "GuiObject", 2)
		local nestedScrollingFrame = find_direct_child(background, { SCROLLING_FRAME_NAME }, "ScrollingFrame")
		if nestedScrollingFrame then
			return nestedScrollingFrame :: ScrollingFrame
		end
	end

	local fallback = find_shallow_named_descendant(shopRoot, { SCROLLING_FRAME_NAME }, "ScrollingFrame", SHALLOW_SEARCH_DEPTH)
	return if fallback then fallback :: ScrollingFrame else nil
end

local function find_shop_panel(framesContainer: Instance?, frameName: string, kind: string, templateName: string): ShopPanel?
	local shopRoot = find_shop_root(framesContainer, frameName)
	if not shopRoot then
		return nil
	end

	local tabsContainer = find_direct_child(shopRoot, { TABS_CONTAINER_NAME }, "GuiObject")
		or find_shallow_named_descendant(shopRoot, { TABS_CONTAINER_NAME }, "GuiObject", SHALLOW_SEARCH_DEPTH)
	if not tabsContainer then
		return nil
	end

	local scrollingFrame = find_scrolling_frame(shopRoot)
	if not scrollingFrame then
		return nil
	end

	local template = find_direct_child(scrollingFrame, { templateName }, "GuiObject")
		or find_shallow_named_descendant(scrollingFrame, { templateName }, "GuiObject", 2)
	if not template then
		return nil
	end

	local seedsButton = find_direct_child(tabsContainer, { SEED_TAB_NAME }, "GuiButton")
		or find_gui_button(tabsContainer, { SEED_TAB_NAME }, 2)
	local fruitsButton = find_direct_child(tabsContainer, { FRUIT_TAB_NAME }, "GuiButton")
		or find_gui_button(tabsContainer, { FRUIT_TAB_NAME }, 2)
	if not seedsButton or not fruitsButton then
		return nil
	end

	local closeButton = find_direct_child(shopRoot, CLOSE_BUTTON_NAMES, "GuiButton")
		or find_gui_button(shopRoot, CLOSE_BUTTON_NAMES, 2)
	local restockButton = find_direct_child(shopRoot, RESTOCK_BUTTON_NAMES, "GuiButton")
		or find_gui_button(shopRoot, RESTOCK_BUTTON_NAMES, 2)

	return {
		Kind = kind,
		Root = shopRoot,
		ScrollingFrame = scrollingFrame,
		Template = template :: GuiObject,
		TemplateMap = nil,
		SeedsButton = seedsButton :: GuiButton,
		FruitsButton = fruitsButton :: GuiButton,
		CloseButton = closeButton :: GuiButton?,
		RestockButton = restockButton :: GuiButton?,
		Entries = {},
		BuildToken = 0,
		BuildStarted = false,
		BuildCompleted = false,
	}
end

local function try_get_shop_ui(): ShopUi?
	local mainUi = playerGui:FindFirstChild(MAIN_UI_NAME)
	if not mainUi then
		return nil
	end

	local mainframe = mainUi:FindFirstChild(MAINFRAME_NAME)
	if not mainframe then
		return nil
	end

	local framesContainer = mainframe:FindFirstChild(FRAMES_CONTAINER_NAME)
	if not framesContainer then
		return nil
	end

	local seedPanel = find_shop_panel(framesContainer, SEED_SHOP_FRAME_NAME, "Seed", SEED_TEMPLATE_NAME)
	local fruitPanel = find_shop_panel(framesContainer, FRUIT_SHOP_FRAME_NAME, "Fruit", FRUIT_TEMPLATE_NAME)
	if not seedPanel or not fruitPanel then
		return nil
	end

	return {
		SeedPanel = seedPanel,
		FruitPanel = fruitPanel,
	}
end

local function bind_panel_buttons(panel: ShopPanel)
	currentUiConnections[#currentUiConnections + 1] = panel.SeedsButton.Activated:Connect(function()
		show_tab("Seed")
	end)

	currentUiConnections[#currentUiConnections + 1] = panel.FruitsButton.Activated:Connect(function()
		show_tab("Fruit")
	end)

	if panel.CloseButton then
		currentUiConnections[#currentUiConnections + 1] = panel.CloseButton.Activated:Connect(function()
			hide_shop()
		end)
	end

	if panel.RestockButton then
		currentUiConnections[#currentUiConnections + 1] = panel.RestockButton.Activated:Connect(function()
			show_tab("Seed")
		end)
	end
end

local function bind_ui(ui: ShopUi)
	disconnect_connections(currentUiConnections)

	if currentUi then
		reset_panel(currentUi.SeedPanel)
		reset_panel(currentUi.FruitPanel)
	end

	currentUi = ui

	apply_manual_shop_control(ui.SeedPanel)
	apply_manual_shop_control(ui.FruitPanel)

	bind_panel_buttons(ui.SeedPanel)
	bind_panel_buttons(ui.FruitPanel)

	currentUiConnections[#currentUiConnections + 1] = DataUtility.client.bind("Currencies.Horseshoes", function()
		refresh_all()
	end)

	currentUiConnections[#currentUiConnections + 1] = DataUtility.client.bind("Inventory.Seeds", function()
		refresh_kind("Seed")
	end)

	currentUiConnections[#currentUiConnections + 1] = DataUtility.client.bind("Inventory.Fruits", function()
		refresh_kind("Fruit")
	end)

	show_tab(activeTab)

	local primaryPanel = get_panel(ui, activeTab) or ui.SeedPanel
	local secondaryPanel = if primaryPanel == ui.SeedPanel then ui.FruitPanel else ui.SeedPanel

	start_panel_build(primaryPanel)
	task.delay(SECONDARY_TAB_PRELOAD_DELAY_SECONDS, function()
		if currentUi == ui then
			start_panel_build(secondaryPanel)
		end
	end)
end

local function initialize_shop()
	wait_for_preload_ready()

	local dataSuccess, dataError = pcall(function()
		DataUtility.client.ensure_remotes()
	end)

	if not dataSuccess then
		warn("[FarmingShop] falha ao inicializar DataUtility: " .. tostring(dataError))
	end

	local attempts = 0

	while true do
		attempts += 1

		local ui = try_get_shop_ui()
		if ui then
			bind_ui(ui)
			return
		end

		if attempts % SHOP_UI_WARNING_INTERVAL == 0 then
			warn("[FarmingShop] aguardando SeedShop/FruitShop UI no PlayerGui...")
		end

		task.wait(SHOP_UI_DISCOVERY_INTERVAL)
	end
end

task.defer(function()
	local success, errorMessage = pcall(initialize_shop)
	if not success then
		warn("[FarmingShop] inicializacao falhou: " .. tostring(errorMessage))
	end
end)