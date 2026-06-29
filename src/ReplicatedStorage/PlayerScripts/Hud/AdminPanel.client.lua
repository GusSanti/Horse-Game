local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))

local SCREEN_GUI_NAME = "AdminPanelGui"

local gameplayRemotes = ReplicatedStorage:WaitForChild(NetworkConfig.GameplayFolderName)
local adminRemotes = gameplayRemotes:WaitForChild(NetworkConfig.Admin.FolderName)
local getCatalogRemote = adminRemotes:WaitForChild(NetworkConfig.Admin.GetItemCatalog)
local requestItemRemote = adminRemotes:WaitForChild(NetworkConfig.Admin.RequestItemTool)

local hasAccess = false
local adminRank = 0
local categoryCatalog = {}
local selectedCategoryName = nil

local screenGui
local overlay
local rootFrame
local categoryListFrame
local itemListFrame
local itemListLayout
local rankValueLabel
local accessValueLabel
local hintLabel
local statusLabel
local sectionTitleLabel
local emptyStateLabel
local refreshButton
local getAllButton

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

local function set_status(message, isError)
	if not statusLabel then
		return
	end

	statusLabel.Text = message
	statusLabel.TextColor3 = isError and Color3.fromRGB(255, 164, 164) or Color3.fromRGB(170, 226, 184)
end

local function invoke_remote(remote, ...)
	local success, response = pcall(function(...)
		return remote:InvokeServer(...)
	end, ...)

	if success then
		return response
	end

	set_status("Falha ao falar com o servidor.", true)
	return nil
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
			hintLabel.Text = "Pressione M para abrir a aba e pegue tools por categoria."
		else
			local minimumRank = localPlayer:GetAttribute("AdminMinimumRank") or 250
			local groupId = localPlayer:GetAttribute("AdminGroupId") or 1071228359
			hintLabel.Text = ("Requer rank %d+ no grupo %d."):format(minimumRank, groupId)
		end
	end

	if refreshButton then
		refreshButton.Visible = hasAccess
	end

	if getAllButton then
		getAllButton.Visible = hasAccess
	end

	if screenGui and not hasAccess then
		screenGui.Enabled = false
	end
end

local function find_selected_category()
	for _, categoryDefinition in ipairs(categoryCatalog) do
		if categoryDefinition.Name == selectedCategoryName then
			return categoryDefinition
		end
	end

	return nil
end

local function render_item_list()
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
				set_status("Voce nao tem permissao para pegar tools.", true)
				return
			end

			local response = invoke_remote(requestItemRemote, {
				Mode = "Single",
				CategoryName = categoryDefinition.Name,
				ItemId = itemDefinition.ItemId,
			})

			if response and response.Success then
				set_status(("Tool entregue: %s"):format(response.ItemName or itemDefinition.Name), false)
			else
				set_status("Nao foi possivel entregar a tool.", true)
			end
		end)
	end

	local layoutContentSize = itemListLayout.AbsoluteContentSize
	itemListFrame.CanvasSize = UDim2.fromOffset(0, layoutContentSize.Y + 8)
end

local function render_category_list()
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

local function fetch_catalog()
	if not hasAccess then
		return
	end

	set_status("Carregando categorias...", false)
	local response = invoke_remote(getCatalogRemote)

	if not response or response.Success ~= true then
		categoryCatalog = {}
		selectedCategoryName = nil
		render_category_list()
		render_item_list()
		set_status("Nao foi possivel carregar as categorias.", true)
		return
	end

	categoryCatalog = response.Categories or {}

	if selectedCategoryName == nil or find_selected_category() == nil then
		selectedCategoryName = categoryCatalog[1] and categoryCatalog[1].Name or nil
	end

	render_category_list()
	render_item_list()
	set_status("Categorias carregadas.", false)
end

local function toggle_panel()
	if not hasAccess or not screenGui then
		return
	end

	screenGui.Enabled = not screenGui.Enabled

	if screenGui.Enabled then
		fetch_catalog()
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
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = screenGui,
	})

	rootFrame = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 28, 39),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(980, 560),
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

	create("TextLabel", {
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

	create("TextLabel", {
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

	local content = create("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(22, 88),
		Size = UDim2.new(1, -44, 1, -110),
		Parent = rootFrame,
	})

	local leftColumn = create("Frame", {
		Name = "LeftColumn",
		BackgroundTransparency = 1,
		Size = UDim2.new(0.29, -10, 1, 0),
		Parent = content,
	})

	local rightColumn = create("Frame", {
		Name = "RightColumn",
		BackgroundTransparency = 1,
		Position = UDim2.new(0.29, 10, 0, 0),
		Size = UDim2.new(0.71, -10, 1, 0),
		Parent = content,
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

		local response = invoke_remote(requestItemRemote, {
			Mode = "Category",
			CategoryName = categoryDefinition.Name,
		})

		if response and response.Success then
			set_status(("Categoria entregue: %s (%d tools)"):format(categoryDefinition.Name, response.GrantedCount or 0), false)
		else
			set_status("Nao foi possivel entregar a categoria inteira.", true)
		end
	end)

	statusLabel = create("TextLabel", {
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
end

build_panel()
refresh_access_state()
render_category_list()
render_item_list()

localPlayer:GetAttributeChangedSignal("CanOpenAdminPanel"):Connect(function()
	refresh_access_state()
	if hasAccess then
		fetch_catalog()
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
