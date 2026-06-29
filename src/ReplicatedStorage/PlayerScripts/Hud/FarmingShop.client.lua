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
local requestInFlight = false

local COINS_FRAME_NAMES = { "Coins", "Coin" }
local COINS_LABEL_NAMES = { "Current", "Currents" }
local SHOP_FRAME_NAMES = { "Shop" }
local SCROLLING_FRAME_NAMES = { "ScrollingFrame", "ScrollFrame", "Scroll" }
local SEED_FRAME_NAMES = { "Seed", "Seeds" }
local FRUIT_FRAME_NAMES = { "Fruit", "Fruits", "Foods" }
local SEED_TAB_NAMES = { "SeedsBT", "SeedBT", "SeedsButton" }
local FRUIT_TAB_NAMES = { "FoodsBT", "FoodBT", "FruitsBT", "FruitBT" }
local BUY_BUTTON_NAMES = { "BuyButton", "BuyBT", "Buy" }
local SELL_BUTTON_NAMES = { "SellButton", "SellBT", "Sell" }
local NAME_LABEL_NAMES = { "Name", "Title", "ItemName" }
local STOCK_LABEL_NAMES = { "Stock", "Owned", "Amount", "Count", "Quantity", "Qtd" }
local VALUE_LABEL_NAMES = { "Value", "Price", "SellValue" }

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

local function matches_name(instance: Instance, aliases): boolean
	local instanceName = normalize_key(instance.Name)
	if not instanceName then
		return false
	end

	for _, alias in ipairs(aliases or {}) do
		if normalize_key(alias) == instanceName then
			return true
		end
	end

	return false
end

local function find_first_named_descendant(root: Instance?, aliases, className: string?): Instance?
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if matches_name(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if matches_name(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
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

local function collect_click_targets(root: Instance?): { GuiButton }
	local buttons = {}

	if not root then
		return buttons
	end

	if root:IsA("GuiButton") then
		buttons[#buttons + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			buttons[#buttons + 1] = descendant
		end
	end

	return buttons
end

local function disable_legacy_scripts(root: Instance?, trove)
	if not root then
		return
	end

	local function remove_legacy(instance: Instance)
		if instance:IsA("LocalScript") then
			instance:Destroy()
		end
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		remove_legacy(descendant)
	end

	trove:Add(root.DescendantAdded:Connect(remove_legacy))
end

local function get_shop_root(mainFrame: Instance): Instance?
	local shopFrame = find_first_named_descendant(mainFrame, SHOP_FRAME_NAMES, nil)
	if not shopFrame then
		return mainFrame
	end

	return find_first_named_descendant(shopFrame, SCROLLING_FRAME_NAMES, nil) or shopFrame
end

local function get_seed_frame(mainFrame: Instance): GuiObject?
	local frame = find_first_named_descendant(get_shop_root(mainFrame), SEED_FRAME_NAMES, nil)
	if frame and frame:IsA("GuiObject") then
		return frame
	end

	return nil
end

local function get_fruit_frame(mainFrame: Instance): GuiObject?
	local frame = find_first_named_descendant(get_shop_root(mainFrame), FRUIT_FRAME_NAMES, nil)
	if frame and frame:IsA("GuiObject") then
		return frame
	end

	return nil
end

local function set_first_text(root: Instance?, aliases, text: string)
	local label = find_first_named_descendant(root, aliases, "TextLabel")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function update_tab_state(mainFrame: Instance)
	local seedFrame = get_seed_frame(mainFrame)
	local fruitFrame = get_fruit_frame(mainFrame)

	if seedFrame then
		seedFrame.Visible = activeTab == "Seed"
	end

	if fruitFrame then
		fruitFrame.Visible = activeTab == "Fruit"
	end
end

local function update_coin_text(mainFrame: Instance, horseshoes: number)
	local coinsFrame = find_first_named_descendant(mainFrame, COINS_FRAME_NAMES, nil)
	set_first_text(coinsFrame, COINS_LABEL_NAMES, format_horseshoes_text(horseshoes))
end

local function update_seed_card(mainFrame: Instance, seedCount: number)
	local seedFrame = get_seed_frame(mainFrame)
	if not seedFrame then
		return
	end

	set_first_text(seedFrame, NAME_LABEL_NAMES, FarmingCatalog.Seed.DisplayName)
	set_first_text(seedFrame, STOCK_LABEL_NAMES, format_stock_text(seedCount))
	set_first_text(seedFrame, VALUE_LABEL_NAMES, format_seed_value_text())
end

local function update_fruit_card(mainFrame: Instance, fruitCount: number)
	local fruitFrame = get_fruit_frame(mainFrame)
	if not fruitFrame then
		return
	end

	set_first_text(fruitFrame, NAME_LABEL_NAMES, FarmingCatalog.Fruit.DisplayName)
	set_first_text(fruitFrame, STOCK_LABEL_NAMES, format_stock_text(fruitCount))
	set_first_text(fruitFrame, VALUE_LABEL_NAMES, format_fruit_value_text())
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

local function bind_click_group(root: Instance?, trove, callback: () -> ())
	local seenButtons = {}

	for _, button in ipairs(collect_click_targets(root)) do
		if not seenButtons[button] and is_button(button) then
			seenButtons[button] = true
			trove:Add(button.Activated:Connect(callback))
		end
	end
end

local function resolve_ui(mainFrame: Instance)
	local coinsFrame = find_first_named_descendant(mainFrame, COINS_FRAME_NAMES, nil)
	local currentLabel = find_first_named_descendant(coinsFrame, COINS_LABEL_NAMES, "TextLabel")
	local seedFrame = get_seed_frame(mainFrame)
	local fruitFrame = get_fruit_frame(mainFrame)
	local seedsTab = find_first_named_descendant(mainFrame, SEED_TAB_NAMES, nil)
	local fruitTab = find_first_named_descendant(mainFrame, FRUIT_TAB_NAMES, nil)
	local buyRoot = find_first_named_descendant(seedFrame, BUY_BUTTON_NAMES, nil)
	local sellRoot = find_first_named_descendant(fruitFrame, SELL_BUTTON_NAMES, nil)

	if not currentLabel or not seedFrame or not fruitFrame or not seedsTab or not fruitTab or not buyRoot or not sellRoot then
		return nil
	end

	return {
		MainFrame = mainFrame,
		CoinsLabel = currentLabel,
		SeedFrame = seedFrame,
		FruitFrame = fruitFrame,
		SeedsTab = seedsTab,
		FruitTab = fruitTab,
		BuyRoot = buyRoot,
		SellRoot = sellRoot,
	}
end

local function find_main_frame(): Instance?
	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant.Name == "Main" and (descendant:IsA("LayerCollector") or descendant:IsA("GuiObject")) then
			local ui = resolve_ui(descendant)
			if ui then
				return ui.MainFrame
			end
		end
	end

	return nil
end

local function bind_main_frame(mainFrame: Instance)
	if currentMainFrame == mainFrame then
		return
	end

	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentMainFrame = mainFrame

	local ui = resolve_ui(mainFrame)
	if not ui then
		return
	end

	disable_legacy_scripts(ui.SeedsTab, uiTrove)
	disable_legacy_scripts(ui.FruitTab, uiTrove)
	disable_legacy_scripts(ui.BuyRoot, uiTrove)
	disable_legacy_scripts(ui.SellRoot, uiTrove)

	bind_click_group(ui.SeedsTab, uiTrove, function()
		activeTab = "Seed"
		update_tab_state(mainFrame)
	end)

	bind_click_group(ui.FruitTab, uiTrove, function()
		activeTab = "Fruit"
		update_tab_state(mainFrame)
	end)

	bind_click_group(ui.BuyRoot, uiTrove, function()
		call_shop_action("BuySeed")
	end)

	bind_click_group(ui.SellRoot, uiTrove, function()
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
