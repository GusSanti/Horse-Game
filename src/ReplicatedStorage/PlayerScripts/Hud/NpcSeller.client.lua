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
local Net = require(Libraries:WaitForChild("Net"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local activeShopId = nil
local activeCategory = nil
local sellerRoot = nil
local scrollingFrame = nil
local templateSource = nil
local cardConnections = {}
local zoneState = {
	Cowboy = false,
	Doctor = false,
}

local SHOP_TABS = {
	Cowboy = {
		{ Category = "Water", Label = "Water" },
		{ Category = "Misc", Label = "Care" },
	},
	Doctor = {
		{ Category = "Medicine", Label = "Medicine" },
	},
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

local function find_label(root, names)
	return find_named(root, names, "TextLabel")
end

local function set_button_text(button, value)
	if button:IsA("TextButton") then button.Text = value end
	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") then descendant.Text = value end
	end
end

local function find_item_asset(item)
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

local function populate_icon(card, item)
	local viewport = find_named(card, { "ViewportFrame", "ViewPortFrame", "Viewport" }, "ViewportFrame")
	if not viewport then return end
	for _, child in ipairs(viewport:GetChildren()) do child:Destroy() end
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
	model.Parent = worldModel
	local boundsCFrame, boundsSize
	if model:IsA("Model") then
		boundsCFrame, boundsSize = model:GetBoundingBox()
	elseif model:IsA("BasePart") then
		boundsCFrame, boundsSize = model.CFrame, model.Size
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

local function disconnect_cards()
	for _, connection in ipairs(cardConnections) do connection:Disconnect() end
	table.clear(cardConnections)
	if scrollingFrame then
		for _, child in ipairs(scrollingFrame:GetChildren()) do
			if child:GetAttribute("NpcSellerCard") then child:Destroy() end
		end
	end
end

local function get_items()
	local items = {}
	for _, item in ipairs(ToolItemCatalog.GetItemsForShop(activeShopId) or {}) do
		if item.ToolCategory == activeCategory then table.insert(items, item) end
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

local function render()
	if not (sellerRoot and scrollingFrame and templateSource and activeShopId and activeCategory) then return end
	disconnect_cards()
	local restock = find_button(sellerRoot, { "RestyockBT", "RestockBT", "ReestockBT" })
	if restock then
		restock.Visible = activeShopId == "Cowboy" and activeCategory ~= "Water"
	end
	local horseshoes = tonumber(DataUtility.client.get("Currencies.Horseshoes")) or 0
	for _, item in ipairs(get_items()) do
		local card = templateSource:Clone()
		card.Name = item.ItemId
		card:SetAttribute("NpcSellerCard", true)
		card.Visible = true
		card.LayoutOrder = item.SortOrder or 0
		card.Parent = scrollingFrame
		local name = find_label(card, { "ItemNameTX", "NameTX", "Name" })
		local price = find_label(card, { "ValueTX", "PriceTX", "Price" })
		local stock = find_label(card, { "StockCountTX", "StockTX", "CountTX" })
		if name then name.Text = item.DisplayName end
		if price then price.Text = "$" .. tostring(item.Price or 0) end
		if stock then stock.Visible = false end
		populate_icon(card, item)
		local buy = find_button(card, { "PurchaseBT", "BuyBT", "Buy" })
		if buy then
			buy.Active = horseshoes >= (item.Price or 0)
			buy.AutoButtonColor = buy.Active
			local connection = buy.Activated:Connect(function()
				local response = Net.Function.BuyNpcShopItem:Call(activeShopId, item.ItemId)
				if response and response.Success then render() end
			end)
			table.insert(cardConnections, connection)
		end
	end
	update_canvas_size()
	task.defer(update_canvas_size)
end

local function bind_seller()
	if sellerRoot and sellerRoot.Parent and scrollingFrame and templateSource then return true end
	sellerRoot = nil
	scrollingFrame = nil
	templateSource = nil
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
	return true
end

local function open_shop(shopId)
	local tabs = SHOP_TABS[shopId]
	if not tabs or not bind_seller() then return end
	activeShopId = shopId
	activeCategory = tabs[1].Category
	sellerRoot.Visible = true
	local tabsRoot = find_named(sellerRoot, { "BuySellSeedsFR", "Tabs", "TabButtons" }, "GuiObject") or sellerRoot
	if tabsRoot ~= sellerRoot then
		tabsRoot.Visible = shopId ~= "Doctor"
	end
	local buttons = {}
	for _, child in ipairs(tabsRoot:GetDescendants()) do
		if child:IsA("GuiButton") then table.insert(buttons, child) end
	end
	table.sort(buttons, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
	for index, button in ipairs(buttons) do
		local tab = tabs[index]
		button.Visible = tab ~= nil
		if tab then
			set_button_text(button, tab.Label)
			button:SetAttribute("NpcSellerCategory", tab.Category)
			if button:GetAttribute("NpcSellerBound") ~= true then
				button:SetAttribute("NpcSellerBound", true)
				button.Activated:Connect(function()
					activeCategory = button:GetAttribute("NpcSellerCategory")
					render()
				end)
			end
		end
	end
	local close = find_button(sellerRoot, { "CloseBT", "ExitBT", "Close" })
	if close and close:GetAttribute("NpcSellerBound") ~= true then
		close:SetAttribute("NpcSellerBound", true)
		close.Activated:Connect(function() sellerRoot.Visible = false end)
	end
	local restock = find_button(sellerRoot, { "RestyockBT", "RestockBT", "ReestockBT" })
	if restock then
		restock.Visible = shopId == "Cowboy" and activeCategory ~= "Water"
		if restock:GetAttribute("NpcSellerBound") ~= true then
			restock:SetAttribute("NpcSellerBound", true)
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

DataUtility.client.ensure_remotes()
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
			sellerRoot.Visible = false
		end
		zoneState[shopId] = isInside
	end
end)

DataUtility.client.bind("Currencies.Horseshoes", render)
