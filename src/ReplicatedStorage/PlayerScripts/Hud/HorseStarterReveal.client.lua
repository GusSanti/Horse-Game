local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local GameData = Modules:WaitForChild("GameData")
local HudModules = ClientModules:WaitForChild("Hud")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local Trove = require(Libraries:WaitForChild("Trove"))
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

local RESULT_GUI_NAME = "HorseStarterRevealRewardGui"
local POINTER_ANGLE_DEGREES = -90
local SLOT_COUNT = 8
local WHEEL_SPIN_DURATION = 5.2
local WHEEL_SPIN_FULL_TURNS = 6
local RESULT_DISPLAY_SECONDS = 3

local SLOT_CAMERA_CONFIG = HorseViewportRenderer.Presets.Wheel
local RESULT_CAMERA_CONFIG = HorseViewportRenderer.Presets.Reward

local horseOptions = HorseCatalog.GetRouletteHorseOptions()

local rootTrove = Trove.new()
local uiTrove = Trove.new()

local currentUi = nil
local activePendingReveal = nil
local currentRevealHorseId = nil
local preparedRevealHorseId = nil
local preparedUiRoot = nil
local isSpinInProgress = false

local rewardGui = nil
local rewardOverlay = nil
local rewardViewport = nil
local rewardNameLabel = nil

local gameplayRemotes = ReplicatedStorage:WaitForChild(NetworkConfig.GameplayFolderName)
local horseRemotes = gameplayRemotes:WaitForChild(NetworkConfig.Horse.FolderName)
local acknowledgeRevealRemote = horseRemotes:WaitForChild(NetworkConfig.Horse.AcknowledgeReveal)

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
		DisplayOrder = 140,
		Enabled = false,
		Parent = playerGui,
	})

	rewardOverlay = create("Frame", {
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
		Parent = rewardOverlay,
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

local function prewarm_preview_snapshots()
	HorseViewportRenderer.PrewarmCatalogs(horseOptions, { SLOT_CAMERA_CONFIG, RESULT_CAMERA_CONFIG })
end

local function populate_horse_viewport(viewportFrame, horseOption, cameraConfig, cameraKey)
	if not viewportFrame then return end
	if not horseOption then
		HorseViewportRenderer.Clear(viewportFrame)
		return
	end
	HorseViewportRenderer.QueueCatalog(viewportFrame, horseOption.CatalogId, cameraConfig, {
		ModelKey = horseOption.ModelKey,
		Priority = cameraKey == "reward" and 1 or 4,
	})
end

local function find_horse_option(catalogId)
	for _, horseOption in ipairs(horseOptions) do
		if horseOption.CatalogId == catalogId then
			return horseOption
		end
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
		WinningSlotIndex = nil,
		SlotAssignments = nil,
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

local function acknowledge_reveal(horseId)
	if type(horseId) ~= "string" or horseId == "" then
		return
	end

	acknowledgeRevealRemote:FireServer(horseId)
end

local function reset_wheel_rotation(ui)
	local baseRotation = ui.WheelBg:GetAttribute("StarterRevealBaseRotation")
	if type(baseRotation) ~= "number" then
		baseRotation = ui.WheelBg.Rotation
		ui.WheelBg:SetAttribute("StarterRevealBaseRotation", baseRotation)
	end

	ui.WheelBg.Rotation = baseRotation
end

local function shuffle_array(items)
	for index = #items, 2, -1 do
		local swapIndex = math.random(1, index)
		items[index], items[swapIndex] = items[swapIndex], items[index]
	end
end

local function build_slot_assignments(finalHorseOption, slotCount)
	local assignments = table.create(slotCount)
	local winningSlotIndex = slotCount > 1 and math.random(2, slotCount) or 1
	local fillers = {}

	for _, horseOption in ipairs(horseOptions) do
		if horseOption.CatalogId ~= finalHorseOption.CatalogId then
			fillers[#fillers + 1] = horseOption
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

local function cleanup_reveal_state()
	isSpinInProgress = false
	activePendingReveal = nil
	currentRevealHorseId = nil
	preparedRevealHorseId = nil
	preparedUiRoot = nil
	hide_reward_gui()

	if currentUi then
		set_button_enabled(currentUi.SpinButton, true)
		if currentUi.Root then
			currentUi.Root.Visible = false
		end
		reset_wheel_rotation(currentUi)
	end
end

local function show_reward_result(horseOption)
	build_reward_gui()
	populate_horse_viewport(rewardViewport, horseOption, RESULT_CAMERA_CONFIG, "reward")
	rewardNameLabel.Text = horseOption.DisplayName or horseOption.CatalogId
	show_reward_gui()
end

local function prepare_raffle_ui_for_reveal(pendingReveal)
	if not currentUi or not pendingReveal then
		return false
	end

	if preparedRevealHorseId == pendingReveal.HorseId and preparedUiRoot == currentUi.Root then
		return true
	end

	local finalHorseOption = find_horse_option(pendingReveal.CatalogId)
	if not finalHorseOption then
		return false
	end

	hide_reward_gui()
	close_other_frames(currentUi.FramesContainer, currentUi.Root)
	currentUi.Root.Visible = true
	set_button_enabled(currentUi.SpinButton, true)
	reset_wheel_rotation(currentUi)

	RunService.Heartbeat:Wait()

	currentUi.Slots = collect_wheel_slots(currentUi.WheelBg)
	if #currentUi.Slots == 0 then
		return false
	end

	local slotAssignments, winningSlotIndex = build_slot_assignments(
		finalHorseOption,
		math.min(#currentUi.Slots, SLOT_COUNT)
	)

	currentUi.WinningSlotIndex = winningSlotIndex
	currentUi.SlotAssignments = slotAssignments

	for slotIndex, slot in ipairs(currentUi.Slots) do
		local horseOption = slotAssignments[((slotIndex - 1) % #slotAssignments) + 1]
		slot.HorseOption = horseOption
		slot.Label.Text = horseOption.DisplayName or horseOption.CatalogId
		populate_horse_viewport(slot.ViewportFrame, horseOption, SLOT_CAMERA_CONFIG, "wheel")
	end

	preparedRevealHorseId = pendingReveal.HorseId
	preparedUiRoot = currentUi.Root
	return true
end

local function finish_reveal(pendingReveal, finalHorseOption)
	if currentUi and currentUi.Root then
		currentUi.Root.Visible = false
	end

	show_reward_result(finalHorseOption)
	task.wait(RESULT_DISPLAY_SECONDS)
	hide_reward_gui()
	acknowledge_reveal(pendingReveal.HorseId)
	cleanup_reveal_state()
end

local function play_spin()
	if isSpinInProgress or not activePendingReveal or not currentUi then
		return
	end

	if not prepare_raffle_ui_for_reveal(activePendingReveal) then
		return
	end

	local finalHorseOption = find_horse_option(activePendingReveal.CatalogId)
	local winningSlot = currentUi.Slots[currentUi.WinningSlotIndex or 1]
	if not finalHorseOption or not winningSlot then
		acknowledge_reveal(activePendingReveal.HorseId)
		cleanup_reveal_state()
		return
	end

	isSpinInProgress = true
	set_button_enabled(currentUi.SpinButton, false)

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

	if not activePendingReveal or activePendingReveal.HorseId ~= currentRevealHorseId then
		cleanup_reveal_state()
		return
	end

	finish_reveal(activePendingReveal, finalHorseOption)
end

local function bind_ui(ui)
	if currentUi and currentUi.Root == ui.Root and currentUi.WheelBg == ui.WheelBg then
		return
	end

	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = ui
	preparedUiRoot = nil
	preparedRevealHorseId = nil

	uiTrove:Connect(ui.Root.AncestryChanged, function(_, parent)
		if parent then
			return
		end

		if currentUi and currentUi.Root == ui.Root then
			currentUi = nil
			preparedUiRoot = nil
			preparedRevealHorseId = nil
			task.defer(function()
				local reboundUi = get_raffle_ui()
				if reboundUi then
					bind_ui(reboundUi)
				end
			end)
		end
	end)

	uiTrove:Connect(ui.SpinButton.Activated, function()
		if not activePendingReveal or isSpinInProgress then
			return
		end

		task.spawn(play_spin)
	end)

	if ui.CloseButton then
		uiTrove:Connect(ui.CloseButton.Activated, function()
			if activePendingReveal then
				return
			end

			ui.Root.Visible = false
		end)
	end

	if activePendingReveal then
		task.defer(function()
			prepare_raffle_ui_for_reveal(activePendingReveal)
		end)
	end
end

local function try_bind_ui()
	local ui = get_raffle_ui()
	if not ui then
		return
	end

	bind_ui(ui)
end

local function is_reveal_ui_related(instance)
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

local function queue_reveal(pendingReveal)
	if type(pendingReveal) ~= "table" then
		return
	end

	if currentRevealHorseId == pendingReveal.HorseId and activePendingReveal then
		return
	end

	activePendingReveal = pendingReveal
	currentRevealHorseId = pendingReveal.HorseId
	preparedRevealHorseId = nil
	preparedUiRoot = nil
	isSpinInProgress = false

	if currentUi then
		task.defer(function()
			prepare_raffle_ui_for_reveal(pendingReveal)
		end)
	end
end

DataUtility.client.ensure_remotes()
build_reward_gui()
hide_reward_gui()
prewarm_preview_snapshots()

rootTrove:Connect(playerGui.DescendantAdded, function(instance)
	if is_reveal_ui_related(instance) or instance:IsA("LayerCollector") then
		try_bind_ui()
	end
end)

rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
	if currentUi and (instance == currentUi.Root or instance:IsDescendantOf(currentUi.Root)) then
		currentUi = nil
		preparedUiRoot = nil
		preparedRevealHorseId = nil
		task.defer(try_bind_ui)
	elseif is_reveal_ui_related(instance) then
		task.defer(try_bind_ui)
	end
end)

DataUtility.client.bind("Progression.PendingHorseReveal", function(pendingReveal)
	if type(pendingReveal) == "table" then
		queue_reveal(pendingReveal)
	else
		cleanup_reveal_state()
	end
end)

try_bind_ui()

local initialPendingReveal = DataUtility.client.get("Progression.PendingHorseReveal")
if type(initialPendingReveal) == "table" then
	queue_reveal(initialPendingReveal)
end

rootTrove:Add(function()
	uiTrove:Destroy()
	hide_reward_gui()
end)
