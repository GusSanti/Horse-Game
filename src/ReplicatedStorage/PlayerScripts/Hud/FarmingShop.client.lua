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
local activeTab = "Seed"
local currentMainFrame = nil
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

local function format_stock_text(amount: number): string
	return ("Stock: %d"):format(amount)
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
		end
	end

	return nil
end

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
	end

	if fruitFrame and fruitFrame:IsA("GuiObject") then
		fruitFrame.Visible = activeTab == "Fruit"
	end
end

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

	uiTrove:Add(DataUtility.client.bind("Currencies.Horseshoes", function(horseshoes)
		if currentMainFrame == mainFrame then
			update_coin_text(mainFrame, horseshoes or 0)
		end
	end))

	uiTrove:Add(DataUtility.client.bind(FarmingCatalog.Seed.InventoryPath, function(seedsBucket)
		if currentMainFrame == mainFrame then
			update_seed_card(mainFrame, FarmingCatalog.GetItemCount(seedsBucket or {}, FarmingCatalog.Seed.ItemId))
		end
	end))

	uiTrove:Add(DataUtility.client.bind(FarmingCatalog.Fruit.InventoryPath, function(fruitBucket)
		if currentMainFrame == mainFrame then
			update_fruit_card(mainFrame, FarmingCatalog.GetItemCount(fruitBucket or {}, FarmingCatalog.Fruit.ItemId))
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

	refresh_all_text(mainFrame)
end

local function try_bind_ui()
	local mainFrame = find_main_frame()
	if mainFrame then
		bind_main_frame(mainFrame)
	end
end

DataUtility.client.ensure_remotes()

rootTrove:Add(playerGui.DescendantAdded:Connect(function()
	try_bind_ui()
end))

try_bind_ui()
