local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")
local HudModules = ClientModules:WaitForChild("Hud")

local ToolDictionary = require(Dictionary:WaitForChild("ToolDictionary"))
local HorseMountConfig = require(GameData:WaitForChild("HorseMountConfig"))
local Net = require(Libraries:WaitForChild("Net"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseMountCamera = require(HudModules:WaitForChild("HorseMountCamera"))
local HorseMountUi = require(HudModules:WaitForChild("HorseMountUi"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local plotValue = localPlayer:WaitForChild(ToolDictionary.PlotValueName)

local BUTTON_TEXT = "Montar"
local MOUNT_ROOT_NAME = "HorseMountRoot"
local MOUNT_LINEAR_VELOCITY_NAME = "HorseMountLinearVelocity"
local MOUNT_ALIGN_ORIENTATION_NAME = "HorseMountAlignOrientation"
local LOCAL_MOUNT_SMOOTHNESS = 26
local DISMOUNT_ACTION_NAME = "HorseMountDismount"

local HORSE_FOLDER_NAME = ToolDictionary.HorseFolderName
local VISUAL_HORSE_ATTRIBUTE = ToolDictionary.VisualHorseAttribute
local HORSE_ID_ATTRIBUTE = ToolDictionary.HorseIdAttribute

local requestInFlight = false
local panelOpen = false
local horseButtons = {}
local ui = {}
local send_mount_input
local request_dismount
local sync_mount_state_from_server
local isTouchDevice = UserInputService.TouchEnabled
local mobileSprintPressed = false
local localPrediction = {
	HorseVisual = nil,
	MountRoot = nil,
	LinearVelocity = nil,
	AlignOrientation = nil,
	CurrentYaw = 0,
	CurrentSpeed = 0,
	ForwardHeldTime = 0,
	LastMoveDirection = nil,
	GroundOffset = 0,
	Position = nil,
	Movement = nil,
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
local cameraController = HorseMountCamera.new(localPlayer, HorseMountConfig)

local function bind_dismount_action()
	ContextActionService:BindActionAtPriority(
		DISMOUNT_ACTION_NAME,
		function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				request_dismount()
			end

			return Enum.ContextActionResult.Sink
		end,
		false,
		3000,
		Enum.KeyCode.LeftControl,
		Enum.KeyCode.RightControl,
		Enum.KeyCode.P
	)
end

local function unbind_dismount_action()
	ContextActionService:UnbindAction(DISMOUNT_ACTION_NAME)
end

local function get_default_camera_subject() return localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid") or nil end

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

local function build_yaw_from_direction(direction) return math.atan2(-direction.X, -direction.Z) end

local function wrap_angle(angle) return math.atan2(math.sin(angle), math.cos(angle)) end

local function is_finite_number(value) return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge end

local function move_towards(current, target, maxDelta)
	if math.abs(target - current) <= maxDelta then
		return target
	end

	if target > current then
		return current + maxDelta
	end

	return current - maxDelta
end

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

local function get_move_vector()
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

	local fadeTime = HorseMountConfig.RiderResumeBlendTime or 0.24
	local tracks = animationState.Tracks

	if mode == "Idle" then
		stop_local_track(tracks.HopOn, 0.05)
		stop_local_track(tracks.HopOff, 0.05)
		stop_local_track(tracks.Ride, fadeTime)
		play_local_track(tracks.Idle, fadeTime, 1, 1)
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

local function smooth_local_character_to_root_cframe(targetRootCFrame, duration)
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
	play_local_track(tracks.HopOn, 0.05, 1, 1)
	animationState.Mode = "Mounting"

	if targetCFrame then
		task.spawn(function()
			local moveDelay = math.min(0.08, math.max(duration or 0, 0) * 0.12)
			if moveDelay > 0 then
				task.wait(moveDelay)
			end

			if transitionToken ~= animationState.TransitionToken then
				return
			end

			smooth_local_character_to_root_cframe(
				targetCFrame,
				math.max((duration or HorseMountConfig.MountTransitionDuration or 1.8) - moveDelay, 0.12)
			)
		end)
	end
end

local function play_local_dismount_transition(animationDuration, settleDuration, targetCFrame)
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
	play_local_track(tracks.HopOff, 0.05, 1, 1)
	animationState.Mode = "Dismounting"

	task.spawn(function()
		local leadTime = math.max(HorseMountConfig.DismountFinalPoseLeadTime or 0, 0)
		local holdTime = math.max(HorseMountConfig.DismountFinalPoseHoldTime or 0, 0)
		local waitTime = math.max((animationDuration or 0) - leadTime, 0)
		if waitTime > 0 then
			task.wait(waitTime)
		end

		if transitionToken ~= animationState.TransitionToken then
			return
		end

		if targetCFrame then
			smooth_local_character_to_root_cframe(targetCFrame, math.max(settleDuration or 0, 0.08))
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

	local moveX, moveZ = get_move_vector()
	local inputMagnitude = math.sqrt((moveX * moveX) + (moveZ * moveZ))
	local moving = (localPrediction.CurrentSpeed or 0) > 0.25
		or inputMagnitude > (HorseMountConfig.ForwardInputDeadzone or 0.05)

	set_local_rider_mode(moving and "Ride" or "Idle")
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

local function get_instance_lowest_y(instance)
	if instance:IsA("BasePart") then
		return get_base_part_lowest_y(instance)
	end

	local lowestY = math.huge
	local foundBasePart = false

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			foundBasePart = true
			lowestY = math.min(lowestY, get_base_part_lowest_y(descendant))
		end
	end

	if not foundBasePart then
		return nil
	end

	return lowestY
end

local function get_ground_offset(instance)
	local lowestY = get_instance_lowest_y(instance)
	if not lowestY then
		return 0
	end

	return instance:GetPivot().Position.Y - lowestY
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
	local movement = type(horse) == "table" and horse.Movement or nil

	return {
		WalkSpeed = type(movement) == "table" and movement.WalkSpeed or 14,
		TrotSpeed = type(movement) == "table" and movement.TrotSpeed or 18,
		CanterSpeed = type(movement) == "table" and movement.CanterSpeed or 22,
		SprintSpeed = type(movement) == "table" and movement.SprintSpeed or 26,
		TurnRate = type(movement) == "table" and movement.TurnRate or 0.8,
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
		mobileSprintPressed
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	) or false
end

local function set_mobile_sprint_pressed(pressed)
	mobileSprintPressed = pressed == true

	if ui.MobileSprintButton then
		ui.MobileSprintButton.BackgroundColor3 = mobileSprintPressed
			and Color3.fromRGB(186, 118, 34)
			or Color3.fromRGB(131, 82, 25)
	end
end

local function reset_local_prediction()
	localPrediction.HorseVisual = nil
	localPrediction.MountRoot = nil
	localPrediction.LinearVelocity = nil
	localPrediction.AlignOrientation = nil
	localPrediction.CurrentYaw = mountedState.CameraYaw
	localPrediction.CurrentSpeed = 0
	localPrediction.ForwardHeldTime = 0
	localPrediction.LastMoveDirection = nil
	localPrediction.GroundOffset = 0
	localPrediction.Position = nil
	localPrediction.Movement = nil
end

local function ensure_local_prediction()
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
		localPrediction.ForwardHeldTime = 0
		localPrediction.LastMoveDirection = nil
		localPrediction.GroundOffset = horseVisual and get_ground_offset(horseVisual) or 0
		localPrediction.Movement = get_prediction_movement(mountedState.HorseId)
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
	local currentYaw = localPrediction.CurrentYaw
	local targetYaw = currentYaw
	local turnRateAlpha = math.clamp((movement.TurnRate or 0.8) - 0.65, 0, 0.25) / 0.25
	local maxTurnSpeedDegrees = HorseMountConfig.TurnSpeedBaseDegrees + (HorseMountConfig.TurnSpeedScaleDegrees * turnRateAlpha)
	local inputX, inputZ = get_move_vector()
	local inputMagnitude = math.sqrt((inputX * inputX) + (inputZ * inputZ))
	if inputMagnitude > 1 then
		inputX /= inputMagnitude
		inputZ /= inputMagnitude
	end

	local forwardAmount = math.max(0, -inputZ)
	local backwardAmount = math.max(0, inputZ)
	local currentSpeed = localPrediction.CurrentSpeed
	local walkSpeed = movement.WalkSpeed or 14
	local sprintSpeed = movement.SprintSpeed or 26
	local startForwardSpeed = math.max(movement.TrotSpeed or 18, movement.CanterSpeed or 22)
	local sprinting = is_sprint_input_active()
	local cameraOrientation = CFrame.Angles(0, mountedState.CameraYaw, 0)
	local desiredMoveVector = (cameraOrientation.RightVector * inputX) + (cameraOrientation.LookVector * (-inputZ))
	local desiredMoveDirection = nil

	if desiredMoveVector.Magnitude > 0.001 then
		desiredMoveDirection = desiredMoveVector.Unit
	end

	if sprinting then
		local wasForwarding = localPrediction.ForwardHeldTime > 0
		localPrediction.ForwardHeldTime = math.min(
			HorseMountConfig.ForwardAccelerationSeconds,
			localPrediction.ForwardHeldTime + deltaTime
		)

		local forwardAlpha = math.clamp(
			localPrediction.ForwardHeldTime / HorseMountConfig.ForwardAccelerationSeconds,
			0,
			1
		)
		local forwardTargetSpeed = startForwardSpeed + ((sprintSpeed - startForwardSpeed) * forwardAlpha)

		if not wasForwarding and currentSpeed < startForwardSpeed then
			currentSpeed = startForwardSpeed
		else
			currentSpeed = move_towards(
				currentSpeed,
				forwardTargetSpeed,
				HorseMountConfig.SidewaysAccelerationPerSecond * deltaTime
			)
		end

		targetYaw = mountedState.CameraYaw
		desiredMoveDirection = cameraOrientation.LookVector
	else
		localPrediction.ForwardHeldTime = math.max(
			0,
			localPrediction.ForwardHeldTime - (deltaTime * HorseMountConfig.ForwardDecayPerSecond)
		)

		if desiredMoveDirection then
			local directionScale = math.max(forwardAmount, backwardAmount, math.abs(inputX), 0.35)
			local targetWalkSpeed = walkSpeed * directionScale
			currentSpeed = move_towards(
				currentSpeed,
				targetWalkSpeed,
				HorseMountConfig.SidewaysAccelerationPerSecond * deltaTime
			)
			targetYaw = build_yaw_from_direction(desiredMoveDirection)
		else
			currentSpeed = move_towards(
				currentSpeed,
				0,
				HorseMountConfig.PassiveBrakingPerSecond * deltaTime
			)
		end
	end

	localPrediction.CurrentSpeed = math.max(0, currentSpeed)
	local angleDelta = wrap_angle(targetYaw - currentYaw)
	currentYaw += math.clamp(angleDelta, -math.rad(maxTurnSpeedDegrees) * deltaTime, math.rad(maxTurnSpeedDegrees) * deltaTime)
	localPrediction.CurrentYaw = wrap_angle(currentYaw)

	local orientation = CFrame.Angles(0, localPrediction.CurrentYaw, 0)
	if desiredMoveDirection and desiredMoveDirection.Magnitude > 0.001 then
		localPrediction.LastMoveDirection = desiredMoveDirection
	end

	local moveDirection = localPrediction.LastMoveDirection
	if not moveDirection or moveDirection.Magnitude <= 0 then
		moveDirection = orientation.LookVector
		localPrediction.LastMoveDirection = moveDirection
	end

	local currentPosition = mountRoot.Position
	local verticalVelocity = 0
	if HorseMountConfig.StickMountedHorseToGround == true then
		local groundedPosition = resolve_ground_position(
			currentPosition,
			{ horseVisual, localPlayer.Character },
			localPrediction.GroundOffset
		)
		local verticalError = groundedPosition.Y - currentPosition.Y
		verticalVelocity = math.clamp(
			verticalError * (HorseMountConfig.GroundStickResponsiveness or 16),
			-(HorseMountConfig.GroundStickMaxVelocity or 48),
			HorseMountConfig.GroundStickMaxVelocity or 48
		)
	end

	linearVelocity.VectorVelocity = (moveDirection * localPrediction.CurrentSpeed) + Vector3.new(0, verticalVelocity, 0)
	alignOrientation.CFrame = orientation
	localPrediction.Position = currentPosition
end

local function get_control_start_yaw() return cameraController:getControlStartYaw(get_character_root_part, mountedState) end
local function prepare_camera_for_mount() cameraController:prepareCameraForMount() end
local function start_camera_transition(mode, duration) cameraController:startCameraTransition(mode, duration) end
local function cancel_camera_transition() cameraController:cancelCameraTransition() end
local function restore_camera() cameraController:restoreCamera(get_character_root_part) end
local function release_camera_after_dismount() cameraController:releaseCameraAfterDismount() end
local function update_camera_restore(deltaTime) cameraController:updateCameraRestore(deltaTime, get_character_root_part) end
local function update_camera_transition(deltaTime) cameraController:updateCameraTransition(deltaTime, mountedState, get_character_root_part) end
local function update_camera_fov(deltaTime) cameraController:updateCameraFov(deltaTime, mountedState, localPrediction, get_prediction_movement, is_sprint_input_active) end
local function get_running_sensitivity_multiplier() return cameraController:getRunningSensitivityMultiplier(mountedState, localPrediction, get_prediction_movement) end
local function update_ui_state() HorseMountUi.updateUiState(ui, { mountedState = mountedState, requestInFlight = requestInFlight, panelOpen = panelOpen, isTouchDevice = isTouchDevice }) end

local function render_horse_list()
	HorseMountUi.renderHorseList(ui, horseButtons, {
		plotValue = plotValue,
		dataUtility = DataUtility,
		onSelectHorse = function(horseEntry)
			if requestInFlight or mountedState.Active then
				return
			end

			requestInFlight = true
			update_ui_state()

			local cameraYaw = get_control_start_yaw()
			mountedState.CameraYaw = cameraYaw

			local success, response = pcall(function()
				return Net.Function.HorseMountAction:Call({
					Action = "Mount",
					HorseId = horseEntry.Id,
					CameraYaw = cameraYaw,
				})
			end)

			requestInFlight = false

			if success and response and response.Success and response.State and response.State.Mounted == true then
				panelOpen = false
				sync_mount_state_from_server(response.State)
			else
				mountedState.TransitionMode = nil
				clear_transition_root_targets()
				cancel_camera_transition()
				restore_camera()
			end

			update_ui_state()
		end,
	})
end

local function ensure_ui()
	HorseMountUi.ensureUi(ui, {
		playerGui = playerGui,
		onTogglePanelRequested = function()
			if requestInFlight or mountedState.Active then
				return
			end

			panelOpen = not panelOpen
			if panelOpen then
				render_horse_list()
			end

			update_ui_state()
		end,
		onSetMobileSprintPressed = function(pressed)
			if not mountedState.Active then
				return
			end

			set_mobile_sprint_pressed(pressed)
		end,
		onDismountRequested = function()
			request_dismount()
		end,
	})

	update_ui_state()
end

send_mount_input = function(forceSend)
	if not mountedState.Active then
		return
	end

	local now = os.clock()
	local moveX, moveZ = get_move_vector()
	local sprinting = is_sprint_input_active()

	if sprinting then
		moveX = 0
		moveZ = 0
	end

	local yawChanged = math.abs(mountedState.CameraYaw - lastSentCameraYaw) >= 0.01
	local moveChanged = math.abs(moveX - lastSentMoveX) >= 0.01 or math.abs(moveZ - lastSentMoveZ) >= 0.01
	local sprintChanged = sprinting ~= lastSentSprinting

	if not forceSend and now - lastInputSentAt < HorseMountConfig.InputSendInterval and not yawChanged and not moveChanged and not sprintChanged then
		return
	end

	lastInputSentAt = now
	lastSentMoveX = moveX
	lastSentMoveZ = moveZ
	lastSentCameraYaw = mountedState.CameraYaw
	lastSentSprinting = sprinting

	Net.Event.HorseMountInput:Fire({
		MoveX = moveX,
		MoveZ = moveZ,
		CameraYaw = mountedState.CameraYaw,
		Sprinting = sprinting,
	})
end

sync_mount_state_from_server = function(statePayload)
	local wasMounted = mountedState.Active
	local previousTransitionMode = mountedState.TransitionMode
	local mounted = type(statePayload) == "table" and statePayload.Mounted == true

	mountedState.Active = mounted
	mountedState.HorseId = mounted and statePayload.HorseId or nil
	mountedState.HorseName = mounted and statePayload.HorseName or nil

	if mounted then
		panelOpen = false
		bind_dismount_action()
		mountedState.TransitionMode = nil
		clear_transition_root_targets()
		cancel_camera_transition()

		if not wasMounted then
			if previousTransitionMode ~= "Mounting" then
				mountedState.CameraYaw = get_control_start_yaw()
			end
			set_mobile_sprint_pressed(false)
			reset_local_prediction()
			prepare_camera_for_mount()
			send_mount_input(true)
		end

		set_local_rider_mode("Idle")
	elseif wasMounted then
		mountedState.TransitionMode = nil
		clear_transition_root_targets()
		set_mobile_sprint_pressed(false)
		reset_local_prediction()
		unbind_dismount_action()
		stop_local_rider_tracks(0.08)
		if previousTransitionMode == "Dismounting" then
			task.spawn(function()
				RunService.Heartbeat:Wait()
				if not mountedState.Active then
					release_camera_after_dismount()
				end
			end)
		else
			restore_camera()
		end
	elseif UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter
		or (Workspace.CurrentCamera and Workspace.CurrentCamera.CameraType == Enum.CameraType.Scriptable)
	then
		mountedState.TransitionMode = nil
		clear_transition_root_targets()
		unbind_dismount_action()
		stop_local_rider_tracks(0.08)
		restore_camera()
	end

	update_ui_state()
end

request_dismount = function()
	if requestInFlight or not mountedState.Active or mountedState.TransitionMode == "Dismounting" then
		return
	end

	requestInFlight = true
	unbind_dismount_action()
	update_ui_state()

	local success, response = pcall(function()
		return Net.Function.HorseMountAction:Call({
			Action = "Dismount",
		})
	end)

	requestInFlight = false

	if success and response and response.Success then
		update_ui_state()
	else
		mountedState.TransitionMode = nil
		clear_transition_root_targets()
		cancel_camera_transition()
		if mountedState.Active then
			bind_dismount_action()
		end
		update_ui_state()
	end
end

ensure_ui()

DataUtility.client.bind("Horses.Owned", function()
	if panelOpen then
		render_horse_list()
	end
end)

DataUtility.client.bind("Horses.OrderedIds", function()
	if panelOpen then
		render_horse_list()
	end
end)

localPlayer.CharacterRemoving:Connect(function()
	clear_local_rider_animation_state()
	sync_mount_state_from_server({
		Mounted = false,
	})
end)

localPlayer.CharacterAdded:Connect(function()
	clear_local_rider_animation_state()
	task.defer(function()
		if not mountedState.Active then
			restore_camera()
		end
	end)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not mountedState.Active then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftControl
		or input.KeyCode == Enum.KeyCode.RightControl
		or input.KeyCode == Enum.KeyCode.P
	then
		request_dismount()
		return
	end

	if gameProcessed then
		return
	end
end)

Net.Event.HorseMountState:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.Kind == "Mounting" then
		if is_finite_number(payload.CameraYaw) then
			mountedState.CameraYaw = payload.CameraYaw
		end

		mountedState.TransitionMode = "Mounting"
		clear_transition_root_targets()
		play_local_mount_transition(
			payload.Duration or HorseMountConfig.MountTransitionDuration or 1.8,
			payload.TargetCFrame
		)
	elseif payload.Kind == "Mounted" and payload.State then
		sync_mount_state_from_server(payload.State)
	elseif payload.Kind == "Dismounting" then
		if mountedState.Active then
			mountedState.TransitionMode = "Dismounting"
			clear_transition_root_targets()
			unbind_dismount_action()
			release_camera_after_dismount()
			play_local_dismount_transition(
				payload.AnimationDuration or HorseMountConfig.DismountTransitionDuration or 0.95,
				payload.SettleDuration or HorseMountConfig.DismountSettleDuration or 0.12,
				payload.TargetCFrame
			)
			update_ui_state()
		end
	elseif payload.Kind == "Unmounted" then
		sync_mount_state_from_server({
			Mounted = false,
		})
	end
end)

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
	update_camera_restore(deltaTime)
	update_camera_transition(deltaTime)

	if not mountedState.Active then
		return
	end

	if mountedState.TransitionMode == "Dismounting" then
		return
	end

	local sensitivityMultiplier = get_running_sensitivity_multiplier()
	mountedState.CameraYaw = wrap_angle(
		mountedState.CameraYaw - (UserInputService:GetMouseDelta().X * HorseMountConfig.MouseSensitivity * sensitivityMultiplier)
	)

	update_local_mount_prediction(deltaTime)

	local rootPart = get_character_root_part()
	local camera = Workspace.CurrentCamera
	if camera and rootPart then
		local yawCFrame = CFrame.Angles(0, mountedState.CameraYaw, 0)
		local focus = rootPart.Position + Vector3.new(0, HorseMountConfig.CameraFocusHeightOffset, 0)
		local centeredPosition = focus
			- (yawCFrame.LookVector * HorseMountConfig.CameraBackOffset)
			+ Vector3.new(0, HorseMountConfig.CameraHeightOffset, 0)
		local centeredLookAt = focus + (yawCFrame.LookVector * HorseMountConfig.CameraLookAhead)
		local centeredCFrame = CFrame.lookAt(centeredPosition, centeredLookAt)
		local desiredCFrame = centeredCFrame + (yawCFrame.RightVector * HorseMountConfig.CameraSideOffset)
		local blendAlpha = 1 - math.exp(-HorseMountConfig.CameraSmoothness * deltaTime)

		camera.CameraType = Enum.CameraType.Scriptable
		camera.CFrame = camera.CFrame:Lerp(desiredCFrame, blendAlpha)
	end

	update_camera_fov(deltaTime)
	update_local_rider_animation()

	send_mount_input(false)
end)
