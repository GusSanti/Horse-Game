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

local currentUi = nil
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

local function find_text_label(root: Instance?, name: string): TextLabel?
	local instance = root and root:FindFirstChild(name, true)
	if instance and instance:IsA("TextLabel") then
		return instance
	end

	return nil
end

local function find_button(root: Instance?, name: string): GuiButton?
	local instance = root and root:FindFirstChild(name, true)
	if instance and instance:IsA("GuiButton") then
		return instance
	end

	return nil
end

local function get_main_ui(main: Instance)
	local coins = main:FindFirstChild("Coins")
	local shop = main:FindFirstChild("Shop")
	local scrollingFrame = shop and shop:FindFirstChild("ScrollingFrame")
	local seedTemplate = scrollingFrame and scrollingFrame:FindFirstChild("Seed")
	local fruitTemplate = scrollingFrame and scrollingFrame:FindFirstChild("Fruit")
	local seedsButton = main:FindFirstChild("SeedsBT", true)
	local foodsButton = main:FindFirstChild("FoodsBT", true)
	local currentLabel = find_text_label(coins, "Current") or find_text_label(coins, "Currents")

	if not currentLabel then
		return nil
	end

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

	if not foodsButton or not foodsButton:IsA("GuiButton") then
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

local function find_main_ui()
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
	local seedImage = card:FindFirstChild("SeedImage", true)
	local viewportFrame = seedImage and seedImage:FindFirstChild("ViewportFrame", true)

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

	local nameLabel = find_text_label(card, "Name")
	local stockLabel = find_text_label(card, "Stock")
	local valueLabel = find_text_label(card, "Value")

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

		local buttonName = activeTab == "Seed" and "BuyButton" or "SellButton"
		local remoteName = activeTab == "Seed" and "BuySeed" or "SellFruit"
		local button = find_button(card, buttonName)

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
