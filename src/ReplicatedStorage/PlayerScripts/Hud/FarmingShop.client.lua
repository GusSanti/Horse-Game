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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local currentMainFrame = nil
local activeTab = "Seed"

local function normalize_amount(amount: number?): number
	return math.max(0, math.floor(tonumber(amount) or 0))
end

local function is_text_object(instance: Instance?): boolean
	return instance ~= nil
		and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox"))
end

local function is_gui_button(instance: Instance?): boolean
	return instance ~= nil and instance:IsA("GuiButton")
end

local function format_horseshoe_text(amount: number): string
	return ("Horseshoe: %d$"):format(normalize_amount(amount))
end

local function format_stock_text(amount: number): string
	return ("Stock: %d"):format(normalize_amount(amount))
end

local function format_seed_value_text(): string
	return ("Value: %d Horseshoe"):format(FarmingCatalog.Seed.Price)
end

local function format_fruit_value_text(): string
	return ("Value: %d Horseshoes"):format(FarmingCatalog.Fruit.SellPrice)
end

local function get_bucket_count(inventoryPath: string, itemId: string): number
	local bucket = DataUtility.client.get(inventoryPath) or {}
	return FarmingCatalog.GetItemCount(bucket, itemId)
end

local function set_text(container: Instance, childName: string, text: string)
	local label = container:FindFirstChild(childName)

	if label and is_text_object(label) then
		label.Text = text
	end
end

local function find_coin_label(mainFrame: Frame)
	local coinsFrame = mainFrame:FindFirstChild("Coins")
	if not coinsFrame then
		return nil
	end

	local coinLabel = coinsFrame:FindFirstChild("Current") or coinsFrame:FindFirstChild("Currents")
	if coinLabel and is_text_object(coinLabel) then
		return coinLabel
	end

	return nil
end

local function resolve_controls(mainFrame: Frame)
	local shopFrame = mainFrame:FindFirstChild("Shop")
	local seedsButton = mainFrame:FindFirstChild("SeedsBT")
	local foodsButton = mainFrame:FindFirstChild("FoodsBT")
	local coinsLabel = find_coin_label(mainFrame)

	if not shopFrame or not shopFrame:IsA("GuiObject") then
		return nil
	end

	local scrollingFrame = shopFrame:FindFirstChild("ScrollingFrame")
	if not scrollingFrame or not scrollingFrame:IsA("ScrollingFrame") then
		return nil
	end

	local seedFrame = scrollingFrame:FindFirstChild("Seed")
	local fruitFrame = scrollingFrame:FindFirstChild("Fruit")
	local buyButton = seedFrame and seedFrame:FindFirstChild("BuyButton")
	local sellButton = fruitFrame and fruitFrame:FindFirstChild("SellButton")

	if not (seedFrame and seedFrame:IsA("GuiObject")) then
		return nil
	end

	if not (fruitFrame and fruitFrame:IsA("GuiObject")) then
		return nil
	end

	if not (coinsLabel and is_gui_button(seedsButton) and is_gui_button(foodsButton)) then
		return nil
	end

	if not (is_gui_button(buyButton) and is_gui_button(sellButton)) then
		return nil
	end

	return {
		CoinsLabel = coinsLabel,
		SeedFrame = seedFrame,
		FruitFrame = fruitFrame,
		SeedsButton = seedsButton,
		FoodsButton = foodsButton,
		BuyButton = buyButton,
		SellButton = sellButton,
	}
end

local function find_main_frame(): Frame?
	local uiScreenGui = playerGui:FindFirstChild("UI")
	if uiScreenGui and uiScreenGui:IsA("ScreenGui") then
		local directMain = uiScreenGui:FindFirstChild("Main")
		if directMain and directMain:IsA("Frame") and resolve_controls(directMain) then
			return directMain
		end
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("Frame") and descendant.Name == "Main" and resolve_controls(descendant) then
			return descendant
		end
	end

	return nil
end

local function update_tab_state(controls)
	controls.SeedFrame.Visible = activeTab == "Seed"
	controls.FruitFrame.Visible = activeTab == "Fruit"
end

local function update_coin_text(controls, horseshoes: number)
	controls.CoinsLabel.Text = format_horseshoe_text(horseshoes)
end

local function update_seed_card(controls, seedCount: number)
	set_text(controls.SeedFrame, "Name", FarmingCatalog.Seed.DisplayName)
	set_text(controls.SeedFrame, "Stock", format_stock_text(seedCount))
	set_text(controls.SeedFrame, "Value", format_seed_value_text())
end

local function update_fruit_card(controls, fruitCount: number)
	set_text(controls.FruitFrame, "Name", FarmingCatalog.Fruit.DisplayName)
	set_text(controls.FruitFrame, "Stock", format_stock_text(fruitCount))
	set_text(controls.FruitFrame, "Value", format_fruit_value_text())
end

local function refresh_all(controls)
	update_coin_text(controls, DataUtility.client.get("Currencies.Horseshoes") or 0)
	update_seed_card(controls, get_bucket_count(FarmingCatalog.Seed.InventoryPath, FarmingCatalog.Seed.ItemId))
	update_fruit_card(controls, get_bucket_count(FarmingCatalog.Fruit.InventoryPath, FarmingCatalog.Fruit.ItemId))
	update_tab_state(controls)
end

local function apply_shop_response(controls, response)
	if type(response) ~= "table" then
		return
	end

	if response.Horseshoes ~= nil then
		update_coin_text(controls, response.Horseshoes)
	end

	if response.SeedCount ~= nil then
		update_seed_card(controls, response.SeedCount)
	end

	if response.FruitCount ~= nil then
		update_fruit_card(controls, response.FruitCount)
	end
end

local function bind_main_frame(mainFrame: Frame)
	local controls = resolve_controls(mainFrame)
	if not controls then
		return
	end

	currentMainFrame = mainFrame
	uiTrove:Destroy()
	uiTrove = Trove.new()

	local actionLocks = {}

	local function run_shop_action(remoteName: string)
		if actionLocks[remoteName] then
			return
		end

		actionLocks[remoteName] = true

		task.spawn(function()
			local success, response = pcall(function()
				return Net.Function[remoteName]:Call()
			end)

			actionLocks[remoteName] = false

			if currentMainFrame ~= mainFrame then
				return
			end

			if success then
				apply_shop_response(controls, response)
			end
		end)
	end

	uiTrove:Add(controls.SeedsButton.Activated:Connect(function()
		activeTab = "Seed"
		update_tab_state(controls)
	end))

	uiTrove:Add(controls.FoodsButton.Activated:Connect(function()
		activeTab = "Fruit"
		update_tab_state(controls)
	end))

	uiTrove:Add(controls.BuyButton.Activated:Connect(function()
		run_shop_action("BuySeed")
	end))

	uiTrove:Add(controls.SellButton.Activated:Connect(function()
		run_shop_action("SellFruit")
	end))

	uiTrove:Add(DataUtility.client.bind("Currencies.Horseshoes", function(horseshoes)
		if currentMainFrame == mainFrame then
			update_coin_text(controls, horseshoes or 0)
		end
	end))

	uiTrove:Add(DataUtility.client.bind(FarmingCatalog.Seed.InventoryPath, function(seedBucket)
		if currentMainFrame == mainFrame then
			update_seed_card(controls, FarmingCatalog.GetItemCount(seedBucket or {}, FarmingCatalog.Seed.ItemId))
		end
	end))

	uiTrove:Add(DataUtility.client.bind(FarmingCatalog.Fruit.InventoryPath, function(fruitBucket)
		if currentMainFrame == mainFrame then
			update_fruit_card(controls, FarmingCatalog.GetItemCount(fruitBucket or {}, FarmingCatalog.Fruit.ItemId))
		end
	end))

	uiTrove:Add(mainFrame.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		if currentMainFrame == mainFrame then
			currentMainFrame = nil
			uiTrove:Destroy()
			uiTrove = Trove.new()
		end
	end))

	refresh_all(controls)
end

local function try_bind_ui()
	local mainFrame = find_main_frame()
	if mainFrame then
		bind_main_frame(mainFrame)
	end
end

DataUtility.client.ensure_remotes()

rootTrove:Add(playerGui.ChildAdded:Connect(function(child)
	if child.Name == "UI" or child:FindFirstChild("Main", true) then
		try_bind_ui()
	end
end))

rootTrove:Add(playerGui.DescendantAdded:Connect(function(instance)
	if instance.Name == "Main"
		or instance.Name == "Shop"
		or instance.Name == "ScrollingFrame"
		or instance.Name == "Seed"
		or instance.Name == "Fruit"
		or instance.Name == "SeedsBT"
		or instance.Name == "FoodsBT"
		or instance.Name == "BuyButton"
		or instance.Name == "SellButton"
		or instance.Name == "Current"
		or instance.Name == "Currents"
	then
		try_bind_ui()
	end
end))

try_bind_ui()
