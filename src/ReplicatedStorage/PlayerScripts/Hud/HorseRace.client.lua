local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")
local HudModules = ClientModules:WaitForChild("Hud")

local Net = require(Libraries:WaitForChild("Net"))
local RaceConfig = require(GameData:WaitForChild("RaceConfig"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local RaceVisualFactory = require(Utility:WaitForChild("RaceVisualFactory"))
local HorseRaceVisuals = require(HudModules:WaitForChild("HorseRaceVisuals"))
local Notifications = require(HudModules:WaitForChild("Notifications"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local CONTROL_ACTION_NAME = "HorseRaceLockControls"
local RACE_INVITE_NOTIFICATION_ID = "HorseRaceInvite"
local HORSESHOE_ICON = "rbxassetid://113664849235987"
local requestInFlight = false
local rowFrames = {}
local selectedHorseId = nil
local lastInviteCountdownSecond = nil
local previousCameraType = nil
local previousCameraSubject = nil
local update_visibility
local update_dynamic_text
local open_race_invitation
local show_race_invite_notification
local leaderboardVisible = true
local raceStartedAt = nil
local lastRenderedResult = nil
local raceUiFocusActive = false
local hiddenGuiStates = {}
local hiddenBlurStates = {}

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
	raceStartedAt = nil
	lastRenderedResult = nil

	clear_race_visuals()
	unlock_camera()
end

local function destroy_existing_rows()
	for userId, row in pairs(rowFrames) do
		row:Destroy()
		rowFrames[userId] = nil
	end
end

local function find_named(root, name, className)
	if not root then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == name and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function find_all_named(root, name, className)
	local matches = {}
	if not root then
		return matches
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant.Name == name and (not className or descendant:IsA(className)) then
			matches[#matches + 1] = descendant
		end
	end

	return matches
end

local function set_text(instance, text)
	if instance and (instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox")) then
		instance.Text = text
	end
end

local function set_visible(instance, visible)
	if instance and instance:IsA("GuiObject") then
		instance.Visible = visible
	end
end

local function get_ancestor_screen_gui(instance)
	local current = instance
	while current do
		if current:IsA("ScreenGui") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function set_race_ui_focus(enabled)
	if raceUiFocusActive == enabled then
		return
	end
	raceUiFocusActive = enabled

	if enabled then
		local raceScreenGui = get_ancestor_screen_gui(ui.ActionArena)
		for _, child in ipairs(playerGui:GetChildren()) do
			if child:IsA("ScreenGui") and child ~= raceScreenGui then
				hiddenGuiStates[child] = child.Enabled
				child.Enabled = false
			end
		end

		local frames = ui.ActionArena and ui.ActionArena.Parent
		if frames then
			for _, child in ipairs(frames:GetChildren()) do
				if child ~= ui.ActionArena and child:IsA("GuiObject") then
					hiddenGuiStates[child] = child.Visible
					child.Visible = false
				end
			end
		end

		if ui.HudRoot and not ui.ActionArena:IsDescendantOf(ui.HudRoot) then
			hiddenGuiStates[ui.HudRoot] = ui.HudRoot.Visible
			ui.HudRoot.Visible = false
		end

		for _, effect in ipairs(Lighting:GetDescendants()) do
			if effect:IsA("BlurEffect") then
				hiddenBlurStates[effect] = effect.Enabled
				effect.Enabled = false
			end
		end
		return
	end

	for instance, wasVisible in pairs(hiddenGuiStates) do
		if instance.Parent then
			if instance:IsA("ScreenGui") then
				instance.Enabled = wasVisible
			elseif instance:IsA("GuiObject") then
				instance.Visible = wasVisible
			end
		end
		hiddenGuiStates[instance] = nil
	end

	for effect, wasEnabled in pairs(hiddenBlurStates) do
		if effect.Parent then
			effect.Enabled = wasEnabled
		end
		hiddenBlurStates[effect] = nil
	end
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

local function render_horse_viewport(viewport, entry)
	if not viewport or not entry then
		return
	end

	clear_viewport(viewport)
	local model = RaceVisualFactory.CreateRaceModel(entry, nil)
	if not model then
		return
	end

	local worldModel = Instance.new("WorldModel")
	model.Parent = worldModel
	worldModel.Parent = viewport

	local boxCFrame, boxSize = model:GetBoundingBox()
	local focus = boxCFrame.Position + Vector3.new(0, boxSize.Y * 0.1, 0)
	local distance = math.max(boxSize.X, boxSize.Y, boxSize.Z) * 1.45
	local camera = Instance.new("Camera")
	camera.FieldOfView = 32
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(boxSize.X * 0.28, boxSize.Y * 0.08, distance), focus)
	camera.Parent = viewport
	viewport.BackgroundTransparency = 1
	viewport.CurrentCamera = camera
end

local function render_player_viewport(viewport, userId)
	if not viewport then
		return
	end

	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	if not character then
		return
	end

	local previousArchivable = character.Archivable
	character.Archivable = true
	local success, characterClone = pcall(function()
		return character:Clone()
	end)
	character.Archivable = previousArchivable
	if not success or not characterClone then
		return
	end

	clear_viewport(viewport)
	for _, descendant in ipairs(characterClone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("Animator") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CastShadow = false
		end
	end

	local worldModel = Instance.new("WorldModel")
	characterClone.Parent = worldModel
	worldModel.Parent = viewport

	local boxCFrame, boxSize = characterClone:GetBoundingBox()
	local boxOffset = characterClone:GetPivot():ToObjectSpace(boxCFrame)
	characterClone:PivotTo(CFrame.new(0, boxSize.Y * 0.5, 0) * boxOffset:Inverse())
	boxCFrame, boxSize = characterClone:GetBoundingBox()

	local focus = boxCFrame.Position + Vector3.new(0, boxSize.Y * 0.08, 0)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 34
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(boxSize.X * 0.34, boxSize.Y * 0.08, -math.max(5.8, boxSize.Y * 1.7)), focus)
	camera.Parent = viewport
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(210, 210, 210)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.CurrentCamera = camera
end

local function get_reward_item_source(itemDefinition)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local itemsFolder = assets and assets:FindFirstChild("Items")
	if not itemsFolder or not itemDefinition then
		return nil
	end

	for _, name in ipairs({ itemDefinition.ItemId, itemDefinition.ToolName, itemDefinition.DisplayName }) do
		if type(name) == "string" and name ~= "" then
			local source = itemsFolder:FindFirstChild(name, true)
			if source then
				return source
			end
		end
	end

	return nil
end

local function render_reward_item_viewport(viewport, itemId)
	if not viewport then
		return
	end

	clear_viewport(viewport)
	local definition = ToolItemCatalog.GetItemDefinition(itemId)
	local source = get_reward_item_source(definition)
	if not source then
		return
	end

	local sourceClone = source:Clone()
	for _, descendant in ipairs(sourceClone:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end

	local model = sourceClone
	if not model:IsA("Model") then
		model = Instance.new("Model")
		model.Name = sourceClone.Name
		if sourceClone:IsA("BasePart") then
			sourceClone.Parent = model
		else
			for _, child in ipairs(sourceClone:GetChildren()) do
				child.Parent = model
			end
			sourceClone:Destroy()
		end
	end

	local hasParts = false
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			hasParts = true
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
		end
	end
	if not hasParts then
		model:Destroy()
		return
	end

	model:PivotTo(CFrame.new())
	local worldModel = Instance.new("WorldModel")
	model.Parent = worldModel
	worldModel.Parent = viewport

	local boxCFrame, boxSize = model:GetBoundingBox()
	local focus = boxCFrame.Position
	local distance = math.max(2.5, math.max(boxSize.X, boxSize.Y, boxSize.Z) * 1.7)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(distance * 0.35, distance * 0.2, distance), focus)
	camera.Parent = viewport
	viewport.BackgroundTransparency = 1
	viewport.CurrentCamera = camera
end

local function get_or_create_reward_text(slot)
	local textLabel = slot:FindFirstChild("RaceRewardText")
	if textLabel and textLabel:IsA("TextLabel") then
		return textLabel
	end

	textLabel = Instance.new("TextLabel")
	textLabel.Name = "RaceRewardText"
	textLabel.AnchorPoint = Vector2.new(0.5, 1)
	textLabel.BackgroundColor3 = Color3.fromRGB(24, 18, 12)
	textLabel.BackgroundTransparency = 0.22
	textLabel.BorderSizePixel = 0
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextColor3 = Color3.fromRGB(255, 244, 214)
	textLabel.TextScaled = true
	textLabel.TextWrapped = true
	textLabel.Position = UDim2.new(0.5, 0, 1, -2)
	textLabel.Size = UDim2.new(1, -8, 0, 28)
	textLabel.ZIndex = slot.ZIndex + 10
	textLabel.Parent = slot

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = textLabel
	return textLabel
end

local function get_or_create_reward_icon(slot)
	local icon = slot:FindFirstChild("RaceRewardIcon")
	if icon and icon:IsA("ImageLabel") then
		return icon
	end

	icon = Instance.new("ImageLabel")
	icon.Name = "RaceRewardIcon"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.BackgroundTransparency = 1
	icon.Image = HORSESHOE_ICON
	icon.Position = UDim2.new(0.5, 0, 0.43, 0)
	icon.Size = UDim2.fromOffset(54, 54)
	icon.ZIndex = slot.ZIndex + 9
	icon.Parent = slot
	return icon
end

local function render_result_rewards(resultPanel, entry)
	local rewardsRoot = find_named(resultPanel, "Rewards")
	if not rewardsRoot then
		return
	end

	local reward = state.Result
		and state.Result.RewardsByUserId
		and state.Result.RewardsByUserId[localPlayer.UserId]
		or (entry and entry.Reward)
	local rewards = {
		{ Text = ("%d Horseshoes"):format(math.max(0, tonumber(reward and reward.Horseshoes) or 0)) },
	}
	for _, itemReward in ipairs(reward and reward.Items or {}) do
		local definition = ToolItemCatalog.GetItemDefinition(itemReward.ItemId)
		rewards[#rewards + 1] = {
			ItemId = itemReward.ItemId,
			Text = ("%s x%d"):format(
				definition and definition.DisplayName or itemReward.ItemId,
				math.max(1, math.floor(tonumber(itemReward.Amount) or 1))
			),
		}
	end

	for index, slot in ipairs(find_all_named(rewardsRoot, "ItemDisplayBG", "GuiObject")) do
		local rewardEntry = rewards[index]
		set_visible(slot, rewardEntry ~= nil)
		if rewardEntry then
			local viewport = find_named(slot, "ViewportFrame", "ViewportFrame")
			local icon = get_or_create_reward_icon(slot)
			if rewardEntry.ItemId then
				icon.Visible = false
				render_reward_item_viewport(viewport, rewardEntry.ItemId)
			elseif viewport then
				icon.Visible = true
				clear_viewport(viewport)
			else
				icon.Visible = true
			end
			get_or_create_reward_text(slot).Text = rewardEntry.Text
		end
	end
end

local function refresh_leaderboard()
	if not ui.BoardList or not ui.TemplateCraft then
		return
	end

	local activeRows = {}
	for index, entry in ipairs(state.Entries) do
		local row = rowFrames[entry.UserId]
		if not row or row.Parent ~= ui.BoardList then
			row = ui.TemplateCraft:Clone()
			row.Name = tostring(entry.UserId)
			row.Visible = true
			row.Parent = ui.BoardList
			render_player_viewport(find_named(row, "ViewportFrame", "ViewportFrame"), entry.UserId)
			rowFrames[entry.UserId] = row
		end

		row.LayoutOrder = index
		row.Visible = true
		set_text(find_named(row, "ItemNameTX"), entry.PlayerName or "Player")
		set_text(find_named(row, "PositionTX"), tostring(entry.Rank or index))
		activeRows[entry.UserId] = true
	end

	for userId, row in pairs(rowFrames) do
		if not activeRows[userId] then
			row:Destroy()
			rowFrames[userId] = nil
		end
	end
end

local function refresh_horse_options()
	selectedHorseId = nil
	for _, horse in ipairs(state.HorseOptions) do
		if horse.CanRace ~= false and horse.IsEquipped then
			selectedHorseId = horse.Id
			return
		end
	end

	for _, horse in ipairs(state.HorseOptions) do
		if horse.CanRace ~= false then
			selectedHorseId = horse.Id
			return
		end
	end
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
		if selectedHorseId and selectedHorseId ~= horseId then
			submit_join_request(selectedHorseId)
		end
	elseif response.Code == "HorseNeedsTooLow" then
		state.HorseOptions = response.HorseOptions or state.HorseOptions
		state.NoticeText = ("%s is at %d%%. It must stay above %d%%."):format(
			get_status_display_name(response.BlockedStatus, response.BlockedStatusDisplay),
			response.BlockedPercent or 0,
			response.MinimumPercent or 50
		)
		selectedHorseId = response.HorseId or selectedHorseId
		refresh_horse_options()
		show_race_invite_notification()
	elseif response.Code == "InviteExpired" or response.Code == "InviteClosed" or response.Code == "NoActiveRound" then
		reset_state()
		destroy_existing_rows()
		update_visibility()
		update_dynamic_text()
	end
end

open_race_invitation = function()
	refresh_horse_options()
	if not selectedHorseId then
		for _, horse in ipairs(state.HorseOptions) do
			if type(horse.Id) == "string" and horse.Id ~= "" then
				selectedHorseId = horse.Id
				break
			end
		end
	end

	if selectedHorseId then
		submit_join_request(selectedHorseId)
	end
end

local function get_unavailable_race_horse()
	for _, horse in ipairs(state.HorseOptions) do
		if horse.CanRace == false then
			return horse
		end
	end

	return nil
end

local function has_race_ready_horse()
	for _, horse in ipairs(state.HorseOptions) do
		if horse.CanRace ~= false then
			return true
		end
	end

	return false
end

local function get_race_invite_details(): string
	if not has_race_ready_horse() then
		local horse = get_unavailable_race_horse()
		if horse then
			local statusName = get_status_display_name(
				horse.RaceBlockedStatus or horse.RaceLowestStatus,
				horse.RaceBlockedStatusDisplay or horse.RaceLowestStatusDisplay
			)
			return ("A corrida abriu, mas %s esta doente: %s em %d%%. Cuide dele para chegar a %d%%.")
				:format(
					horse.Name or horse.DisplayName or "seu cavalo",
					statusName,
					horse.RaceBlockedPercent or horse.RaceLowestPercent or 0,
					horse.RaceMinPercent or 50
				)
		end
	end

	return ("Race registration is open. Closes in %s."):format(format_countdown(state.InviteDeadline - os.clock()))
end

local function get_race_invite_accept_text(): string
	return has_race_ready_horse() and "Join" or "Tentar entrar"
end

local function get_race_invite_title(): string
	return has_race_ready_horse() and "Race available" or "Corrida aberta - cavalo doente"
end

show_race_invite_notification = function()
	if state.Phase ~= "Invite" or not state.RoundId or os.clock() >= state.InviteDeadline then
		return
	end

	lastInviteCountdownSecond = math.ceil(math.max(0, state.InviteDeadline - os.clock()))

	Notifications.ShowDialogue({
		id = RACE_INVITE_NOTIFICATION_ID,
		title = get_race_invite_title(),
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
		title = get_race_invite_title(),
		details = get_race_invite_details(),
		acceptText = get_race_invite_accept_text(),
	})
end

local function bind_ui()
	if ui.ActionArena and ui.ActionArena.Parent then
		return true
	end

	local mainFrame = playerGui:FindFirstChild("MainframeFR", true) or playerGui:FindFirstChild("MainFrameFR", true)
	local actionArena = mainFrame and find_named(mainFrame, "ActionArena", "GuiObject")
	if not actionArena then
		return false
	end

	ui.ActionArena = actionArena
	ui.HudRoot = find_named(mainFrame, "HUDFR", "GuiObject")
	ui.Leaderboard = find_named(actionArena, "Leaderboard", "GuiObject")
	ui.BoardList = find_named(ui.Leaderboard, "ListScrollingFrame", "GuiObject")
	ui.TemplateCraft = ui.BoardList and ui.BoardList:FindFirstChild("TemplateCraft")
	ui.RankingBT = find_named(actionArena, "RankingBT", "GuiButton")
	ui.LossImage = find_named(actionArena, "LossImage", "GuiObject")
	ui.VictoryImage = find_named(actionArena, "VictoryImage", "GuiObject")
	ui.TimeTX = find_named(actionArena, "TimeTX")
	ui.TimeShadowTX = find_named(actionArena, "TimeShadowTX")

	if ui.TemplateCraft then
		ui.TemplateCraft.Visible = false
	end

	if ui.RankingBT then
		ui.RankingBT.MouseButton1Click:Connect(function()
			leaderboardVisible = not leaderboardVisible
			update_visibility()
		end)
	end

	refresh_leaderboard()

	return true
end

local function format_race_time(seconds)
	local wholeSeconds = math.max(0, math.floor(seconds))
	return ("%02d:%02d"):format(math.floor(wholeSeconds / 60), wholeSeconds % 60)
end

local function get_result_entry()
	return find_local_entry() or (state.Result and state.Result.Winner)
end

local function update_result_panel(hasResult)
	if not hasResult or not state.Result or not state.Result.Winner then
		set_visible(ui.LossImage, false)
		set_visible(ui.VictoryImage, false)
		lastRenderedResult = nil
		return
	end
	if lastRenderedResult == state.Result then
		return
	end

	local winner = state.Result.Winner
	local didWin = winner.UserId == localPlayer.UserId
	local resultPanel = didWin and ui.VictoryImage or ui.LossImage
	set_visible(ui.VictoryImage, didWin)
	set_visible(ui.LossImage, not didWin)

	local entry = get_result_entry()
	set_text(find_named(resultPanel, "PositionTX"), ("%d%s Place"):format((entry and entry.Rank) or (didWin and 1 or 0), didWin and "st" or "th"))
	render_result_rewards(resultPanel, entry)
	lastRenderedResult = state.Result
end

local function build_ui()
	bind_ui()
end

update_visibility = function()
	if not bind_ui() then
		return
	end

	local now = os.clock()
	local hasResult = state.Result ~= nil and now < state.ResultDeadline
	local shouldShowArena = state.LocalJoined or state.LocalWatchingRace or hasResult
	set_race_ui_focus(shouldShowArena)
	set_visible(ui.ActionArena, shouldShowArena)
	set_visible(ui.Leaderboard, shouldShowArena and leaderboardVisible and #state.Entries > 0)
	update_result_panel(hasResult)
end

update_dynamic_text = function()
	if not bind_ui() then
		return
	end

	local elapsed = raceStartedAt and (os.clock() - raceStartedAt) or 0
	if state.Result and state.Result.Winner then
		elapsed = (state.Result.Winner.FinishTimeMs or 0) / 1000
	end

	local displayTime = format_race_time(elapsed)
	set_text(ui.TimeTX, displayTime)
	set_text(ui.TimeShadowTX, displayTime)
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
	raceStartedAt = os.clock()
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
	sync_race_visuals()
	update_visibility()
	update_dynamic_text()
end

Lighting.DescendantAdded:Connect(function(effect)
	if raceUiFocusActive and effect:IsA("BlurEffect") then
		hiddenBlurStates[effect] = effect.Enabled
		effect.Enabled = false
	end
end)

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
