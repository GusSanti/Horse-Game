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
<<<<<<< HEAD
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
=======
local requestInFlight = false

local function find_named_descendant(root: Instance?, name: string): Instance?
	if not root then
		return nil
	end

	local directChild = root:FindFirstChild(name)
	if directChild then
		return directChild
	end

	return root:FindFirstChild(name, true)
end

local function is_button(instance: Instance?): boolean
	return instance ~= nil and instance:IsA("GuiButton")
end
>>>>>>> main

local function format_stock_text(amount: number): string
	return ("Stock: %d"):format(normalize_amount(amount))
end

local function format_horseshoes_text(amount: number): string
	return ("Horseshoe: %d$"):format(amount)
end

local function format_seed_value_text(): string
	return ("Value: %d Horseshoe"):format(FarmingCatalog.Seed.Price)
end

local function format_fruit_value_text(): string
	return ("Value: %d Horseshoes"):format(FarmingCatalog.Fruit.SellPrice)
end

<<<<<<< HEAD
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
=======
local function find_main_frame(): Instance?
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("GuiObject") and descendant.Name == "Main" then
			local coins = find_named_descendant(descendant, "Coins")
			local currentLabel = coins and find_named_descendant(coins, "Current")
			local shop = find_named_descendant(descendant, "Shop")
			local scrollingFrame = shop and find_named_descendant(shop, "ScrollingFrame")
			local seedFrame = scrollingFrame and find_named_descendant(scrollingFrame, "Seed")
			local fruitFrame = scrollingFrame and find_named_descendant(scrollingFrame, "Fruit")
			local buyButton = seedFrame and find_named_descendant(seedFrame, "BuyButton")
			local sellButton = fruitFrame and find_named_descendant(fruitFrame, "SellButton")
			local seedsButton = find_named_descendant(descendant, "SeedsBT")
			local foodsButton = find_named_descendant(descendant, "FoodsBT")

			if currentLabel and is_button(buyButton) and is_button(sellButton) and is_button(seedsButton) and is_button(foodsButton) then
				return descendant
			end
>>>>>>> main
		end
	end

	return nil
end

<<<<<<< HEAD
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
=======
local function disable_legacy_button_scripts(button: Instance?, trove)
	if not button then
		return
	end

	local function remove_if_legacy(instance: Instance)
		if instance:IsA("LocalScript") then
			instance:Destroy()
		end
	end

	for _, child in ipairs(button:GetDescendants()) do
		remove_if_legacy(child)
	end

	trove:Add(button.DescendantAdded:Connect(remove_if_legacy))
end

local function cleanup_legacy_ui_scripts(mainFrame: Instance, trove)
	local shopFrame = find_named_descendant(mainFrame, "Shop")
	local scrollingFrame = shopFrame and find_named_descendant(shopFrame, "ScrollingFrame")
	local seedFrame = scrollingFrame and find_named_descendant(scrollingFrame, "Seed")
	local fruitFrame = scrollingFrame and find_named_descendant(scrollingFrame, "Fruit")

	disable_legacy_button_scripts(find_named_descendant(mainFrame, "SeedsBT"), trove)
	disable_legacy_button_scripts(find_named_descendant(mainFrame, "FoodsBT"), trove)
	disable_legacy_button_scripts(seedFrame and find_named_descendant(seedFrame, "BuyButton"), trove)
	disable_legacy_button_scripts(fruitFrame and find_named_descendant(fruitFrame, "SellButton"), trove)
end

local function update_tab_state(mainFrame: Instance)
	local shopFrame = find_named_descendant(mainFrame, "Shop")
	if not shopFrame then
		return
	end

	local scrollingFrame = find_named_descendant(shopFrame, "ScrollingFrame")
	if not scrollingFrame then
		return
	end

	local seedFrame = find_named_descendant(scrollingFrame, "Seed")
	local fruitFrame = find_named_descendant(scrollingFrame, "Fruit")

	if seedFrame and seedFrame:IsA("GuiObject") then
		seedFrame.Visible = activeTab == "Seed"
>>>>>>> main
	end

	if response.FruitCount ~= nil then
		update_fruit_card(controls, response.FruitCount)
	end
end

<<<<<<< HEAD
local function bind_main_frame(mainFrame: Frame)
	local controls = resolve_controls(mainFrame)
	if not controls then
=======
local function update_coin_text(mainFrame: Instance, horseshoes: number)
	local coinsFrame = find_named_descendant(mainFrame, "Coins")
	local currentLabel = coinsFrame and find_named_descendant(coinsFrame, "Current")

	if currentLabel and currentLabel:IsA("TextLabel") then
		currentLabel.Text = format_horseshoes_text(horseshoes)
	end
end

local function update_seed_card(mainFrame: Instance, seedCount: number)
	local shopFrame = find_named_descendant(mainFrame, "Shop")
	local scrollingFrame = shopFrame and find_named_descendant(shopFrame, "ScrollingFrame")
	local seedFrame = scrollingFrame and find_named_descendant(scrollingFrame, "Seed")

	if not seedFrame then
		return
	end

	local nameLabel = find_named_descendant(seedFrame, "Name")
	local stockLabel = find_named_descendant(seedFrame, "Stock")
	local valueLabel = find_named_descendant(seedFrame, "Value")

	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = FarmingCatalog.Seed.DisplayName
	end

	if stockLabel and stockLabel:IsA("TextLabel") then
		stockLabel.Text = format_stock_text(seedCount)
	end

	if valueLabel and valueLabel:IsA("TextLabel") then
		valueLabel.Text = format_seed_value_text()
	end
end

local function update_fruit_card(mainFrame: Instance, fruitCount: number)
	local shopFrame = find_named_descendant(mainFrame, "Shop")
	local scrollingFrame = shopFrame and find_named_descendant(shopFrame, "ScrollingFrame")
	local fruitFrame = scrollingFrame and find_named_descendant(scrollingFrame, "Fruit")

	if not fruitFrame then
		return
	end

	local nameLabel = find_named_descendant(fruitFrame, "Name")
	local stockLabel = find_named_descendant(fruitFrame, "Stock")
	local valueLabel = find_named_descendant(fruitFrame, "Value")

	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Text = FarmingCatalog.Fruit.DisplayName
	end

	if stockLabel and stockLabel:IsA("TextLabel") then
		stockLabel.Text = format_stock_text(fruitCount)
	end

	if valueLabel and valueLabel:IsA("TextLabel") then
		valueLabel.Text = format_fruit_value_text()
	end
end

local function refresh_all_text(mainFrame: Instance)
	local horseshoes = DataUtility.client.get("Currencies.Horseshoes") or 0
	local seedsBucket = DataUtility.client.get(FarmingCatalog.Seed.InventoryPath) or {}
	local fruitBucket = DataUtility.client.get(FarmingCatalog.Fruit.InventoryPath) or {}

	update_coin_text(mainFrame, horseshoes)
	update_seed_card(mainFrame, FarmingCatalog.GetItemCount(seedsBucket, FarmingCatalog.Seed.ItemId))
	update_fruit_card(mainFrame, FarmingCatalog.GetItemCount(fruitBucket, FarmingCatalog.Fruit.ItemId))
	update_tab_state(mainFrame)
end

local function call_shop_action(remoteName: string)
	if requestInFlight then
		return
	end

	requestInFlight = true

	task.spawn(function()
		pcall(function()
			Net.Function[remoteName]:Call()
		end)

		requestInFlight = false
	end)
end

local function bind_button(button: Instance?, trove, callback: () -> ())
	if not is_button(button) then
>>>>>>> main
		return
	end

	trove:Add(button.Activated:Connect(callback))

	if button:IsA("TextButton") or button:IsA("ImageButton") then
		trove:Add(button.MouseButton1Click:Connect(callback))
	end
end

local function bind_main_frame(mainFrame: Instance)
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentMainFrame = mainFrame
	cleanup_legacy_ui_scripts(mainFrame, uiTrove)

<<<<<<< HEAD
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
=======
	local seedsButton = find_named_descendant(mainFrame, "SeedsBT")
	local foodsButton = find_named_descendant(mainFrame, "FoodsBT")
	local shopFrame = find_named_descendant(mainFrame, "Shop")
	local scrollingFrame = shopFrame and find_named_descendant(shopFrame, "ScrollingFrame")
	local seedFrame = scrollingFrame and find_named_descendant(scrollingFrame, "Seed")
	local fruitFrame = scrollingFrame and find_named_descendant(scrollingFrame, "Fruit")
	local buyButton = seedFrame and find_named_descendant(seedFrame, "BuyButton")
	local sellButton = fruitFrame and find_named_descendant(fruitFrame, "SellButton")

	bind_button(seedsButton, uiTrove, function()
		activeTab = "Seed"
		update_tab_state(mainFrame)
	end)

	bind_button(foodsButton, uiTrove, function()
		activeTab = "Fruit"
		update_tab_state(mainFrame)
	end)

	bind_button(buyButton, uiTrove, function()
		call_shop_action("BuySeed")
	end)

	bind_button(sellButton, uiTrove, function()
		call_shop_action("SellFruit")
	end)
>>>>>>> main

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
