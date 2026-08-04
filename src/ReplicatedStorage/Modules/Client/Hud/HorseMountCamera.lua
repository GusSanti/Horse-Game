local Workspace = game:GetService("Workspace")

local HorseMountCamera = {}
HorseMountCamera.__index = HorseMountCamera

local CAMERA_HEAD_OFFSET = Vector3.new(0, 1.5, 0)
local CAMERA_R15_HEAD_OFFSET = Vector3.new(0, 1.5, 0)
local CAMERA_R15_HEAD_OFFSET_NO_SCALING = Vector3.new(0, 2, 0)
local CAMERA_HUMANOID_ROOT_PART_SIZE = Vector3.new(2, 2, 1)
local CAMERA_SEAT_OFFSET = Vector3.new(0, 5, 0)

local function build_angle_y(cframe)
	local lookVector = cframe.LookVector
	return math.atan2(-lookVector.X, -lookVector.Z)
end

local function build_eased_alpha(alpha)
	return alpha * alpha * (3 - (2 * alpha))
end

local function get_camera_subject_position(cameraSubject)
	if not cameraSubject then
		return nil
	end

	if cameraSubject:IsA("Humanoid") then
		local humanoid = cameraSubject
		local rootPart = humanoid.RootPart
		if not rootPart then
			return nil
		end

		local heightOffset = CAMERA_HEAD_OFFSET
		if humanoid.RigType == Enum.HumanoidRigType.R15 then
			if humanoid.AutomaticScalingEnabled then
				heightOffset = CAMERA_R15_HEAD_OFFSET
				local rootPartSizeOffset = (rootPart.Size.Y / 2) - (CAMERA_HUMANOID_ROOT_PART_SIZE.Y / 2)
				heightOffset += Vector3.new(0, rootPartSizeOffset, 0)
			else
				heightOffset = CAMERA_R15_HEAD_OFFSET_NO_SCALING
			end
		end

		return rootPart.CFrame.Position + rootPart.CFrame:VectorToWorldSpace(heightOffset + humanoid.CameraOffset)
	end

	if cameraSubject:IsA("VehicleSeat") then
		return cameraSubject.CFrame.Position + cameraSubject.CFrame:VectorToWorldSpace(CAMERA_SEAT_OFFSET)
	end

	if cameraSubject:IsA("SkateboardPlatform") then
		return cameraSubject.CFrame.Position + CAMERA_SEAT_OFFSET
	end

	if cameraSubject:IsA("BasePart") then
		return cameraSubject.Position
	end

	if cameraSubject:IsA("Model") then
		if cameraSubject.PrimaryPart then
			return cameraSubject.PrimaryPart.Position
		end

		return cameraSubject:GetModelCFrame().Position
	end

	return nil
end

function HorseMountCamera.new(localPlayer, horseMountConfig)
	return setmetatable({
		localPlayer = localPlayer,
		config = horseMountConfig,
		previousCameraType = nil,
		previousCameraSubject = nil,
		previousFieldOfView = nil,
		previousCameraMinZoomDistance = nil,
		cachedPlayerCameras = nil,
		cameraReleaseToken = 0,
		cameraBobTime = 0,
		cameraBobHumanoid = nil,
		cameraBobBaseOffset = nil,
		cameraTransitionState = {
			Active = false,
			Mode = nil,
			Elapsed = 0,
			Duration = 0,
			StartCFrame = nil,
			StartFieldOfView = nil,
		},
	}, HorseMountCamera)
end

function HorseMountCamera:getDefaultCameraSubject()
	local character = self.localPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid") or nil
end

function HorseMountCamera:getResolvedCameraSubject(targetCameraSubject)
	local resolvedSubject = targetCameraSubject
	if not resolvedSubject or not resolvedSubject.Parent then
		resolvedSubject = self:getDefaultCameraSubject()
	end

	return resolvedSubject
end

function HorseMountCamera:getPlayerCameras()
	if self.cachedPlayerCameras then
		return self.cachedPlayerCameras
	end

	local playerScripts = self.localPlayer:FindFirstChild("PlayerScripts")
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

	local getCameras = requiredPlayerModule.GetCameras
	if type(getCameras) ~= "function" then
		return nil
	end

	local cameraSuccess, cameras = pcall(function()
		return requiredPlayerModule:GetCameras()
	end)
	if not cameraSuccess or type(cameras) ~= "table" then
		return nil
	end

	self.cachedPlayerCameras = cameras
	return self.cachedPlayerCameras
end

function HorseMountCamera:seedDefaultCameraController(camera, targetCameraSubject)
	local cameras = self:getPlayerCameras()
	local activeCameraController = cameras and cameras.activeCameraController
	if not camera or not activeCameraController then
		return
	end

	local subjectPosition = get_camera_subject_position(targetCameraSubject or camera.CameraSubject)
	if subjectPosition then
		local desiredDistance = (camera.CFrame.Position - subjectPosition).Magnitude
		if desiredDistance == desiredDistance and desiredDistance ~= math.huge and desiredDistance ~= -math.huge and desiredDistance > 0.05 then
			pcall(function()
				activeCameraController:SetCameraToSubjectDistance(desiredDistance)
			end)
		end

		activeCameraController.lastSubjectPosition = subjectPosition
		activeCameraController.lastCameraFocus = CFrame.new(subjectPosition)
	end

	activeCameraController.lastCameraTransform = camera.CFrame
	activeCameraController.lastSubjectCFrame = nil
	activeCameraController.lastUserPanCamera = tick()
end

function HorseMountCamera:forceReleaseCameraControls(targetCameraType, targetCameraSubject)
	self.cameraReleaseToken += 1
	local releaseToken = self.cameraReleaseToken
	local resolvedCameraType = targetCameraType or Enum.CameraType.Custom
	local resolvedCameraSubject = self:getResolvedCameraSubject(targetCameraSubject)

	local camera = Workspace.CurrentCamera
	if camera then
		if resolvedCameraSubject then
			camera.CameraSubject = resolvedCameraSubject
		end

		camera.CameraType = resolvedCameraType
		self:seedDefaultCameraController(camera, resolvedCameraSubject)
	end

	local function apply_release_state()
		if releaseToken ~= self.cameraReleaseToken then
			return
		end

		local releaseCamera = Workspace.CurrentCamera
		if releaseCamera then
			self:seedDefaultCameraController(releaseCamera, resolvedCameraSubject)
		end
	end

	apply_release_state()
	task.defer(apply_release_state)
	task.delay(0.05, apply_release_state)
end

function HorseMountCamera:cancelCameraTransition()
	self.cameraTransitionState.Active = false
	self.cameraTransitionState.Mode = nil
	self.cameraTransitionState.Elapsed = 0
	self.cameraTransitionState.Duration = 0
	self.cameraTransitionState.StartCFrame = nil
	self.cameraTransitionState.StartFieldOfView = nil
end

function HorseMountCamera:getControlStartYaw(getCharacterRootPart, mountedState)
	local camera = Workspace.CurrentCamera
	if camera then
		return build_angle_y(camera.CFrame)
	end

	local rootPart = getCharacterRootPart()
	if rootPart then
		return build_angle_y(rootPart.CFrame)
	end

	return mountedState.CameraYaw
end

function HorseMountCamera:buildCameraTargetCFrameFromRootCFrame(rootCFrame, yaw, focusHeightOffset, backOffset, heightOffset, lookAhead, sideOffset)
	if not rootCFrame then
		return nil
	end

	local yawCFrame = CFrame.Angles(0, yaw, 0)
	local focus = rootCFrame.Position + Vector3.new(0, focusHeightOffset, 0)
	local centeredPosition = focus
		- (yawCFrame.LookVector * backOffset)
		+ Vector3.new(0, heightOffset, 0)
	local centeredLookAt = focus + (yawCFrame.LookVector * lookAhead)
	local centeredCFrame = CFrame.lookAt(centeredPosition, centeredLookAt)
	return centeredCFrame + (yawCFrame.RightVector * sideOffset)
end

function HorseMountCamera:getTransitionRootCFrame(mountedState, getCharacterRootPart)
	local rootPart = getCharacterRootPart()
	if rootPart then
		return rootPart.CFrame
	end

	local startRootCFrame = mountedState.TransitionStartRootCFrame
	local targetRootCFrame = mountedState.TransitionTargetRootCFrame
	if typeof(startRootCFrame) == "CFrame" and typeof(targetRootCFrame) == "CFrame" then
		local duration = math.max(self.cameraTransitionState.Duration or 0, 0.05)
		local alpha = math.clamp(self.cameraTransitionState.Elapsed / duration, 0, 1)
		return startRootCFrame:Lerp(targetRootCFrame, build_eased_alpha(alpha))
	end

	return nil
end

function HorseMountCamera:getTransitionCameraCFrame(mountedState, getCharacterRootPart)
	local rootCFrame = self:getTransitionRootCFrame(mountedState, getCharacterRootPart)
	if not rootCFrame then
		return nil
	end

	local yaw = mountedState.CameraYaw
	local focusHeightOffset = self.config.TransitionCameraFocusHeightOffset or 1.7
	local backOffset = self.config.TransitionCameraBackOffset or 9.25
	local heightOffset = self.config.TransitionCameraHeightOffset or 4.1
	local lookAhead = self.config.TransitionCameraLookAhead or 5.5
	local sideOffset = self.config.TransitionCameraSideOffset or 10.5

	if mountedState.TransitionMode == "Dismounting" then
		yaw = build_angle_y(rootCFrame)
	elseif mountedState.TransitionMode == "Mounting" and typeof(mountedState.TransitionTargetRootCFrame) == "CFrame" then
		yaw = build_angle_y(mountedState.TransitionTargetRootCFrame)
		focusHeightOffset = self.config.CameraFocusHeightOffset or focusHeightOffset
		backOffset = self.config.CameraBackOffset or backOffset
		heightOffset = self.config.CameraHeightOffset or heightOffset
		lookAhead = self.config.CameraLookAhead or lookAhead
		sideOffset = self.config.CameraSideOffset or sideOffset
	elseif not mountedState.Active and mountedState.TransitionMode ~= "Mounting" then
		yaw = build_angle_y(rootCFrame)
	end

	return self:buildCameraTargetCFrameFromRootCFrame(
		rootCFrame,
		yaw,
		focusHeightOffset,
		backOffset,
		heightOffset,
		lookAhead,
		sideOffset
	)
end

function HorseMountCamera:startCameraTransition(mode, duration)
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	self.cameraTransitionState.Active = true
	self.cameraTransitionState.Mode = mode
	self.cameraTransitionState.Elapsed = 0
	self.cameraTransitionState.Duration = math.max(duration or 0, 0.05)
	self.cameraTransitionState.StartCFrame = camera.CFrame
	self.cameraTransitionState.StartFieldOfView = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
end

function HorseMountCamera:updateCameraTransition(deltaTime, mountedState, getCharacterRootPart)
	if not self.cameraTransitionState.Active then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		self:cancelCameraTransition()
		return
	end

	local targetCFrame = self:getTransitionCameraCFrame(mountedState, getCharacterRootPart)
	if not targetCFrame then
		return
	end

	self.cameraTransitionState.Elapsed += deltaTime
	local duration = math.max(self.cameraTransitionState.Duration or 0, 0.05)
	local alpha = math.clamp(self.cameraTransitionState.Elapsed / duration, 0, 1)
	local easedAlpha = build_eased_alpha(alpha)

	camera.CameraType = Enum.CameraType.Scriptable
	if self.cameraTransitionState.StartCFrame and alpha < 1 then
		camera.CFrame = self.cameraTransitionState.StartCFrame:Lerp(targetCFrame, easedAlpha)
	else
		local blendAlpha = 1 - math.exp(-(self.config.CameraSmoothness or 14) * deltaTime)
		camera.CFrame = camera.CFrame:Lerp(targetCFrame, blendAlpha)
	end

	if self.cameraTransitionState.StartFieldOfView ~= nil and self.previousFieldOfView ~= nil then
		camera.FieldOfView = self.cameraTransitionState.StartFieldOfView
			+ ((self.previousFieldOfView - self.cameraTransitionState.StartFieldOfView) * math.min(easedAlpha, 1))
	end
end

function HorseMountCamera:restoreZoomLimits()
	if self.previousCameraMinZoomDistance == nil then
		return
	end

	pcall(function()
		self.localPlayer.CameraMinZoomDistance = self.previousCameraMinZoomDistance
	end)

	self.previousCameraMinZoomDistance = nil
end

function HorseMountCamera:applyZoomLimits()
	local minZoomDistance = tonumber(self.config.MountedMinZoomDistance) or 0
	if minZoomDistance <= 0 or self.previousCameraMinZoomDistance ~= nil then
		return
	end

	self.previousCameraMinZoomDistance = self.localPlayer.CameraMinZoomDistance
	pcall(function()
		self.localPlayer.CameraMinZoomDistance = math.min(minZoomDistance, self.localPlayer.CameraMaxZoomDistance)
	end)
end

function HorseMountCamera:releaseCameraAfterDismount()
	local camera = Workspace.CurrentCamera
	self:cancelCameraTransition()
	self:resetCameraMotion()
	self:restoreZoomLimits()

	local targetCameraType = self.previousCameraType
	if targetCameraType == nil or targetCameraType == Enum.CameraType.Scriptable then
		targetCameraType = Enum.CameraType.Custom
	end

	local targetCameraSubject = self.previousCameraSubject
	if not targetCameraSubject or not targetCameraSubject.Parent then
		targetCameraSubject = self:getDefaultCameraSubject()
	end

	if camera and self.previousFieldOfView ~= nil then
		camera.FieldOfView = self.previousFieldOfView
	end

	self:forceReleaseCameraControls(targetCameraType, targetCameraSubject)

	self.previousCameraType = nil
	self.previousCameraSubject = nil
	self.previousFieldOfView = nil
end

function HorseMountCamera:prepareCameraForMount()
	local camera = Workspace.CurrentCamera
	if not camera then
		return
	end

	if self.previousCameraType == nil then
		self.previousCameraType = camera.CameraType
		self.previousCameraSubject = camera.CameraSubject
		self.previousFieldOfView = camera.FieldOfView
	end

	self:applyZoomLimits()
end

function HorseMountCamera:handOverToDefaultCamera()
	self:cancelCameraTransition()
	self:forceReleaseCameraControls(Enum.CameraType.Custom, self:getDefaultCameraSubject())
end

function HorseMountCamera:updateCameraFov(deltaTime, mountedState, localPrediction, getPredictionMovement, isSprintInputActive)
	local camera = Workspace.CurrentCamera
	if not camera or not mountedState.Active then
		return
	end

	local movement = localPrediction.Movement or getPredictionMovement(mountedState.HorseId)
	local sprintSpeed = movement.SprintSpeed or 26
	local speedAlpha = 0
	if sprintSpeed > 0 then
		speedAlpha = math.clamp((localPrediction.CurrentSpeed or 0) / sprintSpeed, 0, 1)
	end

	local baseFov = self.previousFieldOfView or self.config.MountedBaseFov
	local targetFov = baseFov + (self.config.MountedFovBoost * speedAlpha)
	if isSprintInputActive() then
		targetFov += self.config.MountedSprintFovBoost
	end

	local blendAlpha = 1 - math.exp(-(self.config.MountedFovSmoothness or 8) * deltaTime)
	camera.FieldOfView = camera.FieldOfView + ((targetFov - camera.FieldOfView) * blendAlpha)
end

function HorseMountCamera:resetCameraMotion()
	local humanoid = self.cameraBobHumanoid
	if humanoid and humanoid.Parent and self.cameraBobBaseOffset then
		humanoid.CameraOffset = self.cameraBobBaseOffset
	end
	self.cameraBobTime = 0
	self.cameraBobHumanoid = nil
	self.cameraBobBaseOffset = nil
end

function HorseMountCamera:updateCameraMotion(deltaTime, mountedState, localPrediction, getPredictionMovement)
	if not mountedState.Active then
		self:resetCameraMotion()
		return
	end

	local humanoid = self:getDefaultCameraSubject()
	if not humanoid then
		self:resetCameraMotion()
		return
	end
	if self.cameraBobHumanoid ~= humanoid then
		self:resetCameraMotion()
		self.cameraBobHumanoid = humanoid
		self.cameraBobBaseOffset = humanoid.CameraOffset
	end

	local movement = localPrediction.Movement or getPredictionMovement(mountedState.HorseId)
	local sprintSpeed = math.max(tonumber(movement.SprintSpeed) or 26, 0.01)
	local speedAlpha = math.clamp(math.abs(localPrediction.CurrentSpeed or 0) / sprintSpeed, 0, 1)
	local amplitude = math.max(tonumber(self.config.HorseCameraBobAmplitude) or 0.08, 0) * speedAlpha
	local frequency = math.max(tonumber(self.config.HorseCameraBobFrequency) or 7, 0)
	self.cameraBobTime += math.max(deltaTime, 0) * frequency * (0.55 + (speedAlpha * 0.45))

	local baseOffset = self.cameraBobBaseOffset or Vector3.zero
	humanoid.CameraOffset = baseOffset + Vector3.new(0, math.sin(self.cameraBobTime * math.pi * 2) * amplitude, 0)
end

return HorseMountCamera
