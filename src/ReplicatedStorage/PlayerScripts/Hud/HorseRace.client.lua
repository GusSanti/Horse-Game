local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")
local HudModules = ClientModules:WaitForChild("Hud")

local Net = require(Libraries:WaitForChild("Net"))
local RaceConfig = require(GameData:WaitForChild("RaceConfig"))
local RaceVisualFactory = require(Utility:WaitForChild("RaceVisualFactory"))
local HorseRaceVisuals = require(HudModules:WaitForChild("HorseRaceVisuals"))
local Notifications = require(HudModules:WaitForChild("Notifications"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local CONTROL_ACTION_NAME = "HorseRaceLockControls"
local RACE_INVITE_NOTIFICATION_ID = "HorseRaceInvite"
local requestInFlight = false
local rowFrames = {}
local horseButtons = {}
local selectedHorseId = nil
local lastInviteCountdownSecond = nil
local previousCameraType = nil
local previousCameraSubject = nil
local update_visibility
local update_dynamic_text

local state = {
	Phase = "Idle",
	RoundId = nil,
	InviteDeadline = 0,
	ResultDeadline = 0,
	LocalJoined = false,
	LocalWatchingRace = false,
	HorseOptions = {},
	Entries = {},
	Result = nil,
	NoticeText = "",
	CameraLocked = false,
	CameraMoving = false,
	CameraBaseCFrame = nil,
	CameraRotation = nil,
	CameraSpeed = RaceConfig.CameraSpeed,
	CameraProgress = 0,
	CameraDistance = RaceConfig.RaceDistance,
}

local ui = {}
local raceVisuals = {
	Folder = nil,
	ByUserId = {},
}
local raceVisualContext = {
	Workspace = Workspace,
	TweenService = TweenService,
	RaceConfig = RaceConfig,
	RaceVisualFactory = RaceVisualFactory,
	localPlayer = localPlayer,
	state = state,
	raceVisuals = raceVisuals,
}

local function extract_rotation(cframe) return CFrame.fromMatrix(Vector3.zero, cframe.XVector, cframe.YVector, cframe.ZVector) end

local function create_instance(className, props)
	local instance = Instance.new(className)

	for key, value in pairs(props) do
		instance[key] = value
	end

	return instance
end

local function apply_panel_style(frame, accentColor)
	frame.BackgroundColor3 = Color3.fromRGB(17, 20, 24)
	frame.BorderSizePixel = 0

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = accentColor or Color3.fromRGB(113, 224, 170)
	stroke.Thickness = 1
	stroke.Transparency = 0.15
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.Parent = frame
end

local function create_label(parent, name, props)
	local label = create_instance("TextLabel", {
		Name = name,
		BackgroundTransparency = 1,
		Font = Enum.Font.Code,
		TextColor3 = Color3.fromRGB(240, 243, 246),
		TextSize = 16,
		TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = parent,
	})

	for key, value in pairs(props) do
		label[key] = value
	end

	return label
end

local function create_button(parent, name, props)
	local button = create_instance("TextButton", {
		Name = name,
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(35, 103, 77),
		BorderSizePixel = 0,
		Font = Enum.Font.Code,
		TextColor3 = Color3.fromRGB(245, 247, 250),
		TextSize = 16,
		Parent = parent,
	})

	for key, value in pairs(props) do
		button[key] = value
	end

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = button

	return button
end

local function format_countdown(seconds) local clamped = math.max(0, math.floor(seconds + 0.999)); return ("%02d:%02d"):format(math.floor(clamped / 60), clamped % 60) end

local function hide_race_invite_notification()
	Notifications.HideDialogue(RACE_INVITE_NOTIFICATION_ID)
end

local STATUS_DISPLAY_NAMES = {
	Happiness = "Happiness",
	Hunger = "Hunger",
	Thirst = "Thirst",
	Cleanliness = "Cleanliness",
	Health = "Health",
}

local function get_status_display_name(statusName, fallback)
	return (type(statusName) == "string" and statusName ~= "" and STATUS_DISPLAY_NAMES[statusName]) or fallback or statusName or "Status"
end

local function find_local_entry()
	for _, entry in ipairs(state.Entries) do
		if entry.UserId == localPlayer.UserId then return entry end
	end
	return nil
end

local function find_horse_option(horseId)
	if type(horseId) ~= "string" or horseId == "" then
		return nil
	end

	for _, horse in ipairs(state.HorseOptions) do
		if horse.Id == horseId then
			return horse
		end
	end

	return nil
end

local function get_selected_horse_option() return find_horse_option(selectedHorseId) end

local function set_button_enabled(button, enabled, enabledColor, disabledColor)
	if not button then
		return
	end

	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = enabled
		and (enabledColor or Color3.fromRGB(35, 103, 77))
		or (disabledColor or Color3.fromRGB(58, 62, 68))
	button.TextTransparency = enabled and 0 or 0.18
end

local function sync_race_visuals() HorseRaceVisuals.syncRaceVisuals(raceVisualContext) end
local function clear_race_visuals() HorseRaceVisuals.clearRaceVisuals(raceVisualContext) end
local function update_race_visual_motion(visual, deltaTime, now) HorseRaceVisuals.updateRaceVisualMotion(raceVisualContext, visual, deltaTime, now) end

local function lock_controls(shouldLock)
	if shouldLock then
		ContextActionService:BindActionAtPriority(
			CONTROL_ACTION_NAME,
			function()
				return Enum.ContextActionResult.Sink
			end,
			false,
			3000,
			Enum.PlayerActions.CharacterForward,
			Enum.PlayerActions.CharacterBackward,
			Enum.PlayerActions.CharacterLeft,
			Enum.PlayerActions.CharacterRight,
			Enum.PlayerActions.CharacterJump
		)
	else
		ContextActionService:UnbindAction(CONTROL_ACTION_NAME)
	end
end

local function unlock_camera()
	if not state.CameraLocked then
		lock_controls(false)
		return
	end

	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = previousCameraType or Enum.CameraType.Custom
		camera.CameraSubject = previousCameraSubject
	end

	previousCameraType = nil
	previousCameraSubject = nil

	state.CameraLocked = false
	state.CameraMoving = false
	state.CameraBaseCFrame = nil
	state.CameraRotation = nil
	state.CameraProgress = 0
	lock_controls(false)
end

local function lock_camera(cameraCFrame, moving)
	local camera = Workspace.CurrentCamera
	if not camera or not cameraCFrame then
		return
	end

	if not state.CameraLocked then
		previousCameraType = camera.CameraType
		previousCameraSubject = camera.CameraSubject
	end

	state.CameraLocked = true
	state.CameraMoving = moving == true
	state.CameraBaseCFrame = cameraCFrame
	state.CameraRotation = extract_rotation(cameraCFrame)
	state.CameraProgress = 0
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = cameraCFrame
	lock_controls(true)
end

local function reset_state()
	hide_race_invite_notification()
	state.Phase = "Idle"
	state.RoundId = nil
	state.InviteDeadline = 0
	state.ResultDeadline = 0
	state.LocalJoined = false
	state.LocalWatchingRace = false
	state.HorseOptions = {}
	state.Entries = {}
	state.Result = nil
	state.NoticeText = ""
	state.CameraSpeed = RaceConfig.CameraSpeed
	state.CameraDistance = RaceConfig.RaceDistance
	selectedHorseId = nil

	clear_race_visuals()
	unlock_camera()
end

local function destroy_existing_rows()
	for userId, row in pairs(rowFrames) do
		row:Destroy()
		rowFrames[userId] = nil
	end
end

local function destroy_existing_horse_buttons()
	for horseId, button in pairs(horseButtons) do
		button:Destroy()
		horseButtons[horseId] = nil
	end
end

local function refresh_leaderboard()
	destroy_existing_rows()

	for _, entry in ipairs(state.Entries) do
		local row = create_instance("Frame", {
			Name = tostring(entry.UserId),
			BackgroundColor3 = Color3.fromRGB(23, 27, 31),
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 46),
			Parent = ui.BoardList,
		})

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = row

		local title = create_label(row, "Title", {
			Size = UDim2.new(1, -106, 0.52, 0),
			Position = UDim2.new(0, 10, 0, 4),
			Text = ("%d. %s"):format(entry.Rank or 1, entry.PlayerName or "Player"),
			TextSize = 15,
		})
		title.TextColor3 = entry.UserId == localPlayer.UserId
			and Color3.fromRGB(115, 224, 170)
			or Color3.fromRGB(240, 243, 246)

		create_label(row, "Horse", {
			Size = UDim2.new(1, -106, 0.4, 0),
			Position = UDim2.new(0, 10, 0.55, -2),
			Text = entry.HorseName or "Horse",
			TextSize = 13,
			TextColor3 = Color3.fromRGB(164, 173, 184),
		})

		create_label(row, "Distance", {
			Size = UDim2.new(0, 96, 0, 22),
			Position = UDim2.new(1, -100, 0, 4),
			Text = ("%.1f / %d"):format(entry.Progress or 0, entry.Distance or RaceConfig.RaceDistance),
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Right,
		})

		local barBack = create_instance("Frame", {
			Name = "BarBack",
			BackgroundColor3 = Color3.fromRGB(37, 42, 48),
			BorderSizePixel = 0,
			Size = UDim2.new(0, 96, 0, 8),
			Position = UDim2.new(1, -100, 1, -14),
			Parent = row,
		})

		local barCorner = Instance.new("UICorner")
		barCorner.CornerRadius = UDim.new(1, 0)
		barCorner.Parent = barBack

		local ratio = math.clamp((entry.Progress or 0) / (entry.Distance or RaceConfig.RaceDistance), 0, 1)
		local barFill = create_instance("Frame", {
			Name = "BarFill",
			BackgroundColor3 = entry.UserId == localPlayer.UserId
				and Color3.fromRGB(115, 224, 170)
				or Color3.fromRGB(233, 182, 96),
			BorderSizePixel = 0,
			Size = UDim2.new(ratio, 0, 1, 0),
			Parent = barBack,
		})

		local barFillCorner = Instance.new("UICorner")
		barFillCorner.CornerRadius = UDim.new(1, 0)
		barFillCorner.Parent = barFill

		rowFrames[entry.UserId] = row
	end
end

local function update_horse_selection_visuals()
	for horseId, button in pairs(horseButtons) do
		local horse = find_horse_option(horseId)
		local selected = horseId == selectedHorseId
		local canRace = horse and horse.CanRace ~= false
		button.BackgroundColor3 = selected
			and (canRace and Color3.fromRGB(52, 122, 94) or Color3.fromRGB(123, 78, 52))
			or (canRace and Color3.fromRGB(27, 31, 36) or Color3.fromRGB(46, 32, 32))
	end
end

local function refresh_horse_options()
	destroy_existing_horse_buttons()

	for _, horse in ipairs(state.HorseOptions) do
		local title = horse.Name or horse.DisplayName or horse.Id
		local canRace = horse.CanRace ~= false
		local blockedStatusName = get_status_display_name(
			horse.RaceBlockedStatus or horse.RaceLowestStatus,
			horse.RaceBlockedStatusDisplay or horse.RaceLowestStatusDisplay
		)
		local metaText = canRace
			and "Ready to race"
			or ("%s %d%%  |  minimum %d%%"):format(
				blockedStatusName,
				horse.RaceBlockedPercent or horse.RaceLowestPercent or 0,
				horse.RaceMinPercent or 50
			)

		local button = create_button(ui.SelectList, horse.Id, {
			BackgroundColor3 = canRace and Color3.fromRGB(27, 31, 36) or Color3.fromRGB(46, 32, 32),
			Size = UDim2.new(1, 0, 0, 46),
			Text = "",
		})

		create_label(button, "HorseName", {
			Size = UDim2.new(1, -14, 0.52, 0),
			Position = UDim2.new(0, 8, 0, 4),
			Text = title .. (horse.IsEquipped and "  [equipped]" or ""),
			TextSize = 14,
		})

		create_label(button, "HorseMeta", {
			Size = UDim2.new(1, -14, 0.36, 0),
			Position = UDim2.new(0, 8, 0.6, -1),
			Text = metaText,
			TextSize = 12,
			TextColor3 = canRace and Color3.fromRGB(164, 173, 184) or Color3.fromRGB(244, 184, 164),
		})

		button.MouseButton1Click:Connect(function()
			selectedHorseId = horse.Id
			update_horse_selection_visuals()
			local selectedHorse = get_selected_horse_option()
			local selectedCanRace = selectedHorse and selectedHorse.CanRace ~= false
			set_button_enabled(ui.SelectConfirm, selectedCanRace, Color3.fromRGB(35, 103, 77))
			ui.SelectConfirm.Text = selectedCanRace and "Join" or "Care first"
		end)

		horseButtons[horse.Id] = button
	end

	if not selectedHorseId or not find_horse_option(selectedHorseId) then
		for _, horse in ipairs(state.HorseOptions) do
			if horse.CanRace ~= false then
				selectedHorseId = horse.Id
				break
			end
		end

		if not selectedHorseId and state.HorseOptions[1] then
			selectedHorseId = state.HorseOptions[1].Id
		end
	end

	update_horse_selection_visuals()

	local selectedHorse = get_selected_horse_option()
	local selectedCanRace = selectedHorse and selectedHorse.CanRace ~= false
	set_button_enabled(ui.SelectConfirm, selectedCanRace, Color3.fromRGB(35, 103, 77))
	ui.SelectConfirm.Text = selectedCanRace and "Join" or "Care first"
end

local function submit_leave_request()
	if requestInFlight or not state.RoundId then
		return
	end

	requestInFlight = true
	local ok, response = pcall(function()
		return Net.Function.RaceAction:Call({
			Action = "Leave",
			RoundId = state.RoundId,
		})
	end)
	requestInFlight = false

	if ok and response and response.Success then
		state.LocalJoined = false
		state.LocalWatchingRace = false
		if os.clock() < state.InviteDeadline then
			state.Phase = "Invite"
		else
			state.Phase = "Idle"
		end
		unlock_camera()
		sync_race_visuals()
		update_visibility()
		update_dynamic_text()
	end
end

local function submit_join_request(horseId)
	if requestInFlight or not state.RoundId then
		return
	end

	requestInFlight = true
	local ok, response = pcall(function()
		return Net.Function.RaceAction:Call({
			Action = "Join",
			RoundId = state.RoundId,
			HorseId = horseId,
		})
	end)
	requestInFlight = false

	if not ok or not response then
		return
	end

	if response.Success then
		hide_race_invite_notification()
		state.LocalJoined = true
		state.Phase = "Queue"
		state.NoticeText = ""
		ui.SelectFrame.Visible = false
		if response.CameraCFrame then
			lock_camera(response.CameraCFrame, false)
		end
		sync_race_visuals()
		update_visibility()
		update_dynamic_text()
		return
	end

	if response.Code == "HorseSelectionRequired" then
		state.NoticeText = ""
		state.HorseOptions = response.HorseOptions or state.HorseOptions
		refresh_horse_options()
		ui.SelectFrame.Visible = true
	elseif response.Code == "HorseNeedsTooLow" then
		state.HorseOptions = response.HorseOptions or state.HorseOptions
		state.NoticeText = ("%s is at %d%%. It must stay above %d%%."):format(
			get_status_display_name(response.BlockedStatus, response.BlockedStatusDisplay),
			response.BlockedPercent or 0,
			response.MinimumPercent or 50
		)
		selectedHorseId = response.HorseId or selectedHorseId
		refresh_horse_options()
		ui.SelectFrame.Visible = true
	elseif response.Code == "InviteExpired" or response.Code == "InviteClosed" or response.Code == "NoActiveRound" then
		reset_state()
		destroy_existing_rows()
		update_visibility()
		update_dynamic_text()
	end
end

local function open_race_invitation()
	if #state.HorseOptions <= 1 then
		local onlyHorse = state.HorseOptions[1]
		if onlyHorse and onlyHorse.CanRace == false then
			selectedHorseId = onlyHorse.Id
			refresh_horse_options()
			ui.SelectFrame.Visible = true
			return
		end

		submit_join_request(onlyHorse and onlyHorse.Id or nil)
		return
	end

	ui.SelectFrame.Visible = true
end

local function get_race_invite_details(): string
	return ("Race registration is open. Closes in %s."):format(format_countdown(state.InviteDeadline - os.clock()))
end

local function get_race_invite_accept_text(): string
	if #state.HorseOptions > 1 then
		return "Choose horse"
	end

	local onlyHorse = state.HorseOptions[1]
	if onlyHorse and onlyHorse.CanRace == false then
		return "Care for horse"
	end

	return "Join"
end

local function show_race_invite_notification()
	if state.Phase ~= "Invite" or not state.RoundId or os.clock() >= state.InviteDeadline then
		return
	end

	lastInviteCountdownSecond = math.ceil(math.max(0, state.InviteDeadline - os.clock()))

	Notifications.ShowDialogue({
		id = RACE_INVITE_NOTIFICATION_ID,
		title = "Race available",
		details = get_race_invite_details(),
		acceptText = get_race_invite_accept_text(),
		denyText = "Later",
		hideTasks = true,
		onAccept = open_race_invitation,
	})
end

local function update_race_invite_countdown()
	if state.Phase ~= "Invite" or not Notifications.IsDialogueActive(RACE_INVITE_NOTIFICATION_ID) then
		return
	end

	local remainingSeconds = math.ceil(math.max(0, state.InviteDeadline - os.clock()))
	if remainingSeconds == lastInviteCountdownSecond then
		return
	end

	lastInviteCountdownSecond = remainingSeconds
	Notifications.UpdateDialogue(RACE_INVITE_NOTIFICATION_ID, {
		details = get_race_invite_details(),
		acceptText = get_race_invite_accept_text(),
	})
end

local function build_ui()
	local screenGui = create_instance("ScreenGui", {
		Name = "HorseRaceHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = playerGui,
	})

	local selectFrame = create_instance("Frame", {
		Name = "SelectFrame",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 122),
		Size = UDim2.fromOffset(430, 296),
		Parent = screenGui,
	})
	apply_panel_style(selectFrame, Color3.fromRGB(115, 224, 170))

	local boardFrame = create_instance("Frame", {
		Name = "BoardFrame",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 122),
		Size = UDim2.fromOffset(300, 270),
		Parent = screenGui,
	})
	apply_panel_style(boardFrame, Color3.fromRGB(115, 224, 170))

	local resultFrame = create_instance("Frame", {
		Name = "ResultFrame",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 122),
		Size = UDim2.fromOffset(460, 74),
		Parent = screenGui,
	})
	apply_panel_style(resultFrame, Color3.fromRGB(233, 182, 96))

	ui.ScreenGui = screenGui
	ui.SelectFrame = selectFrame
	ui.BoardFrame = boardFrame
	ui.ResultFrame = resultFrame

	ui.SelectTitle = create_label(selectFrame, "SelectTitle", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "Choose a horse",
		TextSize = 18,
	})

	ui.SelectMeta = create_label(selectFrame, "SelectMeta", {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 28),
		Text = "Only horses above 50% can race.",
		TextSize = 13,
		TextColor3 = Color3.fromRGB(164, 173, 184),
	})

	ui.SelectList = create_instance("ScrollingFrame", {
		Name = "SelectList",
		Active = true,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Color3.fromRGB(22, 25, 29),
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(),
		Position = UDim2.new(0, 0, 0, 56),
		ScrollBarThickness = 6,
		Size = UDim2.new(1, 0, 1, -108),
		Parent = selectFrame,
	})

	local selectListCorner = Instance.new("UICorner")
	selectListCorner.CornerRadius = UDim.new(0, 12)
	selectListCorner.Parent = ui.SelectList

	local selectLayout = Instance.new("UIListLayout")
	selectLayout.Padding = UDim.new(0, 8)
	selectLayout.Parent = ui.SelectList

	ui.SelectConfirm = create_button(selectFrame, "SelectConfirm", {
		Position = UDim2.new(0, 0, 1, -44),
		Size = UDim2.fromOffset(156, 40),
		Text = "Join",
	})

	ui.SelectCancel = create_button(selectFrame, "SelectCancel", {
		BackgroundColor3 = Color3.fromRGB(54, 61, 68),
		Position = UDim2.new(1, -156, 1, -44),
		Size = UDim2.fromOffset(156, 40),
		Text = "Back",
	})

	ui.BoardTitle = create_label(boardFrame, "BoardTitle", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "Leaderboard",
		TextSize = 17,
	})

	ui.BoardSubtitle = create_label(boardFrame, "BoardSubtitle", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 0, 24),
		Text = "",
		TextSize = 12,
		TextColor3 = Color3.fromRGB(164, 173, 184),
	})
	ui.BoardSubtitle.Visible = false

	ui.BoardList = create_instance("Frame", {
		Name = "BoardList",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 34),
		Size = UDim2.new(1, 0, 1, -34),
		Parent = boardFrame,
	})

	local boardLayout = Instance.new("UIListLayout")
	boardLayout.Padding = UDim.new(0, 8)
	boardLayout.Parent = ui.BoardList

	ui.ResultLabel = create_label(resultFrame, "ResultLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		TextWrapped = true,
		Text = "Race results.",
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	})

	ui.SelectCancel.MouseButton1Click:Connect(function()
		ui.SelectFrame.Visible = false
		if not state.LocalJoined then
		end
	end)

	ui.SelectConfirm.MouseButton1Click:Connect(function()
		if requestInFlight or not selectedHorseId then
			return
		end

		submit_join_request(selectedHorseId)
	end)

	ui.SelectFrame.Visible = false
	ui.BoardFrame.Visible = false
	ui.ResultFrame.Visible = false
end

update_visibility = function()
	local now = os.clock()
	local inviteActive = state.RoundId ~= nil and now < state.InviteDeadline and state.Phase ~= "Race"
	local hasResult = state.Result ~= nil and now < state.ResultDeadline

	ui.BoardFrame.Visible = (state.LocalJoined or state.LocalWatchingRace or hasResult) and #state.Entries > 0
	ui.ResultFrame.Visible = hasResult

	local shouldShowSelect = ui.SelectFrame.Visible and inviteActive and not state.LocalJoined
	ui.SelectFrame.Visible = shouldShowSelect
end

update_dynamic_text = function()
	local now = os.clock()
	local resultRemaining = math.max(0, state.ResultDeadline - now)
	local inviteNotice = state.NoticeText

	ui.SelectMeta.Text = inviteNotice ~= ""
		and inviteNotice
		or "Only horses above 50% can race."

	if state.Result and resultRemaining > 0 and state.Result.Winner then
		local winner = state.Result.Winner
		ui.ResultLabel.Text = ("%s won with %s in %.2fs and earned %d Horseshoes.")
			:format(
				winner.PlayerName or "Player",
				winner.HorseName or "Horse",
				(winner.FinishTimeMs or 0) / 1000,
				winner.Reward or 0
			)
	end
end

local function handle_invite(payload)
	state.Phase = "Invite"
	state.RoundId = payload.RoundId
	state.InviteDeadline = os.clock() + math.max(0, payload.SecondsRemaining or 0)
	state.HorseOptions = payload.HorseOptions or {}
	state.Entries = payload.Entries or state.Entries
	state.LocalJoined = false
	state.LocalWatchingRace = false
	state.Result = nil
	state.ResultDeadline = 0
	state.NoticeText = ""
	selectedHorseId = nil
	refresh_horse_options()
	sync_race_visuals()
	update_visibility()
	update_dynamic_text()
	show_race_invite_notification()
end

local function handle_queue_update(payload)
	if state.RoundId and payload.RoundId ~= state.RoundId then
		return
	end

	state.RoundId = payload.RoundId
	state.InviteDeadline = os.clock() + math.max(0, payload.SecondsRemaining or 0)
	state.Entries = payload.Entries or {}
	state.NoticeText = ""

	local localEntry = find_local_entry()
	state.LocalJoined = localEntry ~= nil

	if state.LocalJoined then
		state.Phase = "Queue"
		if payload.CameraCFrame and not state.CameraLocked then
			lock_camera(payload.CameraCFrame, false)
		end
	elseif state.Phase ~= "Race" and state.Phase ~= "Result" then
		state.LocalWatchingRace = false
		state.Phase = os.clock() < state.InviteDeadline and "Invite" or "Idle"
		unlock_camera()
	end

	refresh_leaderboard()
	sync_race_visuals()
	update_visibility()
	update_dynamic_text()
end

local function handle_race_started(payload)
	if state.RoundId and payload.RoundId ~= state.RoundId then
		return
	end

	state.RoundId = payload.RoundId
	state.Phase = "Race"
	state.Entries = payload.Entries or {}
	state.LocalWatchingRace = find_local_entry() ~= nil
	state.LocalJoined = state.LocalWatchingRace
	state.CameraSpeed = payload.CameraSpeed or RaceConfig.CameraSpeed
	state.CameraDistance = payload.Distance or RaceConfig.RaceDistance
	state.NoticeText = ""
	ui.SelectFrame.Visible = false
	hide_race_invite_notification()

	if state.LocalWatchingRace and payload.CameraCFrame then
		lock_camera(payload.CameraCFrame, true)
	else
		unlock_camera()
	end

	refresh_leaderboard()
	sync_race_visuals()
	update_visibility()
	update_dynamic_text()
end

local function handle_race_status(payload)
	if state.RoundId and payload.RoundId ~= state.RoundId then
		return
	end

	state.Entries = payload.Entries or {}
	state.LocalWatchingRace = find_local_entry() ~= nil
	refresh_leaderboard()
	sync_race_visuals()
	update_visibility()
	update_dynamic_text()
end

local function handle_result(payload)
	if state.RoundId and payload.RoundId ~= state.RoundId then
		return
	end

	local shouldShowResult = find_local_entry() ~= nil
		or state.LocalJoined
		or state.LocalWatchingRace
		or (payload.Winner and payload.Winner.UserId == localPlayer.UserId)

	if not shouldShowResult then
		state.Phase = "Idle"
		state.RoundId = nil
		state.Entries = {}
		state.Result = nil
		state.ResultDeadline = 0
		sync_race_visuals()
		update_visibility()
		update_dynamic_text()
		return
	end

	state.Phase = "Result"
	state.Result = payload
	state.ResultDeadline = os.clock() + math.max(0, payload.Duration or 0)
	state.Entries = payload.Entries or state.Entries
	state.LocalJoined = false
	state.LocalWatchingRace = find_local_entry() ~= nil or (payload.Winner and payload.Winner.UserId == localPlayer.UserId)
	state.CameraMoving = false
	state.NoticeText = ""
	hide_race_invite_notification()

	refresh_leaderboard()
	sync_race_visuals()
	update_visibility()
	update_dynamic_text()
end

local function handle_reset(payload)
	if state.RoundId and payload.RoundId and payload.RoundId ~= state.RoundId then
		return
	end

	reset_state()
	destroy_existing_rows()
	destroy_existing_horse_buttons()
	sync_race_visuals()
	update_visibility()
	update_dynamic_text()
end

build_ui()
update_visibility()
update_dynamic_text()

Net.Event.RaceState:Connect(function(payload)
	if type(payload) ~= "table" or not payload.Kind then
		return
	end

	if payload.Kind == "InviteOpened" then
		handle_invite(payload)
	elseif payload.Kind == "QueueUpdated" then
		handle_queue_update(payload)
	elseif payload.Kind == "RaceStarted" then
		handle_race_started(payload)
	elseif payload.Kind == "RaceStatus" then
		handle_race_status(payload)
	elseif payload.Kind == "Result" then
		handle_result(payload)
	elseif payload.Kind == "Reset" then
		handle_reset(payload)
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
	local now = os.clock()

	for _, visual in pairs(raceVisuals.ByUserId) do
		if visual.Model and visual.Model.Parent then
			update_race_visual_motion(visual, deltaTime, now)
		end
	end

	if state.CameraLocked and state.CameraBaseCFrame and state.CameraRotation then
		local camera = Workspace.CurrentCamera
		if camera then
			if state.CameraMoving then
				state.CameraProgress = math.min(
					state.CameraDistance,
					state.CameraProgress + state.CameraSpeed * deltaTime
				)
			end

			local basePosition = state.CameraBaseCFrame.Position
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.new(
				basePosition.X,
				basePosition.Y,
				basePosition.Z - state.CameraProgress
			) * state.CameraRotation
		end
	end

	if state.Result and os.clock() >= state.ResultDeadline and state.Phase == "Result" then
		state.Result = nil
	end

	if state.Phase == "Invite" and os.clock() >= state.InviteDeadline and not state.LocalJoined then
		hide_race_invite_notification()
		state.Phase = "Idle"
		sync_race_visuals()
	end

	update_race_invite_countdown()
	update_visibility()
	update_dynamic_text()
end)
