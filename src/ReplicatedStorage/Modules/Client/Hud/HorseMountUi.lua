local HorseMountUi = {}

local GUI_NAME = "HorseMountGui"
local BUTTON_TEXT = "Montar"
local MOBILE_CONTROL_GAP = 10

local function create_instance(className, properties)
	local instance = Instance.new(className)

	for propertyName, propertyValue in pairs(properties) do
		instance[propertyName] = propertyValue
	end

	return instance
end

function HorseMountUi.clearHorseButtons(horseButtons)
	for _, button in ipairs(horseButtons) do
		if button and button.Parent then
			button:Destroy()
		end
	end

	table.clear(horseButtons)
end

function HorseMountUi.getOwnedHorses(plotValue, dataUtility)
	local horses = dataUtility.client.get("Horses")
	local ownedHorses = type(horses) == "table" and horses.Owned or nil
	if type(ownedHorses) ~= "table" then
		return {}
	end

	local orderedIds = type(horses.OrderedIds) == "table" and horses.OrderedIds or {}
	local orderedEntries = {}
	local unorderedEntries = {}
	local seenIds = {}

	local function add_entry(horseId, horse, targetList)
		if type(horseId) ~= "string" or horseId == "" or type(horse) ~= "table" or seenIds[horseId] then
			return
		end

		seenIds[horseId] = true

		local horseName = horse.Nickname
		if type(horseName) ~= "string" or horseName == "" then
			horseName = horse.DisplayName
		end

		if type(horseName) ~= "string" or horseName == "" then
			horseName = horseId
		end

		targetList[#targetList + 1] = {
			Id = horseId,
			Name = horseName,
		}
	end

	for _, horseId in ipairs(orderedIds) do
		add_entry(horseId, ownedHorses[horseId], orderedEntries)
	end

	for horseId, horse in pairs(ownedHorses) do
		add_entry(horseId, horse, unorderedEntries)
	end

	table.sort(unorderedEntries, function(a, b)
		return string.lower(a.Name) < string.lower(b.Name)
	end)

	for _, entry in ipairs(unorderedEntries) do
		orderedEntries[#orderedEntries + 1] = entry
	end

	return orderedEntries
end

function HorseMountUi.updatePanelCanvas(ui)
	local layout = ui.ListLayout
	local listFrame = ui.ListFrame
	if not layout or not listFrame then
		return
	end

	listFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 8)
end

function HorseMountUi.updateUiState(ui, params)
	if not ui.ActionButton then
		return
	end

	local mountedState = params.mountedState
	local requestInFlight = params.requestInFlight
	local panelOpen = params.panelOpen
	local isTouchDevice = params.isTouchDevice
	local canShowButton = not mountedState.Active or mountedState.TransitionMode == nil
	local canUseMountedControls = mountedState.Active and mountedState.TransitionMode ~= "Dismounting"

	ui.ActionButton.Visible = canShowButton
	ui.ActionButton.Text = requestInFlight and "..." or BUTTON_TEXT
	ui.ActionButton.AutoButtonColor = canShowButton and not requestInFlight
	ui.ActionButton.Active = canShowButton and not requestInFlight
	ui.ActionButton.BackgroundColor3 = requestInFlight
		and Color3.fromRGB(91, 91, 91)
		or Color3.fromRGB(36, 111, 79)

	local shouldShowPanel = canShowButton and panelOpen and not requestInFlight
	ui.ListPanel.Visible = shouldShowPanel

	if ui.MobileControlsFrame then
		ui.MobileControlsFrame.Visible = isTouchDevice and canUseMountedControls
	end

	if ui.MobileSprintButton then
		ui.MobileSprintButton.Visible = isTouchDevice and canUseMountedControls
	end

	if ui.MobileDismountButton then
		ui.MobileDismountButton.Visible = isTouchDevice and canUseMountedControls
	end
end

function HorseMountUi.renderHorseList(ui, horseButtons, params)
	HorseMountUi.clearHorseButtons(horseButtons)

	local horses = HorseMountUi.getOwnedHorses(params.plotValue, params.dataUtility)
	if #horses == 0 then
		local emptyLabel = create_instance("TextLabel", {
			Name = "EmptyLabel",
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Size = UDim2.new(1, -6, 0, 32),
			Text = "Nenhum cavalo disponivel",
			TextColor3 = Color3.fromRGB(223, 223, 223),
			TextSize = 14,
			Parent = ui.ListFrame,
		})

		horseButtons[#horseButtons + 1] = emptyLabel
		HorseMountUi.updatePanelCanvas(ui)
		return
	end

	for _, horseEntry in ipairs(horses) do
		local horseButton = create_instance("TextButton", {
			Name = horseEntry.Id,
			AutoButtonColor = true,
			BackgroundColor3 = Color3.fromRGB(37, 42, 47),
			BorderSizePixel = 0,
			Font = Enum.Font.Gotham,
			Text = ("%s  (%s)"):format(horseEntry.Nickname ~= "" and horseEntry.Nickname or horseEntry.DisplayName or horseEntry.Id, horseEntry.Id),
			TextColor3 = Color3.fromRGB(242, 242, 242),
			TextSize = 15,
			Size = UDim2.new(1, -6, 0, 38),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = ui.ListFrame,
		})

		create_instance("UICorner", {
			CornerRadius = UDim.new(0, 10),
			Parent = horseButton,
		})

		create_instance("UIPadding", {
			PaddingLeft = UDim.new(0, 12),
			PaddingRight = UDim.new(0, 12),
			Parent = horseButton,
		})

		create_instance("UIStroke", {
			Color = Color3.fromRGB(255, 255, 255),
			Transparency = 0.88,
			Parent = horseButton,
		})

		horseButton.MouseButton1Click:Connect(function()
			params.onSelectHorse(horseEntry)
		end)

		horseButtons[#horseButtons + 1] = horseButton
	end

	HorseMountUi.updatePanelCanvas(ui)
end

function HorseMountUi.ensureUi(ui, params)
	if ui.ScreenGui and ui.ScreenGui.Parent then
		return
	end

	local existingGui = params.playerGui:FindFirstChild(GUI_NAME)
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = create_instance("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = params.playerGui,
	})

	local actionButton = create_instance("TextButton", {
		Name = "ActionButton",
		AnchorPoint = Vector2.new(1, 0),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(36, 111, 79),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, -24, 0, 24),
		Size = UDim2.fromOffset(160, 46),
		Text = BUTTON_TEXT,
		TextColor3 = Color3.fromRGB(246, 247, 248),
		TextSize = 17,
		Parent = screenGui,
	})

	create_instance("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = actionButton,
	})

	create_instance("UIStroke", {
		Color = Color3.fromRGB(173, 232, 204),
		Transparency = 0.2,
		Parent = actionButton,
	})

	local listPanel = create_instance("Frame", {
		Name = "ListPanel",
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(20, 24, 28),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Position = UDim2.new(1, -24, 0, 80),
		Size = UDim2.fromOffset(310, 220),
		Visible = false,
		Parent = screenGui,
	})

	create_instance("UICorner", {
		CornerRadius = UDim.new(0, 16),
		Parent = listPanel,
	})

	create_instance("UIStroke", {
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0.83,
		Parent = listPanel,
	})

	create_instance("UIPadding", {
		PaddingTop = UDim.new(0, 14),
		PaddingBottom = UDim.new(0, 14),
		PaddingLeft = UDim.new(0, 14),
		PaddingRight = UDim.new(0, 14),
		Parent = listPanel,
	})

	create_instance("TextLabel", {
		Name = "TitleLabel",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Seus cavalos",
		TextColor3 = Color3.fromRGB(248, 235, 198),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 24),
		Parent = listPanel,
	})

	local listFrame = create_instance("ScrollingFrame", {
		Name = "ListFrame",
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.None,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		CanvasSize = UDim2.fromOffset(0, 0),
		Position = UDim2.new(0, 0, 0, 32),
		ScrollBarImageColor3 = Color3.fromRGB(145, 157, 170),
		ScrollBarThickness = 5,
		Size = UDim2.new(1, 0, 1, -32),
		Parent = listPanel,
	})

	local listLayout = create_instance("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = listFrame,
	})

	local mobileControlsFrame = create_instance("Frame", {
		Name = "MobileControlsFrame",
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(1, -24, 1, -120),
		Size = UDim2.fromOffset(160, 110),
		Visible = false,
		Parent = screenGui,
	})

	local mobileRunButton = create_instance("TextButton", {
		Name = "MobileSprintButton",
		AnchorPoint = Vector2.new(1, 1),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(39, 129, 84),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(160, 48),
		Text = "Correr",
		TextColor3 = Color3.fromRGB(243, 247, 244),
		TextSize = 18,
		Visible = false,
		Parent = mobileControlsFrame,
	})

	create_instance("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = mobileRunButton,
	})

	create_instance("UIStroke", {
		Color = Color3.fromRGB(198, 244, 216),
		Transparency = 0.18,
		Parent = mobileRunButton,
	})

	local mobileDismountButton = create_instance("TextButton", {
		Name = "MobileDismountButton",
		AnchorPoint = Vector2.new(1, 1),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(157, 64, 64),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.fromOffset(160, 48),
		Text = "Desmontar",
		TextColor3 = Color3.fromRGB(247, 236, 236),
		TextSize = 17,
		Visible = false,
		Parent = mobileControlsFrame,
	})

	create_instance("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = mobileDismountButton,
	})

	create_instance("UIStroke", {
		Color = Color3.fromRGB(255, 205, 205),
		Transparency = 0.24,
		Parent = mobileDismountButton,
	})

	mobileDismountButton.Position = UDim2.new(1, 0, 1, 0)
	mobileRunButton.Position = UDim2.new(1, 0, 1, -(48 + MOBILE_CONTROL_GAP))

	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		HorseMountUi.updatePanelCanvas(ui)
	end)

	actionButton.MouseButton1Click:Connect(params.onTogglePanelRequested)

	mobileRunButton.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			params.onSetMobileSprintPressed(true)
		end
	end)

	mobileRunButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			params.onSetMobileSprintPressed(false)
		end
	end)

	mobileDismountButton.MouseButton1Click:Connect(params.onDismountRequested)

	ui.ScreenGui = screenGui
	ui.ActionButton = actionButton
	ui.ListPanel = listPanel
	ui.ListFrame = listFrame
	ui.ListLayout = listLayout
	ui.MobileControlsFrame = mobileControlsFrame
	ui.MobileSprintButton = mobileRunButton
	ui.MobileDismountButton = mobileDismountButton
end

return HorseMountUi
