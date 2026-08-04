local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Client = Modules:WaitForChild("Client")
local Dictionary = Modules:WaitForChild("Dictionary")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local StableDictionary = require(Dictionary:WaitForChild("StableDictionary"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HudAnim = require(Libraries:WaitForChild("HudAnim"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local UIRouter = require(Client:WaitForChild("Hud"):WaitForChild("UIRouter"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local ROOT_NAMES = { "Upgrade" }
local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainframeFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local ITEM_BACKGROUND_NAMES = { "ItemBG" }
local DISPLAY_NAMES = { "ItemDisplayBG", "ItemDisplay", "Display" }
local SHOP_NAMES = { "ItemShopBG", "ItemShop", "Shop" }
local VIEWPORT_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }
local DISPLAY_TITLE_NAMES = { "ItemTX", "ItemNameTX", "NameTX", "Name" }
local DETAILS_NAMES = { "DetailsTX", "DetailTX", "DescriptionTX", "Description" }
local BUY_BUTTON_NAMES = { "Buy", "BuyBT", "PurchaseBT" }
local BUY_TEXT_NAMES = { "BTTX", "BuyTX", "PriceTX", "Text" }
local CLOSE_BUTTON_NAMES = { "ExitBT", "CloseBT", "Close", "Exit" }
local HORSESHOE_TEXT_NAMES = { "HorseshoeTX", "HorseshoesTX", "AmountTX", "ValueTX", "CountTX" }
local ROUTE_ID = "Upgrade"

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local currentRoot = nil
local unregisterRoute = nil
local purchaseInFlight = false
local statusMessage = nil
local previewViewport = nil
local previewLevel = nil
local boundCloseButtons = {}
local boundPurchaseButtons = {}

local function normalized_name(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmed = string.gsub(value, "^%s*(.-)%s*$", "%1")
	if trimmed == "" then
		return nil
	end

	return string.lower(trimmed)
end

local function has_name(instance, aliases)
	local instanceName = normalized_name(instance.Name)
	if not instanceName then
		return false
	end

	for _, alias in ipairs(aliases) do
		if instanceName == normalized_name(alias) then
			return true
		end
	end

	return false
end

local function find_named(root, aliases, className, recursive)
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if has_name(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	if recursive == false then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if has_name(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function set_text(instance, value)
	if not instance then
		return
	end

	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		instance.Text = value
	end
end

local function set_button_text(button, value)
	set_text(button, value)
	if not button then
		return
	end

	local label = find_named(button, BUY_TEXT_NAMES, "TextLabel")
	if label then
		set_text(label, value)
		return
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			set_text(descendant, value)
		end
	end
end

local function format_horseshoes(value)
	local amount = math.max(0, math.floor(tonumber(value) or 0))
	local formatted = tostring(amount)
	repeat
		local replaced
		formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1.%2")
	until replaced == 0
	return formatted
end

local function find_upgrade_root()
	local fallbackRoot = nil
	for _, candidate in ipairs(playerGui:GetDescendants()) do
		if has_name(candidate, ROOT_NAMES) and candidate:IsA("GuiObject") then
			fallbackRoot = fallbackRoot or candidate
			local itemBackground = find_named(candidate, ITEM_BACKGROUND_NAMES, "GuiObject")
			local itemDisplay = find_named(itemBackground or candidate, DISPLAY_NAMES, "GuiObject")
			if itemBackground and itemDisplay then
				return candidate
			end
		end
	end

	return fallbackRoot
end

local function set_root_visible(isVisible, animate)
	if not currentRoot then
		return
	end

	if HudAnim.set_visible then
		HudAnim.set_visible(currentRoot, isVisible == true, animate ~= false)
	else
		currentRoot.Visible = isVisible == true
	end
end

local function find_preview_source(level)
	local levelName = StableDictionary.get_level_template_name(level)
	local roots = { Workspace, ReplicatedStorage }
	local workspaceStables = Workspace:FindFirstChild("Stables")
	local replicatedStables = ReplicatedStorage:FindFirstChild("Stables")
	local stablePreviews = ReplicatedStorage:FindFirstChild("StablePreviews")
	if workspaceStables then
		table.insert(roots, 1, workspaceStables)
	end
	if replicatedStables then
		table.insert(roots, 2, replicatedStables)
	end
	if stablePreviews then
		table.insert(roots, 1, stablePreviews)
	end

	for _, searchRoot in ipairs(roots) do
		if searchRoot then
			local source = searchRoot:FindFirstChild(levelName, true)
			if source then
				-- LevelN is the complete stable model. PlayerSpawn is only an
				-- invisible positioning marker and must never be the viewport source.
				return source
			end
		end
	end

	return nil
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

local function create_preview_part(parent, name, size, position, color)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Material = Enum.Material.Wood
	part.Color = color
	part.Size = size
	part.Position = position
	part.Parent = parent
	return part
end

local function create_fallback_preview(level)
	local model = Instance.new("Model")
	model.Name = ("StableLevel%dPreview"):format(level)

	local width = 12 + level * 2
	local depth = 9 + level
	local height = 6 + level * 0.35
	local wood = Color3.fromRGB(124, 80, 50)
	local darkWood = Color3.fromRGB(83, 50, 31)
	local roof = Color3.fromRGB(72, 80, 96)

	create_preview_part(model, "Floor", Vector3.new(width, 0.5, depth), Vector3.new(0, 0, 0), darkWood)
	create_preview_part(model, "BackWall", Vector3.new(width, height, 0.5), Vector3.new(0, height * 0.5, -depth * 0.5), wood)
	create_preview_part(model, "LeftWall", Vector3.new(0.5, height, depth), Vector3.new(-width * 0.5, height * 0.5, 0), wood)
	create_preview_part(model, "RightWall", Vector3.new(0.5, height, depth), Vector3.new(width * 0.5, height * 0.5, 0), wood)
	create_preview_part(model, "Roof", Vector3.new(width + 1, 0.7, depth + 1), Vector3.new(0, height + 0.35, 0), roof)

	for index, x in ipairs({ -width * 0.4, width * 0.4 }) do
		create_preview_part(model, ("Post%d"):format(index), Vector3.new(0.7, height, 0.7), Vector3.new(x, height * 0.5, depth * 0.4), darkWood)
	end

	return model
end

local function render_preview(viewport, level)
	if not viewport then
		return
	end
	if previewViewport == viewport and previewLevel == level and viewport.Parent then
		return
	end

	clear_viewport(viewport)
	viewport.Visible = true
	viewport.BackgroundTransparency = 1

	local source = find_preview_source(level)
	local clone = nil
	if source then
		local success, clonedSource = pcall(function()
			return source:Clone()
		end)
		if success then
			clone = clonedSource
		end
	end
	if not clone then
		clone = create_fallback_preview(level)
	end

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = false
		end
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	local displayModel
	if clone:IsA("Model") then
		displayModel = clone
	else
		displayModel = Instance.new("Model")
		clone.Parent = displayModel
	end
	displayModel.Parent = worldModel

	local boundsSuccess, boundsCFrame, boundsSize = pcall(function()
		return displayModel:GetBoundingBox()
	end)
	if not boundsSuccess or not boundsSize then
		previewViewport = nil
		previewLevel = nil
		return
	end

	local largest = math.max(boundsSize.X, boundsSize.Y, boundsSize.Z, 1)
	local distance = largest * 1.25
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(
		boundsCFrame.Position + Vector3.new(distance * 0.8, distance * 0.45, distance),
		boundsCFrame.Position
	)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	previewViewport = viewport
	previewLevel = level
end

local function get_upgrade_data()
	local stable = DataUtility.client.get("Stable")
	local currentLevel = StableDictionary.get_normalized_level(type(stable) == "table" and stable.Level or nil)
	local nextLevel = currentLevel + 1
	if nextLevel > StableDictionary.MaxLevel then
		return currentLevel, nil, nil
	end

	return currentLevel, nextLevel, StableDictionary.get_level_upgrade(nextLevel)
end

local function render()
	if not currentRoot then
		return
	end

	local itemBackground = find_named(currentRoot, ITEM_BACKGROUND_NAMES, "GuiObject")
	local display = find_named(itemBackground or currentRoot, DISPLAY_NAMES, "GuiObject")
	local shop = find_named(currentRoot, SHOP_NAMES, "GuiObject")
	-- ItemTX and DetailsTX are siblings of ItemDisplayBG under ItemBG.
	local title = find_named(itemBackground, DISPLAY_TITLE_NAMES, nil)
	local displayDetails = find_named(itemBackground, DETAILS_NAMES, nil)
	local viewport = find_named(display, VIEWPORT_NAMES, "ViewportFrame")
	local shopDetails = find_named(shop, DETAILS_NAMES, nil)
	local buyButton = find_named(shop, BUY_BUTTON_NAMES, "GuiButton")
	local horseshoes = math.max(0, math.floor(tonumber(DataUtility.client.get("Currencies.Horseshoes")) or 0))
	local _, nextLevel, upgrade = get_upgrade_data()

	if not itemBackground then
		return
	end
	if not display then
		return
	end

	local horseshoeBox = find_named(currentRoot, { "HorseshoeBG" }, "GuiObject")
	local horseshoeText = find_named(horseshoeBox, HORSESHOE_TEXT_NAMES, "TextLabel")
	if horseshoeText then
		set_text(horseshoeText, format_horseshoes(horseshoes))
	end

	if not nextLevel or type(upgrade) ~= "table" then
		set_text(title, "Estábulo no nível máximo")
		set_text(displayDetails, "Você concluiu todas as expansões disponíveis do estábulo.")
		set_text(shopDetails, "Não há mais melhorias de estábulo para comprar.")
		if buyButton then
			buyButton.Active = false
			buyButton.AutoButtonColor = false
			set_button_text(buyButton, "NÍVEL MÁXIMO")
		end
		render_preview(viewport, StableDictionary.MaxLevel)
		return
	end

	local price = math.max(0, math.floor(tonumber(upgrade.Price) or 0))
	set_text(title, ("Estábulo - Nível %d"):format(nextLevel))
	set_text(displayDetails, upgrade.Description or "Expanda seu estábulo para o próximo nível.")
	set_text(
		shopDetails,
		("Compre o nível %d do estábulo por %s ferraduras."):format(nextLevel, format_horseshoes(price))
	)
	if buyButton then
		local canBuy = not purchaseInFlight and horseshoes >= price
		buyButton.Active = canBuy
		buyButton.AutoButtonColor = canBuy
		set_button_text(buyButton, ("COMPRAR - %s"):format(format_horseshoes(price)))
	end
	render_preview(viewport, nextLevel)

	if statusMessage then
		set_text(shopDetails, statusMessage)
	end
end

local function get_purchase_error_message(response)
	local code = type(response) == "table" and response.Code or nil
	if code == "NotEnoughHorseshoes" then
		local price = type(response) == "table" and response.Price or 0
		return ("Ferraduras insuficientes. Você precisa de %s."):format(format_horseshoes(price))
	elseif code == "MaxLevel" then
		return "Seu estábulo já está no nível máximo."
	elseif code == "LevelChangeBusy" then
		return "A melhoria anterior ainda está sendo aplicada."
	elseif code == "LevelPlotTemplateMissing" then
		return "O modelo do próximo nível do estábulo não foi encontrado."
	end

	return "Não foi possível comprar esta melhoria agora."
end

local function request_upgrade()
	if purchaseInFlight then
		return
	end

	local _, nextLevel, upgrade = get_upgrade_data()
	if not nextLevel or type(upgrade) ~= "table" then
		return
	end

	local horseshoes = math.max(0, math.floor(tonumber(DataUtility.client.get("Currencies.Horseshoes")) or 0))
	if horseshoes < (tonumber(upgrade.Price) or 0) then
		statusMessage = ("Ferraduras insuficientes. Você precisa de %s."):format(format_horseshoes(upgrade.Price))
		render()
		return
	end

	purchaseInFlight = true
	statusMessage = "Comprando melhoria..."
	render()

	task.spawn(function()
		local success, response = pcall(function()
			return Net.Function.UpgradeStable:Call()
		end)

		purchaseInFlight = false
		if success and type(response) == "table" and response.Success == true then
			statusMessage = ("Estábulo melhorado para o nível %d!"):format(response.CurrentLevel or nextLevel)
		else
			statusMessage = get_purchase_error_message(success and response or nil)
		end
		render()
	end)
end

local function destroy_ui_binding()
	if unregisterRoute then
		unregisterRoute()
		unregisterRoute = nil
	end
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentRoot = nil
	purchaseInFlight = false
	statusMessage = nil
	previewViewport = nil
	previewLevel = nil
	table.clear(boundCloseButtons)
	table.clear(boundPurchaseButtons)
end

local function bind_controls()
	if not currentRoot then
		return
	end

	local closeButton = find_named(currentRoot, CLOSE_BUTTON_NAMES, "GuiButton")
	if closeButton and not boundCloseButtons[closeButton] then
		boundCloseButtons[closeButton] = true
		uiTrove:Connect(closeButton.Activated, function()
			UIRouter.Close(ROUTE_ID, true)
		end)
	end

	local shop = find_named(currentRoot, SHOP_NAMES, "GuiObject")
	local buyButton = find_named(shop, BUY_BUTTON_NAMES, "GuiButton")
	if buyButton and not boundPurchaseButtons[buyButton] then
		boundPurchaseButtons[buyButton] = true
		uiTrove:Connect(buyButton.Activated, request_upgrade)
	end
end

local function bind_ui(root)
	if currentRoot == root and root.Parent then
		bind_controls()
		render()
		return
	end

	destroy_ui_binding()
	currentRoot = root

	currentRoot:SetAttribute("UIOpen", true)
	pcall(function()
		HudAnim.bind(currentRoot)
		HudAnim.apply_defaults_to_buttons(currentRoot)
		HudAnim.bind_all(currentRoot)
	end)

	unregisterRoute = UIRouter.Register(ROUTE_ID, {
		SetOpen = function(isOpen, animate)
			set_root_visible(isOpen, animate)
		end,
	}, currentRoot.Visible)

	bind_controls()

	uiTrove:Connect(currentRoot.AncestryChanged, function(_, parent)
		if not parent and currentRoot == root then
			destroy_ui_binding()
		end
	end)

	render()
end

local function try_bind_ui()
	local root = find_upgrade_root()
	if root then
		bind_ui(root)
	elseif currentRoot then
		destroy_ui_binding()
	end
end

local function open_upgrade()
	try_bind_ui()
	statusMessage = nil
	render()
	if not UIRouter.Open(ROUTE_ID, true) then
		set_root_visible(true, true)
	end
end

DataUtility.client.ensure_remotes()
rootTrove:Connect(ProximityPromptService.PromptTriggered, function(prompt)
	if prompt:GetAttribute("StableUpgradeNpc") == true then
		open_upgrade()
	end
end)
rootTrove:Connect(playerGui.DescendantAdded, try_bind_ui)
rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
	if currentRoot and (instance == currentRoot or currentRoot:IsDescendantOf(instance)) then
		task.defer(try_bind_ui)
	end
end)

local stableConnection = DataUtility.client.bind("Stable", render)
if stableConnection then
	rootTrove:Add(stableConnection)
end
local horseshoeConnection = DataUtility.client.bind("Currencies.Horseshoes", render)
if horseshoeConnection then
	rootTrove:Add(horseshoeConnection)
end

try_bind_ui()

script:SetAttribute("RuntimeReady", true)
