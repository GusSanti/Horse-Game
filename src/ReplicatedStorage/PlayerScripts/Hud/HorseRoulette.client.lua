local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local GameData = Modules:WaitForChild("GameData")
local HudModules = ClientModules:WaitForChild("Hud")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local Trove = require(Libraries:WaitForChild("Trove"))
local HorseInteractionUi = require(HudModules:WaitForChild("HorseInteractionUi"))
local HorseViewportRenderer = require(HudModules:WaitForChild("HorseViewportRenderer"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainFrameFR", "MainframeFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local RAFFLE_ROOT_NAMES = { "Raffle" }
local RAFFLE_BACKGROUND_NAMES = { "RaffleBG" }
local WHEEL_BACKGROUND_NAMES = { "WheelBG" }
local SPIN_BUTTON_NAMES = { "SpinBT" }
local CLOSE_BUTTON_NAMES = { "CloseBT" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }

local RESULT_GUI_NAME = "HorseRouletteRewardGui"
local POINTER_ANGLE_DEGREES = -90
local SLOT_COUNT = 8
local WHEEL_SPIN_DURATION = 5.2
local WHEEL_SPIN_FULL_TURNS = 6
local RESULT_DISPLAY_SECONDS = 3
local STUDIO_ACCESS_OVERRIDE = RunService:IsStudio()

local SLOT_CAMERA_CONFIG = HorseViewportRenderer.Presets.Wheel
local RESULT_CAMERA_CONFIG = HorseViewportRenderer.Presets.Reward

local horseOptions = HorseCatalog.GetRouletteHorseOptions()

local rootTrove = Trove.new()
local uiTrove = Trove.new()

local currentUi = nil
local pendingStarterReveal = false
local isRouletteOpen = false
local isRouletteRolling = false
local isDialogueVisible = false
local slotPopulateGeneration = 0
local rewardGui = nil
local rewardViewport = nil
local rewardNameLabel = nil

local rouletteState = {
	Price = HorseCatalog.RoulettePrice or 500,
	Balance = 0,
	FreeWhenZero = false,
	Horses = horseOptions,
	CanRoll = true,
}

local update_spin_button
local play_spin

local _adminRemotesFolder = nil
local _adminRemotesFolderResolved = false
local _cachedRemotes = {}

local function normalize_key(value)
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

local function matches_alias(instance, aliases)
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

local function find_named_instance(root, aliases, className, recursive)
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

local function find_gui_object(root, aliases, recursive)
	return find_named_instance(root, aliases, "GuiObject", recursive)
end

local function find_gui_button(root, aliases, recursive)
	return find_named_instance(root, aliases, "GuiButton", recursive)
end

local function find_viewport_frame(root)
	if not root then
		return nil
	end

	if root:IsA("ViewportFrame") then
		return root
	end

	return find_named_instance(root, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
end

local function create(className, properties)
	local instance = Instance.new(className)

	for propertyName, value in pairs(properties) do
		instance[propertyName] = value
	end

	return instance
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

local function get_roulette_state_remote()
	return get_admin_remote(NetworkConfig.Admin.GetHorseRouletteState)
end

local function get_roulette_roll_remote()
	return get_admin_remote(NetworkConfig.Admin.RollHorseRoulette)
end

local function has_access()
	return STUDIO_ACCESS_OVERRIDE or localPlayer:GetAttribute("CanOpenAdminPanel") == true
end

local function set_button_enabled(button, isEnabled)
	if not button then
		return
	end

	button.Active = isEnabled
	button.Selectable = isEnabled

	if button:IsA("TextButton") or button:IsA("ImageButton") then
		button.AutoButtonColor = isEnabled
	end
end

local function ensure_notice_label(ui)
	if not ui or not ui.Root then
		return nil
	end

	local noticeLabel = ui.Root:FindFirstChild("HorseRouletteNotice")
	if noticeLabel and noticeLabel:IsA("TextLabel") then
		return noticeLabel
	end

	noticeLabel = create("TextLabel", {
		Name = "HorseRouletteNotice",
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.fromOffset(360, 28),
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 16,
		TextTransparency = 1,
		ZIndex = ui.Root.ZIndex + 10,
		Parent = ui.Root,
	})

	return noticeLabel
end

local function show_notice(ui, text, isError)
	local noticeLabel = ensure_notice_label(ui)
	if not noticeLabel then
		return
	end

	ui.NoticeToken = (ui.NoticeToken or 0) + 1
	local noticeToken = ui.NoticeToken

	noticeLabel.Text = text
	noticeLabel.TextColor3 = isError and Color3.fromRGB(255, 176, 176) or Color3.fromRGB(197, 245, 182)
	noticeLabel.TextTransparency = 0

	task.spawn(function()
		task.wait(2)
		if not currentUi or currentUi ~= ui or ui.NoticeToken ~= noticeToken then
			return
		end

		local fadeTween = TweenService:Create(
			noticeLabel,
			TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ TextTransparency = 1 }
		)
		fadeTween:Play()
	end)
end

local function clear_notice(ui)
	local noticeLabel = ensure_notice_label(ui)
	if not noticeLabel then
		return
	end

	ui.NoticeToken = (ui.NoticeToken or 0) + 1
	noticeLabel.Text = ""
	noticeLabel.TextTransparency = 1
end

local function format_horseshoes(amount)
	return tostring(math.max(0, math.floor(tonumber(amount) or 0)))
end

local function hide_dialogue()
	isDialogueVisible = false
	HorseInteractionUi.HideDialogue()
end

local function show_dialogue(config)
	local shown = HorseInteractionUi.ShowDialogue({
		title = config.title,
		details = config.details,
		acceptText = config.acceptText,
		denyText = config.denyText,
		onAccept = function()
			isDialogueVisible = false
			if type(config.onAccept) == "function" then
				config.onAccept()
			end
			if update_spin_button then
				task.defer(update_spin_button)
			end
		end,
		onDeny = function()
			isDialogueVisible = false
			if type(config.onDeny) == "function" then
				config.onDeny()
			end
			if update_spin_button then
				task.defer(update_spin_button)
			end
		end,
	})

	isDialogueVisible = shown == true
	return isDialogueVisible
end

local function apply_fredoka_font(label)
	local success = pcall(function()
		label.FontFace = Font.new(
			"rbxasset://fonts/families/FredokaOne.json",
			Enum.FontWeight.Bold,
			Enum.FontStyle.Normal
		)
	end)

	if not success then
		label.Font = Enum.Font.FredokaOne
	end
end

local function build_reward_gui()
	if rewardGui then
		return
	end

	rewardGui = create("ScreenGui", {
		Name = RESULT_GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 141,
		Enabled = false,
		Parent = playerGui,
	})

	local overlay = create("Frame", {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = rewardGui,
	})

	local content = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 380),
		Parent = overlay,
	})

	rewardViewport = create("ViewportFrame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.fromOffset(340, 250),
		Ambient = Color3.fromRGB(225, 225, 225),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-0.8, -1, -0.45),
		Parent = content,
	})

	rewardNameLabel = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, 0, 0, 268),
		Size = UDim2.fromOffset(360, 72),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		TextWrapped = true,
		Parent = content,
	})

	apply_fredoka_font(rewardNameLabel)

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Thickness = 2.2
	stroke.Transparency = 0.15
	stroke.Parent = rewardNameLabel

	create("UITextSizeConstraint", {
		MaxTextSize = 36,
		Parent = rewardNameLabel,
	})
end

local function show_reward_gui()
	build_reward_gui()
	rewardGui.Enabled = true
end

local function hide_reward_gui()
	if rewardGui then
		rewardGui.Enabled = false
	end
end

local function clear_viewport(viewportFrame)
	HorseViewportRenderer.Clear(viewportFrame)
end

local function prewarm_preview_snapshots(availableHorses)
	local previewHorses = type(availableHorses) == "table" and availableHorses or horseOptions
	HorseViewportRenderer.PrewarmCatalogs(previewHorses, { SLOT_CAMERA_CONFIG, RESULT_CAMERA_CONFIG })
end

local function populate_horse_viewport(viewportFrame, horseOption, cameraConfig, cameraKey)
	if not viewportFrame then return end
	if not horseOption then
		clear_viewport(viewportFrame)
		return
	end
	HorseViewportRenderer.QueueCatalog(viewportFrame, horseOption.CatalogId, cameraConfig, {
		ModelKey = horseOption.ModelKey,
		Priority = cameraKey == "reward" and 1 or 4,
	})
end

local function find_horse_option(catalogId, fallbackHorse)
	for _, horseOption in ipairs(rouletteState.Horses or {}) do
		if horseOption.CatalogId == catalogId then
			return horseOption
		end
	end

	for _, horseOption in ipairs(horseOptions) do
		if horseOption.CatalogId == catalogId then
			return horseOption
		end
	end

	if type(fallbackHorse) == "table" and type(fallbackHorse.CatalogId) == "string" then
		return {
			CatalogId = fallbackHorse.CatalogId,
			DisplayName = fallbackHorse.DisplayName or fallbackHorse.CatalogId,
			Rarity = fallbackHorse.Rarity,
			ModelKey = fallbackHorse.ModelKey,
		}
	end

	local definition = HorseCatalog.GetDefinition(catalogId)
	if not definition then
		return nil
	end

	return {
		CatalogId = definition.CatalogId,
		DisplayName = definition.DisplayName,
		Rarity = definition.Rarity,
		ModelKey = definition.PlaceholderModelKey,
	}
end

local function find_main_ui_root()
	return find_named_instance(playerGui, MAIN_UI_NAMES, nil, true)
end

local function find_mainframe_root()
	local mainUi = find_main_ui_root()
	if not mainUi then
		return nil
	end

	return find_named_instance(mainUi, MAINFRAME_NAMES, nil, true)
end

local function find_frames_container()
	local mainframe = find_mainframe_root()
	if not mainframe then
		return nil
	end

	return find_named_instance(mainframe, FRAMES_CONTAINER_NAMES, nil, true)
end

local function get_slot_screen_angle(slotLabel, wheelBg)
	local wheelCenter = wheelBg.AbsolutePosition + (wheelBg.AbsoluteSize * 0.5)
	local slotCenter = slotLabel.AbsolutePosition + (slotLabel.AbsoluteSize * 0.5)
	local offset = slotCenter - wheelCenter

	return math.deg(math.atan2(offset.Y, offset.X))
end

local function normalize_positive_angle(angle)
	return ((angle % 360) + 360) % 360
end

local function collect_wheel_slots(wheelBg)
	if not wheelBg then
		return {}
	end

	local slots = {}

	local function try_add_slot(candidate)
		if not (candidate:IsA("TextLabel") or candidate:IsA("TextButton")) then
			return
		end

		local viewportFrame = find_viewport_frame(candidate)
		if not viewportFrame then
			return
		end

		slots[#slots + 1] = {
			Label = candidate,
			ViewportFrame = viewportFrame,
		}
	end

	for _, child in ipairs(wheelBg:GetChildren()) do
		try_add_slot(child)
	end

	if #slots == 0 then
		for _, descendant in ipairs(wheelBg:GetDescendants()) do
			try_add_slot(descendant)
		end
	end

	table.sort(slots, function(leftSlot, rightSlot)
		local leftAngle = normalize_positive_angle(get_slot_screen_angle(leftSlot.Label, wheelBg) - POINTER_ANGLE_DEGREES)
		local rightAngle = normalize_positive_angle(get_slot_screen_angle(rightSlot.Label, wheelBg) - POINTER_ANGLE_DEGREES)
		return leftAngle < rightAngle
	end)

	while #slots > SLOT_COUNT do
		table.remove(slots)
	end

	return slots
end

local function get_raffle_ui()
	local framesContainer = find_frames_container()
	if not framesContainer then
		return nil
	end

	local raffleRoot = find_named_instance(framesContainer, RAFFLE_ROOT_NAMES, "GuiObject", true)
	if not raffleRoot then
		return nil
	end

	local raffleBg = find_gui_object(raffleRoot, RAFFLE_BACKGROUND_NAMES, true) or raffleRoot
	local wheelBg = find_gui_object(raffleBg, WHEEL_BACKGROUND_NAMES, true)
	local spinButton = find_gui_button(raffleRoot, SPIN_BUTTON_NAMES, true)
	local closeButton = find_gui_button(raffleRoot, CLOSE_BUTTON_NAMES, true)

	if not wheelBg or not spinButton then
		return nil
	end

	return {
		Root = raffleRoot,
		FramesContainer = framesContainer,
		WheelBg = wheelBg,
		SpinButton = spinButton,
		CloseButton = closeButton,
		Slots = collect_wheel_slots(wheelBg),
	}
end

local function close_other_frames(framesContainer, targetFrame)
	if not framesContainer or not targetFrame then
		return
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if child:IsA("GuiObject") and child ~= targetFrame then
			child.Visible = false
		end
	end
end

local function reset_wheel_rotation(ui)
	local baseRotation = ui.WheelBg:GetAttribute("HorseRouletteBaseRotation")
	if type(baseRotation) ~= "number" then
		baseRotation = ui.WheelBg.Rotation
		ui.WheelBg:SetAttribute("HorseRouletteBaseRotation", baseRotation)
	end

	ui.WheelBg.Rotation = baseRotation
end

local function shuffle_array(items)
	for index = #items, 2, -1 do
		local swapIndex = math.random(1, index)
		items[index], items[swapIndex] = items[swapIndex], items[index]
	end
end

local function build_idle_slot_assignments(availableHorses, slotCount)
	local source = {}

	for _, horseOption in ipairs(availableHorses or {}) do
		source[#source + 1] = horseOption
	end

	if #source == 0 then
		for _, horseOption in ipairs(horseOptions) do
			source[#source + 1] = horseOption
		end
	end

	if #source == 0 then
		return {}
	end

	shuffle_array(source)

	local assignments = table.create(slotCount)
	for slotIndex = 1, slotCount do
		assignments[slotIndex] = source[((slotIndex - 1) % #source) + 1]
	end

	return assignments
end

local function build_result_slot_assignments(finalHorseOption, slotCount)
	local assignments = table.create(slotCount)
	local winningSlotIndex = slotCount > 1 and math.random(2, slotCount) or 1
	local fillers = {}

	for _, horseOption in ipairs(rouletteState.Horses or {}) do
		if horseOption.CatalogId ~= finalHorseOption.CatalogId then
			fillers[#fillers + 1] = horseOption
		end
	end

	if #fillers == 0 then
		for _, horseOption in ipairs(horseOptions) do
			if horseOption.CatalogId ~= finalHorseOption.CatalogId then
				fillers[#fillers + 1] = horseOption
			end
		end
	end

	if #fillers == 0 then
		fillers[1] = finalHorseOption
	end

	shuffle_array(fillers)

	local fillerIndex = 1
	for slotIndex = 1, slotCount do
		if slotIndex == winningSlotIndex then
			assignments[slotIndex] = finalHorseOption
		else
			assignments[slotIndex] = fillers[fillerIndex]
			fillerIndex += 1
			if fillerIndex > #fillers then
				fillerIndex = 1
			end
		end
	end

	return assignments, winningSlotIndex
end

local function cancel_slot_population()
	slotPopulateGeneration += 1
end

local function populate_slots(ui, slotAssignments, populateViewportsAsync)
	if not ui or #slotAssignments == 0 then
		return
	end

	cancel_slot_population()
	local generation = slotPopulateGeneration

	for slotIndex, slot in ipairs(ui.Slots) do
		local horseOption = slotAssignments[((slotIndex - 1) % #slotAssignments) + 1]
		slot.Label.Text = horseOption.DisplayName or horseOption.CatalogId

		if populateViewportsAsync then
			clear_viewport(slot.ViewportFrame)
		else
			populate_horse_viewport(slot.ViewportFrame, horseOption, SLOT_CAMERA_CONFIG, "wheel")
		end
	end

	if not populateViewportsAsync then
		return
	end

	task.spawn(function()
		for slotIndex, slot in ipairs(ui.Slots) do
			if slotPopulateGeneration ~= generation or currentUi ~= ui or not isRouletteOpen then
				return
			end

			local horseOption = slotAssignments[((slotIndex - 1) % #slotAssignments) + 1]
			populate_horse_viewport(slot.ViewportFrame, horseOption, SLOT_CAMERA_CONFIG, "wheel")

			if slotIndex < #ui.Slots then
				RunService.Heartbeat:Wait()
			end
		end
	end)
end

update_spin_button = function()
	if not currentUi or pendingStarterReveal then
		return
	end

	local hasHorsePool = #rouletteState.Horses > 0
	local enabled = has_access()
		and isRouletteOpen
		and (not isRouletteRolling)
		and (not isDialogueVisible)
		and hasHorsePool

	set_button_enabled(currentUi.SpinButton, enabled)
end

local function close_roulette(forceClose)
	isRouletteOpen = false
	isRouletteRolling = false
	cancel_slot_population()
	hide_dialogue()
	hide_reward_gui()

	if not currentUi then
		return
	end

	clear_notice(currentUi)
	set_button_enabled(currentUi.SpinButton, true)
	reset_wheel_rotation(currentUi)

	if currentUi.Root and (forceClose or not pendingStarterReveal) then
		currentUi.Root.Visible = false
	end
end

local function fetch_roulette_state()
	if not has_access() then
		if currentUi then
			show_notice(currentUi, "You do not have access to open the roulette.", true)
		end
		return false
	end

	local success, response = invoke_remote(get_roulette_state_remote())
	if not success or not response or response.Success ~= true then
		if currentUi then
			show_notice(currentUi, "Could not load the roulette.", true)
		end
		return false
	end

	rouletteState.Price = tonumber(response.Price) or rouletteState.Price
	rouletteState.Balance = math.max(0, tonumber(response.Balance) or 0)
	rouletteState.FreeWhenZero = response.FreeWhenZero == true
	rouletteState.Horses = type(response.Horses) == "table" and response.Horses or horseOptions
	rouletteState.CanRoll = response.CanRoll == true
	prewarm_preview_snapshots(rouletteState.Horses)

	return true
end

local function show_reward_result(horseOption)
	build_reward_gui()
	populate_horse_viewport(rewardViewport, horseOption, RESULT_CAMERA_CONFIG, "reward")
	rewardNameLabel.Text = horseOption.DisplayName or horseOption.CatalogId
	show_reward_gui()
end

local function show_insufficient_funds_dialog()
	local priceText = format_horseshoes(rouletteState.Price)
	local balanceText = format_horseshoes(rouletteState.Balance)
	local dialogShown = show_dialogue({
		title = "Not enough Horseshoes",
		details = string.format(
			"You need %s Horseshoes to spin the roulette.\nCurrent balance: %s.",
			priceText,
			balanceText
		),
		acceptText = "OK",
		denyText = "Close",
	})

	if not dialogShown and currentUi then
		show_notice(
			currentUi,
			string.format("You need %s Horseshoes to spin the roulette.", priceText),
			true
		)
	end

	update_spin_button()
end

local function request_spin()
	if pendingStarterReveal or not isRouletteOpen or isRouletteRolling or isDialogueVisible or not currentUi then
		return
	end

	local balance = math.max(0, tonumber(rouletteState.Balance) or 0)
	local price = math.max(0, tonumber(rouletteState.Price) or 0)
	if balance < price then
		show_insufficient_funds_dialog()
		return
	end

	local dialogShown = show_dialogue({
		title = "Confirm roulette",
		details = string.format(
			"Do you want to spend %s Horseshoes to spin the roulette?",
			format_horseshoes(price)
		),
		acceptText = "Confirm",
		denyText = "Cancel",
		onAccept = function()
			task.spawn(play_spin)
		end,
	})

	if not dialogShown then
		task.spawn(play_spin)
		return
	end

	update_spin_button()
end

local function open_roulette()
	if pendingStarterReveal or isRouletteRolling or not has_access() then
		return
	end

	if not currentUi then
		return
	end

	if not fetch_roulette_state() then
		return
	end

	hide_reward_gui()
	hide_dialogue()
	close_other_frames(currentUi.FramesContainer, currentUi.Root)
	currentUi.Root.Visible = true
	isRouletteOpen = true
	clear_notice(currentUi)
	reset_wheel_rotation(currentUi)

	RunService.Heartbeat:Wait()

	currentUi.Slots = collect_wheel_slots(currentUi.WheelBg)
	if #currentUi.Slots == 0 then
		close_roulette(true)
		return
	end

	local slotAssignments = build_idle_slot_assignments(
		rouletteState.Horses,
		math.min(#currentUi.Slots, SLOT_COUNT)
	)
	populate_slots(currentUi, slotAssignments, true)
	update_spin_button()
end

play_spin = function()
	if pendingStarterReveal or not isRouletteOpen or isRouletteRolling or not currentUi then
		return
	end

	isRouletteRolling = true
	update_spin_button()

	local success, response = invoke_remote(get_roulette_roll_remote())
	if not success or not response or response.Success ~= true then
		rouletteState.Balance = math.max(0, tonumber(response and response.RemainingHorseshoes) or rouletteState.Balance)
		isRouletteRolling = false

		if response and response.MessageCode == "InsufficientFunds" then
			show_insufficient_funds_dialog()
		elseif response and response.Code == "AccessDenied" then
			show_notice(currentUi, "You do not have access to use the roulette.", true)
		else
			show_notice(currentUi, "Could not spin the roulette.", true)
		end

		update_spin_button()
		return
	end

	rouletteState.Balance = math.max(0, tonumber(response.RemainingHorseshoes) or rouletteState.Balance)
	clear_notice(currentUi)

	local finalHorse = response.RolledHorse
	local finalHorseOption = finalHorse and find_horse_option(finalHorse.CatalogId, finalHorse) or nil
	if not finalHorseOption then
		close_roulette(true)
		return
	end

	currentUi.Slots = collect_wheel_slots(currentUi.WheelBg)
	if #currentUi.Slots == 0 then
		close_roulette(true)
		return
	end

	local slotAssignments, winningSlotIndex = build_result_slot_assignments(
		finalHorseOption,
		math.min(#currentUi.Slots, SLOT_COUNT)
	)
	populate_slots(currentUi, slotAssignments, false)

	local winningSlot = currentUi.Slots[winningSlotIndex]
	if not winningSlot then
		close_roulette(true)
		return
	end

	local currentRotation = currentUi.WheelBg.Rotation
	local slotAngle = get_slot_screen_angle(winningSlot.Label, currentUi.WheelBg)
	local deltaRotation = normalize_positive_angle(POINTER_ANGLE_DEGREES - slotAngle)
	local targetRotation = currentRotation + (WHEEL_SPIN_FULL_TURNS * 360) + deltaRotation

	local spinTween = TweenService:Create(
		currentUi.WheelBg,
		TweenInfo.new(WHEEL_SPIN_DURATION, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Rotation = targetRotation }
	)

	spinTween:Play()
	spinTween.Completed:Wait()

	if pendingStarterReveal or not isRouletteOpen then
		close_roulette(true)
		return
	end

	if currentUi and currentUi.Root then
		currentUi.Root.Visible = false
	end

	isRouletteOpen = false
	show_reward_result(finalHorseOption)
	task.wait(RESULT_DISPLAY_SECONDS)
	hide_reward_gui()

	isRouletteRolling = false
	if currentUi then
		reset_wheel_rotation(currentUi)
		update_spin_button()
	end
end

local function bind_ui(ui)
	if currentUi and currentUi.Root == ui.Root and currentUi.WheelBg == ui.WheelBg then
		return
	end

	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = ui

	uiTrove:Connect(ui.Root.AncestryChanged, function(_, parent)
		if parent then
			return
		end

		if currentUi and currentUi.Root == ui.Root then
			currentUi = nil
			task.defer(function()
				local reboundUi = get_raffle_ui()
				if reboundUi then
					bind_ui(reboundUi)
				end
			end)
		end
	end)

	uiTrove:Connect(ui.SpinButton.Activated, function()
		if pendingStarterReveal or not isRouletteOpen or isRouletteRolling then
			return
		end

		task.spawn(request_spin)
	end)

	if ui.CloseButton then
		uiTrove:Connect(ui.CloseButton.Activated, function()
			if pendingStarterReveal or isRouletteRolling then
				return
			end

			close_roulette(true)
		end)
	end

	if isRouletteOpen and not pendingStarterReveal then
		task.defer(open_roulette)
	end

	clear_notice(ui)
end

local function try_bind_ui()
	local ui = get_raffle_ui()
	if not ui then
		return
	end

	bind_ui(ui)
end

local function is_roulette_ui_related(instance)
	return matches_alias(instance, MAIN_UI_NAMES)
		or matches_alias(instance, MAINFRAME_NAMES)
		or matches_alias(instance, FRAMES_CONTAINER_NAMES)
		or matches_alias(instance, RAFFLE_ROOT_NAMES)
		or matches_alias(instance, RAFFLE_BACKGROUND_NAMES)
		or matches_alias(instance, WHEEL_BACKGROUND_NAMES)
		or matches_alias(instance, SPIN_BUTTON_NAMES)
		or matches_alias(instance, CLOSE_BUTTON_NAMES)
		or matches_alias(instance, VIEWPORT_FRAME_NAMES)
end

local function toggle_roulette()
	if pendingStarterReveal or not has_access() then
		return
	end

	if isRouletteRolling then
		return
	end

	try_bind_ui()
	if not currentUi then
		return
	end

	if isRouletteOpen and currentUi.Root and currentUi.Root.Visible then
		close_roulette(true)
		return
	end

	task.spawn(open_roulette)
end

DataUtility.client.ensure_remotes()
build_reward_gui()
hide_reward_gui()
prewarm_preview_snapshots(horseOptions)

rootTrove:Connect(playerGui.DescendantAdded, function(instance)
	if is_roulette_ui_related(instance) or instance:IsA("LayerCollector") then
		try_bind_ui()
	end
end)

rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
	if currentUi and (instance == currentUi.Root or instance:IsDescendantOf(currentUi.Root)) then
		currentUi = nil
		task.defer(try_bind_ui)
	elseif is_roulette_ui_related(instance) then
		task.defer(try_bind_ui)
	end
end)

rootTrove:Add(DataUtility.client.bind("Progression.PendingHorseReveal", function(pendingReveal)
	pendingStarterReveal = type(pendingReveal) == "table"
	if pendingStarterReveal then
		close_roulette(true)
	end
end))

rootTrove:Add(DataUtility.client.bind("Currencies.Horseshoes", function(horseshoes)
	rouletteState.Balance = math.max(0, tonumber(horseshoes) or 0)
	if isRouletteOpen and not pendingStarterReveal then
		update_spin_button()
	end
end))

localPlayer:GetAttributeChangedSignal("CanOpenAdminPanel"):Connect(function()
	if not has_access() then
		close_roulette(true)
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == Enum.KeyCode.H then
		toggle_roulette()
	end
end)

try_bind_ui()

local initialPendingReveal = DataUtility.client.get("Progression.PendingHorseReveal")
pendingStarterReveal = type(initialPendingReveal) == "table"

rootTrove:Add(function()
	uiTrove:Destroy()
	hide_dialogue()
	hide_reward_gui()
end)
