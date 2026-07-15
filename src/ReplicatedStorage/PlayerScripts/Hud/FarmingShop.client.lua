local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))
local FarmingShopViewportCache = require(ClientModules:WaitForChild("Hud"):WaitForChild("FarmingShopViewportCache"))
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

local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"
local FRAMES_CONTAINER_NAME = "Frames"
local SHOP_FRAME_NAME = "SeedShop"
local SHOP_BACKGROUND_NAME = "SeedShopBG"
local TABS_CONTAINER_NAME = "BuySellSeedsFR"
local SCROLLING_FRAME_NAME = "ListScrollingFrame"
local SEED_TEMPLATE_NAME = "SeedListBG"
local FRUIT_TEMPLATE_NAME = "FruitListBG"
local SEED_TAB_NAME = "Seeds"
local FRUIT_TAB_NAME = "Fruits"
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
local SHALLOW_SEARCH_DEPTH = 3

type ShopUi = {
	Root: GuiObject,
	ScrollingFrame: ScrollingFrame,
	SeedTemplate: GuiObject,
	FruitTemplate: GuiObject,
	SeedsButton: GuiButton,
	FruitsButton: GuiButton,
	CloseButton: GuiButton?,
	RestockButton: GuiButton?,
}

type ShopCardEntry = {
	Card: GuiObject,
	Kind: string,
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

type ShopCardTemplateMap = {
	PurchaseButtonPath: {string}?,
	StockCountLabelPath: {string}?,
	ValueLabelPath: {string}?,
	OutOfStockLabelPath: {string}?,
	ButtonTextPath: {string}?,
	NameLabelPath: {string}?,
	ViewportFramePath: {string}?,
}

local currentUi: ShopUi? = nil
local currentUiConnections = {}
local pooledEntriesByKind = {
	Seed = {},
	Fruit = {},
}
local activeEntries = {}
local activeTab = "Seed"
local renderedTab: string? = nil
local requestInFlight = false
local renderQueued = false
local rebuildQueued = false
local poolsInitialized = false

local seedItems = if type(FarmingCatalog.GetSeedItems) == "function" then (FarmingCatalog.GetSeedItems() or {}) else (type(FarmingCatalog.Seeds) == "table" and FarmingCatalog.Seeds or {})
local fruitItems = if type(FarmingCatalog.GetFruitItems) == "function" then (FarmingCatalog.GetFruitItems() or {}) else (type(FarmingCatalog.Fruits) == "table" and FarmingCatalog.Fruits or {})

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
	if instance then
		return instance :: TextLabel
	end

	return nil
end

local function find_gui_button(root: Instance?, aliases): GuiButton?
	local instance = find_shallow_named_descendant(root, aliases, "GuiButton", SHALLOW_SEARCH_DEPTH)
	if instance then
		return instance :: GuiButton
	end

	return nil
end

local function find_viewport_frame(root: Instance?): ViewportFrame?
	local imageContainer = find_shallow_named_descendant(root, IMAGE_CONTAINER_NAMES, nil, 2)
	local viewport = find_direct_child(imageContainer, VIEWPORT_FRAME_NAMES, "ViewportFrame")
	if viewport then
		return viewport :: ViewportFrame
	end

	local fallback = find_shallow_named_descendant(root, VIEWPORT_FRAME_NAMES, "ViewportFrame", SHALLOW_SEARCH_DEPTH)
	if fallback then
		return fallback :: ViewportFrame
	end

	return nil
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

local function get_item_count(bucket, itemId): number
	if type(FarmingCatalog.GetItemCount) == "function" then
		return FarmingCatalog.GetItemCount(bucket, itemId)
	end

	if type(bucket) ~= "table" then
		return 0
	end

	return bucket[itemId] or 0
end

local function get_active_inventory_path(): string
	return if activeTab == "Seed" then "Inventory.Seeds" else "Inventory.Fruits"
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

local function update_canvas_size()
	if not currentUi then
		return
	end

	local layout = currentUi.ScrollingFrame:FindFirstChildOfClass("UIListLayout")
	if layout then
		currentUi.ScrollingFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
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

local function get_relative_child_path(root: Instance, descendant: Instance?): {string}?
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

local function resolve_child_by_path(root: Instance?, path: {string}?, className: string?): Instance?
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

local call_shop

local function create_pooled_card_entry(kind: string, template: GuiObject, templateMap: ShopCardTemplateMap, itemDefinition): ShopCardEntry
	local card = template:Clone()
	card.Name = itemDefinition.ItemId
	card.Visible = false
	card.Parent = nil
	card.LayoutOrder = itemDefinition.SortOrder or 0

	strip_local_scripts(card)

	local entry: ShopCardEntry = {
		Card = card,
		Kind = kind,
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
		entry.ButtonText.Text = if kind == "Seed" then "Buy" else "Sell"
	end

	apply_cached_viewport(entry)

	if entry.PurchaseButton then
		entry.ButtonConnection = entry.PurchaseButton.Activated:Connect(function()
			call_shop(if entry.Kind == "Seed" then "BuySeed" else "SellFruit", entry.ItemDefinition.ItemId)
		end)
	end

	return entry
end

local function release_active_entries()
	for _, entry in ipairs(activeEntries) do
		entry.Card.Visible = false
		entry.Card.Parent = nil
	end

	activeEntries = {}
	renderedTab = nil
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

local function refresh_visible_cards()
	if not currentUi then
		return
	end

	local inventoryBucket = DataUtility.client.get(get_active_inventory_path()) or {}
	local horseshoes = get_horseshoes_amount()

	for _, entry in ipairs(activeEntries) do
		refresh_card(entry, inventoryBucket, horseshoes)
	end
end

call_shop = function(actionName: string, itemId: string)
	if requestInFlight then
		return
	end

	requestInFlight = true
	refresh_visible_cards()

	task.spawn(function()
		pcall(function()
			Net.Function[SHOP_ACTION_REMOTE_NAME]:Call({
				Action = actionName,
				ItemId = itemId,
			})
		end)

		requestInFlight = false
		refresh_visible_cards()
	end)
end

local function attach_entries_for_tab()
	if not currentUi then
		return
	end

	release_active_entries()
	currentUi.ScrollingFrame.CanvasPosition = Vector2.zero

	for _, entry in ipairs(pooledEntriesByKind[activeTab]) do
		entry.Card.Parent = currentUi.ScrollingFrame
		entry.Card.Visible = true
		activeEntries[#activeEntries + 1] = entry
	end

	renderedTab = activeTab
	refresh_visible_cards()
	update_canvas_size()
	task.defer(update_canvas_size)
end

local function render_shop(forceRebuild: boolean)
	if not currentUi then
		return
	end

	if currentUi.RestockButton then
		currentUi.RestockButton.Visible = activeTab == "Fruit"
	end

	if forceRebuild or renderedTab ~= activeTab then
		attach_entries_for_tab()
		return
	end

	refresh_visible_cards()
end

local function schedule_render(forceRebuild: boolean)
	rebuildQueued = rebuildQueued or forceRebuild
	if renderQueued then
		return
	end

	renderQueued = true

	task.defer(function()
		renderQueued = false

		local shouldRebuild = rebuildQueued
		rebuildQueued = false

		render_shop(shouldRebuild)
	end)
end

local function build_card_pools(ui: ShopUi)
	if poolsInitialized then
		return
	end

	local seedTemplateMap = create_template_map(ui.SeedTemplate)
	local fruitTemplateMap = create_template_map(ui.FruitTemplate)

	local function build_pool_for_kind(kind: string, template: GuiObject, templateMap: ShopCardTemplateMap, itemDefinitions)
		for _, itemDefinition in ipairs(itemDefinitions) do
			local entry = create_pooled_card_entry(kind, template, templateMap, itemDefinition)
			pooledEntriesByKind[kind][#pooledEntriesByKind[kind] + 1] = entry
		end
	end

	build_pool_for_kind("Seed", ui.SeedTemplate, seedTemplateMap, seedItems)
	build_pool_for_kind("Fruit", ui.FruitTemplate, fruitTemplateMap, fruitItems)

	ui.SeedTemplate.Visible = false
	ui.FruitTemplate.Visible = false
	ui.SeedTemplate.Parent = nil
	ui.FruitTemplate.Parent = nil

	poolsInitialized = true
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

	local shopRoot = framesContainer:FindFirstChild(SHOP_FRAME_NAME)
	if not shopRoot or not shopRoot:IsA("GuiObject") then
		return nil
	end

	local shopBackground = shopRoot:FindFirstChild(SHOP_BACKGROUND_NAME)
	local tabsContainer = shopRoot:FindFirstChild(TABS_CONTAINER_NAME)
	if not shopBackground or not shopBackground:IsA("GuiObject") or not tabsContainer then
		return nil
	end

	local scrollingFrame = shopBackground:FindFirstChild(SCROLLING_FRAME_NAME)
	local seedTemplate = scrollingFrame and scrollingFrame:FindFirstChild(SEED_TEMPLATE_NAME)
	local fruitTemplate = scrollingFrame and scrollingFrame:FindFirstChild(FRUIT_TEMPLATE_NAME)
	local seedsButton = tabsContainer:FindFirstChild(SEED_TAB_NAME)
	local fruitsButton = tabsContainer:FindFirstChild(FRUIT_TAB_NAME)

	if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
		return nil
	end

	if not seedTemplate or not seedTemplate:IsA("GuiObject") then
		return nil
	end

	if not fruitTemplate or not fruitTemplate:IsA("GuiObject") then
		return nil
	end

	if not seedsButton or not seedsButton:IsA("GuiButton") then
		return nil
	end

	if not fruitsButton or not fruitsButton:IsA("GuiButton") then
		return nil
	end

	return {
		Root = shopRoot :: GuiObject,
		ScrollingFrame = scrollingFrame :: ScrollingFrame,
		SeedTemplate = seedTemplate :: GuiObject,
		FruitTemplate = fruitTemplate :: GuiObject,
		SeedsButton = seedsButton :: GuiButton,
		FruitsButton = fruitsButton :: GuiButton,
		CloseButton = find_direct_child(shopRoot, CLOSE_BUTTON_NAMES, "GuiButton") :: GuiButton?,
		RestockButton = find_direct_child(shopRoot, RESTOCK_BUTTON_NAMES, "GuiButton") :: GuiButton?,
	}
end

local function bind_ui(ui: ShopUi)
	disconnect_connections(currentUiConnections)
	release_active_entries()

	currentUi = ui
	build_card_pools(ui)

	currentUiConnections[#currentUiConnections + 1] = ui.SeedsButton.Activated:Connect(function()
		activeTab = "Seed"
		schedule_render(true)
	end)

	currentUiConnections[#currentUiConnections + 1] = ui.FruitsButton.Activated:Connect(function()
		activeTab = "Fruit"
		schedule_render(true)
	end)

	if ui.CloseButton then
		currentUiConnections[#currentUiConnections + 1] = ui.CloseButton.Activated:Connect(function()
			ui.Root.Visible = false
		end)
	end

	if ui.RestockButton then
		currentUiConnections[#currentUiConnections + 1] = ui.RestockButton.Activated:Connect(function()
			activeTab = "Seed"
			schedule_render(true)
		end)
	end

	currentUiConnections[#currentUiConnections + 1] = DataUtility.client.bind("Currencies.Horseshoes", function()
		schedule_render(false)
	end)

	currentUiConnections[#currentUiConnections + 1] = DataUtility.client.bind("Inventory.Seeds", function()
		if activeTab == "Seed" then
			schedule_render(false)
		end
	end)

	currentUiConnections[#currentUiConnections + 1] = DataUtility.client.bind("Inventory.Fruits", function()
		if activeTab == "Fruit" then
			schedule_render(false)
		end
	end)

	schedule_render(true)
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
			warn("[FarmingShop] aguardando SeedShop UI no PlayerGui...")
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