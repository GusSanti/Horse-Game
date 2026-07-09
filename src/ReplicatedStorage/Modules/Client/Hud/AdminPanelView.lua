local AdminPanelView = {}

local function create(className, properties)
	local instance = Instance.new(className)

	for propertyName, value in pairs(properties) do
		instance[propertyName] = value
	end

	return instance
end

function AdminPanelView.build(context)
	local playerGui = context.localPlayer:WaitForChild("PlayerGui")

	local screenGui = create("ScreenGui", {
		Name = context.screenGuiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		Enabled = false,
		Parent = playerGui,
	})

	local overlay = create("Frame", {
		Name = "Overlay",
		BackgroundColor3 = Color3.fromRGB(7, 12, 18),
		BackgroundTransparency = 0.28,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = screenGui,
	})

	local rootFrame = create("Frame", {
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

	local titleLabel = create("TextLabel", {
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

	local subtitleLabel = create("TextLabel", {
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

	local refreshButton = create("TextButton", {
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

	refreshButton.Activated:Connect(context.fetchCatalog)

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

	local itemTabButton = create("TextButton", {
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
		context.setActiveTab(context.itemTabName)
	end)

	local horseTabButton = create("TextButton", {
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
		context.setActiveTab(context.horseTabName)
	end)

	local itemsContentFrame = create("Frame", {
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

	local rankValueLabel = create("TextLabel", {
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

	local accessValueLabel = create("TextLabel", {
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

	local hintLabel = create("TextLabel", {
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

	local categoryListFrame = create("ScrollingFrame", {
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

	local sectionTitleLabel = create("TextLabel", {
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

	local getAllButton = create("TextButton", {
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

	getAllButton.Activated:Connect(context.onRequestSelectedCategory)

	local itemStatusLabel = create("TextLabel", {
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

	local itemListFrame = create("ScrollingFrame", {
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

	local itemListLayout = create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = itemListFrame,
	})

	itemListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		itemListFrame.CanvasSize = UDim2.fromOffset(0, itemListLayout.AbsoluteContentSize.Y + 8)
	end)

	local emptyStateLabel = create("TextLabel", {
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

	local horseContentFrame = create("Frame", {
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

	local rouletteBalanceLabel = create("TextLabel", {
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

	local rouletteCardScale = create("UIScale", {
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

	local rouletteCardStroke = create("UIStroke", {
		Color = Color3.fromRGB(132, 195, 121),
		Transparency = 0.08,
		Thickness = 2,
		Parent = viewportCard,
	})

	local rouletteViewportFrame = create("ViewportFrame", {
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

	local rouletteDimmer = create("Frame", {
		Name = "Dimmer",
		BackgroundColor3 = Color3.fromRGB(7, 10, 15),
		BackgroundTransparency = 0.52,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = rouletteViewportFrame,
	})

	local rouletteRevealLabel = create("TextLabel", {
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

	local rouletteRevealScale = create("UIScale", {
		Scale = 1,
		Parent = rouletteRevealLabel,
	})

	local rouletteNameLabel = create("TextLabel", {
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

	local rouletteRarityBadge = create("Frame", {
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

	local rouletteRarityStroke = create("UIStroke", {
		Color = Color3.fromRGB(132, 195, 121),
		Transparency = 0.14,
		Thickness = 1.2,
		Parent = rouletteRarityBadge,
	})

	local rouletteRarityLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "COMMON",
		TextColor3 = Color3.fromRGB(232, 247, 227),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = rouletteRarityBadge,
	})

	local rouletteStatusLabel = create("TextLabel", {
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

	local rouletteRollButton = create("TextButton", {
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

	rouletteRollButton.Activated:Connect(context.onRouletteRoll)

	local rouletteRuleLabel = create("TextLabel", {
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

	return {
		ScreenGui = screenGui,
		Overlay = overlay,
		RootFrame = rootFrame,
		TitleLabel = titleLabel,
		SubtitleLabel = subtitleLabel,
		RefreshButton = refreshButton,
		ItemTabButton = itemTabButton,
		HorseTabButton = horseTabButton,
		ItemsContentFrame = itemsContentFrame,
		HorseContentFrame = horseContentFrame,
		CategoryListFrame = categoryListFrame,
		ItemListFrame = itemListFrame,
		ItemListLayout = itemListLayout,
		RankValueLabel = rankValueLabel,
		AccessValueLabel = accessValueLabel,
		HintLabel = hintLabel,
		ItemStatusLabel = itemStatusLabel,
		SectionTitleLabel = sectionTitleLabel,
		EmptyStateLabel = emptyStateLabel,
		GetAllButton = getAllButton,
		RouletteBalanceLabel = rouletteBalanceLabel,
		RouletteViewportFrame = rouletteViewportFrame,
		RouletteNameLabel = rouletteNameLabel,
		RouletteRarityLabel = rouletteRarityLabel,
		RouletteRarityBadge = rouletteRarityBadge,
		RouletteRarityStroke = rouletteRarityStroke,
		RouletteStatusLabel = rouletteStatusLabel,
		RouletteRollButton = rouletteRollButton,
		RouletteRuleLabel = rouletteRuleLabel,
		RouletteDimmer = rouletteDimmer,
		RouletteRevealLabel = rouletteRevealLabel,
		RouletteRevealScale = rouletteRevealScale,
		RouletteCardScale = rouletteCardScale,
		RouletteCardStroke = rouletteCardStroke,
	}
end

return AdminPanelView
