local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")
local HudModules = ClientModules:WaitForChild("Hud")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))
local AdminPanelView = require(HudModules:WaitForChild("AdminPanelView"))
local HorseViewportRenderer = require(HudModules:WaitForChild("HorseViewportRenderer"))

local SCREEN_GUI_NAME = "AdminPanelGui"
local ITEM_TAB_NAME = "Items"
local HORSE_TAB_NAME = "Horses"
local CARE_TAB_NAME = "Care"
local STUDIO_ACCESS_OVERRIDE = RunService:IsStudio()

local RARITY_STYLES = {
	Common = {
		Accent = Color3.fromRGB(132, 195, 121),
		Surface = Color3.fromRGB(42, 70, 48),
		Text = Color3.fromRGB(232, 247, 227),
	},
	Uncommon = {
		Accent = Color3.fromRGB(89, 174, 212),
		Surface = Color3.fromRGB(34, 65, 83),
		Text = Color3.fromRGB(229, 243, 251),
	},
	Rare = {
		Accent = Color3.fromRGB(103, 124, 240),
		Surface = Color3.fromRGB(39, 48, 96),
		Text = Color3.fromRGB(234, 239, 255),
	},
	Epic = {
		Accent = Color3.fromRGB(188, 109, 255),
		Surface = Color3.fromRGB(78, 43, 112),
		Text = Color3.fromRGB(244, 232, 255),
	},
	Legendary = {
		Accent = Color3.fromRGB(242, 177, 73),
		Surface = Color3.fromRGB(111, 70, 24),
		Text = Color3.fromRGB(255, 245, 227),
	},
}

local SPIN_DELAYS = {
	0.08, 0.08, 0.08, 0.08,
	0.09, 0.09,
	0.10, 0.10,
	0.11, 0.12,
	0.14, 0.16,
	0.19, 0.23,
	0.28, 0.34,
	0.42, 0.52,
	0.65, 0.82,
}

-- All admin remotes are resolved lazily so a slow server start does not
-- block the entire LocalScript and break the M-key toggle.
local _adminRemotesFolder = nil
local _adminRemotesFolderResolved = false
local _cachedRemotes = {}

local function get_admin_remotes_folder()
	if _adminRemotesFolderResolved then
		return _adminRemotesFolder
	end
	local gameplayRemotes = ReplicatedStorage:WaitForChild(NetworkConfig.GameplayFolderName, 15)
	if gameplayRemotes then
		_adminRemotesFolder = gameplayRemotes:WaitForChild(NetworkConfig.Admin.FolderName, 15)
	end
	_adminRemotesFolderResolved = true
	return _adminRemotesFolder
end

local function get_admin_remote(remoteName)
	if _cachedRemotes[remoteName] then
		return _cachedRemotes[remoteName]
	end
	local folder = get_admin_remotes_folder()
	if not folder then
		return nil
	end
	local remote = folder:WaitForChild(remoteName, 10)
	if remote then
		_cachedRemotes[remoteName] = remote
	end
	return remote
end

local function get_catalog_remote()
	return get_admin_remote(NetworkConfig.Admin.GetItemCatalog)
end

local function get_request_item_remote()
	return get_admin_remote(NetworkConfig.Admin.RequestItemTool)
end

local function get_roulette_state_remote()
	return get_admin_remote(NetworkConfig.Admin.GetHorseRouletteState)
end

local function get_roulette_roll_remote()
	return get_admin_remote(NetworkConfig.Admin.RollHorseRoulette)
end

local function get_restore_equipped_horse_needs_remote()
	return get_admin_remote(NetworkConfig.Admin.RestoreEquippedHorseNeeds)
end

local hasAccess = false
local adminRank = 0
local selectedTabName = ITEM_TAB_NAME
local categoryCatalog = {}
local selectedCategoryName = nil
local rouletteState = {
	Price = 500,
	Balance = 0,
	FreeWhenZero = true,
	Horses = {},
	SelectedIndex = 0,
	IsRolling = false,
}
local rouletteHorseByCatalogId = {}
local roulettePreview = {
	WorldModel = nil,
	Camera = nil,
	Model = nil,
	Focus = Vector3.new(0, 3.5, 0),
	CameraDistance = 14,
	CameraHeight = 4.5,
	OrbitAngle = -1.3,
}

local screenGui
local overlay
local rootFrame
local titleLabel
local subtitleLabel
local refreshButton
local itemTabButton
local horseTabButton
local careTabButton
local itemsContentFrame
local horseContentFrame
local careContentFrame
local categoryListFrame
local itemListFrame
local itemListLayout
local rankValueLabel
local accessValueLabel
local hintLabel
local itemStatusLabel
local sectionTitleLabel
local emptyStateLabel
local getAllButton
local rouletteBalanceLabel
local rouletteViewportFrame
local rouletteNameLabel
local rouletteRarityLabel
local rouletteRarityBadge
local rouletteRarityStroke
local rouletteStatusLabel
local rouletteRollButton
local rouletteRuleLabel
local rouletteDimmer
local rouletteRevealLabel
local rouletteRevealScale
local rouletteCardScale
local rouletteCardStroke
local careStatusLabel
local careRestoreButton

local render_category_list
local render_item_list
local fetch_catalog
local fetch_roulette_state
local select_roulette_horse_by_index
local update_roulette_button
local set_active_tab

local function create(className, properties)
	local instance = Instance.new(className)

	for propertyName, value in pairs(properties) do
		instance[propertyName] = value
	end

	return instance
end

local function clear_children(parent, predicate)
	for _, child in ipairs(parent:GetChildren()) do
		if not predicate or predicate(child) then
			child:Destroy()
		end
	end
end

local function set_status(targetLabel, message, isError)
	if not targetLabel then
		return
	end

	targetLabel.Text = message
	targetLabel.TextColor3 = isError and Color3.fromRGB(255, 166, 166) or Color3.fromRGB(175, 228, 187)
end

local function set_item_status(message, isError)
	set_status(itemStatusLabel, message, isError)
end

local function set_roulette_status(message, isError)
	set_status(rouletteStatusLabel, message, isError)
end

local function set_care_status(message, isError)
	set_status(careStatusLabel, message, isError)
end

local function invoke_remote(remote, ...)
	if not remote then
		return false, "RemoteNotFound"
	end

	local success, response = pcall(function(...)
		return remote:InvokeServer(...)
	end, ...)

	return success, response
end

local function get_rarity_style(rarity)
	return RARITY_STYLES[rarity] or RARITY_STYLES.Common
end

local function find_selected_category()
	for _, categoryDefinition in ipairs(categoryCatalog) do
		if categoryDefinition.Name == selectedCategoryName then
			return categoryDefinition
		end
	end

	return nil
end

local function clear_preview_world()
	HorseViewportRenderer.Clear(rouletteViewportFrame)
	roulettePreview.WorldModel = nil
	roulettePreview.Camera = nil
	roulettePreview.Model = nil
end

local function update_rarity_badge(horseOption)
	local style = get_rarity_style(horseOption and horseOption.Rarity or nil)

	if rouletteRarityBadge then
		rouletteRarityBadge.BackgroundColor3 = style.Surface
	end

	if rouletteRarityStroke then
		rouletteRarityStroke.Color = style.Accent
	end

	if rouletteRarityLabel then
		rouletteRarityLabel.TextColor3 = style.Text
		rouletteRarityLabel.Text = horseOption and string.upper(horseOption.Rarity or "Common") or "COMMON"
	end

	if rouletteCardStroke then
		rouletteCardStroke.Color = style.Accent
	end
end

local function mount_preview_model(horseOption)
	if not rouletteViewportFrame then
		return
	end

	if not horseOption then
		clear_preview_world()
		update_rarity_badge(nil)
		if rouletteNameLabel then
			rouletteNameLabel.Text = "No horse selected"
		end
		return
	end

	if rouletteNameLabel then
		rouletteNameLabel.Text = horseOption.DisplayName or horseOption.CatalogId
	end

	update_rarity_badge(horseOption)
	HorseViewportRenderer.QueueCatalog(
		rouletteViewportFrame,
		horseOption.CatalogId,
		HorseViewportRenderer.Presets.Admin,
		{
			ModelKey = horseOption.ModelKey,
			Priority = rouletteState.IsRolling and 2 or 3,
			Callback = function(success, scene)
				if not success or not scene or not scene.Model then return end
				local model = scene.Model
				local boxCFrame, boxSize = model:GetBoundingBox()
				local offset = model:GetPivot():ToObjectSpace(boxCFrame)
				local targetBoxCFrame = CFrame.new(0, math.max(2.2, boxSize.Y * 0.5), 0)
					* CFrame.Angles(0, math.rad(25), 0)
				model:PivotTo(targetBoxCFrame * offset:Inverse())

				local _, positionedSize = model:GetBoundingBox()
				roulettePreview.WorldModel = scene.WorldModel
				roulettePreview.Camera = scene.Camera
				roulettePreview.Model = model
				roulettePreview.Focus = Vector3.new(0, math.max(2.5, positionedSize.Y * 0.56), 0)
				roulettePreview.CameraDistance = math.max(12, positionedSize.X * 1.45 + positionedSize.Z + 3.5)
				roulettePreview.CameraHeight = math.max(3.8, positionedSize.Y * 0.33)
			end,
		}
	)
end

local function get_selected_roulette_horse()
	return rouletteState.Horses[rouletteState.SelectedIndex]
end

local function find_roulette_index(catalogId)
	for index, horseOption in ipairs(rouletteState.Horses) do
		if horseOption.CatalogId == catalogId then
			return index
		end
	end

	return nil
end

local function refresh_roulette_balance_label()
	if not rouletteBalanceLabel then
		return
	end

	rouletteBalanceLabel.Text = ("Horseshoes: %d"):format(rouletteState.Balance or 0)
end

update_roulette_button = function()
	if not rouletteRollButton then
		return
	end

	local canFreeRoll = rouletteState.FreeWhenZero and rouletteState.Balance == 0
	local hasPaidBalance = rouletteState.Balance >= rouletteState.Price
	local hasMidrangeBalance = rouletteState.Balance > 0 and rouletteState.Balance < rouletteState.Price
	local hasHorsePool = #rouletteState.Horses > 0

	local enabled = hasAccess
		and (not rouletteState.IsRolling)
		and hasHorsePool
		and (canFreeRoll or hasPaidBalance)

	if rouletteState.IsRolling then
		rouletteRollButton.Text = "Rolling..."
	elseif canFreeRoll then
		rouletteRollButton.Text = "Roll for Free"
	elseif hasMidrangeBalance then
		rouletteRollButton.Text = "Insufficient balance"
	else
		rouletteRollButton.Text = ("Roll - %d Horseshoes"):format(rouletteState.Price)
	end

	rouletteRollButton.Active = enabled
	rouletteRollButton.AutoButtonColor = enabled
	rouletteRollButton.BackgroundColor3 = enabled
		and Color3.fromRGB(215, 121, 58)
		or Color3.fromRGB(86, 93, 104)
	rouletteRollButton.TextColor3 = enabled
		and Color3.fromRGB(253, 247, 240)
		or Color3.fromRGB(214, 219, 226)
end

local function render_selected_roulette_horse()
	local horseOption = get_selected_roulette_horse()
	mount_preview_model(horseOption)
end

select_roulette_horse_by_index = function(index)
	if #rouletteState.Horses == 0 then
		rouletteState.SelectedIndex = 0
		render_selected_roulette_horse()
		return
	end

	rouletteState.SelectedIndex = math.clamp(index, 1, #rouletteState.Horses)
	render_selected_roulette_horse()
end

local function apply_roulette_reveal(horseOption, response)
	local style = get_rarity_style(horseOption and horseOption.Rarity or nil)
	local headline = "New horse"

	if response.LostBecauseNoSlot then
		headline = "Stable full, horse lost"
	elseif response.AlreadyOwnedCatalog then
		headline = "Duplicate"
	end

	if rouletteRevealLabel then
		rouletteRevealLabel.Text = headline
		rouletteRevealLabel.TextColor3 = style.Accent
		rouletteRevealLabel.Visible = true
	end

	if rouletteRevealScale then
		rouletteRevealScale.Scale = 0.82
	end

	if rouletteCardScale then
		rouletteCardScale.Scale = 1
	end

	local revealTween = rouletteRevealScale and TweenService:Create(
		rouletteRevealScale,
		TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)
	local growTween = rouletteCardScale and TweenService:Create(
		rouletteCardScale,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1.04 }
	)
	local settleTween = rouletteCardScale and TweenService:Create(
		rouletteCardScale,
		TweenInfo.new(0.14, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Scale = 1 }
	)

	if revealTween then
		revealTween:Play()
	end

	if growTween then
		local growConnection
		growConnection = growTween.Completed:Connect(function()
			if growConnection then
				growConnection:Disconnect()
				growConnection = nil
			end

			if settleTween then
				settleTween:Play()
			end
		end)

		growTween:Play()
	end

	if response.LostBecauseNoSlot then
		set_roulette_status("Your stable was full. The horse was lost.", true)
	elseif response.AlreadyOwnedCatalog then
		set_roulette_status(("You rolled %s again."):format(horseOption.DisplayName), false)
	else
		set_roulette_status(("You won %s."):format(horseOption.DisplayName), false)
	end
end

local function play_roulette_spin(response)
	local finalHorse = response and response.RolledHorse or nil
	if not finalHorse or #rouletteState.Horses == 0 then
		rouletteState.IsRolling = false
		update_roulette_button()
		set_roulette_status("Could not show the roulette result.", true)
		return
	end

	local finalIndex = find_roulette_index(finalHorse.CatalogId) or 1
	local currentIndex = rouletteState.SelectedIndex > 0 and rouletteState.SelectedIndex or 1

	rouletteState.IsRolling = true
	update_roulette_button()

	if rouletteRevealLabel then
		rouletteRevealLabel.Visible = false
	end

	if rouletteDimmer then
		rouletteDimmer.Visible = true
	end

	set_roulette_status("Roulette spinning...", false)

	for stepIndex, delaySeconds in ipairs(SPIN_DELAYS) do
		if stepIndex == #SPIN_DELAYS then
			currentIndex = finalIndex
		else
			local attempts = 0
			repeat
				currentIndex = (currentIndex % #rouletteState.Horses) + 1
				attempts += 1
			until currentIndex ~= finalIndex or stepIndex >= (#SPIN_DELAYS - 4) or attempts > #rouletteState.Horses
		end

		select_roulette_horse_by_index(currentIndex)
		task.wait(delaySeconds)
	end

	task.wait(1.2)

	rouletteState.Balance = tonumber(response.RemainingHorseshoes) or rouletteState.Balance
	refresh_roulette_balance_label()
	apply_roulette_reveal(get_selected_roulette_horse() or finalHorse, response)

	if rouletteDimmer then
		rouletteDimmer.Visible = false
	end

	rouletteState.IsRolling = false
	update_roulette_button()
end

local function render_roulette_state(response)
	local currentCatalogId = get_selected_roulette_horse() and get_selected_roulette_horse().CatalogId or nil

	rouletteState.Price = tonumber(response.Price) or rouletteState.Price
	rouletteState.Balance = tonumber(response.Balance) or rouletteState.Balance
	rouletteState.FreeWhenZero = response.FreeWhenZero == true
	rouletteState.Horses = type(response.Horses) == "table" and response.Horses or {}
	rouletteHorseByCatalogId = {}

	for _, horseOption in ipairs(rouletteState.Horses) do
		rouletteHorseByCatalogId[horseOption.CatalogId] = horseOption
	end

	if rouletteRuleLabel then
		rouletteRuleLabel.Text = ("Admins with 0 Horseshoes roll for free. Normal cost: %d."):format(rouletteState.Price)
	end

	refresh_roulette_balance_label()

	if #rouletteState.Horses == 0 then
		rouletteState.SelectedIndex = 0
		render_selected_roulette_horse()
		update_roulette_button()
		return
	end

	local targetIndex = currentCatalogId and find_roulette_index(currentCatalogId) or nil
	if not targetIndex then
		targetIndex = 1
	end

	select_roulette_horse_by_index(targetIndex)
	update_roulette_button()
end

fetch_roulette_state = function()
	if not hasAccess then
		return
	end

	local rouletteStateRemote = get_roulette_state_remote()
	if not rouletteStateRemote then
		set_roulette_status("Roulette remote was not found on the server.", true)
		return
	end

	local success, response = invoke_remote(rouletteStateRemote)
	if not success then
		set_roulette_status("Could not reach the server.", true)
		return
	end

	if not response or response.Success ~= true then
		set_roulette_status("Could not load the roulette.", true)
		return
	end

	render_roulette_state(response)
	set_roulette_status("Roulette ready.", false)
end

render_item_list = function()
	local categoryDefinition = find_selected_category()
	clear_children(itemListFrame, function(child)
		return child:IsA("TextButton") or child:IsA("Frame")
	end)

	if not categoryDefinition then
		sectionTitleLabel.Text = "Select a category"
		emptyStateLabel.Visible = true
		emptyStateLabel.Text = hasAccess and "Choose a category in the left column." or "Admin access is required."
		getAllButton.Active = false
		getAllButton.AutoButtonColor = false
		getAllButton.BackgroundColor3 = Color3.fromRGB(60, 80, 103)
		return
	end

	sectionTitleLabel.Text = ("%s (%d)"):format(categoryDefinition.Name, categoryDefinition.ItemCount or #categoryDefinition.Items)
	emptyStateLabel.Visible = #categoryDefinition.Items == 0
	emptyStateLabel.Text = "No tools found in this category."

	getAllButton.Active = hasAccess
	getAllButton.AutoButtonColor = hasAccess
	getAllButton.BackgroundColor3 = hasAccess and Color3.fromRGB(70, 112, 93) or Color3.fromRGB(60, 80, 103)

	for _, itemDefinition in ipairs(categoryDefinition.Items) do
		local itemButton = create("TextButton", {
			Name = itemDefinition.ItemId or itemDefinition.Name,
			BackgroundColor3 = Color3.fromRGB(35, 46, 61),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 82),
			AutoButtonColor = hasAccess,
			Font = Enum.Font.Gotham,
			Text = "",
			Parent = itemListFrame,
		})

		create("UICorner", {
			CornerRadius = UDim.new(0, 14),
			Parent = itemButton,
		})

		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = itemDefinition.Name,
			TextColor3 = Color3.fromRGB(235, 242, 255),
			TextSize = 16,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(16, 12),
			Size = UDim2.new(1, -150, 0, 18),
			Parent = itemButton,
		})

		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = itemDefinition.PriceLabel ~= "" and itemDefinition.PriceLabel or "No price",
			TextColor3 = Color3.fromRGB(182, 197, 217),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(16, 36),
			Size = UDim2.new(1, -150, 0, 16),
			Parent = itemButton,
		})

		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = itemDefinition.ToolTip ~= "" and itemDefinition.ToolTip or "Click to get this tool.",
			TextColor3 = Color3.fromRGB(164, 178, 198),
			TextSize = 13,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(16, 54),
			Size = UDim2.new(1, -150, 0, 14),
			Parent = itemButton,
		})

		local getButton = create("TextButton", {
			Name = "GetButton",
			AnchorPoint = Vector2.new(1, 0.5),
			BackgroundColor3 = hasAccess and Color3.fromRGB(76, 121, 163) or Color3.fromRGB(60, 80, 103),
			BorderSizePixel = 0,
			Position = UDim2.new(1, -14, 0.5, 0),
			Size = UDim2.fromOffset(108, 38),
			AutoButtonColor = hasAccess,
			Font = Enum.Font.GothamBold,
			Text = "Pegar",
			TextColor3 = Color3.fromRGB(244, 248, 255),
			TextSize = 14,
			Parent = itemButton,
		})

		create("UICorner", {
			CornerRadius = UDim.new(0, 12),
			Parent = getButton,
		})

		getButton.Activated:Connect(function()
			if not hasAccess then
				set_item_status("You do not have permission to get tools.", true)
				return
			end

			local success, response = invoke_remote(get_request_item_remote(), {
				Mode = "Single",
				CategoryName = categoryDefinition.Name,
				ItemId = itemDefinition.ItemId,
			})

			if not success then
				set_item_status("Could not reach the server.", true)
			elseif response and response.Success then
				set_item_status(("Tool entregue: %s"):format(response.ItemName or itemDefinition.Name), false)
			else
				set_item_status("Could not grant the tool.", true)
			end
		end)
	end

	itemListFrame.CanvasSize = UDim2.fromOffset(0, itemListLayout.AbsoluteContentSize.Y + 8)
end

render_category_list = function()
	clear_children(categoryListFrame, function(child)
		return child:IsA("TextButton")
	end)

	for _, categoryDefinition in ipairs(categoryCatalog) do
		local isSelected = categoryDefinition.Name == selectedCategoryName
		local categoryButton = create("TextButton", {
			Name = categoryDefinition.Name,
			BackgroundColor3 = isSelected and Color3.fromRGB(76, 121, 163) or Color3.fromRGB(35, 46, 61),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 54),
			AutoButtonColor = hasAccess,
			Font = Enum.Font.Gotham,
			Text = "",
			Parent = categoryListFrame,
		})

		create("UICorner", {
			CornerRadius = UDim.new(0, 12),
			Parent = categoryButton,
		})

		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = categoryDefinition.Name,
			TextColor3 = Color3.fromRGB(240, 245, 255),
			TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 10),
			Size = UDim2.new(1, -28, 0, 16),
			Parent = categoryButton,
		})

		create("TextLabel", {
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = ("%d tools"):format(categoryDefinition.ItemCount or #categoryDefinition.Items),
			TextColor3 = Color3.fromRGB(192, 205, 223),
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Position = UDim2.fromOffset(14, 28),
			Size = UDim2.new(1, -28, 0, 14),
			Parent = categoryButton,
		})

		categoryButton.Activated:Connect(function()
			selectedCategoryName = categoryDefinition.Name
			render_category_list()
			render_item_list()
		end)
	end
end

fetch_catalog = function()
	if not hasAccess then
		return
	end

	set_item_status("Loading categories...", false)

	local success, response = invoke_remote(get_catalog_remote())
	if not success then
		categoryCatalog = {}
		selectedCategoryName = nil
		render_category_list()
		render_item_list()
		set_item_status("Could not reach the server.", true)
		return
	end

	if not response or response.Success ~= true then
		categoryCatalog = {}
		selectedCategoryName = nil
		render_category_list()
		render_item_list()
		set_item_status("Could not load the categories.", true)
		return
	end

	categoryCatalog = response.Categories or {}

	if selectedCategoryName == nil or find_selected_category() == nil then
		selectedCategoryName = categoryCatalog[1] and categoryCatalog[1].Name or nil
	end

	render_category_list()
	render_item_list()
	set_item_status("Categories loaded.", false)
end

local function update_tab_button_visual(button, selected)
	if not button then
		return
	end

	button.BackgroundColor3 = selected and Color3.fromRGB(76, 121, 163) or Color3.fromRGB(39, 53, 71)
	button.TextColor3 = selected and Color3.fromRGB(245, 249, 255) or Color3.fromRGB(189, 202, 219)
end

set_active_tab = function(tabName)
	if tabName ~= ITEM_TAB_NAME and tabName ~= HORSE_TAB_NAME and tabName ~= CARE_TAB_NAME then
		tabName = ITEM_TAB_NAME
	end
	selectedTabName = tabName

	local onItems = selectedTabName == ITEM_TAB_NAME
	local onHorses = selectedTabName == HORSE_TAB_NAME
	local onCare = selectedTabName == CARE_TAB_NAME

	if itemsContentFrame then
		itemsContentFrame.Visible = onItems
	end

	if horseContentFrame then
		horseContentFrame.Visible = onHorses
	end

	if careContentFrame then
		careContentFrame.Visible = onCare
	end

	if refreshButton then
		refreshButton.Visible = hasAccess and onItems
	end

	update_tab_button_visual(itemTabButton, onItems)
	update_tab_button_visual(horseTabButton, onHorses)
	update_tab_button_visual(careTabButton, onCare)

	if titleLabel then
		titleLabel.Text = onItems and "Admin Item Browser" or (onHorses and "Admin Horse Roulette" or "Admin Horse Care")
	end

	if subtitleLabel then
		if onItems then
			subtitleLabel.Text = "Get tools from ReplicatedStorage.Assets.Items by category."
		elseif onHorses then
			subtitleLabel.Text = "Visual horse roulette using the same starter pool."
		else
			subtitleLabel.Text = "Restore the currently equipped horse."
		end
	end

	if not hasAccess then
		return
	end

	if onItems then
		fetch_catalog()
	elseif onHorses then
		fetch_roulette_state()
	else
		set_care_status("Ready to restore the equipped horse.", false)
	end
end

local function refresh_access_state()
	hasAccess = STUDIO_ACCESS_OVERRIDE or localPlayer:GetAttribute("CanOpenAdminPanel") == true
	adminRank = localPlayer:GetAttribute("AdminRank") or 0

	if rankValueLabel then
		rankValueLabel.Text = ("Current rank: %d"):format(adminRank)
	end

	if accessValueLabel then
		accessValueLabel.Text = hasAccess and "Access: Granted" or "Access: Denied"
		accessValueLabel.TextColor3 = hasAccess and Color3.fromRGB(149, 232, 174) or Color3.fromRGB(255, 157, 157)
	end

	if hintLabel then
		if hasAccess then
			hintLabel.Text = STUDIO_ACCESS_OVERRIDE
				and "Studio access granted. Press M for items and H for the roulette."
				or "Press M for items and H for the horse roulette."
		else
			local minimumRank = localPlayer:GetAttribute("AdminMinimumRank") or 250
			local groupId = localPlayer:GetAttribute("AdminGroupId") or 1071228359
			hintLabel.Text = ("Requires rank %d+ in group %d."):format(minimumRank, groupId)
		end
	end

	if screenGui and not hasAccess then
		screenGui.Enabled = false
	end

	update_roulette_button()
	if careRestoreButton then
		careRestoreButton.Active = hasAccess
		careRestoreButton.AutoButtonColor = hasAccess
		careRestoreButton.BackgroundColor3 = hasAccess and Color3.fromRGB(72, 142, 92) or Color3.fromRGB(86, 93, 104)
	end
	if screenGui then
		set_active_tab(selectedTabName)
	end
end

local function toggle_panel()
	if not hasAccess or not screenGui then
		return
	end

	screenGui.Enabled = not screenGui.Enabled

	if screenGui.Enabled then
		set_active_tab(selectedTabName)
	end
end

local function build_panel()
	local refs = AdminPanelView.build({
		localPlayer = localPlayer,
		screenGuiName = SCREEN_GUI_NAME,
		itemTabName = ITEM_TAB_NAME,
		horseTabName = HORSE_TAB_NAME,
		careTabName = CARE_TAB_NAME,
		fetchCatalog = fetch_catalog,
		setActiveTab = set_active_tab,
		onRequestSelectedCategory = function()
			local categoryDefinition = find_selected_category()
			if not hasAccess or not categoryDefinition then
				return
			end

			local success, response = invoke_remote(get_request_item_remote(), {
				Mode = "Category",
				CategoryName = categoryDefinition.Name,
			})

			if not success then
				set_item_status("Could not reach the server.", true)
			elseif response and response.Success then
				set_item_status(("Category granted: %s (%d tools)"):format(categoryDefinition.Name, response.GrantedCount or 0), false)
			else
				set_item_status("Could not grant the full category.", true)
			end
		end,
		onRouletteRoll = function()
			if rouletteState.IsRolling then
				return
			end

			local canFreeRoll = rouletteState.FreeWhenZero and rouletteState.Balance == 0
			if rouletteState.Balance > 0 and rouletteState.Balance < rouletteState.Price then
				set_roulette_status("You need 500 Horseshoes, or 0 for a free roll.", true)
				return
			end

			if not canFreeRoll and rouletteState.Balance < rouletteState.Price then
				set_roulette_status("Not enough Horseshoes for the roulette.", true)
				return
			end

			local rouletteRollRemote = get_roulette_roll_remote()
			if not rouletteRollRemote then
				set_roulette_status("Roulette request is unavailable on the server.", true)
				return
			end

			local success, response = invoke_remote(rouletteRollRemote)
			if not success then
				set_roulette_status("Could not reach the server.", true)
				return
			end

			if not response or response.Success ~= true then
				if response and response.MessageCode == "InsufficientFunds" then
					rouletteState.Balance = tonumber(response.RemainingHorseshoes) or rouletteState.Balance
					refresh_roulette_balance_label()
					update_roulette_button()
					set_roulette_status("You need 500 Horseshoes, or 0 for a free roll.", true)
				else
					set_roulette_status("Could not complete the roulette roll.", true)
				end
				return
			end

			task.spawn(play_roulette_spin, response)
		end,
		onRestoreEquippedHorse = function()
			if not hasAccess then
				return
			end

			local restoreRemote = get_restore_equipped_horse_needs_remote()
			if not restoreRemote then
				set_care_status("Horse care request is unavailable on the server.", true)
				return
			end

			if careRestoreButton then
				careRestoreButton.Active = false
				careRestoreButton.AutoButtonColor = false
			end
			set_care_status("Restoring the equipped horse...", false)

			local success, response = invoke_remote(restoreRemote)
			if careRestoreButton then
				careRestoreButton.Active = hasAccess
				careRestoreButton.AutoButtonColor = hasAccess
			end

			if not success then
				set_care_status("Could not reach the server.", true)
			elseif response and response.Success then
				set_care_status(("%s is now at 100%%."):format(response.HorseName or "Equipped horse"), false)
			else
				set_care_status("No equipped horse was found.", true)
			end
		end,
	})

	screenGui = refs.ScreenGui
	overlay = refs.Overlay
	rootFrame = refs.RootFrame
	titleLabel = refs.TitleLabel
	subtitleLabel = refs.SubtitleLabel
	refreshButton = refs.RefreshButton
	itemTabButton = refs.ItemTabButton
	horseTabButton = refs.HorseTabButton
	careTabButton = refs.CareTabButton
	itemsContentFrame = refs.ItemsContentFrame
	horseContentFrame = refs.HorseContentFrame
	careContentFrame = refs.CareContentFrame
	categoryListFrame = refs.CategoryListFrame
	itemListFrame = refs.ItemListFrame
	itemListLayout = refs.ItemListLayout
	rankValueLabel = refs.RankValueLabel
	accessValueLabel = refs.AccessValueLabel
	hintLabel = refs.HintLabel
	itemStatusLabel = refs.ItemStatusLabel
	sectionTitleLabel = refs.SectionTitleLabel
	emptyStateLabel = refs.EmptyStateLabel
	getAllButton = refs.GetAllButton
	rouletteBalanceLabel = refs.RouletteBalanceLabel
	rouletteViewportFrame = refs.RouletteViewportFrame
	rouletteNameLabel = refs.RouletteNameLabel
	rouletteRarityLabel = refs.RouletteRarityLabel
	rouletteRarityBadge = refs.RouletteRarityBadge
	rouletteRarityStroke = refs.RouletteRarityStroke
	rouletteStatusLabel = refs.RouletteStatusLabel
	rouletteRollButton = refs.RouletteRollButton
	rouletteRuleLabel = refs.RouletteRuleLabel
	rouletteDimmer = refs.RouletteDimmer
	rouletteRevealLabel = refs.RouletteRevealLabel
	rouletteRevealScale = refs.RouletteRevealScale
	rouletteCardScale = refs.RouletteCardScale
	rouletteCardStroke = refs.RouletteCardStroke
	careStatusLabel = refs.CareStatusLabel
	careRestoreButton = refs.CareRestoreButton
end
build_panel()
refresh_access_state()
render_category_list()
render_item_list()
update_roulette_button()

RunService.RenderStepped:Connect(function(deltaTime)
	if not screenGui or not screenGui.Enabled or selectedTabName ~= HORSE_TAB_NAME then
		return
	end

	if not roulettePreview.Camera or not roulettePreview.Model then
		return
	end

	roulettePreview.OrbitAngle += deltaTime * (rouletteState.IsRolling and 1.2 or 0.34)

	local focus = roulettePreview.Focus
	local angle = roulettePreview.OrbitAngle
	local position = focus + Vector3.new(
		math.cos(angle) * roulettePreview.CameraDistance,
		roulettePreview.CameraHeight,
		math.sin(angle) * roulettePreview.CameraDistance
	)

	roulettePreview.Camera.CFrame = CFrame.lookAt(position, focus + Vector3.new(0, 0.3, 0))
end)

DataUtility.client.bind("Currencies.Horseshoes", function(horseshoes)
	rouletteState.Balance = math.max(0, tonumber(horseshoes) or 0)
	refresh_roulette_balance_label()
	update_roulette_button()
end)

localPlayer:GetAttributeChangedSignal("CanOpenAdminPanel"):Connect(function()
	refresh_access_state()
	if hasAccess and screenGui and screenGui.Enabled then
		set_active_tab(selectedTabName)
	end
end)

localPlayer:GetAttributeChangedSignal("AdminRank"):Connect(refresh_access_state)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.M then
		toggle_panel()
	end
end)
