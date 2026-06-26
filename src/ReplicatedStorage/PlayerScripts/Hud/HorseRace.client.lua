local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")

local Net = require(Libraries:WaitForChild("Net"))
local RaceConfig = require(GameData:WaitForChild("RaceConfig"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local CONTROL_ACTION_NAME = "HorseRaceLockControls"

local requestInFlight = false
local rowFrames = {}
local horseButtons = {}
local selectedHorseId = nil
local previousCameraType = nil
local previousCameraSubject = nil

local state = {
	Phase = "Idle",
	RoundId = nil,
	InviteDeadline = 0,
	ResultDeadline = 0,
	InviteDismissed = false,
	LocalJoined = false,
	LocalWatchingRace = false,
	HorseOptions = {},
	Entries = {},
	Result = nil,
	CameraLocked = false,
	CameraMoving = false,
	CameraBaseCFrame = nil,
	CameraRotation = nil,
	CameraSpeed = RaceConfig.CameraSpeed,
	CameraProgress = 0,
	CameraDistance = RaceConfig.RaceDistance,
}

local ui = {}

local function extract_rotation(cframe)
	return CFrame.fromMatrix(Vector3.zero, cframe.XVector, cframe.YVector, cframe.ZVector)
end

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

local function format_countdown(seconds)
	local clamped = math.max(0, math.floor(seconds + 0.999))
	return ("%02d:%02d"):format(math.floor(clamped / 60), clamped % 60)
end

local function find_local_entry()
	for _, entry in ipairs(state.Entries) do
		if entry.UserId == localPlayer.UserId then
			return entry
		end
	end

	return nil
end

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
	state.Phase = "Idle"
	state.RoundId = nil
	state.InviteDeadline = 0
	state.ResultDeadline = 0
	state.InviteDismissed = false
	state.LocalJoined = false
	state.LocalWatchingRace = false
	state.HorseOptions = {}
	state.Entries = {}
	state.Result = nil
	state.CameraSpeed = RaceConfig.CameraSpeed
	state.CameraDistance = RaceConfig.RaceDistance
	selectedHorseId = nil

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
		local selected = horseId == selectedHorseId
		button.BackgroundColor3 = selected and Color3.fromRGB(52, 122, 94) or Color3.fromRGB(27, 31, 36)
	end
end

local function refresh_horse_options()
	destroy_existing_horse_buttons()

	for _, horse in ipairs(state.HorseOptions) do
		local title = horse.Name or horse.DisplayName or horse.Id
		local stats = ("%s wins:%d affinity:%.2f"):format(
			horse.DisplayName or horse.CatalogId or "Horse",
			horse.RacesWon or 0,
			horse.RaceAffinity or 0
		)

		local button = create_button(ui.SelectList, horse.Id, {
			BackgroundColor3 = Color3.fromRGB(27, 31, 36),
			Size = UDim2.new(1, 0, 0, 52),
			Text = "",
		})

		create_label(button, "HorseName", {
			Size = UDim2.new(1, -14, 0.52, 0),
			Position = UDim2.new(0, 8, 0, 4),
			Text = title .. (horse.IsEquipped and "  [equipado]" or ""),
			TextSize = 15,
		})

		create_label(button, "HorseMeta", {
			Size = UDim2.new(1, -14, 0.36, 0),
			Position = UDim2.new(0, 8, 0.6, -1),
			Text = stats,
			TextSize = 12,
			TextColor3 = Color3.fromRGB(164, 173, 184),
		})

		button.MouseButton1Click:Connect(function()
			selectedHorseId = horse.Id
			update_horse_selection_visuals()
		end)

		horseButtons[horse.Id] = button
	end

	if not selectedHorseId and state.HorseOptions[1] then
		selectedHorseId = state.HorseOptions[1].Id
	end

	update_horse_selection_visuals()
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
			state.InviteDismissed = false
		else
			state.Phase = "Idle"
		end
		unlock_camera()
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
		state.LocalJoined = true
		state.Phase = "Queue"
		state.InviteDismissed = true
		ui.SelectFrame.Visible = false
		if response.CameraCFrame then
			lock_camera(response.CameraCFrame, false)
		end
		update_visibility()
		update_dynamic_text()
		return
	end

	if response.Code == "HorseSelectionRequired" then
		state.HorseOptions = response.HorseOptions or state.HorseOptions
		refresh_horse_options()
		ui.SelectFrame.Visible = true
	elseif response.Code == "InviteExpired" or response.Code == "InviteClosed" or response.Code == "NoActiveRound" then
		reset_state()
		destroy_existing_rows()
		update_visibility()
		update_dynamic_text()
	end
end

local function build_ui()
	local screenGui = create_instance("ScreenGui", {
		Name = "HorseRaceHud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = playerGui,
	})

	local commandBar = create_instance("Frame", {
		Name = "CommandBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(760, 116),
		Parent = screenGui,
	})
	apply_panel_style(commandBar, Color3.fromRGB(115, 224, 170))

	local inviteFrame = create_instance("Frame", {
		Name = "InviteFrame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -28),
		Size = UDim2.fromOffset(520, 214),
		Parent = screenGui,
	})
	apply_panel_style(inviteFrame, Color3.fromRGB(233, 182, 96))

	local selectFrame = create_instance("Frame", {
		Name = "SelectFrame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, -18),
		Size = UDim2.fromOffset(560, 360),
		Parent = screenGui,
	})
	apply_panel_style(selectFrame, Color3.fromRGB(115, 224, 170))

	local boardFrame = create_instance("Frame", {
		Name = "BoardFrame",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -18, 0, 18),
		Size = UDim2.fromOffset(320, 270),
		Parent = screenGui,
	})
	apply_panel_style(boardFrame, Color3.fromRGB(115, 224, 170))

	local resultFrame = create_instance("Frame", {
		Name = "ResultFrame",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 18),
		Size = UDim2.fromOffset(520, 92),
		Parent = screenGui,
	})
	apply_panel_style(resultFrame, Color3.fromRGB(233, 182, 96))

	ui.ScreenGui = screenGui
	ui.CommandBar = commandBar
	ui.InviteFrame = inviteFrame
	ui.SelectFrame = selectFrame
	ui.BoardFrame = boardFrame
	ui.ResultFrame = resultFrame

	ui.CommandTitle = create_label(commandBar, "Title", {
		Size = UDim2.new(0.55, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "> horse_race -- idle",
		TextSize = 15,
	})

	ui.CommandCountdown = create_label(commandBar, "Countdown", {
		Size = UDim2.new(0, 120, 0, 20),
		Position = UDim2.new(1, -120, 0, 0),
		Text = "00:00",
		TextSize = 17,
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	ui.CommandStatus = create_label(commandBar, "Status", {
		Size = UDim2.new(1, -220, 0, 30),
		Position = UDim2.new(0, 0, 0, 26),
		Text = "Aguardando proxima corrida.",
		TextSize = 22,
	})

	ui.CommandMeta = create_label(commandBar, "Meta", {
		Size = UDim2.new(1, -220, 0, 18),
		Position = UDim2.new(0, 0, 0, 62),
		Text = "Slots: 0/0",
		TextSize = 14,
		TextColor3 = Color3.fromRGB(164, 173, 184),
	})

	ui.CommandHint = create_label(commandBar, "Hint", {
		Size = UDim2.new(1, -220, 0, 18),
		Position = UDim2.new(0, 0, 0, 84),
		Text = "A corrida anda apenas no eixo Z.",
		TextSize = 13,
		TextColor3 = Color3.fromRGB(110, 118, 129),
	})

	ui.CommandAction = create_button(commandBar, "Action", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, 0, 1, 0),
		Size = UDim2.fromOffset(176, 40),
		Text = "Participar",
	})

	ui.InviteTitle = create_label(inviteFrame, "InviteTitle", {
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "> corrida disponivel",
		TextSize = 18,
	})

	ui.InviteBody = create_label(inviteFrame, "InviteBody", {
		Size = UDim2.new(1, 0, 0, 66),
		Position = UDim2.new(0, 0, 0, 34),
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "Seu cavalo entra no slot livre, a camera trava em Race.Camera e a largada sai em 20s.",
		TextSize = 18,
	})

	ui.InviteCountdown = create_label(inviteFrame, "InviteCountdown", {
		Size = UDim2.new(1, 0, 0, 20),
		Position = UDim2.new(0, 0, 0, 112),
		Text = "Fecha em 00:20",
		TextSize = 15,
	})

	ui.InviteMeta = create_label(inviteFrame, "InviteMeta", {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 136),
		Text = "Slots confirmados: 0/0",
		TextSize = 13,
		TextColor3 = Color3.fromRGB(164, 173, 184),
	})

	ui.InviteJoin = create_button(inviteFrame, "InviteJoin", {
		Position = UDim2.new(0, 0, 1, -44),
		Size = UDim2.fromOffset(174, 40),
		Text = "Participar",
	})

	ui.InviteClose = create_button(inviteFrame, "InviteClose", {
		BackgroundColor3 = Color3.fromRGB(54, 61, 68),
		Position = UDim2.new(1, -174, 1, -44),
		Size = UDim2.fromOffset(160, 40),
		Text = "Fechar",
	})

	ui.SelectTitle = create_label(selectFrame, "SelectTitle", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "> escolha o cavalo",
		TextSize = 18,
	})

	ui.SelectMeta = create_label(selectFrame, "SelectMeta", {
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0, 28),
		Text = "Se voce tem um cavalo so, entra direto.",
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
		Size = UDim2.new(1, 0, 1, -116),
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
		Size = UDim2.fromOffset(196, 40),
		Text = "Confirmar cavalo",
	})

	ui.SelectCancel = create_button(selectFrame, "SelectCancel", {
		BackgroundColor3 = Color3.fromRGB(54, 61, 68),
		Position = UDim2.new(1, -176, 1, -44),
		Size = UDim2.fromOffset(176, 40),
		Text = "Voltar",
	})

	ui.BoardTitle = create_label(boardFrame, "BoardTitle", {
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "> placar da corrida",
		TextSize = 17,
	})

	ui.BoardSubtitle = create_label(boardFrame, "BoardSubtitle", {
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 0, 24),
		Text = "Atualiza conforme os cavalos trocam de ritmo.",
		TextSize = 12,
		TextColor3 = Color3.fromRGB(164, 173, 184),
	})

	ui.BoardList = create_instance("Frame", {
		Name = "BoardList",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 1, -52),
		Parent = boardFrame,
	})

	local boardLayout = Instance.new("UIListLayout")
	boardLayout.Padding = UDim.new(0, 8)
	boardLayout.Parent = ui.BoardList

	ui.ResultLabel = create_label(resultFrame, "ResultLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		TextWrapped = true,
		Text = "Resultado da corrida.",
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
	})

	ui.CommandAction.MouseButton1Click:Connect(function()
		if requestInFlight then
			return
		end

		if state.LocalJoined and state.Phase == "Queue" then
			submit_leave_request()
			return
		end

		if #state.HorseOptions <= 1 then
			submit_join_request(state.HorseOptions[1] and state.HorseOptions[1].Id or nil)
			return
		end

		ui.SelectFrame.Visible = true
		state.InviteDismissed = true
	end)

	ui.InviteJoin.MouseButton1Click:Connect(function()
		if #state.HorseOptions <= 1 then
			submit_join_request(state.HorseOptions[1] and state.HorseOptions[1].Id or nil)
		else
			ui.SelectFrame.Visible = true
			state.InviteDismissed = true
		end
	end)

	ui.InviteClose.MouseButton1Click:Connect(function()
		state.InviteDismissed = true
	end)

	ui.SelectCancel.MouseButton1Click:Connect(function()
		ui.SelectFrame.Visible = false
		if not state.LocalJoined then
			state.InviteDismissed = false
		end
	end)

	ui.SelectConfirm.MouseButton1Click:Connect(function()
		if requestInFlight or not selectedHorseId then
			return
		end

		submit_join_request(selectedHorseId)
	end)

	ui.CommandBar.Visible = false
	ui.InviteFrame.Visible = false
	ui.SelectFrame.Visible = false
	ui.BoardFrame.Visible = false
	ui.ResultFrame.Visible = false
end

local function update_visibility()
	local now = os.clock()
	local inviteActive = state.RoundId ~= nil and now < state.InviteDeadline and state.Phase ~= "Race"
	local hasResult = state.Result ~= nil and now < state.ResultDeadline
	local shouldShowBar = inviteActive or state.LocalJoined or state.LocalWatchingRace or hasResult

	ui.CommandBar.Visible = shouldShowBar
	ui.InviteFrame.Visible = inviteActive and not state.LocalJoined and not state.InviteDismissed and not ui.SelectFrame.Visible
	ui.BoardFrame.Visible = (state.LocalJoined or state.LocalWatchingRace or hasResult) and #state.Entries > 0
	ui.ResultFrame.Visible = hasResult

	local shouldShowSelect = ui.SelectFrame.Visible and inviteActive and not state.LocalJoined
	ui.SelectFrame.Visible = shouldShowSelect
end

local function update_dynamic_text()
	local now = os.clock()
	local localEntry = find_local_entry()
	local participantCount = #state.Entries
	local inviteRemaining = math.max(0, state.InviteDeadline - now)
	local resultRemaining = math.max(0, state.ResultDeadline - now)

	if state.Phase == "Race" then
		ui.CommandTitle.Text = "> horse_race -- race_live"
		ui.CommandStatus.Text = localEntry
			and ("Seu cavalo: %s | slot %d"):format(localEntry.HorseName or "Horse", localEntry.SlotIndex or 0)
			or "Corrida em andamento."
		ui.CommandMeta.Text = ("Participantes: %d | distancia: %d studs"):format(participantCount, RaceConfig.RaceDistance)
		ui.CommandHint.Text = "Velocidade muda suavemente a cada 30 studs para forcar ultrapassagens."
		ui.CommandCountdown.Text = "LIVE"
		ui.CommandAction.Visible = false
	elseif state.Phase == "Queue" then
		ui.CommandTitle.Text = "> horse_race -- staging"
		ui.CommandStatus.Text = localEntry
			and ("Aguardando largada com %s no slot %d."):format(localEntry.HorseName or "Horse", localEntry.SlotIndex or 0)
			or "Aguardando largada."
		ui.CommandMeta.Text = ("Confirmados: %d | max: %d"):format(participantCount, RaceConfig.MaxParticipants)
		ui.CommandHint.Text = "A camera ja esta presa em Race.Camera; a largada sai quando o contador zerar."
		ui.CommandCountdown.Text = format_countdown(inviteRemaining)
		ui.CommandAction.Visible = inviteRemaining > 0
		ui.CommandAction.Text = "Sair da fila"
	elseif state.Phase == "Invite" then
		ui.CommandTitle.Text = "> horse_race -- invite_open"
		ui.CommandStatus.Text = "Tem corrida aberta. Seu cavalo vai correr 220 studs no eixo Z."
		ui.CommandMeta.Text = ("Confirmados: %d | cavalos: %d"):format(participantCount, #state.HorseOptions)
		ui.CommandHint.Text = "Se tiver mais de um cavalo, voce escolhe antes de entrar."
		ui.CommandCountdown.Text = format_countdown(inviteRemaining)
		ui.CommandAction.Visible = true
		ui.CommandAction.Text = "Participar"
	elseif state.Result and resultRemaining > 0 then
		ui.CommandTitle.Text = "> horse_race -- result"
		ui.CommandStatus.Text = ui.ResultLabel.Text
		ui.CommandMeta.Text = ("Encerrando em %s"):format(format_countdown(resultRemaining))
		ui.CommandHint.Text = "Os assets e a camera voltam ao normal quando esse timer fechar."
		ui.CommandCountdown.Text = format_countdown(resultRemaining)
		ui.CommandAction.Visible = false
	else
		ui.CommandTitle.Text = "> horse_race -- idle"
		ui.CommandStatus.Text = "Aguardando proxima corrida."
		ui.CommandMeta.Text = "O proximo convite abre automaticamente."
		ui.CommandHint.Text = "A corrida anda apenas diminuindo Z, com camera em ritmo constante."
		ui.CommandCountdown.Text = "00:00"
		ui.CommandAction.Visible = false
	end

	ui.InviteCountdown.Text = ("Fecha em %s"):format(format_countdown(inviteRemaining))
	ui.InviteMeta.Text = ("Slots confirmados: %d/%d"):format(participantCount, RaceConfig.MaxParticipants)
	ui.InviteBody.Text = (#state.HorseOptions <= 1)
		and "Seu cavalo entra direto no primeiro slot vago e espera a largada com a camera travada na pista."
		or "Voce tem mais de um cavalo. Escolha qual entra no slot antes da largada para evitar erro no join."

	if state.Result and resultRemaining > 0 and state.Result.Winner then
		local winner = state.Result.Winner
		ui.ResultLabel.Text = ("%s venceu com %s em %.2fs e ganhou %d Horseshoes.")
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
	state.InviteDismissed = false
	state.LocalJoined = false
	state.LocalWatchingRace = false
	state.Result = nil
	state.ResultDeadline = 0
	selectedHorseId = nil
	refresh_horse_options()
	update_visibility()
	update_dynamic_text()
end

local function handle_queue_update(payload)
	if state.RoundId and payload.RoundId ~= state.RoundId then
		return
	end

	state.RoundId = payload.RoundId
	state.InviteDeadline = os.clock() + math.max(0, payload.SecondsRemaining or 0)
	state.Entries = payload.Entries or {}

	local localEntry = find_local_entry()
	state.LocalJoined = localEntry ~= nil

	if state.LocalJoined then
		state.Phase = "Queue"
		state.InviteDismissed = true
		if payload.CameraCFrame and not state.CameraLocked then
			lock_camera(payload.CameraCFrame, false)
		end
	elseif state.Phase ~= "Race" and state.Phase ~= "Result" then
		state.LocalWatchingRace = false
		state.Phase = os.clock() < state.InviteDeadline and "Invite" or "Idle"
		unlock_camera()
	end

	refresh_leaderboard()
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
	state.InviteDismissed = true
	ui.SelectFrame.Visible = false

	if state.LocalWatchingRace and payload.CameraCFrame then
		lock_camera(payload.CameraCFrame, true)
	else
		unlock_camera()
	end

	refresh_leaderboard()
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

	refresh_leaderboard()
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
		state.Phase = "Idle"
		state.InviteDismissed = false
	end

	update_visibility()
	update_dynamic_text()
end)
