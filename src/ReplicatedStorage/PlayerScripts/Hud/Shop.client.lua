local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")

local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local RobuxShopCatalog = require(GameData:WaitForChild("RobuxShopCatalog"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainframeFR", "MainFrameFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local SHOP_ROOT_NAMES = { "Shop" }
local SCROLLING_FRAME_NAMES = { "ListScrollingFrame", "ScrollingFrame", "ScrollFrame", "Scroll" }
local HORSE_FRAME_NAMES = { "HorseFR" }
local STANDARD_CARD_NAMES = { "HorseBT" }
local FEATURED_CARD_NAMES = { "HorseBigBT" }
local PURCHASE_ROOT_NAMES = { "PurchaseFR" }
local PURCHASE_BUTTON_NAMES = { "PurchaseBT" }
local GIFT_BUTTON_NAMES = { "GiftBT" }
local IMAGE_LABEL_NAMES = { "ImageLabel" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }
local PRODUCT_NAME_NAMES = { "HorseNameTX" }
local PRODUCT_NAME_SHADOW_NAMES = { "HorseNameShadowTX" }
local DETAIL_TEXT_NAMES = { "DetailTX", "DetailsTX" }
local PRICE_TEXT_NAMES = { "PriceTX" }

local ROBUX_SYMBOL = utf8.char(0xE002)
local PROMPT_DEBOUNCE_SECONDS = 1
local GIFT_PICKER_GUI_NAME = "RobuxGiftPickerGui"

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local renderTrove = Trove.new()
local overlayTrove = Trove.new()

local currentUi = nil
local currentCatalog = nil
local catalogRequestToken = 0
local activeGiftPrompt = nil
local lastPromptAtByProductKey = {}

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

local function normalize_whole_number(value): number
	return math.max(0, math.floor(tonumber(value) or 0))
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

local function collect_named_children(root: Instance?, aliases, className: string?): { Instance }
	local results = {}
	if not root then
		return results
	end

	local childOrderLookup = {}
	for index, child in ipairs(root:GetChildren()) do
		childOrderLookup[child] = index
		if matches_alias(child, aliases) and (not className or child:IsA(className)) then
			results[#results + 1] = child
		end
	end

	table.sort(results, function(left, right)
		local leftLayoutOrder = if left:IsA("GuiObject") then left.LayoutOrder else 0
		local rightLayoutOrder = if right:IsA("GuiObject") then right.LayoutOrder else 0
		if leftLayoutOrder == rightLayoutOrder then
			return (childOrderLookup[left] or 0) < (childOrderLookup[right] or 0)
		end

		return leftLayoutOrder < rightLayoutOrder
	end)

	return results
end

local function find_gui_object(root: Instance?, aliases, recursive: boolean?): GuiObject?
	local instance = find_named_instance(root, aliases, "GuiObject", recursive)
	if instance then
		return instance :: GuiObject
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

local function find_text_label(root: Instance?, aliases, recursive: boolean?): TextLabel?
	local instance = find_named_instance(root, aliases, "TextLabel", recursive)
	if instance then
		return instance :: TextLabel
	end

	return nil
end

local function find_image_object(root: Instance?, aliases, recursive: boolean?): GuiObject?
	local instance = find_named_instance(root, aliases, nil, recursive)
	if instance and (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
		return instance :: GuiObject
	end

	return nil
end

local function build_fallback_catalog()
	local fallbackDeveloperProducts = {}
	for _, definition in ipairs(RobuxShopCatalog.GetDeveloperProductDefinitions()) do
		fallbackDeveloperProducts[definition.Key] = RobuxShopCatalog.BuildStaticProductPayload(definition)
	end

	local fallbackGamePasses = {}
	for _, definition in ipairs(RobuxShopCatalog.GetGamePassDefinitions()) do
		fallbackGamePasses[definition.Key] = RobuxShopCatalog.BuildStaticProductPayload(definition)
	end

	return {
		Success = true,
		DeveloperProducts = fallbackDeveloperProducts,
		GamePasses = fallbackGamePasses,
	}
end

local function set_button_enabled(button: GuiButton?, isEnabled: boolean)
	if not button then
		return
	end

	button.Active = isEnabled
	button.Selectable = isEnabled

	if button:IsA("TextButton") or button:IsA("ImageButton") then
		button.AutoButtonColor = isEnabled
	end
end

local function ensure_purchase_click_target(root: GuiObject?): GuiButton?
	if not root then
		return nil
	end

	if root:IsA("GuiButton") then
		return root
	end

	local existingButton = root:FindFirstChild("RobuxShopPurchaseClickTarget")
	if existingButton and existingButton:IsA("GuiButton") then
		return existingButton
	end

	local button = Instance.new("TextButton")
	button.Name = "RobuxShopPurchaseClickTarget"
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = true
	button.Size = UDim2.fromScale(1, 1)
	button.Position = UDim2.fromScale(0, 0)
	button.ZIndex = root.ZIndex + 10
	button.Parent = root

	return button
end

local function format_price_text(product): string
	local priceInRobux = product and product.PriceInRobux or nil
	if type(priceInRobux) ~= "number" or priceInRobux < 0 or product.IsForSale == false then
		return "Indisponivel"
	end

	return ("%s %d"):format(ROBUX_SYMBOL, normalize_whole_number(priceInRobux))
end

local function format_gift_error_message(code): string
	if code == "GiftAlreadyPending" then
		return "Ja existe um presente aguardando confirmacao. Termine ou cancele o anterior."
	end

	if code == "RecipientUnavailable" then
		return "Esse player nao esta mais disponivel para receber o presente agora."
	end

	if code == "InvalidGiftRecipient" then
		return "Escolha um outro player valido para presentear."
	end

	if code == "GiftIntentNotFound" or code == "GiftIntentMissing" then
		return "O presente expirou antes da confirmacao. Tente novamente."
	end

	if code == "ProfileNotReady" then
		return "Seu perfil ainda esta carregando. Tente novamente em alguns segundos."
	end

	if code == "UnsupportedGiftProduct" then
		return "Esse item ainda nao suporta presente."
	end

	return "Nao foi possivel concluir o presente agora."
end

local function destroy_gift_picker()
	overlayTrove:Destroy()
	overlayTrove = Trove.new()
end

local function cancel_gift_intent(intentId: string)
	if type(intentId) ~= "string" or intentId == "" then
		return
	end

	task.spawn(function()
		pcall(function()
			Net.Function[RobuxShopCatalog.RemoteNames.CancelGiftPurchase]:Call(intentId)
		end)
	end)
end

local function prompt_purchase(product)
	if not product then
		return
	end

	local now = os.clock()
	local lastPromptAt = lastPromptAtByProductKey[product.Key] or 0
	if now - lastPromptAt < PROMPT_DEBOUNCE_SECONDS then
		return
	end

	lastPromptAtByProductKey[product.Key] = now

	if product.ProductType == "GamePass" then
		MarketplaceService:PromptGamePassPurchase(localPlayer, product.ProductId)
		return
	end

	MarketplaceService:PromptProductPurchase(localPlayer, product.ProductId)
end

local function get_giftable_players(): { Player }
	local players = {}

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= localPlayer then
			players[#players + 1] = player
		end
	end

	table.sort(players, function(left, right)
		local leftName = string.lower(left.DisplayName ~= "" and left.DisplayName or left.Name)
		local rightName = string.lower(right.DisplayName ~= "" and right.DisplayName or right.Name)
		if leftName == rightName then
			return string.lower(left.Name) < string.lower(right.Name)
		end

		return leftName < rightName
	end)

	return players
end

local function build_overlay_button(parent: Instance, text: string, layoutOrder: number): TextButton
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(37, 41, 49)
	button.BorderSizePixel = 0
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.new(1, 0, 0, 44)
	button.Font = Enum.Font.GothamSemibold
	button.Text = text
	button.TextColor3 = Color3.fromRGB(245, 245, 245)
	button.TextSize = 14
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	return button
end

local function open_gift_picker(product)
	if not product or product.SupportsGifting ~= true or product.ProductType ~= "DeveloperProduct" then
		return
	end

	destroy_gift_picker()

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GIFT_PICKER_GUI_NAME
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 2000
	screenGui.Parent = playerGui
	overlayTrove:Add(screenGui)

	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.AutoButtonColor = false
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Text = ""
	backdrop.Parent = screenGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(23, 26, 32)
	panel.BorderSizePixel = 0
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(430, 360)
	panel.Parent = backdrop

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 14)
	panelCorner.Parent = panel

	local titleLabel = Instance.new("TextLabel")
	titleLabel.BackgroundTransparency = 1
	titleLabel.Position = UDim2.fromOffset(20, 18)
	titleLabel.Size = UDim2.new(1, -40, 0, 28)
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = ("Presentear %s"):format(product.DisplayName or "produto")
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 20
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = panel

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Position = UDim2.fromOffset(20, 48)
	subtitleLabel.Size = UDim2.new(1, -40, 0, 20)
	subtitleLabel.Font = Enum.Font.Gotham
	subtitleLabel.Text = "Escolha quem vai receber o pack quando a compra for confirmada."
	subtitleLabel.TextColor3 = Color3.fromRGB(180, 185, 196)
	subtitleLabel.TextSize = 13
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.Parent = panel

	local statusLabel = Instance.new("TextLabel")
	statusLabel.BackgroundTransparency = 1
	statusLabel.Position = UDim2.fromOffset(20, 72)
	statusLabel.Size = UDim2.new(1, -40, 0, 22)
	statusLabel.Font = Enum.Font.Gotham
	statusLabel.Text = ""
	statusLabel.TextColor3 = Color3.fromRGB(255, 206, 120)
	statusLabel.TextSize = 13
	statusLabel.TextWrapped = true
	statusLabel.TextXAlignment = Enum.TextXAlignment.Left
	statusLabel.Parent = panel

	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Active = true
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.BackgroundTransparency = 1
	listFrame.BorderSizePixel = 0
	listFrame.CanvasSize = UDim2.new()
	listFrame.Position = UDim2.fromOffset(20, 106)
	listFrame.ScrollBarThickness = 6
	listFrame.Size = UDim2.new(1, -40, 1, -166)
	listFrame.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = listFrame

	local footer = Instance.new("Frame")
	footer.BackgroundTransparency = 1
	footer.Position = UDim2.new(0, 20, 1, -50)
	footer.Size = UDim2.new(1, -40, 0, 32)
	footer.Parent = panel

	local cancelButton = build_overlay_button(footer, "Cancelar", 1)
	cancelButton.Size = UDim2.new(0.35, 0, 1, 0)
	cancelButton.Position = UDim2.fromScale(0.65, 0)
	cancelButton.AnchorPoint = Vector2.new(0, 0)

	local requestInFlight = false

	local function set_status(text: string, isError: boolean?)
		statusLabel.Text = text or ""
		statusLabel.TextColor3 = if isError then Color3.fromRGB(255, 132, 132) else Color3.fromRGB(255, 206, 120)
	end

	local function close_overlay()
		destroy_gift_picker()
	end

	overlayTrove:Add(backdrop.Activated:Connect(function()
		close_overlay()
	end))

	overlayTrove:Add(panel.InputBegan:Connect(function()
		-- Consume clicks on the panel so the backdrop doesn't close the picker.
	end))

	overlayTrove:Add(cancelButton.Activated:Connect(function()
		close_overlay()
	end))

	local players = get_giftable_players()
	if #players == 0 then
		set_status("Nao ha outros players no servidor para receber presente agora.", true)
	end

	for index, player in ipairs(players) do
		local buttonText = if player.DisplayName ~= "" and player.DisplayName ~= player.Name
			then ("%s  (@%s)"):format(player.DisplayName, player.Name)
			else player.Name
		local playerButton = build_overlay_button(listFrame, buttonText, index)

		overlayTrove:Add(playerButton.Activated:Connect(function()
			if requestInFlight then
				return
			end

			requestInFlight = true
			set_status(("Preparando presente para %s..."):format(player.Name), false)

			task.spawn(function()
				local beginSuccess, beginResponse = pcall(function()
					return Net.Function[RobuxShopCatalog.RemoteNames.BeginGiftPurchase]:Call(product.Key, player.UserId)
				end)

				if not beginSuccess or type(beginResponse) ~= "table" or beginResponse.Success ~= true then
					requestInFlight = false
					set_status(format_gift_error_message(type(beginResponse) == "table" and beginResponse.Code or ""), true)
					return
				end

				local confirmSuccess, confirmResponse = pcall(function()
					return Net.Function[RobuxShopCatalog.RemoteNames.ConfirmGiftPurchase]:Call(beginResponse.IntentId)
				end)

				if not confirmSuccess or type(confirmResponse) ~= "table" or confirmResponse.Success ~= true then
					cancel_gift_intent(beginResponse.IntentId)
					requestInFlight = false
					set_status(format_gift_error_message(type(confirmResponse) == "table" and confirmResponse.Code or ""), true)
					return
				end

				activeGiftPrompt = {
					IntentId = confirmResponse.IntentId,
					ProductId = confirmResponse.ProductId,
					ProductKey = confirmResponse.ProductKey,
					RecipientUserId = confirmResponse.RecipientUserId,
				}

				close_overlay()

				local promptSuccess, promptError = pcall(function()
					MarketplaceService:PromptProductPurchase(localPlayer, product.ProductId)
				end)

				if not promptSuccess then
					local intentId = activeGiftPrompt and activeGiftPrompt.IntentId or confirmResponse.IntentId
					activeGiftPrompt = nil
					cancel_gift_intent(intentId)
					warn(("[RobuxShop] Falha ao abrir prompt de presente: %s"):format(tostring(promptError)))
				end
			end)
		end))
	end
end

local function apply_product_to_card(card: GuiObject, product)
	card.Visible = product ~= nil
	if not product then
		return
	end

	local productName = product.DisplayName or ""
	local rewardLabel = product.RewardLabel or ""
	local priceText = format_price_text(product)

	local nameLabel = find_text_label(card, PRODUCT_NAME_NAMES, true)
	local shadowLabel = find_text_label(card, PRODUCT_NAME_SHADOW_NAMES, true)
	local detailLabel = find_text_label(card, DETAIL_TEXT_NAMES, true)
	local priceLabel = find_text_label(card, PRICE_TEXT_NAMES, true)
	local purchaseRoot = find_gui_object(card, PURCHASE_ROOT_NAMES, true) or card
	local purchaseButton = find_gui_button(card, PURCHASE_BUTTON_NAMES, true)
		or find_gui_button(purchaseRoot, PURCHASE_BUTTON_NAMES, true)
		or ensure_purchase_click_target(purchaseRoot)
	local giftButton = find_gui_button(card, GIFT_BUTTON_NAMES, true)
		or find_gui_button(purchaseRoot, GIFT_BUTTON_NAMES, true)
	local imageObject = find_image_object(card, IMAGE_LABEL_NAMES, true)
	local viewportFrame = find_named_instance(card, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)

	if nameLabel then
		nameLabel.Text = productName
	end

	if shadowLabel then
		shadowLabel.Text = productName
	end

	if detailLabel then
		detailLabel.Text = rewardLabel
	end

	if priceLabel then
		priceLabel.Text = priceText
	end

	if imageObject then
		(imageObject :: any).Image = product.Image or ""
	end

	if viewportFrame and viewportFrame:IsA("GuiObject") then
		viewportFrame.Visible = false
	end

	local canPromptPurchase = type(product.ProductId) == "number"
		and product.ProductId > 0
		and (product.ProductType == "DeveloperProduct" or product.ProductType == "GamePass")
		and type(product.PriceInRobux) == "number"
		and product.IsForSale ~= false
	local canGiftPurchase = canPromptPurchase and product.SupportsGifting == true and product.ProductType == "DeveloperProduct"

	set_button_enabled(purchaseButton, canPromptPurchase)
	set_button_enabled(giftButton, canGiftPurchase)

	if purchaseButton then
		renderTrove:Add(purchaseButton.Activated:Connect(function()
			if canPromptPurchase then
				prompt_purchase(product)
			end
		end))
	end

	if giftButton then
		renderTrove:Add(giftButton.Activated:Connect(function()
			if canGiftPurchase then
				open_gift_picker(product)
			end
		end))
	end
end

local function render_shop()
	if not currentUi then
		return
	end

	renderTrove:Clean()

	local catalog = currentCatalog or build_fallback_catalog()
	local developerProducts = catalog.DeveloperProducts or {}
	local horseshoesLayout = RobuxShopCatalog.GetSectionLayout("Horseshoes") or {}
	local standardKeys = horseshoesLayout.StandardProductKeys or {}
	local featuredKeys = horseshoesLayout.FeaturedProductKeys or {}

	for index, card in ipairs(currentUi.StandardCards or {}) do
		local productKey = standardKeys[index]
		local product = productKey and developerProducts[productKey] or nil
		apply_product_to_card(card, product)
	end

	if currentUi.FeaturedCard then
		local featuredKey = featuredKeys[1]
		local featuredProduct = featuredKey and developerProducts[featuredKey] or nil
		apply_product_to_card(currentUi.FeaturedCard, featuredProduct)
	end
end

local function request_catalog()
	catalogRequestToken += 1
	local requestToken = catalogRequestToken

	task.spawn(function()
		local success, response = pcall(function()
			return Net.Function[RobuxShopCatalog.RemoteNames.GetCatalog]:Call()
		end)

		if requestToken ~= catalogRequestToken then
			return
		end

		if success and type(response) == "table" and response.Success then
			currentCatalog = response
		else
			currentCatalog = currentCatalog or build_fallback_catalog()
		end

		render_shop()
	end)
end

local function get_shop_ui(shopRoot: GuiObject)
	local scrollingFrame = find_named_instance(shopRoot, SCROLLING_FRAME_NAMES, "ScrollingFrame", true)
	if not scrollingFrame then
		return nil
	end

	local horseFrame = find_gui_object(scrollingFrame, HORSE_FRAME_NAMES, true)
	if not horseFrame then
		return nil
	end

	local standardCards = {}
	for _, instance in ipairs(collect_named_children(horseFrame, STANDARD_CARD_NAMES, "GuiObject")) do
		standardCards[#standardCards + 1] = instance :: GuiObject
	end

	local featuredCard = find_gui_object(scrollingFrame, FEATURED_CARD_NAMES, true)

	if #standardCards < 1 and not featuredCard then
		return nil
	end

	return {
		Root = shopRoot,
		ScrollingFrame = scrollingFrame,
		HorseFrame = horseFrame,
		StandardCards = standardCards,
		FeaturedCard = featuredCard,
	}
end

local function find_shop_ui()
	local mainUi = find_named_instance(playerGui, MAIN_UI_NAMES, nil, true)
	if not mainUi then
		return nil
	end

	local mainframe = find_named_instance(mainUi, MAINFRAME_NAMES, nil, true)
	if not mainframe then
		return nil
	end

	local framesContainer = find_named_instance(mainframe, FRAMES_CONTAINER_NAMES, nil, true)
	if not framesContainer then
		return nil
	end

	local shopRoot = find_gui_object(framesContainer, SHOP_ROOT_NAMES, true)
	if not shopRoot then
		return nil
	end

	return get_shop_ui(shopRoot)
end

local function destroy_ui_binding()
	renderTrove:Clean()
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = nil
	destroy_gift_picker()
end

local function bind_ui(ui)
	if currentUi and currentUi.Root == ui.Root and currentUi.Root.Parent then
		return
	end

	destroy_ui_binding()
	currentUi = ui

	uiTrove:Add(ui.Root:GetPropertyChangedSignal("Visible"):Connect(function()
		if ui.Root.Visible then
			request_catalog()
		else
			destroy_gift_picker()
		end
	end))

	uiTrove:Add(ui.Root.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		if currentUi and currentUi.Root == ui.Root then
			destroy_ui_binding()
		end
	end))

	render_shop()
	request_catalog()
end

local function try_bind_ui()
	if currentUi and currentUi.Root and currentUi.Root.Parent then
		return
	end

	local ui = find_shop_ui()
	if not ui then
		destroy_ui_binding()
		return
	end

	bind_ui(ui)
end

currentCatalog = build_fallback_catalog()

rootTrove:Add(MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, isPurchased)
	if userId ~= localPlayer.UserId then
		return
	end

	if not activeGiftPrompt or activeGiftPrompt.ProductId ~= productId then
		return
	end

	local intentId = activeGiftPrompt.IntentId
	activeGiftPrompt = nil

	if isPurchased ~= true then
		cancel_gift_intent(intentId)
	end
end))

rootTrove:Add(playerGui.DescendantAdded:Connect(function()
	try_bind_ui()
end))

rootTrove:Add(playerGui.DescendantRemoving:Connect(function(instance)
	if currentUi and (instance == currentUi.Root or instance:IsDescendantOf(currentUi.Root)) then
		task.defer(try_bind_ui)
	end
end))

rootTrove:Add(Players.PlayerRemoving:Connect(function(player)
	if player == localPlayer then
		return
	end

	if playerGui:FindFirstChild(GIFT_PICKER_GUI_NAME) then
		destroy_gift_picker()
	end
end))

try_bind_ui()