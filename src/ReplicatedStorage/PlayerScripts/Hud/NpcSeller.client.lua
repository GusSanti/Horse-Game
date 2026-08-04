local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseEquipmentUtility = require(Utility:WaitForChild("Horse"):WaitForChild("HorseEquipmentUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local HudAnim = require(Libraries:WaitForChild("HudAnim"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local activeShopId = nil
local activeCategory = nil
local sellerRoot = nil
local scrollingFrame = nil
local templateSource = nil
local cardConnections = {}
local cardCache = {}
local sellerHudAnimBound = false
local renderedShopId = nil
local renderedCategory = nil
local sellerTabsRoot = nil
local sellerTabButtons = {}
local sellerCloseButton = nil
local sellerRestockButton = nil
local sellerTitle = nil
local zoneState = {
	Cowboy = false,
	Doctor = false,
	TackShop = false,
	Noob = false,
}

local SHOP_TABS = {
	Cowboy = {
		{ Category = "Water", Label = "Water" },
		{ Category = "Tack", Label = "Saddles" },
	},
	Doctor = {
		{ Category = "Medicine", Label = "Medicine" },
	},
	TackShop = {
		{ Category = "Tack", Label = "Tack" },
	},
	Noob = {
		{ Category = "Misc", Label = "Cleaning" },
	},
}

local SHOP_TITLE_BACKGROUND_NAMES = { "SeedShopBG", "FruitShopBG", "ShopBG" }
local SHOP_TITLE_LABEL_NAMES = { "BuyTX", "TitleTX", "ShopTitleTX", "SellerTX" }

local CLOSE_BUTTON_NAMES = {
	close = true,
	closebt = true,
	exitbt = true,
}

local RESTOCK_BUTTON_NAMES = {
	reestockbt = true,
	restockbt = true,
	restyockbt = true,
}

local PURCHASE_BUTTON_NAMES = {
	buy = true,
	buybt = true,
	purchasebt = true,
}

local function find_named(root, names, className)
	for _, instance in ipairs(root:GetDescendants()) do
		for _, name in ipairs(names) do
			if string.lower(instance.Name) == string.lower(name) and (not className or instance:IsA(className)) then
				return instance
			end
		end
	end
end

local function find_button(root, names)
	return find_named(root, names, "GuiButton")
end

local function matches_normalized_name(instance, names)
	return instance and names[string.lower(instance.Name)] == true
end

local function is_close_button(button)
	return matches_normalized_name(button, CLOSE_BUTTON_NAMES)
end

local function is_restock_button(button)
	return matches_normalized_name(button, RESTOCK_BUTTON_NAMES)
end

local function is_purchase_button(button)
	return matches_normalized_name(button, PURCHASE_BUTTON_NAMES)
end

local function is_tab_button_candidate(button)
	if is_close_button(button) or is_restock_button(button) or is_purchase_button(button) then
		return false
	end

	if scrollingFrame and button:IsDescendantOf(scrollingFrame) then
		return false
	end

	return true
end

local function find_label(root, names)
	return find_named(root, names, "TextLabel")
end

local function is_text_instance(instance)
	return instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")
end

local function find_text_instance(root, names)
	if not root then
		return nil
	end

	for _, instance in ipairs(root:GetDescendants()) do
		if is_text_instance(instance) and (not scrollingFrame or not instance:IsDescendantOf(scrollingFrame)) then
			for _, name in ipairs(names) do
				if string.lower(instance.Name) == string.lower(name) then
					return instance
				end
			end
		end
	end
end

local function set_text_instance_text(instance, value)
	if instance and is_text_instance(instance) then
		instance.Text = value
	end
end

local function get_shop_display_name(shopId)
	local shopDefinition = ToolItemCatalog.GetShopDefinition(shopId)
	if shopDefinition and type(shopDefinition.DisplayName) == "string" and shopDefinition.DisplayName ~= "" then
		return shopDefinition.DisplayName
	end

	return tostring(shopId or "Seller")
end

local function update_shop_title(shopId)
	if not sellerRoot then
		return
	end

	if not (sellerTitle and sellerTitle.Parent) then
		local background = find_named(sellerRoot, SHOP_TITLE_BACKGROUND_NAMES, "GuiObject")
		sellerTitle = background and find_text_instance(background, SHOP_TITLE_LABEL_NAMES)
			or find_text_instance(sellerRoot, SHOP_TITLE_LABEL_NAMES)
	end

	set_text_instance_text(sellerTitle, get_shop_display_name(shopId))
end

local function set_button_text(button, value)
	if button:IsA("TextButton") then button.Text = value end
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") then descendant.Text = value end
	end
end

local function find_item_asset(item)
	if item and item.EquipmentType == "Saddle" then
		local saddleVisual = HorseEquipmentUtility.GetSaddleVisualAsset(item)
		if saddleVisual then
			return saddleVisual
		end
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local items = assets and assets:FindFirstChild("Items")
	if not items then return nil end
	local folder = items:FindFirstChild(ToolItemCatalog.GetCategoryFolderName(item))
	for _, root in ipairs({ folder, items }) do
		if root then
			for _, name in ipairs({ item.ToolName, item.DisplayName, item.ItemId }) do
				if type(name) == "string" then
					local asset = root:FindFirstChild(name, true)
					if asset then return asset end
				end
			end
		end
	end
end

local function normalize_image_id(value)
	if type(value) == "number" then
		return ("rbxassetid://%d"):format(value)
	end

	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	if trimmedValue == "" then
		return nil
	end

	if string.match(trimmedValue, "^%d+$") then
		return ("rbxassetid://%s"):format(trimmedValue)
	end

	return trimmedValue
end

local function get_item_icon_image(item)
	if type(item) ~= "table" then
		return nil
	end

	return normalize_image_id(item.IconImage)
		or normalize_image_id(item.IconImageId)
		or normalize_image_id(item.Image)
		or normalize_image_id(item.ImageId)
end

local function clear_viewport(viewport)
	if not viewport then
		return
	end

	for _, child in ipairs(viewport:GetChildren()) do
		child:Destroy()
	end

	viewport.CurrentCamera = nil
end

local function apply_image_icon(card, item, viewport)
	local iconImage = get_item_icon_image(item)
	local imageLabel = find_named(card, { "ImageLabel", "ImageItem", "ItemImage", "Icon" }, "ImageLabel")
		or find_named(card, { "ImageLabel", "ImageItem", "ItemImage", "Icon" }, "ImageButton")

	if not iconImage or not imageLabel then
		return false
	end

	imageLabel.Image = iconImage
	imageLabel.ImageTransparency = 0
	imageLabel.ScaleType = Enum.ScaleType.Fit

	clear_viewport(viewport)
	if viewport then
		viewport.Visible = false
	end

	return true
end

local function populate_icon(card, item)
	local viewport = find_named(card, { "ViewportFrame", "ViewPortFrame", "Viewport" }, "ViewportFrame")
	if apply_image_icon(card, item, viewport) then return end
	if not viewport then return end
	viewport.Visible = true
	clear_viewport(viewport)
	local asset = find_item_asset(item)
	if not asset then return end
	local model = asset:Clone()
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport
	local displayObject = model
	if not model:IsA("Model") and not model:IsA("BasePart") then
		local wrapper = Instance.new("Model")
		wrapper.Name = item.ItemId .. "Preview"
		wrapper.Parent = worldModel
		model.Parent = wrapper
		displayObject = wrapper
	else
		model.Parent = worldModel
	end
	local boundsCFrame, boundsSize
	if displayObject:IsA("Model") then
		boundsCFrame, boundsSize = displayObject:GetBoundingBox()
	elseif displayObject:IsA("BasePart") then
		boundsCFrame, boundsSize = displayObject.CFrame, displayObject.Size
	else
		return
	end
	local largestDimension = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z, 1)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	local distance = largestDimension * 2.2
	camera.CFrame = CFrame.lookAt(
		boundsCFrame.Position + Vector3.new(distance * 0.55, distance * 0.2, distance),
		boundsCFrame.Position
	)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	viewport.BackgroundTransparency = 1
end

local function clear_card_cache()
	for _, connection in ipairs(cardConnections) do connection:Disconnect() end
	table.clear(cardConnections)
	for _, entry in pairs(cardCache) do
		if entry.Card and entry.Card.Parent then
			entry.Card:Destroy()
		end
	end
	table.clear(cardCache)
	renderedShopId = nil
	renderedCategory = nil
end

local function hide_cached_cards()
	for _, entry in pairs(cardCache) do
		if entry.Card and entry.Card.Parent then
			entry.Card.Visible = false
		end
	end
end

local function get_items_for_shop(shopId, category)
	local items = {}
	for _, item in ipairs(ToolItemCatalog.GetItemsForShop(shopId) or {}) do
		if (item.ShopCategory or item.ToolCategory) == category then table.insert(items, item) end
	end
	return items
end

local function update_canvas_size()
	if not scrollingFrame then return end
	local layout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
		or scrollingFrame:FindFirstChildOfClass("UIGridLayout")
	if not layout then return end
	local contentHeight = layout.AbsoluteContentSize.Y + 24
	if activeShopId == "Cowboy" then
		contentHeight = math.max(contentHeight, scrollingFrame.AbsoluteSize.Y * 2)
	elseif activeShopId == "Doctor" then
		contentHeight = math.max(contentHeight, scrollingFrame.AbsoluteSize.Y * 1.35)
	end
	scrollingFrame.CanvasSize = UDim2.fromOffset(0, contentHeight)
end

local render

local function get_card_cache_key(shopId, itemId)
	return tostring(shopId) .. ":" .. tostring(itemId)
end

local function update_card_affordability(entry, horseshoes)
	if not entry.BuyButton then
		return
	end

	entry.BuyButton.Active = horseshoes >= entry.Price
	entry.BuyButton.AutoButtonColor = entry.BuyButton.Active
end

local function get_or_create_card(shopId, item, horseshoes)
	local cacheKey = get_card_cache_key(shopId, item.ItemId)
	local cachedEntry = cardCache[cacheKey]
	if cachedEntry and cachedEntry.Card and cachedEntry.Card.Parent then
		update_card_affordability(cachedEntry, horseshoes)
		return cachedEntry
	end

	local card = templateSource:Clone()
	card.Name = item.ItemId
	card:SetAttribute("NpcSellerCard", true)
	card.Visible = false
	card.LayoutOrder = item.SortOrder or 0
	local name = find_label(card, { "ItemNameTX", "NameTX", "Name" })
	local price = find_label(card, { "ValueTX", "PriceTX", "Price" })
	local stock = find_label(card, { "StockCountTX", "StockTX", "CountTX" })
	if name then name.Text = item.DisplayName end
	if price then price.Text = "$" .. tostring(item.Price or 0) end
	if stock then stock.Visible = false end
	populate_icon(card, item)

	local entry = {
		Card = card,
		BuyButton = find_button(card, { "PurchaseBT", "BuyBT", "Buy" }),
		Price = item.Price or 0,
	}
	cardCache[cacheKey] = entry
	update_card_affordability(entry, horseshoes)

	if entry.BuyButton then
		local connection = entry.BuyButton.Activated:Connect(function()
			local response = Net.Function.BuyNpcShopItem:Call(shopId, item.ItemId)
			if response and response.Success and activeShopId == shopId then
				render()
			end
		end)
		table.insert(cardConnections, connection)
	end

	-- Parent only after the card is fully configured. This avoids repeated layout
	-- and viewport invalidations while each property is populated.
	card.Parent = scrollingFrame
	return entry
end

render = function()
	if not (sellerRoot and scrollingFrame and templateSource and activeShopId and activeCategory) then return end
	local selectionChanged = renderedShopId ~= activeShopId or renderedCategory ~= activeCategory
	if selectionChanged then
		hide_cached_cards()
	end
	local restock = sellerRestockButton
	if restock then
		restock.Visible = activeShopId == "Cowboy" and activeCategory ~= "Water"
	end
	local horseshoes = tonumber(DataUtility.client.get("Currencies.Horseshoes")) or 0
	for _, item in ipairs(get_items_for_shop(activeShopId, activeCategory)) do
		local entry = get_or_create_card(activeShopId, item, horseshoes)
		if selectionChanged then
			entry.Card.Visible = true
		end
	end
	if selectionChanged then
		renderedShopId = activeShopId
		renderedCategory = activeCategory
		update_canvas_size()
		task.defer(update_canvas_size)
	end
end

local function bind_seller()
	if sellerRoot and sellerRoot.Parent and scrollingFrame and templateSource then return true end
	if next(cardCache) then
		clear_card_cache()
	end
	sellerRoot = nil
	scrollingFrame = nil
	templateSource = nil
	sellerHudAnimBound = false
	sellerTabsRoot = nil
	table.clear(sellerTabButtons)
	sellerCloseButton = nil
	sellerRestockButton = nil
	sellerTitle = nil
	sellerRoot = find_named(playerGui, { "Seller" }, "GuiObject")
	if not sellerRoot then return false end
	scrollingFrame = find_named(sellerRoot, { "ListScrollingFrame", "ScrollingFrame", "ScrollFrame", "Scroll" }, "ScrollingFrame")
	if not scrollingFrame then return false end
	local template = find_named(scrollingFrame, { "SeedListBG", "ItemListBG", "ListBG", "ItemTemplate" }, "GuiObject")
	if not template then
		for _, child in ipairs(scrollingFrame:GetChildren()) do
			if child:IsA("GuiObject") and find_button(child, { "PurchaseBT", "BuyBT", "Buy" }) then template = child break end
		end
	end
	if not template then return false end
	templateSource = template:Clone()
	for _, child in ipairs(scrollingFrame:GetChildren()) do
		if child:IsA("GuiObject") then child.Visible = false end
	end
	for _, descendant in ipairs(templateSource:GetDescendants()) do
		if descendant:IsA("LocalScript") or descendant:IsA("Script") then descendant:Destroy() end
	end
	sellerTabsRoot = find_named(sellerRoot, { "BuySellSeedsFR", "Tabs", "TabButtons" }, "GuiObject") or sellerRoot
	for _, child in ipairs(sellerTabsRoot:GetDescendants()) do
		if child:IsA("GuiButton") and is_tab_button_candidate(child) then
			table.insert(sellerTabButtons, child)
		end
	end
	table.sort(sellerTabButtons, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	sellerCloseButton = find_button(sellerRoot, { "CloseBT", "ExitBT", "Close" })
	sellerRestockButton = find_button(sellerRoot, { "RestyockBT", "RestockBT", "ReestockBT" })
	local titleBackground = find_named(sellerRoot, SHOP_TITLE_BACKGROUND_NAMES, "GuiObject")
	sellerTitle = titleBackground and find_text_instance(titleBackground, SHOP_TITLE_LABEL_NAMES)
		or find_text_instance(sellerRoot, SHOP_TITLE_LABEL_NAMES)
	return true
end

local function bind_seller_hud_anim()
	if not sellerRoot or sellerHudAnimBound then
		return
	end

	sellerHudAnimBound = true
	-- Position-only motion keeps the opening feedback without resizing, fading,
	-- or rebuilding the card and viewport tree on every animation frame.
	sellerRoot:SetAttribute("UIOpen", true)
	sellerRoot:SetAttribute("open_anim", "slide_down")
	sellerRoot:SetAttribute("open_offset_px", 18)
	sellerRoot:SetAttribute("open_t", 0.18)
	sellerRoot:SetAttribute("open_fade", false)
	pcall(function()
		HudAnim.bind(sellerRoot)
	end)
end

local function set_seller_visible(isVisible, _animate)
	if not sellerRoot then
		return
	end

	bind_seller_hud_anim()

	if HudAnim.set_visible then
		HudAnim.set_visible(sellerRoot, isVisible == true, _animate ~= false)
	else
		sellerRoot.Visible = isVisible == true
	end
end

local function open_shop(shopId)
	local tabs = SHOP_TABS[shopId]
	if activeShopId == shopId and sellerRoot and sellerRoot.Parent and sellerRoot.Visible then
		return
	end
	if not tabs or not bind_seller() then return end
	activeShopId = shopId
	activeCategory = tabs[1].Category
	update_shop_title(shopId)
	set_seller_visible(true, not sellerRoot.Visible)
	local tabsRoot = sellerTabsRoot or sellerRoot
	if tabsRoot ~= sellerRoot then
		tabsRoot.Visible = shopId ~= "Doctor"
	end
	for index, button in ipairs(sellerTabButtons) do
		local tab = tabs[index]
		button.Visible = tab ~= nil
		if tab then
			set_button_text(button, tab.Label)
			button:SetAttribute("NpcSellerCategory", tab.Category)
			if button:GetAttribute("NpcSellerTabBound") ~= true then
				button:SetAttribute("NpcSellerTabBound", true)
				button.Activated:Connect(function()
					local nextCategory = button:GetAttribute("NpcSellerCategory")
					if nextCategory ~= activeCategory then
						activeCategory = nextCategory
						render()
					end
				end)
			end
		end
	end
	local close = sellerCloseButton
	if close and close:GetAttribute("NpcSellerCloseBound") ~= true then
		close:SetAttribute("NpcSellerCloseBound", true)
		close.Activated:Connect(function()
			set_seller_visible(false, true)
		end)
	end
	local restock = sellerRestockButton
	if restock then
		restock.Visible = shopId == "Cowboy" and activeCategory ~= "Water"
		if restock:GetAttribute("NpcSellerRestockBound") ~= true then
			restock:SetAttribute("NpcSellerRestockBound", true)
			restock.Activated:Connect(function()
				if activeShopId == "Cowboy" then
					activeCategory = "Water"
					restock.Visible = false
					render()
				end
			end)
		end
	end
	render()
end

local function prewarm_cleaning_cards()
	if not bind_seller() then
		return
	end

	local horseshoes = tonumber(DataUtility.client.get("Currencies.Horseshoes")) or 0
	for _, item in ipairs(get_items_for_shop("Noob", "Misc")) do
		local entry = get_or_create_card("Noob", item, horseshoes)
		entry.Card.Visible = true
		RunService.Heartbeat:Wait()
	end
	renderedShopId = "Noob"
	renderedCategory = "Misc"
	bind_seller_hud_anim()
end

DataUtility.client.ensure_remotes()
prewarm_cleaning_cards()
ProximityPromptService.PromptTriggered:Connect(function(prompt)
	local shopId = prompt:GetAttribute("NpcShopId")
	if type(shopId) == "string" then open_shop(shopId) end
end)

local function is_inside_zone(position, part)
	local localPosition = part.CFrame:PointToObjectSpace(position)
	local halfSize = part.Size * 0.5
	return math.abs(localPosition.X) <= halfSize.X
		and math.abs(localPosition.Y) <= halfSize.Y + 6
		and math.abs(localPosition.Z) <= halfSize.Z
end

local function is_player_inside_shop_zone(shopId)
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local zones = Workspace:FindFirstChild("Zones")
	local zone = zones and zones:FindFirstChild(shopId)
	if not rootPart or not zone then return false end
	if zone:IsA("BasePart") then return is_inside_zone(rootPart.Position, zone) end
	for _, descendant in ipairs(zone:GetDescendants()) do
		if descendant:IsA("BasePart") and is_inside_zone(rootPart.Position, descendant) then
			return true
		end
	end
	return false
end

local elapsed = 0
RunService.Heartbeat:Connect(function(deltaTime)
	elapsed += deltaTime
	if elapsed < 0.1 then return end
	elapsed = 0
	for shopId, wasInside in pairs(zoneState) do
		local isInside = is_player_inside_shop_zone(shopId)
		if isInside and not wasInside then
			open_shop(shopId)
		elseif not isInside and wasInside and activeShopId == shopId and sellerRoot then
			set_seller_visible(false, true)
		end
		zoneState[shopId] = isInside
	end
end)

DataUtility.client.bind("Currencies.Horseshoes", render)

script:SetAttribute("RuntimeReady", true)
