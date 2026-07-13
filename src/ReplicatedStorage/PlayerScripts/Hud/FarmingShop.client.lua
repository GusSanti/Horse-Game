local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()

local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"
local FRAMES_CONTAINER_NAME = "Frames"
local SHOP_FRAME_NAME = "SeedShop"
local SHOP_BACKGROUND_NAMES = { "SeedShopBG" }
local TABS_CONTAINER_NAMES = { "BuySellSeedsFR" }
local SCROLLING_FRAME_NAMES = { "ListScrollingFrame", "ScrollingFrame", "ScrollFrame", "Scroll" }
local SEED_TEMPLATE_NAMES = { "SeedListBG" }
local FRUIT_TEMPLATE_NAMES = { "FruitListBG" }
local SEED_TAB_NAMES = { "Seeds" }
local FRUIT_TAB_NAMES = { "Fruits" }
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

local VIEWPORT_FIELD_OF_VIEW = 35
local VIEWPORT_RADIUS_SCALE = 0.55
local VIEWPORT_CAMERA_Y_SCALE = 0.2
local VIEWPORT_CAMERA_X_SCALE = 0.45

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

local currentUi: ShopUi? = nil
local currentSeedTemplateSource: GuiObject? = nil
local currentFruitTemplateSource: GuiObject? = nil
local activeTab = "Seed"
local requestInFlight = false

local function get_seed_items()
	if type(FarmingCatalog.GetSeedItems) == "function" then
		return FarmingCatalog.GetSeedItems() or {}
	end

	return type(FarmingCatalog.Seeds) == "table" and FarmingCatalog.Seeds or {}
end

local function get_fruit_items()
	if type(FarmingCatalog.GetFruitItems) == "function" then
		return FarmingCatalog.GetFruitItems() or {}
	end

	return type(FarmingCatalog.Fruits) == "table" and FarmingCatalog.Fruits or {}
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

local function find_gui_button(root: Instance?, aliases, recursive: boolean?): GuiButton?
	local instance = find_named_instance(root, aliases, "GuiButton", recursive)
	if instance then
		return instance :: GuiButton
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

local function find_scrolling_frame(root: Instance?): ScrollingFrame?
	local instance = find_named_instance(root, SCROLLING_FRAME_NAMES, "ScrollingFrame")
	if instance then
		return instance :: ScrollingFrame
	end

	return nil
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

local function strip_local_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function make_template_source(template: GuiObject): GuiObject
	local source = template:Clone()
	source.Visible = true
	strip_local_scripts(source)

	template.Visible = false
	template.Parent = nil

	return source
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

local function clear_viewport(viewportFrame: ViewportFrame)
	for _, child in ipairs(viewportFrame:GetChildren()) do
		child:Destroy()
	end

	viewportFrame.CurrentCamera = nil :: any
end

local function get_bounds(root: Instance): (Vector3?, Vector3?)
	local minVector = Vector3.new(math.huge, math.huge, math.huge)
	local maxVector = Vector3.new(-math.huge, -math.huge, -math.huge)
	local foundPart = false

	local function include_part(part: BasePart)
		local halfSize = part.Size * 0.5

		for xSign = -1, 1, 2 do
			for ySign = -1, 1, 2 do
				for zSign = -1, 1, 2 do
					local corner = part.CFrame:PointToWorldSpace(Vector3.new(
						halfSize.X * xSign,
						halfSize.Y * ySign,
						halfSize.Z * zSign
					))

					minVector = Vector3.new(
						math.min(minVector.X, corner.X),
						math.min(minVector.Y, corner.Y),
						math.min(minVector.Z, corner.Z)
					)

					maxVector = Vector3.new(
						math.max(maxVector.X, corner.X),
						math.max(maxVector.Y, corner.Y),
						math.max(maxVector.Z, corner.Z)
					)

					foundPart = true
				end
			end
		end
	end

	if root:IsA("BasePart") then
		include_part(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			include_part(descendant)
		end
	end

	if not foundPart then
		return nil, nil
	end

	return (minVector + maxVector) * 0.5, maxVector - minVector
end

local function prepare_viewport_model(root: Instance)
	strip_local_scripts(root)

	if root:IsA("BasePart") then
		root.Anchored = true
		root.CanCollide = false
		root.CanTouch = false
		root.CanQuery = false
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end
end

local function populate_viewport(card: Instance, itemDefinition)
	local imageContainer = find_named_instance(card, IMAGE_CONTAINER_NAMES, nil, true)
	local viewportInstance = nil

	if imageContainer then
		viewportInstance = find_named_instance(imageContainer, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
	end

	if not viewportInstance then
		viewportInstance = find_named_instance(card, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
	end

	if not viewportInstance or not viewportInstance:IsA("ViewportFrame") then
		return
	end

	local viewportFrame = viewportInstance :: ViewportFrame
	clear_viewport(viewportFrame)

	local asset = FarmingUtility.GetViewportAsset(itemDefinition) or FarmingUtility.GetItemAsset(itemDefinition)
	if not asset then
		return
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewportFrame

	local clone = asset:Clone()
	prepare_viewport_model(clone)
	clone.Parent = worldModel

	local center, size = get_bounds(clone)
	if not center or not size then
		return
	end

	local camera = Instance.new("Camera")
	camera.FieldOfView = VIEWPORT_FIELD_OF_VIEW
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.Ambient = Color3.fromRGB(220, 220, 220)
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)

	local radius = math.max(size.X, size.Y, size.Z) * VIEWPORT_RADIUS_SCALE
	local distance = radius / math.tan(math.rad(camera.FieldOfView * 0.5)) + radius
	camera.CFrame = CFrame.lookAt(
		center + Vector3.new(distance * VIEWPORT_CAMERA_X_SCALE, distance * VIEWPORT_CAMERA_Y_SCALE, distance),
		center
	)
end

local function call_shop(remoteName: string, itemId: string)
	if requestInFlight then
		return
	end

	requestInFlight = true

	task.spawn(function()
		pcall(function()
			Net.Function[remoteName]:Call(itemId)
		end)

		requestInFlight = false
	end)
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

local function set_button_enabled(button: GuiButton?, isEnabled: boolean)
	if not button then
		return
	end

	button.Active = isEnabled
	button.Selectable = isEnabled

	if button:IsA("TextButton") then
		button.AutoButtonColor = isEnabled
	elseif button:IsA("ImageButton") then
		button.AutoButtonColor = isEnabled
	end
end

local function configure_card(card: GuiObject, itemDefinition, amount: number, horseshoes: number)
	card.Name = itemDefinition.ItemId
	card.Visible = true
	card.LayoutOrder = itemDefinition.SortOrder or 0

	local nameLabel = find_text_label(card, NAME_LABEL_NAMES, true)
	local stockCountLabel = find_text_label(card, STOCK_COUNT_LABEL_NAMES, true)
	local valueLabel = find_text_label(card, VALUE_LABEL_NAMES, true)
	local outOfStockLabel = find_text_label(card, OUT_OF_STOCK_LABEL_NAMES, true)
	local purchaseButton = find_gui_button(card, PURCHASE_BUTTON_NAMES, true)
	local buttonText = find_text_label(purchaseButton or card, BUTTON_TEXT_NAMES, true)

	if nameLabel then
		nameLabel.Text = itemDefinition.DisplayName
	end

	if stockCountLabel then
		stockCountLabel.Text = format_count(amount)
	end

	if valueLabel then
		valueLabel.Text = format_value(itemDefinition)
	end

	if outOfStockLabel then
		outOfStockLabel.Visible = itemDefinition.Kind == "Seed" and amount <= 0
	end

	if buttonText then
		buttonText.Text = itemDefinition.Kind == "Seed" and "Buy" or "Sell"
	end

	if itemDefinition.Kind == "Seed" then
		set_button_enabled(purchaseButton, horseshoes >= (itemDefinition.Price or 0))
	else
		set_button_enabled(purchaseButton, amount > 0)
	end

	populate_viewport(card, itemDefinition)
end

local function render_shop()
	if not currentUi then
		return
	end

	cardTrove:Clean()
	currentUi.ScrollingFrame.CanvasPosition = Vector2.zero

	if currentUi.RestockButton and currentUi.RestockButton:IsA("GuiObject") then
		currentUi.RestockButton.Visible = activeTab == "Fruit"
	end

	local itemDefinitions = activeTab == "Seed" and get_seed_items() or get_fruit_items()
	local template = activeTab == "Seed" and currentSeedTemplateSource or currentFruitTemplateSource
	local inventoryPath = activeTab == "Seed" and "Inventory.Seeds" or "Inventory.Fruits"
	local inventoryBucket = DataUtility.client.get(inventoryPath) or {}
	local horseshoes = get_horseshoes_amount()

	if not template then
		return
	end

	for _, itemDefinition in ipairs(itemDefinitions) do
		local card = template:Clone()
		card.Parent = currentUi.ScrollingFrame
		cardTrove:Add(card)

		local amount = get_item_count(inventoryBucket, itemDefinition.ItemId)
		configure_card(card, itemDefinition, amount, horseshoes)

		local remoteName = activeTab == "Seed" and "BuySeed" or "SellFruit"
		local button = find_gui_button(card, PURCHASE_BUTTON_NAMES, true)
		if button then
			cardTrove:Add(button.Activated:Connect(function()
				call_shop(remoteName, itemDefinition.ItemId)
			end))
		end
	end

	update_canvas_size()
	task.defer(update_canvas_size)
end

local function get_shop_ui(shopRoot: GuiObject): ShopUi?
	local tabsContainer = find_gui_object(shopRoot, TABS_CONTAINER_NAMES, true)
	local shopBackground = find_gui_object(shopRoot, SHOP_BACKGROUND_NAMES, true) or shopRoot
	local scrollingFrame = find_scrolling_frame(shopBackground)
	local seedTemplate = find_gui_object(scrollingFrame, SEED_TEMPLATE_NAMES, true)
	local fruitTemplate = find_gui_object(scrollingFrame, FRUIT_TEMPLATE_NAMES, true)
	local seedsButton = find_gui_button(tabsContainer or shopRoot, SEED_TAB_NAMES, true)
	local fruitsButton = find_gui_button(tabsContainer or shopRoot, FRUIT_TAB_NAMES, true)

	if not scrollingFrame or not seedTemplate or not fruitTemplate or not seedsButton or not fruitsButton then
		return nil
	end

	return {
		Root = shopRoot,
		ScrollingFrame = scrollingFrame,
		SeedTemplate = seedTemplate,
		FruitTemplate = fruitTemplate,
		SeedsButton = seedsButton,
		FruitsButton = fruitsButton,
		CloseButton = find_gui_button(shopRoot, CLOSE_BUTTON_NAMES, true),
		RestockButton = find_gui_button(shopRoot, RESTOCK_BUTTON_NAMES, true),
	}
end

local function find_main_ui(): ShopUi?
	local mainUi = playerGui:FindFirstChild(MAIN_UI_NAME)
	if not mainUi then
		mainUi = playerGui:FindFirstChild(MAIN_UI_NAME, true)
	end

	if not mainUi then
		return nil
	end

	local mainframe = mainUi:FindFirstChild(MAINFRAME_NAME)
	if not mainframe then
		mainframe = mainUi:FindFirstChild(MAINFRAME_NAME, true)
	end

	if not mainframe then
		return nil
	end

	local framesContainer = mainframe:FindFirstChild(FRAMES_CONTAINER_NAME)
	if not framesContainer then
		framesContainer = mainframe:FindFirstChild(FRAMES_CONTAINER_NAME, true)
	end

	if not framesContainer then
		return nil
	end

	local shopRoot = find_gui_object(framesContainer, { SHOP_FRAME_NAME }, true)
	if not shopRoot then
		return nil
	end

	return get_shop_ui(shopRoot)
end

local function bind_ui(ui: ShopUi)
	uiTrove:Destroy()
	uiTrove = Trove.new()
	cardTrove:Clean()

	currentUi = ui
	local seedTemplateSource = make_template_source(ui.SeedTemplate)
	local fruitTemplateSource = make_template_source(ui.FruitTemplate)

	currentSeedTemplateSource = seedTemplateSource
	currentFruitTemplateSource = fruitTemplateSource

	uiTrove:Add(seedTemplateSource)
	uiTrove:Add(fruitTemplateSource)

	strip_local_scripts(ui.SeedsButton)
	strip_local_scripts(ui.FruitsButton)

	if ui.CloseButton then
		strip_local_scripts(ui.CloseButton)
	end

	if ui.RestockButton then
		strip_local_scripts(ui.RestockButton)
	end

	uiTrove:Add(ui.SeedsButton.Activated:Connect(function()
		activeTab = "Seed"
		render_shop()
	end))

	uiTrove:Add(ui.FruitsButton.Activated:Connect(function()
		activeTab = "Fruit"
		render_shop()
	end))

	if ui.CloseButton then
		uiTrove:Add(ui.CloseButton.Activated:Connect(function()
			set_gui_visible(ui.Root, false)
		end))
	end

	if ui.RestockButton then
		uiTrove:Add(ui.RestockButton.Activated:Connect(function()
			activeTab = "Seed"
			render_shop()
		end))
	end

	uiTrove:Add(DataUtility.client.bind("Currencies.Horseshoes", function()
		render_shop()
	end))

	uiTrove:Add(DataUtility.client.bind("Inventory.Seeds", function()
		if activeTab == "Seed" then
			render_shop()
		end
	end))

	uiTrove:Add(DataUtility.client.bind("Inventory.Fruits", function()
		if activeTab == "Fruit" then
			render_shop()
		end
	end))

	uiTrove:Add(ui.Root.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		if currentUi == ui then
			currentUi = nil
			currentSeedTemplateSource = nil
			currentFruitTemplateSource = nil
			cardTrove:Clean()
			uiTrove:Destroy()
			uiTrove = Trove.new()
		end
	end))

	render_shop()
end

local function try_bind_ui()
	if currentUi and currentUi.Root.Parent then
		return
	end

	local ui = find_main_ui()
	if ui then
		bind_ui(ui)
	end
end

DataUtility.client.ensure_remotes()

rootTrove:Add(playerGui.DescendantAdded:Connect(function()
	try_bind_ui()
end))

rootTrove:Add(playerGui.DescendantRemoving:Connect(function(instance)
	if currentUi and (instance == currentUi.Root or instance == currentUi.ScrollingFrame) then
		task.defer(try_bind_ui)
	end
end))

try_bind_ui()