local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameModules = Modules:WaitForChild("Game")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")
local HudModules = ClientModules:WaitForChild("Hud")

local ToolDictionary = require(Dictionary:WaitForChild("ToolDictionary"))
local HorseMountConfig = require(GameData:WaitForChild("Horse"):WaitForChild("HorseMountConfig"))
local Net = require(Libraries:WaitForChild("Net"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseEquipmentUtility = require(Utility:WaitForChild("Horse"):WaitForChild("HorseEquipmentUtility"))
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))
local HorseMountCamera = require(HudModules:WaitForChild("HorseMountCamera"))
local HorseMovement = require(
	GameModules:WaitForChild("Horse"):WaitForChild("Mount"):WaitForChild("Movement")
)
local HorseGroundProbe = HorseMovement.GroundProbe
local HorseMovementState = HorseMovement.StateMachine

local localPlayer = Players.LocalPlayer
local plotValue = localPlayer:WaitForChild(ToolDictionary.PlotValueName)

local MOUNT_ROOT_NAME = "HorseMountRoot"
local MOUNT_SEAT_NAME = "HorseMountSeat"
local MOUNT_RIDER_WELD_NAME = "HorseMountRiderWeld"
local MOUNT_LINEAR_VELOCITY_NAME = "HorseMountLinearVelocity"
local MOUNT_ALIGN_ORIENTATION_NAME = "HorseMountAlignOrientation"
local MOUNT_MOVEMENT_SOUND_NAME = "HorseMovement"
local MOUNT_MOVEMENT_SOUND_ID = "rbxassetid://108771044697744"
local MOUNT_MOVEMENT_MIN_SPEED = 0.35
local MOUNT_WALK_MIN_PLAYBACK_SPEED = 0.56
local MOUNT_WALK_MAX_PLAYBACK_SPEED = 0.72
local MOUNT_RUN_PLAYBACK_SPEED = 1
local MOUNT_MOVEMENT_VOLUME = 0.45
local LOCAL_MOUNT_SMOOTHNESS = 26
local DISMOUNT_ACTION_NAME = "HorseMountDismount"
local JUMP_ACTION_NAME = "HorseMountJump"
local SPRINT_ACTION_NAME = "HorseMountSprint"
local REAR_ACTION_NAME = "HorseMountRear"

local HORSE_FOLDER_NAME = ToolDictionary.HorseFolderName
local VISUAL_HORSE_ATTRIBUTE = ToolDictionary.VisualHorseAttribute
local HORSE_ID_ATTRIBUTE = ToolDictionary.HorseIdAttribute

local requestInFlight = false
local send_mount_input
local request_dismount
local dismountStopStartedAt: number? = nil
local sync_mount_state_from_server
local ensure_local_prediction
local localPrediction = {
	HorseVisual = nil,
	MountRoot = nil,
	LinearVelocity = nil,
	AlignOrientation = nil,
	CurrentYaw = 0,
	CurrentSpeed = 0,
	TerrainPitch = 0,
	TerrainRoll = 0,
	LastMoveDirection = nil,
	GroundOffset = 0,
	Position = nil,
	Movement = nil,
	JumpPendingRequest = nil,
	JumpPendingLanded = false,
	JumpVerticalVelocity = 0,
	JumpAirborne = false,
	JumpCooldownEndsAt = 0,
	JumpStartedAt = 0,
	JumpExpectedAirSeconds = 0,
	HorizontalState = HorseMovementState.Create(),
	GroundProbe = nil,
	TurnLean = 0,
	RearPitch = 0,
	RearPendingRequest = false,
}

local mountedState = {
	Active = false,
	HorseId = nil,
	HorseName = nil,
	CameraYaw = 0,
	TransitionMode = nil,
	TransitionStartRootCFrame = nil,
	TransitionTargetRootCFrame = nil,
}

local lastInputSentAt = 0
local lastSentMoveX = 0
local lastSentMoveZ = 0
local lastSentCameraYaw = 0
local lastSentSprinting = false
local lastSentStopping = false
local inputSequence = 0
local pendingInputs = {}
local mountMovementSound = nil
local mountTransitionCollisionStates = {}
local mountTransitionCollisionToken = 0
local riderAnimationState = {
	Character = nil,
	Humanoid = nil,
	Animator = nil,
	Tracks = {},
	Resources = {},
	Mode = "None",
	TransitionToken = 0,
	SettleToken = 0,
}
local localHorseAnimationState = {
	HorseVisual = nil,
	Animator = nil,
	Tracks = {},
	Resources = {},
	Mode = "None",
}
local cameraController = HorseMountCamera.new(localPlayer, HorseMountConfig)

local sprintButtonActive = false

local function bind_dismount_action()
	ContextActionService:BindActionAtPriority(
		DISMOUNT_ACTION_NAME,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				request_dismount()
			end

			return Enum.ContextActionResult.Sink
		end,
		true,
		3000,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.RightControl,
		Enum.KeyCode.P,
		Enum.KeyCode.ButtonB
	)
	ContextActionService:SetTitle(DISMOUNT_ACTION_NAME, "Dismount")
end

local function unbind_dismount_action()
	ContextActionService:UnbindAction(DISMOUNT_ACTION_NAME)
end

local function bind_sprint_action()
	sprintButtonActive = false
	ContextActionService:BindAction(
		SPRINT_ACTION_NAME,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				sprintButtonActive = true
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				sprintButtonActive = false
			end

			return Enum.ContextActionResult.Pass
		end,
		true,
		Enum.KeyCode.ButtonL3
	)
	ContextActionService:SetTitle(SPRINT_ACTION_NAME, "Sprint")
end

local function unbind_sprint_action()
	sprintButtonActive = false
	ContextActionService:UnbindAction(SPRINT_ACTION_NAME)
end

local function get_default_camera_subject() return localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid") or nil end

local function disable_character_collisions_for_mount_transition()
	mountTransitionCollisionToken += 1
	table.clear(mountTransitionCollisionStates)

	local character = localPlayer.Character
	if not character then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			mountTransitionCollisionStates[descendant] = descendant.CanCollide
			descendant.CanCollide = false
		end
	end

	return mountTransitionCollisionToken
end

local function restore_character_collisions_after_failed_mount()
	for part, canCollide in pairs(mountTransitionCollisionStates) do
		if part and part.Parent then
			part.CanCollide = canCollide
		end
	end

	table.clear(mountTransitionCollisionStates)
	mountTransitionCollisionToken += 1
end

local function normalize_animation_id(animationId)
	if type(animationId) ~= "string" or animationId == "" then
		return nil
	end

	if string.find(animationId, "rbxassetid://", 1, true) == 1 then
		return animationId
	end

	return "rbxassetid://" .. animationId
end

local function load_local_animation_track(animator, animationId, priority, looped)
	local normalizedAnimationId = normalize_animation_id(animationId)
	if not animator or not normalizedAnimationId then
		return nil, nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = normalizedAnimationId

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not track then
		animation:Destroy()
		return nil, nil
	end

	pcall(function()
		track.Priority = priority or Enum.AnimationPriority.Action4
	end)

	pcall(function()
		track.Looped = looped == true
	end)

	return track, animation
end

local function play_local_track(track, fadeTime, weight, speed)
	if not track then
		return
	end

	pcall(function()
		track:Play(
			fadeTime or HorseMountConfig.AnimationFadeTime or 0.12,
			weight or 1,
			speed or 1
		)
	end)
end

local function stop_local_track(track, fadeTime)
	if not track then
		return
	end

	pcall(function()
		track:Stop(fadeTime or HorseMountConfig.AnimationFadeTime or 0.12)
	end)
end

local function adjust_local_track_speed(track, speed)
	if not track then
		return
	end

	pcall(function()
		track:AdjustSpeed(speed or 1)
	end)
end

local function adjust_local_track_weight(track, weight, fadeTime)
	if not track then
		return
	end

	pcall(function()
		track:AdjustWeight(weight or 1, fadeTime or HorseMountConfig.HorseAnimationBlendTime or 0.24)
	end)
end

local function get_local_rider_animation_state()
	local humanoid = get_default_camera_subject()
	local character = humanoid and humanoid.Parent or nil
	if not humanoid or not character then
		return nil
	end

	if riderAnimationState.Character == character
		and riderAnimationState.Humanoid == humanoid
		and riderAnimationState.Animator
		and riderAnimationState.Animator.Parent
	then
		return riderAnimationState
	end

	riderAnimationState.TransitionToken += 1
	riderAnimationState.SettleToken += 1

	for _, track in pairs(riderAnimationState.Tracks) do
		stop_local_track(track, 0)
	end

	for _, animation in ipairs(riderAnimationState.Resources) do
		animation:Destroy()
	end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	riderAnimationState.Character = character
	riderAnimationState.Humanoid = humanoid
	riderAnimationState.Animator = animator
	riderAnimationState.Tracks = {}
	riderAnimationState.Resources = {}
	riderAnimationState.Mode = "None"

	local trackSpecs = {
		HopOn = { HorseMountConfig.PlayerHopOnAnimationId, false },
		HopOff = { HorseMountConfig.PlayerHopOffAnimationId, false },
		Idle = { HorseMountConfig.PlayerIdleAnimationId, true },
		Ride = { HorseMountConfig.PlayerRideAnimationId, true },
	}

	for trackName, spec in pairs(trackSpecs) do
		local track, animation = load_local_animation_track(
			animator,
			spec[1],
			Enum.AnimationPriority.Action4,
			spec[2]
		)

		riderAnimationState.Tracks[trackName] = track
		if animation then
			riderAnimationState.Resources[#riderAnimationState.Resources + 1] = animation
		end
	end

	return riderAnimationState
end

local function preload_local_rider_animations()
	task.spawn(function()
		local animationState = nil
		local deadline = os.clock() + 5
		repeat
			animationState = get_local_rider_animation_state()
			if not animationState then
				task.wait()
			end
		until animationState or os.clock() >= deadline

		if not animationState then
			return
		end

		local preloadResources = {}
		for _, animation in ipairs(animationState.Resources) do
			preloadResources[#preloadResources + 1] = animation
		end

		local temporaryAnimations = {}
		for _, animationId in ipairs({
			HorseMountConfig.HorseIdleAnimationId,
			HorseMountConfig.HorseWalkAnimationId,
			HorseMountConfig.HorseRunAnimationId,
			HorseMountConfig.HorseJumpAnimationId,
		}) do
			local normalizedAnimationId = normalize_animation_id(animationId)
			if normalizedAnimationId then
				local animation = Instance.new("Animation")
				animation.AnimationId = normalizedAnimationId
				temporaryAnimations[#temporaryAnimations + 1] = animation
				preloadResources[#preloadResources + 1] = animation
			end
		end

		pcall(function()
			ContentProvider:PreloadAsync(preloadResources)
		end)

		for _, animation in ipairs(temporaryAnimations) do
			animation:Destroy()
		end
	end)
end

local function clear_local_horse_animation_state()
	for _, track in pairs(localHorseAnimationState.Tracks) do
		stop_local_track(track, 0.08)
	end

	for _, animation in ipairs(localHorseAnimationState.Resources) do
		animation:Destroy()
	end

	localHorseAnimationState.HorseVisual = nil
	localHorseAnimationState.Animator = nil
	localHorseAnimationState.Tracks = {}
	localHorseAnimationState.Resources = {}
	localHorseAnimationState.Mode = "None"
end

local function get_local_horse_animation_state(horseVisual)
	if not horseVisual or not horseVisual.Parent then
		return nil
	end

	if localHorseAnimationState.HorseVisual == horseVisual
		and localHorseAnimationState.Animator
		and localHorseAnimationState.Animator.Parent
	then
		return localHorseAnimationState
	end

	clear_local_horse_animation_state()
	local animator = horseVisual:FindFirstChildWhichIsA("Animator", true)
	if not animator then
		return nil
	end

	localHorseAnimationState.HorseVisual = horseVisual
	localHorseAnimationState.Animator = animator
	local trackSpecs = {
		Idle = {
			AnimationId = HorseMountConfig.HorseIdleAnimationId,
			Priority = Enum.AnimationPriority.Action2,
			Looped = true,
		},
		Walk = {
			AnimationId = HorseMountConfig.HorseWalkAnimationId,
			Priority = Enum.AnimationPriority.Action2,
			Looped = true,
		},
		Run = {
			AnimationId = HorseMountConfig.HorseRunAnimationId,
			Priority = Enum.AnimationPriority.Action2,
			Looped = true,
		},
		Jump = {
			AnimationId = HorseMountConfig.HorseJumpAnimationId,
			Priority = Enum.AnimationPriority.Action4,
			Looped = false,
		},
	}

	for trackName, spec in pairs(trackSpecs) do
		local track, animation = load_local_animation_track(
			animator,
			spec.AnimationId,
			spec.Priority,
			spec.Looped
		)
		localHorseAnimationState.Tracks[trackName] = track
		if animation then
			localHorseAnimationState.Resources[#localHorseAnimationState.Resources + 1] = animation
		end
	end

	return localHorseAnimationState
end

local function set_local_horse_animation_mode(horseVisual, mode)
	local animationState = get_local_horse_animation_state(horseVisual)
	if not animationState then
		return
	end

	local targetTrack = animationState.Tracks[mode]
	if animationState.Mode == mode and targetTrack and targetTrack.IsPlaying then
		return
	end

	local blendTime = HorseMountConfig.HorseAnimationBlendTime or 0.24
	for trackName, track in pairs(animationState.Tracks) do
		if trackName == "Jump" then
			continue
		end

		if trackName == mode then
			if track and not track.IsPlaying then
				play_local_track(track, blendTime, 1, 1)
			end
			adjust_local_track_weight(track, 1, blendTime)
		else
			stop_local_track(track, blendTime)
		end
	end

	animationState.Mode = mode
end

local function get_local_jump_track_speed(track, airDurationSeconds)
	local animationLength = track and tonumber(track.Length) or nil
	if not animationLength or animationLength <= 0 then
		return 1
	end

	local targetDuration = math.max(tonumber(airDurationSeconds) or 0, 0.05)
	return math.clamp(animationLength / targetDuration, 0.55, 1.8)
end

local function update_local_horse_jump_animation_speed()
	local horseVisual = localPrediction.HorseVisual
	local animationState = get_local_horse_animation_state(horseVisual)
	local jumpTrack = animationState and animationState.Tracks.Jump or nil
	if not jumpTrack or jumpTrack.IsPlaying ~= true then
		return
	end

	local animationLength = tonumber(jumpTrack.Length)
	if not animationLength or animationLength <= 0 then
		return
	end

	local targetDuration = math.max(localPrediction.JumpExpectedAirSeconds or 0, 0.05)
	local startedAt = tonumber(localPrediction.JumpStartedAt) or 0
	if startedAt <= 0 then
		adjust_local_track_speed(jumpTrack, get_local_jump_track_speed(jumpTrack, targetDuration))
		return
	end

	local elapsed = math.max(0, os.clock() - startedAt)
	local remainingTrack = math.max(animationLength - jumpTrack.TimePosition, 0.03)
	local remainingAir = math.max(targetDuration - elapsed, 0.05)
	adjust_local_track_speed(jumpTrack, math.clamp(remainingTrack / remainingAir, 0.55, 1.8))
end

local function play_local_horse_jump_animation(airDurationSeconds)
	local horseVisual = localPrediction.HorseVisual
	local animationState = get_local_horse_animation_state(horseVisual)
	local jumpTrack = animationState and animationState.Tracks.Jump or nil
	if not jumpTrack then
		return
	end

	stop_local_track(jumpTrack, 0.02)
	play_local_track(
		jumpTrack,
		HorseMountConfig.HorseJumpAnimationFadeTime or 0.06,
		1,
		get_local_jump_track_speed(jumpTrack, airDurationSeconds)
	)
end

local function stop_local_rider_tracks(fadeTime)
	local animationState = riderAnimationState
	if not animationState.Animator or not animationState.Character or not animationState.Character.Parent then
		return
	end

	for _, trackName in ipairs({ "HopOn", "HopOff", "Idle", "Ride" }) do
		stop_local_track(animationState.Tracks[trackName], fadeTime)
	end

	animationState.Mode = "None"
end

local function clear_local_rider_animation_state()
	riderAnimationState.TransitionToken += 1
	riderAnimationState.SettleToken += 1

	for _, track in pairs(riderAnimationState.Tracks) do
		stop_local_track(track, 0)
	end

	for _, animation in ipairs(riderAnimationState.Resources) do
		animation:Destroy()
	end

	riderAnimationState.Character = nil
	riderAnimationState.Humanoid = nil
	riderAnimationState.Animator = nil
	riderAnimationState.Tracks = {}
	riderAnimationState.Resources = {}
	riderAnimationState.Mode = "None"
end


local function build_angle_y(cframe) return math.atan2(-cframe.LookVector.X, -cframe.LookVector.Z) end

local function wrap_angle(angle) return math.atan2(math.sin(angle), math.cos(angle)) end

local function is_finite_number(value) return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge end

local function get_character_root_part()
	local character = localPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	return rootPart and rootPart:IsA("BasePart") and rootPart or nil
end

local function clear_transition_root_targets()
	mountedState.TransitionStartRootCFrame = nil
	mountedState.TransitionTargetRootCFrame = nil
end

local function build_character_pivot_from_root(character, rootPart, desiredRootCFrame)
	if not character or not rootPart then
		return desiredRootCFrame
	end

	local relativePivotOffset = rootPart.CFrame:ToObjectSpace(character:GetPivot())
	return desiredRootCFrame * relativePivotOffset
end

local cachedPlayerControls = nil

local function get_player_controls()
	if cachedPlayerControls then
		return cachedPlayerControls
	end

	local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if not playerModule then
		return nil
	end

	local requireSuccess, requiredPlayerModule = pcall(function()
		return require(playerModule)
	end)
	if not requireSuccess or type(requiredPlayerModule) ~= "table" then
		return nil
	end

	local controlsSuccess, controls = pcall(function()
		return requiredPlayerModule:GetControls()
	end)
	if not controlsSuccess or type(controls) ~= "table" then
		return nil
	end

	cachedPlayerControls = controls
	return cachedPlayerControls
end

local function get_keyboard_move_vector()
	local moveX = 0
	local moveZ = 0

	if UserInputService:IsKeyDown(Enum.KeyCode.A) or UserInputService:IsKeyDown(Enum.KeyCode.Left) then
		moveX -= 1
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.D) or UserInputService:IsKeyDown(Enum.KeyCode.Right) then
		moveX += 1
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.W) or UserInputService:IsKeyDown(Enum.KeyCode.Up) then
		moveZ -= 1
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.S) or UserInputService:IsKeyDown(Enum.KeyCode.Down) then
		moveZ += 1
	end

	return moveX, moveZ
end

local function get_gamepad_move_vector()
	local gamepadSuccess, gamepadStates = pcall(function()
		return UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1)
	end)
	if not gamepadSuccess or type(gamepadStates) ~= "table" then
		return 0, 0
	end

	local deadzone = tonumber(HorseMountConfig.GamepadThumbstickDeadzone) or 0.15
	for _, inputObject in ipairs(gamepadStates) do
		if inputObject.KeyCode == Enum.KeyCode.Thumbstick1 then
			local position = inputObject.Position
			if math.sqrt((position.X * position.X) + (position.Y * position.Y)) > deadzone then
				return position.X, -position.Y
			end

			return 0, 0
		end
	end

	return 0, 0
end

local function get_move_vector()
	local moveX = 0
	local moveZ = 0
	local controls = get_player_controls()

	if controls then
		local moveSuccess, moveVector = pcall(function()
			return controls:GetMoveVector()
		end)
		if moveSuccess and typeof(moveVector) == "Vector3" then
			moveX = moveVector.X
			moveZ = moveVector.Z
		end
	end

	if math.abs(moveX) < 0.05 and math.abs(moveZ) < 0.05 then
		moveX, moveZ = get_keyboard_move_vector()
	end

	if math.abs(moveX) < 0.05 and math.abs(moveZ) < 0.05 then
		moveX, moveZ = get_gamepad_move_vector()
	end

	local magnitude = math.sqrt((moveX * moveX) + (moveZ * moveZ))
	if magnitude > 1 then
		moveX /= magnitude
		moveZ /= magnitude
	end

	return moveX, moveZ
end

local function set_local_rider_mode(mode)
	local animationState = get_local_rider_animation_state()
	if not animationState then
		return
	end

	if animationState.Mode == mode then
		local currentTrack = animationState.Tracks[mode]
		if currentTrack and currentTrack.IsPlaying then
			return
		end
	end

	local isMountToIdleTransition = mode == "Idle" and animationState.Mode == "Mounting"
	local fadeTime = isMountToIdleTransition
		and (HorseMountConfig.MountIdleBlendLeadTime or 0.18)
		or (HorseMountConfig.RiderResumeBlendTime or 0.24)
	local tracks = animationState.Tracks

	if mode == "Idle" then
		-- Bring the seated pose in before fading the hop-on pose out. Using the
		-- same blend window prevents the default character pose from showing
		-- between the two animations at the end of mounting.
		play_local_track(tracks.Idle, fadeTime, 1, 1)
		stop_local_track(tracks.HopOn, isMountToIdleTransition and fadeTime or 0.05)
		stop_local_track(tracks.HopOff, 0.05)
		stop_local_track(tracks.Ride, fadeTime)
	elseif mode == "Ride" then
		stop_local_track(tracks.HopOn, 0.05)
		stop_local_track(tracks.HopOff, 0.05)
		stop_local_track(tracks.Idle, fadeTime)
		play_local_track(tracks.Ride, fadeTime, 1, HorseMountConfig.RiderResumeStartSpeed or 0.18)
		adjust_local_track_speed(tracks.Ride, 1)
	else
		stop_local_track(tracks.Idle, fadeTime)
		stop_local_track(tracks.Ride, fadeTime)
	end

	animationState.Mode = mode
end

local function smooth_local_character_to_root_cframe(targetRootCFrame, duration, arcHeight)
	if not targetRootCFrame then
		return
	end

	local animationState = get_local_rider_animation_state()
	if not animationState then
		return
	end

	animationState.SettleToken += 1
	local settleToken = animationState.SettleToken

	task.spawn(function()
		local character = animationState.Character
		local rootPart = get_character_root_part()
		if not character or not rootPart then
			return
		end

		local blendDuration = math.max(duration or 0, 0)
		local startRootCFrame = rootPart.CFrame

		if blendDuration <= 0.01 then
			character:PivotTo(build_character_pivot_from_root(character, rootPart, targetRootCFrame))
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero
			return
		end

		local startedAt = os.clock()
		while settleToken == animationState.SettleToken do
			character = animationState.Character
			rootPart = get_character_root_part()
			if not character or not rootPart then
				break
			end

			local alpha = math.clamp((os.clock() - startedAt) / blendDuration, 0, 1)
			local easedAlpha = alpha * alpha * (3 - (2 * alpha))
			local nextRootCFrame = startRootCFrame:Lerp(targetRootCFrame, easedAlpha)
			local resolvedArcHeight = math.max(arcHeight or 0, 0)
			if resolvedArcHeight > 0 then
				nextRootCFrame += Vector3.new(0, math.sin(alpha * math.pi) * resolvedArcHeight, 0)
			end
			character:PivotTo(build_character_pivot_from_root(character, rootPart, nextRootCFrame))
			rootPart.AssemblyLinearVelocity = Vector3.zero
			rootPart.AssemblyAngularVelocity = Vector3.zero

			if alpha >= 1 then
				break
			end

			RunService.Heartbeat:Wait()
		end
	end)
end

local function play_local_mount_transition(duration, targetCFrame)
	local animationState = get_local_rider_animation_state()
	if not animationState then
		return
	end

	animationState.TransitionToken += 1
	local transitionToken = animationState.TransitionToken
	local tracks = animationState.Tracks
	stop_local_track(tracks.HopOff, 0.05)
	stop_local_track(tracks.Idle, 0.05)
	stop_local_track(tracks.Ride, 0.05)
	local configuredDuration = math.max(HorseMountConfig.MountTransitionDuration or duration or 1.8, 0.05)
	local resolvedDuration = math.max(duration or configuredDuration, 0.05)
	play_local_track(tracks.HopOn, 0.05, 1, configuredDuration / resolvedDuration)
	animationState.Mode = "Mounting"

	-- Start the seated idle pose just before the hop-on track finishes so the
	-- rider never spends a frame in the unanimated fallback pose.
	task.spawn(function()
		local idleLeadTime = math.max(HorseMountConfig.MountIdleBlendLeadTime or 0, 0)
		local waitTime = math.max((duration or HorseMountConfig.MountTransitionDuration or 1.8) - idleLeadTime, 0)
		if waitTime > 0 then
			task.wait(waitTime)
		end

		if transitionToken == animationState.TransitionToken then
			set_local_rider_mode("Idle")
		end
	end)

	if targetCFrame then
		smooth_local_character_to_root_cframe(
			targetCFrame,
			resolvedDuration,
			HorseMountConfig.MountTransitionArcHeight or 0
		)
	end
end

local function play_local_dismount_transition(animationDuration, moveDelay, moveDuration, moveEndsAt, targetCFrame)
	local animationState = get_local_rider_animation_state()
	if not animationState then
		return
	end

	animationState.TransitionToken += 1
	local transitionToken = animationState.TransitionToken
	local tracks = animationState.Tracks
	stop_local_track(tracks.HopOn, 0.05)
	stop_local_track(tracks.Idle, 0.05)
	stop_local_track(tracks.Ride, 0.05)
	local configuredDuration = math.max(HorseMountConfig.DismountTransitionDuration or animationDuration or 0.95, 0.05)
	local resolvedAnimationDuration = math.max(animationDuration or configuredDuration, 0.05)
	play_local_track(tracks.HopOff, 0.05, 1, configuredDuration / resolvedAnimationDuration)
	animationState.Mode = "Dismounting"

	task.spawn(function()
		local holdTime = math.max(HorseMountConfig.DismountFinalPoseHoldTime or 0, 0)
		local resolvedMoveDelay = math.max(moveDelay or 0, 0)
		if resolvedMoveDelay > 0 then
			task.wait(resolvedMoveDelay)
		end

		if transitionToken ~= animationState.TransitionToken then
			return
		end

		local mountRoot = localPrediction.MountRoot
		local mountParent = mountRoot and mountRoot.Parent or nil
		local mountSeat = mountParent and mountParent:FindFirstChild(MOUNT_SEAT_NAME, true) or nil
		if mountSeat then
			local releaseWaitDeadline = math.min(
				is_finite_number(moveEndsAt) and moveEndsAt or (Workspace:GetServerTimeNow() + 0.2),
				Workspace:GetServerTimeNow() + 0.2
			)
			while mountSeat:FindFirstChild(MOUNT_RIDER_WELD_NAME)
				and Workspace:GetServerTimeNow() < releaseWaitDeadline
			do
				RunService.Heartbeat:Wait()
			end
		end

		local resolvedMoveDuration = math.max(moveDuration or (resolvedAnimationDuration - resolvedMoveDelay), 0.08)
		if is_finite_number(moveEndsAt) then
			resolvedMoveDuration = math.max(moveEndsAt - Workspace:GetServerTimeNow(), 0.08)
		end

		if targetCFrame then
			smooth_local_character_to_root_cframe(
				targetCFrame,
				resolvedMoveDuration,
				HorseMountConfig.DismountTransitionArcHeight or 0
			)
		end

		if resolvedMoveDuration > 0 then
			task.wait(resolvedMoveDuration)
		end

		if holdTime > 0 then
			task.wait(holdTime)
		end

		if transitionToken ~= animationState.TransitionToken then
			return
		end

		stop_local_track(tracks.HopOff, 0.03)
	end)
end

local function update_local_rider_animation()
	if not mountedState.Active or mountedState.TransitionMode ~= nil then
		return
	end

	local moving = math.abs(localPrediction.CurrentSpeed or 0) > 0.25
	local galloping = localPrediction.HorizontalState.Mode == "Gallop"
	set_local_rider_mode(moving and galloping and "Ride" or "Idle")
end

local function get_base_part_lowest_y(basePart)
	local cframe = basePart.CFrame
	local halfSizeX = cframe.RightVector * (basePart.Size.X * 0.5)
	local halfSizeY = cframe.UpVector * (basePart.Size.Y * 0.5)
	local halfSizeZ = cframe.LookVector * (basePart.Size.Z * 0.5)
	local lowestY = math.huge

	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local cornerPosition = cframe.Position + (halfSizeX * xSign) + (halfSizeY * ySign) + (halfSizeZ * zSign)
				lowestY = math.min(lowestY, cornerPosition.Y)
			end
		end
	end

	return lowestY
end

local function should_include_in_ground_offset(basePart)
	return basePart.Name ~= MOUNT_ROOT_NAME and basePart.Name ~= MOUNT_SEAT_NAME
end

local function get_instance_lowest_y(instance)
	if instance:IsA("BasePart") then
		if not should_include_in_ground_offset(instance) then
			return nil
		end

		return get_base_part_lowest_y(instance)
	end

	local lowestY = math.huge
	local foundBasePart = false

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") and should_include_in_ground_offset(descendant) then
			foundBasePart = true
			lowestY = math.min(lowestY, get_base_part_lowest_y(descendant))
		end
	end

	if not foundBasePart then
		return nil
	end

	return lowestY
end

local function get_hoof_bone_lowest_y(instance)
	local lowestY = math.huge
	local foundHoofBone = false

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("Bone") then
			local boneName = string.lower(descendant.Name)
			local isHoofBone = string.find(boneName, "hoof", 1, true)
				or string.find(boneName, "foot", 1, true)
				or boneName == "leg_1"
				or boneName == "leg_2"
				or boneName == "leg_3"
				or boneName == "leg_4"

			if isHoofBone then
				foundHoofBone = true
				lowestY = math.min(lowestY, descendant.WorldPosition.Y)
			end
		end
	end

	return foundHoofBone and lowestY or nil
end

local function get_ground_offset(instance)
	local lowestY = get_hoof_bone_lowest_y(instance) or get_instance_lowest_y(instance)
	if not lowestY then
		return 0
	end

	return instance:GetPivot().Position.Y - lowestY
end

local function get_target_ground_offset(baseGroundOffset, sprinting)
	local groundOffset = baseGroundOffset or 0
	if sprinting ~= true then
		groundOffset += HorseMountConfig.IdleWalkGroundOffsetDelta or 0
	end

	return groundOffset
end

local function resolve_ground_position(position, ignoreList, groundOffset)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignoreList
	raycastParams.IgnoreWater = false

	local origin = position + Vector3.new(0, HorseMountConfig.GroundProbeHeight, 0)
	local direction = Vector3.new(0, -(HorseMountConfig.GroundProbeDistance + HorseMountConfig.GroundProbeHeight), 0)
	local result = Workspace:Raycast(origin, direction, raycastParams)

	if result then
		return Vector3.new(
			position.X,
			result.Position.Y + groundOffset + HorseMountConfig.GroundClearance,
			position.Z
		)
	end

	return position
end

local function find_local_horse_visual(horseId)
	local plot = plotValue.Value
	if not plot or type(horseId) ~= "string" or horseId == "" then
		return nil
	end

	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return nil
	end

	for _, descendant in ipairs(horseFolder:GetDescendants()) do
		if descendant:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true and descendant:GetAttribute(HORSE_ID_ATTRIBUTE) == horseId then
			return descendant
		end
	end

	return nil
end

local function get_owned_horse_data(horseId)
	local horses = DataUtility.client.get("Horses")
	local ownedHorses = type(horses) == "table" and horses.Owned or nil
	return type(ownedHorses) == "table" and ownedHorses[horseId] or nil
end

local function get_prediction_movement(horseId)
	local horse = get_owned_horse_data(horseId)
	local movement = type(horse) == "table" and HorseEquipmentUtility.GetEffectiveMovement(horse) or nil

	return {
		WalkSpeed = type(movement) == "table" and movement.WalkSpeed or 14,
		TrotSpeed = type(movement) == "table" and movement.TrotSpeed or 18,
		CanterSpeed = type(movement) == "table" and movement.CanterSpeed or 22,
		SprintSpeed = type(movement) == "table" and movement.SprintSpeed or 26,
		Acceleration = type(movement) == "table" and movement.Acceleration or 0.8,
		TurnRate = type(movement) == "table" and movement.TurnRate or 0.8,
		Jump = type(movement) == "table" and movement.Jump or (HorseMountConfig.HorseJumpBaseStat or 0.78),
	}
end

local function find_mount_root_for_visual(horseVisual)
	if not horseVisual then
		return nil
	end

	if horseVisual:IsA("Model") then
		local candidate = horseVisual:FindFirstChild(MOUNT_ROOT_NAME, true)
		if candidate and candidate:IsA("BasePart") then
			return candidate
		end
	end

	local searchParent = horseVisual.Parent
	if searchParent then
		local candidate = searchParent:FindFirstChild(MOUNT_ROOT_NAME)
		if candidate and candidate:IsA("BasePart") then
			return candidate
		end
	end

	return nil
end

local function find_driver_constraints(mountRoot)
	if not mountRoot then
		return nil, nil
	end

	local linearVelocity = mountRoot:FindFirstChild(MOUNT_LINEAR_VELOCITY_NAME)
	local alignOrientation = mountRoot:FindFirstChild(MOUNT_ALIGN_ORIENTATION_NAME)
	if not linearVelocity or not linearVelocity:IsA("LinearVelocity") then
		linearVelocity = nil
	end

	if not alignOrientation or not alignOrientation:IsA("AlignOrientation") then
		alignOrientation = nil
	end

	return linearVelocity, alignOrientation
end

local function is_sprint_input_active()
	return mountedState.Active and (
		sprintButtonActive
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	) or false
end

local function is_gallop_active()
	return mountedState.Active and localPrediction.HorizontalState.Mode == "Gallop"
end

local function get_local_jump_grounded_position()
	local horseVisual, mountRoot = ensure_local_prediction()
	if not horseVisual or not mountRoot then
		return nil, nil, nil
	end

	local targetGroundOffset = get_target_ground_offset(
		localPrediction.GroundOffset,
		localPrediction.HorizontalState.Mode == "Gallop"
	)
	local groundProbe = localPrediction.GroundProbe
	if groundProbe then
		local sample = groundProbe:Update(
			HorseMountConfig.HorseProbeIntervalSeconds or 0.05,
			mountRoot.Position,
			localPrediction.CurrentYaw,
			localPrediction.GroundOffset
		)
		if sample.GroundY then
			return horseVisual, mountRoot, Vector3.new(
				mountRoot.Position.X,
				sample.GroundY + targetGroundOffset + (HorseMountConfig.GroundClearance or 0),
				mountRoot.Position.Z
			)
		end
	end
	local groundedPosition = resolve_ground_position(
		mountRoot.Position,
		{ horseVisual, localPlayer.Character },
		targetGroundOffset
	)
	return horseVisual, mountRoot, groundedPosition
end

local function is_local_mount_grounded()
	local _, mountRoot, groundedPosition = get_local_jump_grounded_position()
	if not mountRoot or not groundedPosition then
		return false
	end

	return math.abs(mountRoot.Position.Y - groundedPosition.Y) <= (HorseMountConfig.HorseJumpGroundTolerance or 0.75)
end

local function can_begin_local_jump(now)
	if not mountedState.Active or mountedState.TransitionMode ~= nil then
		return false
	end

	if localPrediction.JumpAirborne == true then
		return false
	end

	if (now or os.clock()) < (localPrediction.JumpCooldownEndsAt or 0) then
		return false
	end

	return is_local_mount_grounded()
end

local function get_local_jump_takeoff_velocity(chargeAlpha)
	local movement = localPrediction.Movement or get_prediction_movement(mountedState.HorseId)
	local baseJumpStat = math.max(tonumber(HorseMountConfig.HorseJumpBaseStat) or 0.78, 0.01)
	local jumpStat = type(movement) == "table" and tonumber(movement.Jump) or baseJumpStat
	local jumpScale = math.clamp((jumpStat or baseJumpStat) / baseJumpStat, 0.75, 1.35)
	local minVelocity = HorseMountConfig.HorseJumpMinVelocity or 18
	local maxVelocity = HorseMountConfig.HorseJumpMaxVelocity or 30
	local baseVelocity = minVelocity + ((maxVelocity - minVelocity) * math.clamp(tonumber(chargeAlpha) or 0, 0, 1))
	return baseVelocity * jumpScale
end

local function get_local_jump_expected_air_seconds(verticalVelocity)
	local gravity = math.max(tonumber(HorseMountConfig.HorseJumpGravity) or 58, 0.001)
	local maxAirSeconds = math.max(HorseMountConfig.HorseJumpMaxAirSeconds or 1.35, 0.4)
	local estimatedAirSeconds = (math.max(tonumber(verticalVelocity) or 0, 0) * 2) / gravity
	return math.clamp(estimatedAirSeconds, 0.05, maxAirSeconds)
end

local function request_local_jump()
	local now = os.clock()
	if math.abs(localPrediction.CurrentSpeed or 0)
		<= (HorseMountConfig.HorseJumpDismountSpeedThreshold or 0.25)
	then
		task.defer(request_dismount)
		return
	end

	if not can_begin_local_jump(now) then
		return
	end

	local movement = localPrediction.Movement or get_prediction_movement(mountedState.HorseId)
	local sprintSpeed = math.max(tonumber(movement.SprintSpeed) or 26, 0.01)
	local chargeAlpha = math.clamp(math.abs(localPrediction.CurrentSpeed or 0) / sprintSpeed, 0, 1)
	local takeoffVelocity = get_local_jump_takeoff_velocity(chargeAlpha)
	localPrediction.JumpAirborne = true
	localPrediction.JumpVerticalVelocity = takeoffVelocity
	localPrediction.JumpCooldownEndsAt = now + math.max(HorseMountConfig.HorseJumpCooldownSeconds or 0.9, 0)
	localPrediction.JumpPendingRequest = chargeAlpha
	localPrediction.JumpPendingLanded = false
	localPrediction.JumpStartedAt = now
	localPrediction.JumpExpectedAirSeconds = get_local_jump_expected_air_seconds(takeoffVelocity)

	play_local_horse_jump_animation(localPrediction.JumpExpectedAirSeconds)
	send_mount_input(true)
end

local function bind_jump_action()
	ContextActionService:BindActionAtPriority(
		JUMP_ACTION_NAME,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				request_local_jump()
			end

			return Enum.ContextActionResult.Sink
		end,
		true,
		3000,
		Enum.PlayerActions.CharacterJump,
		Enum.KeyCode.Space
	)
	ContextActionService:SetTitle(JUMP_ACTION_NAME, "Jump")
end

local function unbind_jump_action()
	ContextActionService:UnbindAction(JUMP_ACTION_NAME)
end

local function request_local_rear()
	if not mountedState.Active or mountedState.TransitionMode ~= nil or not is_local_mount_grounded() then
		return
	end

	if HorseMovementState.RequestRear(localPrediction.HorizontalState, HorseMountConfig, os.clock()) then
		localPrediction.CurrentSpeed = 0
		localPrediction.RearPendingRequest = true
		send_mount_input(true)
	end
end

local function bind_rear_action()
	ContextActionService:BindActionAtPriority(
		REAR_ACTION_NAME,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				request_local_rear()
			end
			return Enum.ContextActionResult.Sink
		end,
		true,
		3000,
		Enum.KeyCode.J,
		Enum.KeyCode.ButtonY
	)
	ContextActionService:SetTitle(REAR_ACTION_NAME, "Rear")
end

local function unbind_rear_action()
	ContextActionService:UnbindAction(REAR_ACTION_NAME)
end

local function reset_local_prediction()
	clear_local_horse_animation_state()
	localPrediction.HorseVisual = nil
	localPrediction.MountRoot = nil
	localPrediction.LinearVelocity = nil
	localPrediction.AlignOrientation = nil
	localPrediction.CurrentYaw = mountedState.CameraYaw
	localPrediction.CurrentSpeed = 0
	localPrediction.TerrainPitch = 0
	localPrediction.TerrainRoll = 0
	localPrediction.LastMoveDirection = nil
	localPrediction.GroundOffset = 0
	localPrediction.Position = nil
	localPrediction.Movement = nil
	localPrediction.JumpPendingRequest = nil
	localPrediction.JumpPendingLanded = false
	localPrediction.JumpVerticalVelocity = 0
	localPrediction.JumpAirborne = false
	localPrediction.JumpCooldownEndsAt = 0
	localPrediction.JumpStartedAt = 0
	localPrediction.JumpExpectedAirSeconds = 0
	localPrediction.HorizontalState = HorseMovementState.Create()
	if localPrediction.GroundProbe then
		localPrediction.GroundProbe:Reset()
	end
	localPrediction.GroundProbe = nil
	localPrediction.TurnLean = 0
	localPrediction.RearPitch = 0
	localPrediction.RearPendingRequest = false
end

local function stop_mount_movement_sound()
	if mountMovementSound and mountMovementSound.Parent and mountMovementSound.IsPlaying then
		mountMovementSound:Stop()
	end

	mountMovementSound = nil
end

local function get_mount_movement_sound(mountRoot)
	if not mountRoot then
		return nil
	end

	if mountMovementSound and mountMovementSound.Parent == mountRoot then
		return mountMovementSound
	end

	stop_mount_movement_sound()

	local existingSound = mountRoot:FindFirstChild(MOUNT_MOVEMENT_SOUND_NAME)
	if existingSound and existingSound:IsA("Sound") then
		mountMovementSound = existingSound
		return mountMovementSound
	end

	local sound = Instance.new("Sound")
	sound.Name = MOUNT_MOVEMENT_SOUND_NAME
	sound.SoundId = MOUNT_MOVEMENT_SOUND_ID
	sound.Looped = true
	sound.Volume = MOUNT_MOVEMENT_VOLUME
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 80
	sound.SoundGroup = SoundUtility.GetSFXSoundGroup()
	sound.Parent = mountRoot
	mountMovementSound = sound
	return sound
end

local function update_mount_movement_sound()
	local mountRoot = localPrediction.MountRoot
	local currentSpeed = math.abs(localPrediction.CurrentSpeed or 0)
	if not mountedState.Active or mountedState.TransitionMode ~= nil or not mountRoot or currentSpeed <= MOUNT_MOVEMENT_MIN_SPEED then
		stop_mount_movement_sound()
		return
	end

	local sound = get_mount_movement_sound(mountRoot)
	if not sound then
		return
	end

	local movement = localPrediction.Movement or get_prediction_movement(mountedState.HorseId)
	if localPrediction.HorizontalState.Mode == "Gallop" then
		sound.PlaybackSpeed = MOUNT_RUN_PLAYBACK_SPEED
	else
		local walkingSpeed = math.max(movement.WalkSpeed or 14, MOUNT_MOVEMENT_MIN_SPEED)
		local speedAlpha = math.clamp(currentSpeed / walkingSpeed, 0, 1)
		sound.PlaybackSpeed = MOUNT_WALK_MIN_PLAYBACK_SPEED
			+ ((MOUNT_WALK_MAX_PLAYBACK_SPEED - MOUNT_WALK_MIN_PLAYBACK_SPEED) * speedAlpha)
	end

	if not sound.IsPlaying then
		sound:Play()
	end
end

ensure_local_prediction = function()
	if not mountedState.Active or not mountedState.HorseId then
		reset_local_prediction()
		return nil, nil
	end

	local horseVisual = localPrediction.HorseVisual
	if not horseVisual or not horseVisual.Parent or horseVisual:GetAttribute(HORSE_ID_ATTRIBUTE) ~= mountedState.HorseId then
		horseVisual = find_local_horse_visual(mountedState.HorseId)
		localPrediction.HorseVisual = horseVisual
		localPrediction.MountRoot = nil
		localPrediction.LinearVelocity = nil
		localPrediction.AlignOrientation = nil
		localPrediction.Position = nil
		localPrediction.CurrentSpeed = 0
		localPrediction.LastMoveDirection = nil
		localPrediction.GroundOffset = horseVisual and get_ground_offset(horseVisual) or 0
		localPrediction.Movement = get_prediction_movement(mountedState.HorseId)
		localPrediction.HorizontalState = HorseMovementState.Create()
		localPrediction.TurnLean = 0
		localPrediction.RearPitch = 0
		localPrediction.GroundProbe = HorseGroundProbe.new(Workspace, HorseMountConfig)
		local ignoreList = { horseVisual }
		if localPlayer.Character then
			ignoreList[#ignoreList + 1] = localPlayer.Character
		end
		localPrediction.GroundProbe:SetIgnore(ignoreList)
	end

	if not horseVisual then
		return nil, nil
	end

	local mountRoot = localPrediction.MountRoot
	if not mountRoot or not mountRoot.Parent then
		local candidate = find_mount_root_for_visual(horseVisual)
		if candidate then
			mountRoot = candidate
			localPrediction.MountRoot = mountRoot
			localPrediction.LinearVelocity, localPrediction.AlignOrientation = find_driver_constraints(mountRoot)
			localPrediction.CurrentYaw = build_angle_y(mountRoot.CFrame)
			localPrediction.Position = mountRoot.Position
			localPrediction.LastMoveDirection = mountRoot.CFrame.LookVector
			if localPrediction.GroundProbe then
				local ignoreList = { horseVisual, mountRoot }
				if localPlayer.Character then
					ignoreList[#ignoreList + 1] = localPlayer.Character
				end
				local mountSeat = mountRoot.Parent and mountRoot.Parent:FindFirstChild(MOUNT_SEAT_NAME)
				if mountSeat then
					ignoreList[#ignoreList + 1] = mountSeat
				end
				localPrediction.GroundProbe:SetIgnore(ignoreList)
			end
		end
	end

	if mountRoot and (not localPrediction.LinearVelocity or not localPrediction.AlignOrientation) then
		localPrediction.LinearVelocity, localPrediction.AlignOrientation = find_driver_constraints(mountRoot)
	end

	return horseVisual, mountRoot
end

local function update_local_mount_prediction(deltaTime)
	local horseVisual, mountRoot = ensure_local_prediction()
	if not horseVisual or not mountRoot then
		return
	end

	local linearVelocity = localPrediction.LinearVelocity
	local alignOrientation = localPrediction.AlignOrientation
	if not linearVelocity or not alignOrientation then
		return
	end

	local movement = localPrediction.Movement or get_prediction_movement(mountedState.HorseId)
	local inputX, inputZ = get_move_vector()
	local stoppingForDismount: boolean = dismountStopStartedAt ~= nil
	if stoppingForDismount then
		inputX = 0
		inputZ = 0
	end
	local forwardAmount = math.max(0, -inputZ)
	local backwardAmount = math.max(0, inputZ)
	local currentPosition = mountRoot.Position
	local groundProbe = localPrediction.GroundProbe
	local probeSample = groundProbe and groundProbe:Update(
		deltaTime,
		currentPosition,
		localPrediction.CurrentYaw,
		localPrediction.GroundOffset
	) or {
		GroundY = nil,
		Pitch = 0,
		Roll = 0,
		ObstacleSpeedAlpha = 1,
	}

	local horizontalState = localPrediction.HorizontalState
	HorseMovementState.Step(horizontalState, {
		Forward = forwardAmount,
		Backward = backwardAmount,
		Sprinting = is_sprint_input_active(),
		Stopping = stoppingForDismount,
		ObstacleSpeedAlpha = if localPrediction.JumpAirborne then 1 else probeSample.ObstacleSpeedAlpha,
	}, movement, HorseMountConfig, deltaTime, os.clock())
	localPrediction.CurrentSpeed = horizontalState.Speed

	local sprintSpeed = math.max(tonumber(movement.SprintSpeed) or 26, 0.01)
	local speedAlpha = math.clamp(math.abs(horizontalState.Speed) / sprintSpeed, 0, 1)
	local turnRateAlpha = math.clamp(((movement.TurnRate or 0.8) - 0.65) / 0.25, 0, 1)
	local maxTurnSpeedDegrees = (HorseMountConfig.HorseTurnSpeedBaseDegrees or 65)
		+ ((HorseMountConfig.HorseTurnSpeedScaleDegrees or 55) * turnRateAlpha)
	local turnAtRest = math.clamp(HorseMountConfig.HorseTurnAtRestMultiplier or 0.18, 0, 1)
	local turnSpeedAlpha = turnAtRest + ((1 - turnAtRest) * speedAlpha)
	local reverseSign = if horizontalState.Speed < 0 then -1 else 1
	localPrediction.CurrentYaw = wrap_angle(
		localPrediction.CurrentYaw
		- (inputX * reverseSign * math.rad(maxTurnSpeedDegrees) * turnSpeedAlpha * math.min(deltaTime, 0.1))
	)

	local terrainBlendAlpha = 1 - math.exp(-(HorseMountConfig.TerrainTiltResponsiveness or 8) * deltaTime)
	local targetPitch = if localPrediction.JumpAirborne then 0 else probeSample.Pitch
	local targetRoll = if localPrediction.JumpAirborne then 0 else probeSample.Roll
	localPrediction.TerrainPitch += (targetPitch - localPrediction.TerrainPitch) * terrainBlendAlpha
	localPrediction.TerrainRoll += (targetRoll - localPrediction.TerrainRoll) * terrainBlendAlpha

	local targetTurnLean = -inputX * speedAlpha * math.rad(HorseMountConfig.HorseTurnLeanDegrees or 8)
	local leanBlendAlpha = 1 - math.exp(-(HorseMountConfig.HorseTurnLeanResponsiveness or 7) * deltaTime)
	localPrediction.TurnLean += (targetTurnLean - localPrediction.TurnLean) * leanBlendAlpha
	local targetRearPitch = HorseMovementState.IsRearActive(horizontalState, os.clock())
		and math.rad(HorseMountConfig.HorseRearPitchDegrees or 24)
		or 0
	local rearBlendAlpha = 1 - math.exp(-(HorseMountConfig.HorseRearPoseResponsiveness or 9) * deltaTime)
	localPrediction.RearPitch += (targetRearPitch - localPrediction.RearPitch) * rearBlendAlpha
	local yawOrientation = CFrame.Angles(0, localPrediction.CurrentYaw, 0)
	local orientation = yawOrientation * CFrame.Angles(
		localPrediction.TerrainPitch + localPrediction.RearPitch,
		0,
		localPrediction.TerrainRoll + localPrediction.TurnLean
	)
	local moveDirection = yawOrientation.LookVector
	localPrediction.LastMoveDirection = moveDirection
	local verticalVelocity = 0
	if localPrediction.JumpAirborne == true then
		localPrediction.JumpVerticalVelocity = (localPrediction.JumpVerticalVelocity or 0)
			- ((HorseMountConfig.HorseJumpGravity or 58) * deltaTime)
		update_local_horse_jump_animation_speed()

		if HorseMountConfig.StickMountedHorseToGround == true and probeSample.GroundY then
			local targetGroundOffset = get_target_ground_offset(
				localPrediction.GroundOffset,
				horizontalState.Mode == "Gallop"
			)
			local groundedY = probeSample.GroundY + targetGroundOffset + (HorseMountConfig.GroundClearance or 0)
			local landingTolerance = HorseMountConfig.HorseJumpLandTolerance or 0.45

			if localPrediction.JumpVerticalVelocity <= 0
				and currentPosition.Y <= (groundedY + landingTolerance)
			then
				localPrediction.JumpAirborne = false
				localPrediction.JumpVerticalVelocity = 0
				localPrediction.JumpStartedAt = 0
				localPrediction.JumpExpectedAirSeconds = 0
				localPrediction.JumpPendingLanded = true
				local verticalError = groundedY - currentPosition.Y
				verticalVelocity = math.clamp(
					verticalError * (HorseMountConfig.GroundStickResponsiveness or 16),
					-(HorseMountConfig.GroundStickMaxVelocity or 48),
					HorseMountConfig.GroundStickMaxVelocity or 48
				)
				send_mount_input(true)
			else
				verticalVelocity = localPrediction.JumpVerticalVelocity
			end
		else
			verticalVelocity = localPrediction.JumpVerticalVelocity
		end
	elseif HorseMountConfig.StickMountedHorseToGround == true and probeSample.GroundY then
		local targetGroundOffset = get_target_ground_offset(
			localPrediction.GroundOffset,
			horizontalState.Mode == "Gallop"
		)
		local groundedY = probeSample.GroundY + targetGroundOffset + (HorseMountConfig.GroundClearance or 0)
		local verticalError = groundedY - currentPosition.Y
		verticalVelocity = math.clamp(
			verticalError * (HorseMountConfig.GroundStickResponsiveness or 16),
			-(HorseMountConfig.GroundStickMaxVelocity or 48),
			HorseMountConfig.GroundStickMaxVelocity or 48
		)
	end

	linearVelocity.VectorVelocity = (moveDirection * horizontalState.Speed) + Vector3.new(0, verticalVelocity, 0)
	alignOrientation.CFrame = orientation
	localPrediction.Position = currentPosition
end

local function update_local_horse_animation()
	local horseVisual = localPrediction.HorseVisual
	if not mountedState.Active or mountedState.TransitionMode ~= nil or not horseVisual or not horseVisual.Parent then
		return
	end

	local horizontalMode = localPrediction.HorizontalState.Mode
	local moving = math.abs(localPrediction.CurrentSpeed or 0) > 0.25
	local mode = "Idle"
	if moving then
		mode = horizontalMode == "Gallop" and "Run" or "Walk"
	end

	set_local_horse_animation_mode(horseVisual, mode)
	if localHorseAnimationState.HorseVisual == horseVisual then
		local movement = localPrediction.Movement or get_prediction_movement(mountedState.HorseId)
		local referenceSpeed = mode == "Run"
			and (movement.SprintSpeed or 26)
			or (movement.WalkSpeed or 14)
		local playbackSpeed = 1
		if mode ~= "Idle" and referenceSpeed > 0 then
			playbackSpeed = math.clamp(math.abs(localPrediction.CurrentSpeed or 0) / referenceSpeed, 0.7, 1.25)
		end
		adjust_local_track_speed(localHorseAnimationState.Tracks[mode], playbackSpeed)
	end
end

local function get_control_start_yaw() return cameraController:getControlStartYaw(get_character_root_part, mountedState) end
local function prepare_camera_for_mount() cameraController:prepareCameraForMount() end
local function start_camera_transition(mode, duration) cameraController:startCameraTransition(mode, duration) end
local function cancel_camera_transition() cameraController:cancelCameraTransition() end
local function restore_camera() cameraController:releaseCameraAfterDismount() end
local function hand_over_to_default_camera() cameraController:handOverToDefaultCamera() end
local function update_camera_transition(deltaTime) cameraController:updateCameraTransition(deltaTime, mountedState, get_character_root_part) end
local function update_camera_fov(deltaTime) cameraController:updateCameraFov(deltaTime, mountedState, localPrediction, get_prediction_movement, is_gallop_active) end
local function update_camera_motion(deltaTime) cameraController:updateCameraMotion(deltaTime, mountedState, localPrediction, get_prediction_movement) end

send_mount_input = function(forceSend)
	if not mountedState.Active then
		return
	end

	local now = os.clock()
	local moveX, moveZ = get_move_vector()
	local stoppingForDismount: boolean = dismountStopStartedAt ~= nil
	if stoppingForDismount then
		moveX = 0
		moveZ = 0
	end
	local sprinting = not stoppingForDismount and localPrediction.HorizontalState.Mode == "Gallop"
	local jumpRequested = if stoppingForDismount then nil else localPrediction.JumpPendingRequest
	local jumpLanded = not stoppingForDismount and localPrediction.JumpPendingLanded == true
	local rearRequested = not stoppingForDismount and localPrediction.RearPendingRequest == true

	local yawChanged = math.abs(mountedState.CameraYaw - lastSentCameraYaw) >= 0.01
	local moveChanged = math.abs(moveX - lastSentMoveX) >= 0.01 or math.abs(moveZ - lastSentMoveZ) >= 0.01
	local sprintChanged = sprinting ~= lastSentSprinting
	local stoppingChanged = stoppingForDismount ~= lastSentStopping
	local jumpChanged = jumpRequested ~= nil or jumpLanded or rearRequested

	if not forceSend
		and now - lastInputSentAt < HorseMountConfig.InputSendInterval
		and not yawChanged
		and not moveChanged
		and not sprintChanged
		and not stoppingChanged
		and not jumpChanged
	then
		return
	end

	lastInputSentAt = now
	lastSentMoveX = moveX
	lastSentMoveZ = moveZ
	lastSentCameraYaw = mountedState.CameraYaw
	lastSentSprinting = sprinting
	lastSentStopping = stoppingForDismount

	inputSequence += 1
	pendingInputs[inputSequence] = {
		SentAt = now,
		Speed = localPrediction.CurrentSpeed,
	}
	local expiredSequence = inputSequence - 64
	if expiredSequence > 0 then
		pendingInputs[expiredSequence] = nil
	end

	Net.Event.HorseMountInput:Fire({
		Sequence = inputSequence,
		MoveX = moveX,
		MoveZ = moveZ,
		CameraYaw = mountedState.CameraYaw,
		Sprinting = sprinting,
		Stopping = stoppingForDismount,
		GaitMode = localPrediction.HorizontalState.Mode,
		JumpRequested = jumpRequested ~= nil,
		JumpChargeAlpha = jumpRequested or 0,
		JumpLanded = jumpLanded,
		RearRequested = rearRequested,
	})

	localPrediction.JumpPendingRequest = nil
	localPrediction.JumpPendingLanded = false
	localPrediction.RearPendingRequest = false
end

sync_mount_state_from_server = function(statePayload)
	local wasMounted = mountedState.Active
	local previousTransitionMode = mountedState.TransitionMode
	local mounted = type(statePayload) == "table" and statePayload.Mounted == true
	if not mounted then
		dismountStopStartedAt = nil
	end

	mountedState.Active = mounted
	mountedState.HorseId = mounted and statePayload.HorseId or nil
	mountedState.HorseName = mounted and statePayload.HorseName or nil

	if mounted then
		mountTransitionCollisionToken += 1
		table.clear(mountTransitionCollisionStates)
		bind_dismount_action()
		bind_jump_action()
		bind_rear_action()
		bind_sprint_action()
		mountedState.TransitionMode = nil
		clear_transition_root_targets()
		cancel_camera_transition()

		if not wasMounted then
			if previousTransitionMode ~= "Mounting" then
				mountedState.CameraYaw = get_control_start_yaw()
			end
			reset_local_prediction()
			inputSequence = 0
			table.clear(pendingInputs)
			prepare_camera_for_mount()
			send_mount_input(true)
		end

		hand_over_to_default_camera()

		set_local_rider_mode("Idle")
	elseif wasMounted then
		mountTransitionCollisionToken += 1
		table.clear(mountTransitionCollisionStates)
		mountedState.TransitionMode = nil
		clear_transition_root_targets()
		reset_local_prediction()
		unbind_dismount_action()
		unbind_jump_action()
		unbind_rear_action()
		unbind_sprint_action()
		stop_local_rider_tracks(0.08)
		if previousTransitionMode == "Dismounting" then
			task.spawn(function()
				RunService.Heartbeat:Wait()
				if not mountedState.Active then
					restore_camera()
				end
			end)
		else
			restore_camera()
		end
	elseif Workspace.CurrentCamera and Workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable then
		mountedState.TransitionMode = nil
		clear_transition_root_targets()
		unbind_dismount_action()
		unbind_jump_action()
		unbind_rear_action()
		unbind_sprint_action()
		stop_local_rider_tracks(0.08)
		restore_camera()
	end

end

local function perform_dismount_request()
	unbind_dismount_action()
	unbind_jump_action()
	unbind_rear_action()
	unbind_sprint_action()
	local success, response = pcall(function()
		return Net.Function.HorseMountAction:Call({
			Action = "Dismount",
		})
	end)
	requestInFlight = false
	if success and response and response.Success then
		return
	end

	dismountStopStartedAt = nil
	mountedState.TransitionMode = nil
	clear_transition_root_targets()
	cancel_camera_transition()
	if mountedState.Active then
		bind_dismount_action()
		bind_jump_action()
		bind_rear_action()
		bind_sprint_action()
	end
end

request_dismount = function()
	if requestInFlight
		or dismountStopStartedAt ~= nil
		or not mountedState.Active
		or mountedState.TransitionMode == "Dismounting"
	then
		return
	end

	dismountStopStartedAt = os.clock()
	sprintButtonActive = false
	localPrediction.JumpPendingRequest = nil
	localPrediction.JumpPendingLanded = false
	localPrediction.RearPendingRequest = false
	unbind_jump_action()
	unbind_rear_action()
	unbind_sprint_action()
	send_mount_input(true)
end

localPlayer.CharacterRemoving:Connect(function()
	mountTransitionCollisionToken += 1
	table.clear(mountTransitionCollisionStates)
	clear_local_rider_animation_state()
	sync_mount_state_from_server({
		Mounted = false,
	})
end)

localPlayer.CharacterAdded:Connect(function()
	clear_local_rider_animation_state()
	preload_local_rider_animations()
	task.defer(function()
		if not mountedState.Active then
			restore_camera()
		end
	end)
end)

Net.Event.HorseMountState:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	if payload.Kind == "MovementState" then
		local acknowledgedSequence = tonumber(payload.LastProcessedSequence)
		if acknowledgedSequence then
			for sequence in pendingInputs do
				if sequence <= acknowledgedSequence then
					pendingInputs[sequence] = nil
				end
			end
		end

		local authoritativeSpeed = tonumber(payload.Speed)
		if mountedState.Active
			and payload.CorrectionRequired == true
			and is_finite_number(authoritativeSpeed)
		then
			HorseMovementState.ReconcileSpeed(
				localPrediction.HorizontalState,
				authoritativeSpeed,
				HorseMountConfig.HorseReconcileSpeedThreshold or 5,
				HorseMountConfig.HorseReconcileBlendAlpha or 0.2
			)
			localPrediction.HorizontalState.Mode = HorseMovementState.ClassifySpeed(
				localPrediction.HorizontalState.Speed,
				localPrediction.Movement or get_prediction_movement(mountedState.HorseId),
				HorseMovementState.IsRearActive(localPrediction.HorizontalState, os.clock())
			)
			localPrediction.CurrentSpeed = localPrediction.HorizontalState.Speed
		end
		return
	end

	if payload.Kind == "Mounting" then
		local now = Workspace:GetServerTimeNow()
		local duration = payload.Duration or HorseMountConfig.MountTransitionDuration or 1.8
		if is_finite_number(payload.EndsAt) then
			duration = math.max(payload.EndsAt - now, 0.05)
		end

		if is_finite_number(payload.CameraYaw) then
			mountedState.CameraYaw = payload.CameraYaw
		end

		local collisionToken = disable_character_collisions_for_mount_transition()
		local rootPart = get_character_root_part()
		mountedState.TransitionMode = "Mounting"
		mountedState.TransitionStartRootCFrame = typeof(payload.StartCFrame) == "CFrame"
			and payload.StartCFrame
			or (rootPart and rootPart.CFrame or nil)
		mountedState.TransitionTargetRootCFrame = typeof(payload.TargetCFrame) == "CFrame"
			and payload.TargetCFrame
			or nil
		prepare_camera_for_mount()
		play_local_mount_transition(
			duration,
			payload.TargetCFrame
		)
		task.delay(duration + 0.5, function()
			if collisionToken == mountTransitionCollisionToken and not mountedState.Active then
				restore_character_collisions_after_failed_mount()
			end
		end)
	elseif payload.Kind == "Mounted" and payload.State then
		sync_mount_state_from_server(payload.State)
	elseif payload.Kind == "Dismounting" then
		dismountStopStartedAt = nil
		if mountedState.Active then
			local now = Workspace:GetServerTimeNow()
			local transitionDuration = payload.Duration
				or ((HorseMountConfig.DismountTransitionDuration or 0.95)
					+ (HorseMountConfig.DismountSettleDuration or 0.1))
			if is_finite_number(payload.EndsAt) then
				transitionDuration = math.max(payload.EndsAt - now, 0.05)
			end

			local animationDuration = payload.AnimationDuration
				or HorseMountConfig.DismountTransitionDuration
				or 0.95
			if is_finite_number(payload.AnimationEndsAt) then
				animationDuration = math.max(payload.AnimationEndsAt - now, 0.05)
			end

			local moveDelay = payload.MoveDelay or HorseMountConfig.DismountReleaseDelay or 0.12
			if is_finite_number(payload.ReleaseAt) then
				moveDelay = math.max(payload.ReleaseAt - now, 0)
			end

			local moveDuration = math.max(animationDuration - moveDelay, 0.08)
			local rootPart = get_character_root_part()
			mountedState.TransitionMode = "Dismounting"
			mountedState.TransitionStartRootCFrame = typeof(payload.StartCFrame) == "CFrame"
				and payload.StartCFrame
				or (rootPart and rootPart.CFrame or nil)
			mountedState.TransitionTargetRootCFrame = typeof(payload.TargetCFrame) == "CFrame"
				and payload.TargetCFrame
				or nil
			unbind_dismount_action()
			unbind_jump_action()
			unbind_rear_action()
			unbind_sprint_action()
			set_local_horse_animation_mode(localPrediction.HorseVisual, "Idle")
			start_camera_transition("Dismounting", transitionDuration)
			play_local_dismount_transition(
				animationDuration,
				moveDelay,
				moveDuration,
				payload.AnimationEndsAt,
				payload.TargetCFrame
			)
		end
	elseif payload.Kind == "Unmounted" then
		sync_mount_state_from_server({
			Mounted = false,
		})
	end
end)

preload_local_rider_animations()

task.spawn(function()
	local success, response = pcall(function()
		return Net.Function.HorseMountAction:Call({
			Action = "GetState",
		})
	end)

	if success and response and response.Success and response.State then
		sync_mount_state_from_server(response.State)
	end
end)

RunService.RenderStepped:Connect(function(deltaTime)
	update_camera_transition(deltaTime)

	if not mountedState.Active then
		stop_mount_movement_sound()
		return
	end

	if mountedState.TransitionMode == "Dismounting" then
		stop_mount_movement_sound()
		return
	end

	local camera = Workspace.CurrentCamera
	if camera then
		mountedState.CameraYaw = build_angle_y(camera.CFrame)
	end

	update_local_mount_prediction(deltaTime)
	if dismountStopStartedAt ~= nil and not requestInFlight then
		local elapsed: number = os.clock() - dismountStopStartedAt
		local stopThreshold: number = math.max(
			tonumber(HorseMountConfig.HorseDismountStopSpeedThreshold) or 0.2,
			0
		)
		local timeoutSeconds: number = math.max(
			tonumber(HorseMountConfig.HorseDismountStopTimeoutSeconds) or 2.4,
			0.1
		)
		if (not localPrediction.JumpAirborne and math.abs(localPrediction.CurrentSpeed) <= stopThreshold)
			or elapsed >= timeoutSeconds
		then
			requestInFlight = true
			task.spawn(perform_dismount_request)
		end
	end
	update_local_horse_animation()
	update_mount_movement_sound()

	update_camera_fov(deltaTime)
	update_camera_motion(deltaTime)
	update_local_rider_animation()

	send_mount_input(false)
end)

script:SetAttribute("RuntimeReady", true)
