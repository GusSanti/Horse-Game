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

type ShopUi = {
	Main: Instance,
	CoinsLabel: TextLabel,
	ScrollingFrame: ScrollingFrame,
	SeedTemplate: Frame,
	FruitTemplate: Frame,
	SeedsButton: TextButton,
	FoodsButton: TextButton,
	SeedTemplateSource: GuiObject?,
	FruitTemplateSource: GuiObject?,
}

local currentUi: ShopUi? = nil
local activeTab = "Seed"
local requestInFlight = false

local COINS_FRAME_NAMES = { "Coins", "Coin" }
local COINS_LABEL_NAMES = { "Current", "Currents" }
local SHOP_FRAME_NAMES = { "Shop", "Store" }
local SCROLLING_FRAME_NAMES = { "ScrollingFrame", "ScrollFrame", "Scroll" }
local SEED_TEMPLATE_NAMES = { "Seed", "Seeds" }
local FRUIT_TEMPLATE_NAMES = { "Fruit", "Fruits", "Food", "Foods" }
local SEED_TAB_NAMES = { "SeedsBT", "SeedBT", "SeedsButton" }
local FRUIT_TAB_NAMES = { "FoodsBT", "FoodBT", "FruitsBT", "FruitBT", "FoodsButton", "FruitsButton" }
local BUY_BUTTON_NAMES = { "BuyButton", "BuyBT", "Buy" }
local SELL_BUTTON_NAMES = { "SellButton", "SellBT", "Sell" }
local NAME_LABEL_NAMES = { "Name", "Title", "ItemName" }
local STOCK_LABEL_NAMES = { "Stock", "Owned", "Amount", "Count", "Quantity", "Qtd" }
local VALUE_LABEL_NAMES = { "Value", "Price", "SellValue" }
local IMAGE_CONTAINER_NAMES = { "SeedImage", "FruitImage", "ItemImage", "Image", "Icon" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }

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

local function find_text_label(root: Instance?, aliases): TextLabel?
	local instance = find_named_instance(root, aliases, "TextLabel")
	if instance then
		return instance :: TextLabel
	end

	return nil
end

local function find_text_button(root: Instance?, aliases): TextButton?
	local instance = find_named_instance(root, aliases, "TextButton")
	if instance then
		return instance :: TextButton
	end

	return nil
end

local function find_gui_button(root: Instance?, aliases): GuiButton?
	local instance = find_named_instance(root, aliases, "GuiButton")
	if instance then
		return instance :: GuiButton
	end

	return nil
end

local function find_frame(root: Instance?, aliases): Frame?
	local directFrame = find_named_instance(root, aliases, "Frame", false)
	if directFrame then
		return directFrame :: Frame
	end

	local recursiveFrame = find_named_instance(root, aliases, "Frame")
	if recursiveFrame then
		return recursiveFrame :: Frame
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

local function get_main_ui(main: Instance): ShopUi?
	local coinsFrame = find_named_instance(main, COINS_FRAME_NAMES, nil)
	local shopFrame = find_named_instance(main, SHOP_FRAME_NAMES, nil)
	local scrollingFrame = find_scrolling_frame(shopFrame or main)
	local seedTemplate = find_frame(scrollingFrame, SEED_TEMPLATE_NAMES)
	local fruitTemplate = find_frame(scrollingFrame, FRUIT_TEMPLATE_NAMES)
	local seedsButton = find_text_button(main, SEED_TAB_NAMES)
	local foodsButton = find_text_button(main, FRUIT_TAB_NAMES)
	local currentLabel = find_text_label(coinsFrame, COINS_LABEL_NAMES) or find_text_label(main, COINS_LABEL_NAMES)

	if not currentLabel or not scrollingFrame or not seedTemplate or not fruitTemplate or not seedsButton or not foodsButton then
		return nil
	end

	return {
		Main = main,
		CoinsLabel = currentLabel,
		ScrollingFrame = scrollingFrame,
		SeedTemplate = seedTemplate,
		FruitTemplate = fruitTemplate,
		SeedsButton = seedsButton,
		FoodsButton = foodsButton,
	}
end

local function find_main_ui(): ShopUi?
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant.Name == "Main" then
			local ui = get_main_ui(descendant)
			if ui then
				return ui
			end
		end
	end

	return nil
end

local function strip_local_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("LocalScript") then
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

local function format_stock(amount: number): string
	return ("Stock: %d"):format(amount)
end

local function format_value(itemDefinition): string
	if itemDefinition.Kind == "Seed" then
		return ("Value: %d Horseshoe"):format(itemDefinition.Price or 0)
	end

	return ("Value: %d Horseshoes"):format(itemDefinition.SellPrice or 0)
end

local function update_horseshoes()
	if not currentUi then
		return
	end

	local horseshoes = DataUtility.client.get("Currencies.Horseshoes") or 0
	currentUi.CoinsLabel.Text = ("Horseshoe: %d$"):format(horseshoes)
end

local function clear_viewport(viewportFrame: ViewportFrame)
	for _, child in ipairs(viewportFrame:GetChildren()) do
		child:Destroy()
	end
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
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	if root:IsA("BasePart") then
		root.Anchored = true
		root.CanCollide = false
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
end

local function populate_viewport(card: Instance, itemDefinition)
	local imageContainer = find_named_instance(card, IMAGE_CONTAINER_NAMES, nil)
	local viewportFrame = imageContainer and find_named_instance(imageContainer, VIEWPORT_FRAME_NAMES, "ViewportFrame")
	if not viewportFrame then
		viewportFrame = find_named_instance(card, VIEWPORT_FRAME_NAMES, "ViewportFrame")
	end

	if not viewportFrame or not viewportFrame:IsA("ViewportFrame") then
		return
	end

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
	camera.FieldOfView = 35
	camera.Parent = viewportFrame
	viewportFrame.CurrentCamera = camera
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.Ambient = Color3.fromRGB(220, 220, 220)
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)

	local radius = math.max(size.X, size.Y, size.Z) * 0.55
	local distance = radius / math.tan(math.rad(camera.FieldOfView * 0.5)) + radius
	camera.CFrame = CFrame.lookAt(center + Vector3.new(distance * 0.45, distance * 0.2, distance), center)
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

local function configure_card(card: GuiObject, itemDefinition, amount: number)
	card.Name = itemDefinition.ItemId
	card.Visible = true
	card.LayoutOrder = itemDefinition.SortOrder or 0

	local nameLabel = find_text_label(card, NAME_LABEL_NAMES)
	local stockLabel = find_text_label(card, STOCK_LABEL_NAMES)
	local valueLabel = find_text_label(card, VALUE_LABEL_NAMES)

	if nameLabel then
		nameLabel.Text = itemDefinition.DisplayName
	end

	if stockLabel then
		stockLabel.Text = format_stock(amount)
	end

	if valueLabel then
		valueLabel.Text = format_value(itemDefinition)
	end

	populate_viewport(card, itemDefinition)
end

local function render_shop()
	if not currentUi then
		return
	end

	cardTrove:Clean()
	currentUi.ScrollingFrame.CanvasPosition = Vector2.zero

	local itemDefinitions = activeTab == "Seed" and get_seed_items() or get_fruit_items()
	local template = activeTab == "Seed" and currentUi.SeedTemplateSource or currentUi.FruitTemplateSource
	local inventoryPath = activeTab == "Seed" and "Inventory.Seeds" or "Inventory.Fruits"
	local inventoryBucket = DataUtility.client.get(inventoryPath) or {}

	for _, itemDefinition in ipairs(itemDefinitions) do
		local card = template:Clone()
		card.Parent = currentUi.ScrollingFrame
		cardTrove:Add(card)

		configure_card(card, itemDefinition, get_item_count(inventoryBucket, itemDefinition.ItemId))

		local remoteName = activeTab == "Seed" and "BuySeed" or "SellFruit"
		local buttonAliases = activeTab == "Seed" and BUY_BUTTON_NAMES or SELL_BUTTON_NAMES
		local button = find_gui_button(card, buttonAliases)

		if button then
			cardTrove:Add(button.Activated:Connect(function()
				call_shop(remoteName, itemDefinition.ItemId)
			end))
		end
	end

	update_canvas_size()
	task.defer(update_canvas_size)
end

local function bind_ui(ui)
	uiTrove:Destroy()
	uiTrove = Trove.new()
	cardTrove:Clean()

	currentUi = ui
	currentUi.SeedTemplateSource = make_template_source(ui.SeedTemplate)
	currentUi.FruitTemplateSource = make_template_source(ui.FruitTemplate)
	uiTrove:Add(currentUi.SeedTemplateSource)
	uiTrove:Add(currentUi.FruitTemplateSource)

	strip_local_scripts(ui.SeedsButton)
	strip_local_scripts(ui.FoodsButton)

	uiTrove:Add(ui.SeedsButton.Activated:Connect(function()
		activeTab = "Seed"
		render_shop()
	end))

	uiTrove:Add(ui.FoodsButton.Activated:Connect(function()
		activeTab = "Fruit"
		render_shop()
	end))

	uiTrove:Add(DataUtility.client.bind("Currencies.Horseshoes", update_horseshoes))
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

	uiTrove:Add(ui.Main.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		if currentUi == ui then
			currentUi = nil
			cardTrove:Clean()
			uiTrove:Destroy()
			uiTrove = Trove.new()
		end
	end))

	update_horseshoes()
	render_shop()
end

local function try_bind_ui()
	if currentUi and currentUi.Main.Parent then
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

try_bind_ui()
