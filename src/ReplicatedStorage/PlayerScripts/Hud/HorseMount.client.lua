local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local ToolDictionary = require(Dictionary:WaitForChild("ToolDictionary"))
local HorseMountConfig = require(GameData:WaitForChild("HorseMountConfig"))
local Net = require(Libraries:WaitForChild("Net"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local plotValue = localPlayer:WaitForChild(ToolDictionary.PlotValueName)

local GUI_NAME = "HorseMountGui"
local BUTTON_TEXT = "Montar"
local MOUNT_ROOT_NAME = "HorseMountRoot"
local MOUNT_LINEAR_VELOCITY_NAME = "HorseMountLinearVelocity"
local MOUNT_ALIGN_ORIENTATION_NAME = "HorseMountAlignOrientation"
local LOCAL_MOUNT_SMOOTHNESS = 26
local MOBILE_CONTROL_GAP = 10

local HORSE_FOLDER_NAME = ToolDictionary.HorseFolderName
local VISUAL_HORSE_ATTRIBUTE = ToolDictionary.VisualHorseAttribute
local HORSE_ID_ATTRIBUTE = ToolDictionary.HorseIdAttribute

local previousCameraType = nil
local previousCameraSubject = nil
local previousMouseBehavior = nil
local previousMouseIconEnabled = nil
local previousFieldOfView = nil

local requestInFlight = false
local panelOpen = false
local horseButtons = {}
local ui = {}
local send_mount_input
local request_dismount
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
}

local lastInputSentAt = 0
local lastSentMoveX = 0
local lastSentMoveZ = 0
local lastSentCameraYaw = 0
local lastSentSprinting = false

local function build_angle_y(cframe)
	local lookVector = cframe.LookVector
	return math.atan2(-lookVector.X, -lookVector.Z)
end

local function build_yaw_from_direction(direction)
	return math.atan2(-direction.X, -direction.Z)
end

local function wrap_angle(angle)
	return math.atan2(math.sin(angle), math.cos(angle))
end

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
	if not character then
		return nil
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return rootPart
	end

	return nil
end

local function get_control_start_yaw()
	local camera = Workspace.CurrentCamera
	if camera then
		return build_angle_y(camera.CFrame)
	end

	local rootPart = get_character_root_part()
	if rootPart then
		return build_angle_y(rootPart.CFrame)
	end

	return mountedState.CameraYaw
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
	if type(ownedHorses) ~= "table" then
		return nil
	end

	return ownedHorses[horseId]
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
	if not mountedState.Active then
		return false
	end

	return mobileSprintPressed
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
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
	local groundedPosition = resolve_ground_position(
		currentPosition,
		{ horseVisual, localPlayer.Character },
		localPrediction.GroundOffset
	)
	local verticalError = groundedPosition.Y - currentPosition.Y
	local verticalVelocity = math.clamp(
		verticalError * (HorseMountConfig.GroundStickResponsiveness or 16),
		-(HorseMountConfig.GroundStickMaxVelocity or 48),
		HorseMountConfig.GroundStickMaxVelocity or 48
	)

	linearVelocity.VectorVelocity = (moveDirection * localPrediction.CurrentSpeed) + Vector3.new(0, verticalVelocity, 0)
	alignOrientation.CFrame = orientation
	localPrediction.Position = currentPosition
end

local function restore_camera()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = previousCameraType or Enum.CameraType.Custom

		if previousCameraSubject then
			camera.CameraSubject = previousCameraSubject
		else
			local character = localPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end

		if previousFieldOfView ~= nil then
			camera.FieldOfView = previousFieldOfView
		end
	end

	if previousMouseBehavior ~= nil then
		UserInputService.MouseBehavior = previousMouseBehavior
	end

	if previousMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = previousMouseIconEnabled
	end

	previousCameraType = nil
	previousCameraSubject = nil
	previousMouseBehavior = nil
	previousMouseIconEnabled = nil
	previousFieldOfView = nil
end

local function prepare_camera_for_mount()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	previousCameraType = camera.CameraType
	previousCameraSubject = camera.CameraSubject
	previousMouseBehavior = UserInputService.MouseBehavior
	previousMouseIconEnabled = UserInputService.MouseIconEnabled
	previousFieldOfView = camera.FieldOfView

	camera.CameraType = Enum.CameraType.Scriptable
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
end

local function update_camera_fov(deltaTime)
	local camera = Workspace.CurrentCamera
	if not camera or not mountedState.Active then
		return
	end

	local movement = localPrediction.Movement or get_prediction_movement(mountedState.HorseId)
	local sprintSpeed = movement.SprintSpeed or 26
	local speedAlpha = 0
	if sprintSpeed > 0 then
		speedAlpha = math.clamp((localPrediction.CurrentSpeed or 0) / sprintSpeed, 0, 1)
	end

	local baseFov = previousFieldOfView or HorseMountConfig.MountedBaseFov
	local targetFov = baseFov + (HorseMountConfig.MountedFovBoost * speedAlpha)
	if is_sprint_input_active() then
		targetFov += HorseMountConfig.MountedSprintFovBoost
	end

	local blendAlpha = 1 - math.exp(-(HorseMountConfig.MountedFovSmoothness or 8) * deltaTime)
	camera.FieldOfView = camera.FieldOfView + ((targetFov - camera.FieldOfView) * blendAlpha)
end

local function create_instance(className, properties)
	local instance = Instance.new(className)

	for propertyName, propertyValue in pairs(properties) do
		instance[propertyName] = propertyValue
	end

	return instance
end

local function clear_horse_buttons()
	for _, button in ipairs(horseButtons) do
		if button.Parent then
			button:Destroy()
		end
	end

	table.clear(horseButtons)
end

local function get_owned_horses()
	local horses = DataUtility.client.get("Horses")
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

local function update_panel_canvas()
	local layout = ui.ListLayout
	local listFrame = ui.ListFrame
	if not layout or not listFrame then
		return
	end

	listFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 8)
end

local function update_ui_state()
	if not ui.ActionButton then
		return
	end

	local canShowButton = not mountedState.Active
	ui.ActionButton.Visible = canShowButton
	ui.ActionButton.Text = requestInFlight and "..." or BUTTON_TEXT
	ui.ActionButton.AutoButtonColor = canShowButton and not requestInFlight
	ui.ActionButton.Active = canShowButton and not requestInFlight
	ui.ActionButton.BackgroundColor3 = requestInFlight
		and Color3.fromRGB(67, 88, 77)
		or Color3.fromRGB(36, 111, 79)

	local shouldShowPanel = canShowButton and panelOpen and not requestInFlight
	ui.ListPanel.Visible = shouldShowPanel

	if ui.MobileControlsFrame then
		ui.MobileControlsFrame.Visible = isTouchDevice and mountedState.Active
	end

	if ui.MobileSprintButton then
		ui.MobileSprintButton.Visible = isTouchDevice and mountedState.Active
	end

	if ui.MobileDismountButton then
		ui.MobileDismountButton.Visible = isTouchDevice and mountedState.Active
	end
end

local function render_horse_list()
	clear_horse_buttons()

	local horses = get_owned_horses()
	if #horses == 0 then
		local emptyLabel = create_instance("TextLabel", {
			Name = "EmptyLabel",
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = "Sem cavalos disponiveis",
			TextColor3 = Color3.fromRGB(210, 218, 224),
			TextSize = 15,
			Size = UDim2.new(1, -6, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = ui.ListFrame,
		})

		horseButtons[#horseButtons + 1] = emptyLabel
		update_panel_canvas()
		return
	end

	for _, horseEntry in ipairs(horses) do
		local horseButton = create_instance("TextButton", {
			Name = horseEntry.Id,
			AutoButtonColor = true,
			BackgroundColor3 = Color3.fromRGB(31, 37, 43),
			BorderSizePixel = 0,
			Font = Enum.Font.GothamMedium,
			Text = horseEntry.Name,
			TextColor3 = Color3.fromRGB(245, 247, 250),
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
			if requestInFlight or mountedState.Active then
				return
			end

			requestInFlight = true
			update_ui_state()

			local cameraYaw = get_control_start_yaw()
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
				mountedState.Active = true
				mountedState.HorseId = response.State.HorseId
				mountedState.HorseName = response.State.HorseName
				mountedState.CameraYaw = cameraYaw
				set_mobile_sprint_pressed(false)
				reset_local_prediction()
				prepare_camera_for_mount()
				send_mount_input(true)
			end

			update_ui_state()
		end)

		horseButtons[#horseButtons + 1] = horseButton
	end

	update_panel_canvas()
end

local function ensure_ui()
	if ui.ScreenGui and ui.ScreenGui.Parent then
		return
	end

	local existingGui = playerGui:FindFirstChild(GUI_NAME)
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = create_instance("ScreenGui", {
		Name = GUI_NAME,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
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
		Name = "MobileRunButton",
		AnchorPoint = Vector2.new(1, 1),
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(131, 82, 25),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.fromOffset(160, 48),
		Text = "Correr",
		TextColor3 = Color3.fromRGB(248, 239, 223),
		TextSize = 17,
		Visible = false,
		Parent = mobileControlsFrame,
	})

	create_instance("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = mobileRunButton,
	})

	create_instance("UIStroke", {
		Color = Color3.fromRGB(255, 223, 181),
		Transparency = 0.22,
		Parent = mobileRunButton,
	})

	local mobileDismountButton = create_instance("TextButton", {
		Name = "MobileDismountButton",
		AnchorPoint = Vector2.new(1, 1),
		AutoButtonColor = true,
		BackgroundColor3 = Color3.fromRGB(84, 39, 39),
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.new(1, 0, 0, -(48 + MOBILE_CONTROL_GAP)),
		Size = UDim2.fromOffset(160, 48),
		Text = "Descer",
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

	listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update_panel_canvas)

	actionButton.MouseButton1Click:Connect(function()
		if requestInFlight or mountedState.Active then
			return
		end

		panelOpen = not panelOpen
		if panelOpen then
			render_horse_list()
		end

		update_ui_state()
	end)

	mobileRunButton.InputBegan:Connect(function(input)
		if not mountedState.Active then
			return
		end

		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			set_mobile_sprint_pressed(true)
		end
	end)

	mobileRunButton.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			set_mobile_sprint_pressed(false)
		end
	end)

	mobileDismountButton.MouseButton1Click:Connect(function()
		request_dismount()
	end)

	ui.ScreenGui = screenGui
	ui.ActionButton = actionButton
	ui.ListPanel = listPanel
	ui.ListFrame = listFrame
	ui.ListLayout = listLayout
	ui.MobileControlsFrame = mobileControlsFrame
	ui.MobileSprintButton = mobileRunButton
	ui.MobileDismountButton = mobileDismountButton

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

local function sync_mount_state_from_server(statePayload)
	local wasMounted = mountedState.Active
	local mounted = type(statePayload) == "table" and statePayload.Mounted == true

	mountedState.Active = mounted
	mountedState.HorseId = mounted and statePayload.HorseId or nil
	mountedState.HorseName = mounted and statePayload.HorseName or nil

	if mounted then
		panelOpen = false

		if not wasMounted then
			mountedState.CameraYaw = get_control_start_yaw()
			set_mobile_sprint_pressed(false)
			reset_local_prediction()
			prepare_camera_for_mount()
			send_mount_input(true)
		end
	elseif wasMounted then
		set_mobile_sprint_pressed(false)
		reset_local_prediction()
		restore_camera()
	end

	update_ui_state()
end

request_dismount = function()
	if requestInFlight or not mountedState.Active then
		return
	end

	requestInFlight = true
	update_ui_state()

	local success, response = pcall(function()
		return Net.Function.HorseMountAction:Call({
			Action = "Dismount",
		})
	end)

	requestInFlight = false

	if success and response and response.Success then
		sync_mount_state_from_server({
			Mounted = false,
		})
	else
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or not mountedState.Active then
		return
	end

	if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
		request_dismount()
	end
end)

Net.Event.HorseMountState:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	if payload.Kind == "Mounted" and payload.State then
		sync_mount_state_from_server(payload.State)
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
	if not mountedState.Active then
		return
	end

	mountedState.CameraYaw = wrap_angle(
		mountedState.CameraYaw - (UserInputService:GetMouseDelta().X * HorseMountConfig.MouseSensitivity)
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

	send_mount_input(false)
end)
