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

local function format_stock_text(amount: number): string
	return ("Stock: %d"):format(amount)
end

local function format_seed_value_text(): string
	return ("Value: %d Horseshoe"):format(FarmingCatalog.Seed.Price)
end

local function format_fruit_value_text(): string
	return ("Value: %d Horseshoes"):format(FarmingCatalog.Fruit.SellPrice)
end

local function find_main_frame(): Frame?
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("Frame") and descendant.Name == "Main" then
			local coins = descendant:FindFirstChild("Coins")
			local currentLabel = coins and coins:FindFirstChild("Current")
			local shop = descendant:FindFirstChild("Shop")
			local scrollingFrame = shop and shop:FindFirstChild("ScrollingFrame")
			local seedFrame = scrollingFrame and scrollingFrame:FindFirstChild("Seed")
			local fruitFrame = scrollingFrame and scrollingFrame:FindFirstChild("Fruit")
			local buyButton = seedFrame and seedFrame:FindFirstChild("BuyButton")
			local sellButton = fruitFrame and fruitFrame:FindFirstChild("SellButton")
			local seedsButton = descendant:FindFirstChild("SeedsBT")
			local foodsButton = descendant:FindFirstChild("FoodsBT")

			if currentLabel and buyButton and sellButton and seedsButton and foodsButton then
				return descendant
			end
		end
	end

	return nil
end

local function update_tab_state(mainFrame: Frame)
	local shopFrame = mainFrame:FindFirstChild("Shop")
	if not shopFrame then
		return
	end

	local scrollingFrame = shopFrame:FindFirstChild("ScrollingFrame")
	if not scrollingFrame then
		return
	end

	local seedFrame = scrollingFrame:FindFirstChild("Seed")
	local fruitFrame = scrollingFrame:FindFirstChild("Fruit")

	if seedFrame and seedFrame:IsA("GuiObject") then
		seedFrame.Visible = activeTab == "Seed"
	end

	if fruitFrame and fruitFrame:IsA("GuiObject") then
		fruitFrame.Visible = activeTab == "Fruit"
	end
end

local function update_coin_text(mainFrame: Frame, horseshoes: number)
	local coinsFrame = mainFrame:FindFirstChild("Coins")
	local currentLabel = coinsFrame and coinsFrame:FindFirstChild("Current")

	if currentLabel and currentLabel:IsA("TextLabel") then
		currentLabel.Text = tostring(horseshoes)
	end
end

local function update_seed_card(mainFrame: Frame, seedCount: number)
	local shopFrame = mainFrame:FindFirstChild("Shop")
	local scrollingFrame = shopFrame and shopFrame:FindFirstChild("ScrollingFrame")
	local seedFrame = scrollingFrame and scrollingFrame:FindFirstChild("Seed")

	if not seedFrame then
		return
	end

	local nameLabel = seedFrame:FindFirstChild("Name")
	local stockLabel = seedFrame:FindFirstChild("Stock")
	local valueLabel = seedFrame:FindFirstChild("Value")

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

local function update_fruit_card(mainFrame: Frame, fruitCount: number)
	local shopFrame = mainFrame:FindFirstChild("Shop")
	local scrollingFrame = shopFrame and shopFrame:FindFirstChild("ScrollingFrame")
	local fruitFrame = scrollingFrame and scrollingFrame:FindFirstChild("Fruit")

	if not fruitFrame then
		return
	end

	local nameLabel = fruitFrame:FindFirstChild("Name")
	local stockLabel = fruitFrame:FindFirstChild("Stock")
	local valueLabel = fruitFrame:FindFirstChild("Value")

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

local function refresh_all_text(mainFrame: Frame)
	local horseshoes = DataUtility.client.get("Currencies.Horseshoes") or 0
	local seedsBucket = DataUtility.client.get(FarmingCatalog.Seed.InventoryPath) or {}
	local fruitBucket = DataUtility.client.get(FarmingCatalog.Fruit.InventoryPath) or {}

	update_coin_text(mainFrame, horseshoes)
	update_seed_card(mainFrame, FarmingCatalog.GetItemCount(seedsBucket, FarmingCatalog.Seed.ItemId))
	update_fruit_card(mainFrame, FarmingCatalog.GetItemCount(fruitBucket, FarmingCatalog.Fruit.ItemId))
	update_tab_state(mainFrame)
end

local function call_shop_action(remoteName: string)
	task.spawn(function()
		pcall(function()
			Net.Function[remoteName]:Call()
		end)
	end)
end

local function bind_main_frame(mainFrame: Frame)
	if currentMainFrame == mainFrame then
		return
	end

	currentMainFrame = mainFrame
	uiTrove:Destroy()
	uiTrove = Trove.new()

	local seedsButton = mainFrame:FindFirstChild("SeedsBT")
	local foodsButton = mainFrame:FindFirstChild("FoodsBT")
	local shopFrame = mainFrame:FindFirstChild("Shop")
	local scrollingFrame = shopFrame and shopFrame:FindFirstChild("ScrollingFrame")
	local seedFrame = scrollingFrame and scrollingFrame:FindFirstChild("Seed")
	local fruitFrame = scrollingFrame and scrollingFrame:FindFirstChild("Fruit")
	local buyButton = seedFrame and seedFrame:FindFirstChild("BuyButton")
	local sellButton = fruitFrame and fruitFrame:FindFirstChild("SellButton")

	if seedsButton and seedsButton:IsA("TextButton") then
		uiTrove:Add(seedsButton.MouseButton1Click:Connect(function()
			activeTab = "Seed"
			update_tab_state(mainFrame)
		end))
	end

	if foodsButton and foodsButton:IsA("TextButton") then
		uiTrove:Add(foodsButton.MouseButton1Click:Connect(function()
			activeTab = "Fruit"
			update_tab_state(mainFrame)
		end))
	end

	if buyButton and buyButton:IsA("TextButton") then
		uiTrove:Add(buyButton.MouseButton1Click:Connect(function()
			call_shop_action("BuySeed")
		end))
	end

	if sellButton and sellButton:IsA("TextButton") then
		uiTrove:Add(sellButton.MouseButton1Click:Connect(function()
			call_shop_action("SellFruit")
		end))
	end

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
