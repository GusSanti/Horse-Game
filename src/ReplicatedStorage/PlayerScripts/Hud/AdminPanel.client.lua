local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local RaceVisualFactory = require(Utility:WaitForChild("RaceVisualFactory"))
local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))

local SCREEN_GUI_NAME = "AdminPanelGui"
local ITEM_TAB_NAME = "Items"
local HORSE_TAB_NAME = "Cavalos"

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
local itemsContentFrame
local horseContentFrame
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
	if roulettePreview.WorldModel then
		for _, child in ipairs(roulettePreview.WorldModel:GetChildren()) do
			child:Destroy()
		end
	end

	roulettePreview.Model = nil
end

local function ensure_preview_scene()
	if not rouletteViewportFrame then
		return false
	end

	if not roulettePreview.WorldModel or roulettePreview.WorldModel.Parent ~= rouletteViewportFrame then
		local worldModel = rouletteViewportFrame:FindFirstChild("WorldModel")
		if worldModel and not worldModel:IsA("WorldModel") then
			worldModel:Destroy()
			worldModel = nil
		end

		if not worldModel then
			worldModel = Instance.new("WorldModel")
			worldModel.Name = "WorldModel"
			worldModel.Parent = rouletteViewportFrame
		end

		roulettePreview.WorldModel = worldModel
	end

	if not roulettePreview.Camera or roulettePreview.Camera.Parent ~= rouletteViewportFrame then
		local camera = rouletteViewportFrame:FindFirstChild("PreviewCamera")
		if camera and not camera:IsA("Camera") then
			camera:Destroy()
			camera = nil
		end

		if not camera then
			camera = Instance.new("Camera")
			camera.Name = "PreviewCamera"
			camera.Parent = rouletteViewportFrame
		end

		roulettePreview.Camera = camera
		rouletteViewportFrame.CurrentCamera = camera
	end

	return true
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
	if not ensure_preview_scene() then
		return
	end

	clear_preview_world()

	if not horseOption then
		update_rarity_badge(nil)
		if rouletteNameLabel then
			rouletteNameLabel.Text = "Nenhum cavalo"
		end
		return
	end

	local summary = {
		Id = horseOption.CatalogId,
		HorseId = horseOption.CatalogId,
		CatalogId = horseOption.CatalogId,
		PlaceholderModelKey = horseOption.ModelKey,
	}

	local model = RaceVisualFactory.CreateRaceModel(summary, nil, roulettePreview.WorldModel)
	roulettePreview.Model = model

	local boxCFrame, boxSize = model:GetBoundingBox()
	local offset = model:GetPivot():ToObjectSpace(boxCFrame)
	local targetBoxCFrame = CFrame.new(0, math.max(2.2, boxSize.Y * 0.5), 0) * CFrame.Angles(0, math.rad(25), 0)
	model:PivotTo(targetBoxCFrame * offset:Inverse())

	local _, positionedSize = model:GetBoundingBox()
	roulettePreview.Focus = Vector3.new(0, math.max(2.5, positionedSize.Y * 0.56), 0)
	roulettePreview.CameraDistance = math.max(12, positionedSize.X * 1.45 + positionedSize.Z + 3.5)
	roulettePreview.CameraHeight = math.max(3.8, positionedSize.Y * 0.33)

	if rouletteNameLabel then
		rouletteNameLabel.Text = horseOption.DisplayName or horseOption.CatalogId
	end

	update_rarity_badge(horseOption)
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
		rouletteRollButton.Text = "Rolando..."
	elseif canFreeRoll then
		rouletteRollButton.Text = "Roletar Gratis"
	elseif hasMidrangeBalance then
		rouletteRollButton.Text = "Saldo insuficiente"
	else
		rouletteRollButton.Text = ("Roletar - %d Horseshoes"):format(rouletteState.Price)
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
	local headline = "Novo cavalo"

	if response.LostBecauseNoSlot then
		headline = "Slot cheio, cavalo perdido"
	elseif response.AlreadyOwnedCatalog then
		headline = "Repetido"
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
		set_roulette_status("Sua cocheira estava cheia. O cavalo foi perdido.", true)
	elseif response.AlreadyOwnedCatalog then
		set_roulette_status(("Voce tirou %s novamente."):format(horseOption.DisplayName), false)
	else
		set_roulette_status(("Voce ganhou %s."):format(horseOption.DisplayName), false)
	end
end

local function play_roulette_spin(response)
	local finalHorse = response and response.RolledHorse or nil
	if not finalHorse or #rouletteState.Horses == 0 then
		rouletteState.IsRolling = false
		update_roulette_button()
		set_roulette_status("Nao foi possivel mostrar o resultado da roleta.", true)
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

	set_roulette_status("Roleta girando...", false)

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
		rouletteRuleLabel.Text = ("Admin com 0 Horseshoes rola gratis. Custo normal: %d."):format(rouletteState.Price)
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
		set_roulette_status("Remote de roleta nao encontrado no servidor.", true)
		return
	end

	local success, response = invoke_remote(rouletteStateRemote)
	if not success then
		set_roulette_status("Falha ao falar com o servidor.", true)
		return
	end

	if not response or response.Success ~= true then
		set_roulette_status("Nao foi possivel carregar a roleta.", true)
		return
	end

	render_roulette_state(response)
	set_roulette_status("Roleta pronta.", false)
end

render_item_list = function()
	local categoryDefinition = find_selected_category()
	clear_children(itemListFrame, function(child)
		return child:IsA("TextButton") or child:IsA("Frame")
	end)

	if not categoryDefinition then
		sectionTitleLabel.Text = "Selecione uma categoria"
		emptyStateLabel.Visible = true
		emptyStateLabel.Text = hasAccess and "Escolha uma categoria na coluna da esquerda." or "Acesso de admin necessario."
		getAllButton.Active = false
		getAllButton.AutoButtonColor = false
		getAllButton.BackgroundColor3 = Color3.fromRGB(60, 80, 103)
		return
	end

	sectionTitleLabel.Text = ("%s (%d)"):format(categoryDefinition.Name, categoryDefinition.ItemCount or #categoryDefinition.Items)
	emptyStateLabel.Visible = #categoryDefinition.Items == 0
	emptyStateLabel.Text = "Nenhuma tool encontrada nesta categoria."

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
			Text = itemDefinition.PriceLabel ~= "" and itemDefinition.PriceLabel or "sem preco",
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
			Text = itemDefinition.ToolTip ~= "" and itemDefinition.ToolTip or "Clique para pegar esta tool.",
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
				set_item_status("Voce nao tem permissao para pegar tools.", true)
				return
			end

			local success, response = invoke_remote(get_request_item_remote(), {
				Mode = "Single",
				CategoryName = categoryDefinition.Name,
				ItemId = itemDefinition.ItemId,
			})

			if not success then
				set_item_status("Falha ao falar com o servidor.", true)
			elseif response and response.Success then
				set_item_status(("Tool entregue: %s"):format(response.ItemName or itemDefinition.Name), false)
			else
				set_item_status("Nao foi possivel entregar a tool.", true)
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

	set_item_status("Carregando categorias...", false)

	local success, response = invoke_remote(get_catalog_remote())
	if not success then
		categoryCatalog = {}
		selectedCategoryName = nil
		render_category_list()
		render_item_list()
		set_item_status("Falha ao falar com o servidor.", true)
		return
	end

	if not response or response.Success ~= true then
		categoryCatalog = {}
		selectedCategoryName = nil
		render_category_list()
		render_item_list()
		set_item_status("Nao foi possivel carregar as categorias.", true)
		return
	end

	categoryCatalog = response.Categories or {}

	if selectedCategoryName == nil or find_selected_category() == nil then
		selectedCategoryName = categoryCatalog[1] and categoryCatalog[1].Name or nil
	end

	render_category_list()
	render_item_list()
	set_item_status("Categorias carregadas.", false)
end

local function update_tab_button_visual(button, selected)
	if not button then
		return
	end

	button.BackgroundColor3 = selected and Color3.fromRGB(76, 121, 163) or Color3.fromRGB(39, 53, 71)
	button.TextColor3 = selected and Color3.fromRGB(245, 249, 255) or Color3.fromRGB(189, 202, 219)
end

set_active_tab = function(tabName)
	selectedTabName = tabName

	local onItems = selectedTabName == ITEM_TAB_NAME

	if itemsContentFrame then
		itemsContentFrame.Visible = onItems
	end

	if horseContentFrame then
		horseContentFrame.Visible = not onItems
	end

	if refreshButton then
		refreshButton.Visible = hasAccess and onItems
	end

	update_tab_button_visual(itemTabButton, onItems)
	update_tab_button_visual(horseTabButton, not onItems)

	if titleLabel then
		titleLabel.Text = onItems and "Admin Item Browser" or "Admin Horse Roulette"
	end

	if subtitleLabel then
		subtitleLabel.Text = onItems
			and "Pegue tools do ReplicatedStorage.Assets.Items por categoria."
			or "Roletagem visual de cavalos usando a mesma pool do starter."
	end

	if not hasAccess then
		return
	end

	if onItems then
		fetch_catalog()
	else
		fetch_roulette_state()
	end
end

local function refresh_access_state()
	hasAccess = localPlayer:GetAttribute("CanOpenAdminPanel") == true
	adminRank = localPlayer:GetAttribute("AdminRank") or 0

	if rankValueLabel then
		rankValueLabel.Text = ("Rank atual: %d"):format(adminRank)
	end

	if accessValueLabel then
		accessValueLabel.Text = hasAccess and "Acesso: Liberado" or "Acesso: Bloqueado"
		accessValueLabel.TextColor3 = hasAccess and Color3.fromRGB(149, 232, 174) or Color3.fromRGB(255, 157, 157)
	end

	if hintLabel then
		if hasAccess then
			hintLabel.Text = "Pressione M para abrir, depois troque entre as abas de items e cavalos."
		else
			local minimumRank = localPlayer:GetAttribute("AdminMinimumRank") or 250
			local groupId = localPlayer:GetAttribute("AdminGroupId") or 1071228359
			hintLabel.Text = ("Requer rank %d+ no grupo %d."):format(minimumRank, groupId)
		end
	end

	if screenGui and not hasAccess then
		screenGui.Enabled = false
	end

	update_roulette_button()
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
	local playerGui = localPlayer:WaitForChild("PlayerGui")

	screenGui = create("ScreenGui", {
		Name = SCREEN_GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Enabled = false,
		Parent = playerGui,
	})

	overlay = create("Frame", {
		Name = "Overlay",
		BackgroundColor3 = Color3.fromRGB(7, 12, 18),
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = screenGui,
	})

	rootFrame = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(19, 27, 37),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(980, 610),
		Parent = overlay,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 18),
		Parent = rootFrame,
	})

	create("UIStroke", {
		Color = Color3.fromRGB(74, 121, 163),
		Thickness = 2,
		Transparency = 0.15,
		Parent = rootFrame,
	})

	local topBar = create("Frame", {
		Name = "TopBar",
		BackgroundColor3 = Color3.fromRGB(28, 39, 55),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 72),
		Parent = rootFrame,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 18),
		Parent = topBar,
	})

	create("Frame", {
		Name = "TopBarMask",
		BackgroundColor3 = Color3.fromRGB(28, 39, 55),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 30),
		Size = UDim2.new(1, 0, 1, -30),
		Parent = topBar,
	})

	titleLabel = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Admin Item Browser",
		TextColor3 = Color3.fromRGB(238, 244, 255),
		TextSize = 29,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 14),
		Size = UDim2.new(1, -168, 0, 24),
		Parent = topBar,
	})

	subtitleLabel = create("TextLabel", {
		Name = "Subtitle",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Pegue tools do ReplicatedStorage.Assets.Items por categoria.",
		TextColor3 = Color3.fromRGB(176, 193, 214),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 42),
		Size = UDim2.new(1, -168, 0, 18),
		Parent = topBar,
	})

	refreshButton = create("TextButton", {
		Name = "RefreshButton",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(55, 91, 125),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -104, 0, 18),
		Size = UDim2.fromOffset(70, 34),
		Text = "Refresh",
		TextColor3 = Color3.fromRGB(240, 246, 255),
		TextSize = 13,
		Parent = topBar,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 12),
		Parent = refreshButton,
	})

	refreshButton.Activated:Connect(fetch_catalog)

	local closeButton = create("TextButton", {
		Name = "CloseButton",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(53, 74, 96),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -22, 0, 18),
		Size = UDim2.fromOffset(34, 34),
		Text = "X",
		TextColor3 = Color3.fromRGB(240, 246, 255),
		TextSize = 16,
		Parent = topBar,
	})

	create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = closeButton,
	})

	closeButton.Activated:Connect(function()
		screenGui.Enabled = false
	end)

	local tabBar = create("Frame", {
		Name = "TabBar",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 82),
		Size = UDim2.new(1, -44, 0, 44),
		Parent = rootFrame,
	})

	itemTabButton = create("TextButton", {
		Name = "ItemsTab",
		BackgroundColor3 = Color3.fromRGB(76, 121, 163),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(0, 0),
		Size = UDim2.fromOffset(118, 38),
		Text = "Items",
		TextColor3 = Color3.fromRGB(245, 249, 255),
		TextSize = 14,
		Parent = tabBar,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 12),
		Parent = itemTabButton,
	})

	itemTabButton.Activated:Connect(function()
		set_active_tab(ITEM_TAB_NAME)
	end)

	horseTabButton = create("TextButton", {
		Name = "HorsesTab",
		BackgroundColor3 = Color3.fromRGB(39, 53, 71),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromOffset(128, 0),
		Size = UDim2.fromOffset(126, 38),
		Text = "Cavalos",
		TextColor3 = Color3.fromRGB(189, 202, 219),
		TextSize = 14,
		Parent = tabBar,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 12),
		Parent = horseTabButton,
	})

	horseTabButton.Activated:Connect(function()
		set_active_tab(HORSE_TAB_NAME)
	end)

	itemsContentFrame = create("Frame", {
		Name = "ItemsContent",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 132),
		Size = UDim2.new(1, -44, 1, -154),
		Parent = rootFrame,
	})

	local leftColumn = create("Frame", {
		Name = "LeftColumn",
		BackgroundTransparency = 1,
		Size = UDim2.new(0.29, -10, 1, 0),
		Parent = itemsContentFrame,
	})

	local rightColumn = create("Frame", {
		Name = "RightColumn",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.29, 10, 0, 0),
		Size = UDim2.new(0.71, -10, 1, 0),
		Parent = itemsContentFrame,
	})

	local summaryCard = create("Frame", {
		Name = "SummaryCard",
		BackgroundColor3 = Color3.fromRGB(27, 36, 48),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 186),
		Parent = leftColumn,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 16),
		Parent = summaryCard,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Acesso",
		TextColor3 = Color3.fromRGB(235, 242, 255),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 16),
		Size = UDim2.new(1, -36, 0, 20),
		Parent = summaryCard,
	})

	rankValueLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = "Rank atual: 0",
		TextColor3 = Color3.fromRGB(229, 236, 250),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 52),
		Size = UDim2.new(1, -36, 0, 20),
		Parent = summaryCard,
	})

	accessValueLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Acesso: Bloqueado",
		TextColor3 = Color3.fromRGB(255, 157, 157),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 80),
		Size = UDim2.new(1, -36, 0, 20),
		Parent = summaryCard,
	})

	hintLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "",
		TextColor3 = Color3.fromRGB(198, 212, 231),
		TextSize = 14,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(18, 116),
		Size = UDim2.new(1, -36, 0, 50),
		Parent = summaryCard,
	})

	local categoriesCard = create("Frame", {
		Name = "CategoriesCard",
		BackgroundColor3 = Color3.fromRGB(27, 36, 48),
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 198),
		Size = UDim2.new(1, 0, 1, -198),
		Parent = leftColumn,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 16),
		Parent = categoriesCard,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Categorias",
		TextColor3 = Color3.fromRGB(235, 242, 255),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(18, 16),
		Size = UDim2.new(1, -36, 0, 20),
		Parent = categoriesCard,
	})

	categoryListFrame = create("ScrollingFrame", {
		Name = "CategoryList",
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 48),
		Size = UDim2.new(1, -28, 1, -62),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 6,
		Parent = categoriesCard,
	})

	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = categoryListFrame,
	})

	local toolsCard = create("Frame", {
		Name = "ToolsCard",
		BackgroundColor3 = Color3.fromRGB(27, 36, 48),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = rightColumn,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 16),
		Parent = toolsCard,
	})

	sectionTitleLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Selecione uma categoria",
		TextColor3 = Color3.fromRGB(235, 242, 255),
		TextSize = 20,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 16),
		Size = UDim2.new(1, -200, 0, 22),
		Parent = toolsCard,
	})

	getAllButton = create("TextButton", {
		Name = "GetAllButton",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(70, 112, 93),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -20, 0, 14),
		Size = UDim2.fromOffset(132, 38),
		Text = "Pegar Categoria",
		TextColor3 = Color3.fromRGB(245, 249, 255),
		TextSize = 13,
		Parent = toolsCard,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 12),
		Parent = getAllButton,
	})

	getAllButton.Activated:Connect(function()
		local categoryDefinition = find_selected_category()
		if not hasAccess or not categoryDefinition then
			return
		end

		local success, response = invoke_remote(get_request_item_remote(), {
			Mode = "Category",
			CategoryName = categoryDefinition.Name,
		})

		if not success then
			set_item_status("Falha ao falar com o servidor.", true)
		elseif response and response.Success then
			set_item_status(("Categoria entregue: %s (%d tools)"):format(categoryDefinition.Name, response.GrantedCount or 0), false)
		else
			set_item_status("Nao foi possivel entregar a categoria inteira.", true)
		end
	end)

	itemStatusLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Abra com M para carregar as categorias.",
		TextColor3 = Color3.fromRGB(170, 226, 184),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(20, 48),
		Size = UDim2.new(1, -40, 0, 18),
		Parent = toolsCard,
	})

	itemListFrame = create("ScrollingFrame", {
		Name = "ItemList",
		Active = true,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 82),
		Size = UDim2.new(1, -36, 1, -100),
		CanvasSize = UDim2.fromOffset(0, 0),
		ScrollBarThickness = 8,
		Parent = toolsCard,
	})

	itemListLayout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = itemListFrame,
	})

	itemListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		itemListFrame.CanvasSize = UDim2.fromOffset(0, itemListLayout.AbsoluteContentSize.Y + 8)
	end)

	emptyStateLabel = create("TextLabel", {
		Name = "EmptyState",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Escolha uma categoria na coluna da esquerda.",
		TextColor3 = Color3.fromRGB(172, 188, 209),
		TextSize = 15,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, 40),
		Visible = true,
		Parent = itemListFrame,
	})

	horseContentFrame = create("Frame", {
		Name = "HorseContent",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 132),
		Size = UDim2.new(1, -44, 1, -154),
		Visible = false,
		Parent = rootFrame,
	})

	local rouletteShell = create("Frame", {
		Name = "RouletteShell",
		BackgroundColor3 = Color3.fromRGB(26, 35, 47),
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Parent = horseContentFrame,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 16),
		Parent = rouletteShell,
	})

	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 41, 56)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 28, 39)),
		}),
		Rotation = 90,
		Parent = rouletteShell,
	})

	create("TextLabel", {
		Name = "HorseTitle",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Roleta de Cavalos",
		TextColor3 = Color3.fromRGB(244, 247, 253),
		TextSize = 26,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 18),
		Size = UDim2.new(1, -280, 0, 28),
		Parent = rouletteShell,
	})

	create("TextLabel", {
		Name = "HorseSubtitle",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "A roleta desacelera ate revelar o cavalo sorteado pelo servidor.",
		TextColor3 = Color3.fromRGB(185, 199, 218),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(24, 50),
		Size = UDim2.new(1, -280, 0, 18),
		Parent = rouletteShell,
	})

	local balanceBadge = create("Frame", {
		Name = "BalanceBadge",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(40, 54, 73),
		BorderSizePixel = 0,
		Position = UDim2.new(1, -22, 0, 20),
		Size = UDim2.fromOffset(220, 42),
		Parent = rouletteShell,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 14),
		Parent = balanceBadge,
	})

	create("UIStroke", {
		Color = Color3.fromRGB(99, 145, 186),
		Transparency = 0.32,
		Thickness = 1,
		Parent = balanceBadge,
	})

	rouletteBalanceLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Horseshoes: 0",
		TextColor3 = Color3.fromRGB(240, 246, 255),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = balanceBadge,
	})

	local viewportCard = create("Frame", {
		Name = "ViewportCard",
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(17, 23, 32),
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 88),
		Size = UDim2.fromOffset(560, 306),
		Parent = rouletteShell,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 22),
		Parent = viewportCard,
	})

	rouletteCardScale = create("UIScale", {
		Scale = 1,
		Parent = viewportCard,
	})

	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(33, 43, 59)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 17, 25)),
		}),
		Rotation = 90,
		Parent = viewportCard,
	})

	rouletteCardStroke = create("UIStroke", {
		Color = Color3.fromRGB(132, 195, 121),
		Transparency = 0.08,
		Thickness = 2,
		Parent = viewportCard,
	})

	rouletteViewportFrame = create("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(18, 16),
		Size = UDim2.new(1, -36, 1, -32),
		Ambient = Color3.fromRGB(210, 220, 236),
		LightColor = Color3.fromRGB(255, 247, 237),
		LightDirection = Vector3.new(-0.8, -1, -0.45),
		Parent = viewportCard,
	})

	rouletteDimmer = create("Frame", {
		Name = "Dimmer",
		BackgroundColor3 = Color3.fromRGB(7, 10, 15),
		BackgroundTransparency = 0.52,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = rouletteViewportFrame,
	})

	rouletteRevealLabel = create("TextLabel", {
		Name = "Reveal",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(13, 18, 25),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(242, 177, 73),
		TextSize = 22,
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(270, 42),
		Visible = false,
		Parent = viewportCard,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 14),
		Parent = rouletteRevealLabel,
	})

	create("UIStroke", {
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0.78,
		Thickness = 1,
		Parent = rouletteRevealLabel,
	})

	rouletteRevealScale = create("UIScale", {
		Scale = 1,
		Parent = rouletteRevealLabel,
	})

	rouletteNameLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Nenhum cavalo",
		TextColor3 = Color3.fromRGB(242, 246, 255),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.5, -240, 0, 414),
		Size = UDim2.fromOffset(480, 28),
		Parent = rouletteShell,
	})

	rouletteRarityBadge = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(42, 70, 48),
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 450),
		Size = UDim2.fromOffset(140, 32),
		Parent = rouletteShell,
	})

	create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = rouletteRarityBadge,
	})

	rouletteRarityStroke = create("UIStroke", {
		Color = Color3.fromRGB(132, 195, 121),
		Transparency = 0.14,
		Thickness = 1.2,
		Parent = rouletteRarityBadge,
	})

	rouletteRarityLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "COMMON",
		TextColor3 = Color3.fromRGB(232, 247, 227),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = rouletteRarityBadge,
	})

	rouletteStatusLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Carregue a aba para preparar a roleta.",
		TextColor3 = Color3.fromRGB(175, 228, 187),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.5, -240, 0, 494),
		Size = UDim2.fromOffset(480, 18),
		Parent = rouletteShell,
	})

	rouletteRollButton = create("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(215, 121, 58),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(0.5, 0, 0, 532),
		Size = UDim2.fromOffset(270, 48),
		Text = "Roletar - 500 Horseshoes",
		TextColor3 = Color3.fromRGB(253, 247, 240),
		TextSize = 16,
		Parent = rouletteShell,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 16),
		Parent = rouletteRollButton,
	})

	rouletteRollButton.Activated:Connect(function()
		if rouletteState.IsRolling then
			return
		end

		local canFreeRoll = rouletteState.FreeWhenZero and rouletteState.Balance == 0
		if rouletteState.Balance > 0 and rouletteState.Balance < rouletteState.Price then
			set_roulette_status("Voce precisa ter 500 Horseshoes ou 0 para rolar gratis.", true)
			return
		end

		if not canFreeRoll and rouletteState.Balance < rouletteState.Price then
			set_roulette_status("Saldo insuficiente para a roleta.", true)
			return
		end

		local rouletteRollRemote = get_roulette_roll_remote()
		if not rouletteRollRemote then
			set_roulette_status("Remote de roleta nao encontrado no servidor.", true)
			return
		end

		local success, response = invoke_remote(rouletteRollRemote)
		if not success then
			set_roulette_status("Falha ao falar com o servidor.", true)
			return
		end

		if not response or response.Success ~= true then
			if response and response.MessageCode == "InsufficientFunds" then
				rouletteState.Balance = tonumber(response.RemainingHorseshoes) or rouletteState.Balance
				refresh_roulette_balance_label()
				update_roulette_button()
				set_roulette_status("Voce precisa ter 500 Horseshoes ou 0 para rolar gratis.", true)
			else
				set_roulette_status("Nao foi possivel concluir a roletagem.", true)
			end
			return
		end

		task.spawn(play_roulette_spin, response)
	end)

	rouletteRuleLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Admin com 0 Horseshoes rola gratis. Custo normal: 500.",
		TextColor3 = Color3.fromRGB(188, 201, 217),
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.5, -240, 0, 584),
		Size = UDim2.fromOffset(480, 18),
		Parent = rouletteShell,
	})
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
