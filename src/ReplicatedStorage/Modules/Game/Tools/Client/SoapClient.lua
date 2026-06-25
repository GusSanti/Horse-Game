------------------//SERVICES
local GuiService: GuiService = game:GetService("GuiService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local TweenService: TweenService = game:GetService("TweenService")
local UserInputService: UserInputService = game:GetService("UserInputService")

------------------//CONSTANTS
local localPlayer: Player = Players.LocalPlayer
local modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local dictionary: Folder = modules:WaitForChild("Dictionary")

local toolDictionary = require(dictionary:WaitForChild("ToolDictionary"))
local soapCleaningDictionary = require(dictionary:WaitForChild("SoapCleaningDictionary"))

local IGNORE_REFRESH_ATTRIBUTE: string = toolDictionary.IgnoreRefreshAttribute
local ACTION_NAME: string = soapCleaningDictionary.ActionName
local STAGE_ORDER: {string} = soapCleaningDictionary.StageOrder
local STAGE_LABELS = soapCleaningDictionary.StageLabels
local STAGE_PROGRESS_GOAL: number = soapCleaningDictionary.StageProgressGoal
local SIDE_THRESHOLD: number = soapCleaningDictionary.SideThreshold
local MINIMUM_SCRUB_DISTANCE: number = soapCleaningDictionary.MinimumScrubDistance
local MINIMUM_MOUSE_DRAG_DISTANCE: number = soapCleaningDictionary.MinimumMouseDragDistance
local PROGRESS_STEP_DURATION: number = soapCleaningDictionary.ProgressStepDuration
local PROGRESS_GAIN_PER_STEP: number = soapCleaningDictionary.ProgressGainPerStep
local PROGRESS_TWEEN_TIME: number = soapCleaningDictionary.ProgressTweenTime
local BUBBLE_SPAWN_DISTANCE: number = soapCleaningDictionary.BubbleSpawnDistance
local BUBBLE_COUNT_MIN: number = soapCleaningDictionary.BubbleCountMin
local BUBBLE_COUNT_MAX: number = soapCleaningDictionary.BubbleCountMax
local BUBBLE_SPREAD: number = soapCleaningDictionary.BubbleSpread
local BUBBLE_SURFACE_OFFSET_MIN: number = soapCleaningDictionary.BubbleSurfaceOffsetMin
local BUBBLE_SURFACE_OFFSET_MAX: number = soapCleaningDictionary.BubbleSurfaceOffsetMax
local BUBBLE_APPEAR_TIME: number = soapCleaningDictionary.BubbleAppearTime
local BUBBLE_APPEAR_START_SCALE: number = soapCleaningDictionary.BubbleAppearStartScale
local BUBBLE_SIZE_MIN: number = soapCleaningDictionary.BubbleSizeMin
local BUBBLE_SIZE_MAX: number = soapCleaningDictionary.BubbleSizeMax
local CAMERA_PADDING: number = soapCleaningDictionary.CameraPadding
local CAMERA_HEIGHT_RATIO: number = soapCleaningDictionary.CameraHeightRatio
local CAMERA_DEPTH_RATIO: number = soapCleaningDictionary.CameraDepthRatio
local CAMERA_LERP_SPEED: number = soapCleaningDictionary.CameraLerpSpeed
local TOP_CAMERA_HEIGHT_MULTIPLIER: number = soapCleaningDictionary.TopCameraHeightMultiplier
local TOP_CAMERA_SIDE_RATIO: number = soapCleaningDictionary.TopCameraSideRatio
local PROGRESS_STUDS_OFFSET: number = soapCleaningDictionary.ProgressStudsOffset
local PROGRESS_BAR_WIDTH: number = soapCleaningDictionary.ProgressBarWidth
local PROGRESS_BAR_HEIGHT: number = soapCleaningDictionary.ProgressBarHeight
local FINISH_DELAY: number = soapCleaningDictionary.FinishDelay
local EFFECTS_FOLDER_NAME: string = soapCleaningDictionary.EffectsFolderName
local MOUSE_HITBOX_NAME: string = soapCleaningDictionary.MouseHitboxName
local MOUSE_HITBOX_PADDING: number = soapCleaningDictionary.MouseHitboxPadding
local ASSETS_FOLDER_NAME: string = soapCleaningDictionary.AssetsFolderName
local OBJECTS_FOLDER_NAME: string = soapCleaningDictionary.ObjectsFolderName
local BUBBLE_OBJECT_NAME: string = soapCleaningDictionary.BubbleObjectName
local SHOWER_OBJECT_NAME: string = soapCleaningDictionary.ShowerObjectName
local INSTRUCTION_TEXT: string = soapCleaningDictionary.InstructionText
local RINSE_INSTRUCTION_TEXT: string = soapCleaningDictionary.RinseInstructionText
local COMPLETE_TEXT: string = soapCleaningDictionary.CompleteText
local FINISHING_TEXT: string = soapCleaningDictionary.FinishingText
local RINSE_TITLE_TEXT: string = soapCleaningDictionary.RinseTitleText
local RINSE_COVERAGE_SEGMENTS: number = soapCleaningDictionary.RinseCoverageSegments
local RINSE_COVERAGE_WIDTH_RATIO: number = soapCleaningDictionary.RinseCoverageWidthRatio
local RINSE_MINIMUM_COVERAGE_WIDTH: number = soapCleaningDictionary.RinseMinimumCoverageWidth
local RINSE_BUBBLE_CLEAR_WIDTH_RATIO: number = soapCleaningDictionary.RinseBubbleClearWidthRatio
local RINSE_BUBBLE_MINIMUM_CLEAR_WIDTH: number = soapCleaningDictionary.RinseBubbleMinimumClearWidth
local RINSE_BUBBLE_FADE_TIME: number = soapCleaningDictionary.RinseBubbleFadeTime
local SHOWER_HEIGHT_OFFSET: number = soapCleaningDictionary.ShowerHeightOffset
local SHOWER_FOLLOW_LERP_SPEED: number = soapCleaningDictionary.ShowerFollowLerpSpeed
local CANCEL_KEYS = soapCleaningDictionary.CancelKeys

------------------//VARIABLES
local SoapClient = {}

local activeSession = nil
local bubbleRandom = Random.new()
local bubbleTemplateResolved: boolean = false
local bubbleTemplate: Instance? = nil
local showerTemplateResolved: boolean = false
local showerTemplate: Instance? = nil
local complete_session

------------------//FUNCTIONS
local function disconnect_all(connections: {RBXScriptConnection}): ()
	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function destroy_all(instances: {Instance}): ()
	for _, instance: Instance in instances do
		if instance.Parent then
			instance:Destroy()
		end
	end

	table.clear(instances)
end

local function get_player_gui(): PlayerGui?
	return localPlayer:FindFirstChildOfClass("PlayerGui")
end

local function get_horse_pivot(horseVisual: Instance): CFrame
	if horseVisual:IsA("Model") or horseVisual:IsA("BasePart") then
		return horseVisual:GetPivot()
	end

	return CFrame.new()
end

local function get_horse_extents(horseVisual: Instance): Vector3
	if horseVisual:IsA("Model") then
		return horseVisual:GetExtentsSize()
	end

	if horseVisual:IsA("BasePart") then
		return horseVisual.Size
	end

	return Vector3.new(4, 4, 4)
end

local function get_horse_bounding_box(horseVisual: Instance): (CFrame, Vector3)
	if horseVisual:IsA("Model") then
		return horseVisual:GetBoundingBox()
	end

	if horseVisual:IsA("BasePart") then
		return horseVisual.CFrame, horseVisual.Size
	end

	return get_horse_pivot(horseVisual), get_horse_extents(horseVisual)
end

local function is_descendant_of(instance: Instance?, ancestor: Instance): boolean
	local current = instance
	while current do
		if current == ancestor then
			return true
		end

		current = current.Parent
	end

	return false
end

local function find_focus_part(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end

		for _, descendant: Instance in instance:GetDescendants() do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
	end

	return nil
end

local function get_base_parts(instance: Instance): {BasePart}
	local baseParts: {BasePart} = {}

	if instance:IsA("BasePart") then
		baseParts[#baseParts + 1] = instance
		return baseParts
	end

	for _, descendant: Instance in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			baseParts[#baseParts + 1] = descendant
		end
	end

	return baseParts
end

local function is_cancel_key(keyCode: Enum.KeyCode): boolean
	for _, cancelKey: Enum.KeyCode in CANCEL_KEYS do
		if cancelKey == keyCode then
			return true
		end
	end

	return false
end

local function get_stage_name(session): string
	return STAGE_ORDER[session.stageIndex]
end

local function get_stage_label(stageName: string): string
	return STAGE_LABELS[stageName] or stageName
end

local function lerp_number(current: number, target: number, alpha: number): number
	return current + ((target - current) * alpha)
end

local function get_progress_goal(session): number
	return session.progressGoal or STAGE_PROGRESS_GOAL
end

local function get_progress_title(session): string
	if session.phase == "Rinse" then
		return RINSE_TITLE_TEXT
	end

	local stageName = get_stage_name(session)
	return ("%s  %d/%d"):format(get_stage_label(stageName), session.stageIndex, #STAGE_ORDER)
end

local function get_focus_position(session): Vector3
	local pivot = get_horse_pivot(session.horseVisual)
	return pivot.Position + (pivot.UpVector * (session.extents.Y * 0.2))
end

local function get_stage_camera_cframe(session): CFrame
	local pivot = get_horse_pivot(session.horseVisual)
	local focusPosition = get_focus_position(session)
	local distance = math.max(session.extents.X, session.extents.Y, session.extents.Z) + CAMERA_PADDING
	local sideName = get_stage_name(session)
	local offset = Vector3.zero

	if sideName == "Right" then
		offset = (pivot.RightVector * distance)
			+ (pivot.UpVector * (session.extents.Y * CAMERA_HEIGHT_RATIO))
			- (pivot.LookVector * (session.extents.Z * CAMERA_DEPTH_RATIO))
	elseif sideName == "Front" then
		offset = (pivot.LookVector * distance)
			+ (pivot.UpVector * (session.extents.Y * CAMERA_HEIGHT_RATIO))
			+ (pivot.RightVector * (session.extents.X * 0.1))
	elseif sideName == "Left" then
		offset = (-pivot.RightVector * distance)
			+ (pivot.UpVector * (session.extents.Y * CAMERA_HEIGHT_RATIO))
			- (pivot.LookVector * (session.extents.Z * CAMERA_DEPTH_RATIO))
	elseif sideName == "Back" then
		offset = (-pivot.LookVector * distance)
			+ (pivot.UpVector * (session.extents.Y * CAMERA_HEIGHT_RATIO))
			- (pivot.RightVector * (session.extents.X * 0.1))
	else
		offset = (pivot.UpVector * (distance * TOP_CAMERA_HEIGHT_MULTIPLIER))
			+ (pivot.RightVector * (session.extents.X * TOP_CAMERA_SIDE_RATIO))
			- (pivot.LookVector * (session.extents.Z * 0.12))
	end

	return CFrame.lookAt(focusPosition + offset, focusPosition)
end

local function update_progress_ui(session, shouldTween: boolean?): ()
	local progressAlpha = math.clamp(session.stageProgress / get_progress_goal(session), 0, 1)
	local displayedPercent = math.floor((progressAlpha * 100 * 2) + 0.5) / 2

	session.titleLabel.Text = get_progress_title(session)

	if session.progressTween then
		session.progressTween:Cancel()
		session.progressTween = nil
	end

	if shouldTween then
		session.progressTween = TweenService:Create(
			session.fillFrame,
			TweenInfo.new(PROGRESS_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(progressAlpha, 1) }
		)
		session.progressTween:Play()
	else
		session.fillFrame.Size = UDim2.fromScale(progressAlpha, 1)
	end

	session.progressLabel.Text = ("%.1f%%"):format(displayedPercent)
end

local function create_progress_gui(session): boolean
	local playerGui = get_player_gui()
	if not playerGui then
		return false
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = ACTION_NAME .. "Progress"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "ProgressBillboard"
	billboardGui.Adornee = session.focusPart
	billboardGui.AlwaysOnTop = true
	billboardGui.Size = UDim2.fromOffset(280, 80)
	billboardGui.StudsOffset = Vector3.new(0, (session.extents.Y * 0.5) + PROGRESS_STUDS_OFFSET, 0)
	billboardGui.Parent = screenGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	mainFrame.BackgroundTransparency = 0.16
	mainFrame.BorderSizePixel = 0
	mainFrame.Position = UDim2.fromScale(0.5, 0.5)
	mainFrame.Size = UDim2.fromOffset(260, 68)
	mainFrame.Parent = billboardGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 18)
	mainCorner.Parent = mainFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 16
	titleLabel.Position = UDim2.fromOffset(16, 10)
	titleLabel.Size = UDim2.new(1, -32, 0, 20)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = mainFrame

	local barFrame = Instance.new("Frame")
	barFrame.Name = "BarFrame"
	barFrame.BackgroundColor3 = Color3.fromRGB(44, 52, 66)
	barFrame.BorderSizePixel = 0
	barFrame.Position = UDim2.fromOffset(16, 38)
	barFrame.Size = UDim2.fromOffset(PROGRESS_BAR_WIDTH, PROGRESS_BAR_HEIGHT)
	barFrame.Parent = mainFrame

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barFrame

	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "FillFrame"
	fillFrame.BackgroundColor3 = Color3.fromRGB(255, 244, 196)
	fillFrame.BorderSizePixel = 0
	fillFrame.Size = UDim2.fromScale(0, 1)
	fillFrame.Parent = barFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fillFrame

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.TextColor3 = Color3.fromRGB(206, 214, 227)
	progressLabel.TextSize = 14
	progressLabel.Position = UDim2.new(1, -56, 0, 34)
	progressLabel.Size = UDim2.fromOffset(40, 20)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.Parent = mainFrame

	local instructionGui = Instance.new("ScreenGui")
	instructionGui.Name = ACTION_NAME .. "Instruction"
	instructionGui.ResetOnSpawn = false
	instructionGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	instructionGui.Parent = playerGui

	local instructionFrame = Instance.new("Frame")
	instructionFrame.Name = "InstructionFrame"
	instructionFrame.AnchorPoint = Vector2.new(0.5, 1)
	instructionFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	instructionFrame.BackgroundTransparency = 0.18
	instructionFrame.BorderSizePixel = 0
	instructionFrame.Position = UDim2.new(0.5, 0, 1, -44)
	instructionFrame.Size = UDim2.fromOffset(340, 44)
	instructionFrame.Parent = instructionGui

	local instructionCorner = Instance.new("UICorner")
	instructionCorner.CornerRadius = UDim.new(0, 16)
	instructionCorner.Parent = instructionFrame

	local instructionLabel = Instance.new("TextLabel")
	instructionLabel.Name = "InstructionLabel"
	instructionLabel.BackgroundTransparency = 1
	instructionLabel.Font = Enum.Font.GothamMedium
	instructionLabel.Text = INSTRUCTION_TEXT
	instructionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	instructionLabel.TextSize = 15
	instructionLabel.Size = UDim2.new(1, -24, 1, 0)
	instructionLabel.Position = UDim2.fromOffset(12, 0)
	instructionLabel.Parent = instructionFrame

	session.screenGui = screenGui
	session.instructionGui = instructionGui
	session.titleLabel = titleLabel
	session.fillFrame = fillFrame
	session.progressLabel = progressLabel
	session.instructionLabel = instructionLabel

	session.instances[#session.instances + 1] = screenGui
	session.instances[#session.instances + 1] = instructionGui

	update_progress_ui(session)

	return true
end

local function get_bubble_template(): Instance?
	if bubbleTemplateResolved then
		return bubbleTemplate
	end

	bubbleTemplateResolved = true

	local assetsFolder = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER_NAME)
	if not assetsFolder then
		return nil
	end

	local objectsFolder = assetsFolder:FindFirstChild(OBJECTS_FOLDER_NAME)
	if not objectsFolder then
		return nil
	end

	bubbleTemplate = objectsFolder:FindFirstChild(BUBBLE_OBJECT_NAME)
	return bubbleTemplate
end

local function get_shower_template(): Instance?
	if showerTemplateResolved then
		return showerTemplate
	end

	showerTemplateResolved = true

	local assetsFolder = ReplicatedStorage:FindFirstChild(ASSETS_FOLDER_NAME)
	if not assetsFolder then
		return nil
	end

	showerTemplate = assetsFolder:FindFirstChild(SHOWER_OBJECT_NAME)
	return showerTemplate
end

local function scale_instance(instance: Instance, scale: number): ()
	if instance:IsA("Model") then
		pcall(function()
			instance:ScaleTo(scale)
		end)
		return
	end

	for _, basePart: BasePart in get_base_parts(instance) do
		basePart.Size *= scale
	end
end

local function place_instance(instance: Instance, targetCFrame: CFrame): ()
	if instance:IsA("Model") then
		instance:PivotTo(targetCFrame)
		return
	end

	if instance:IsA("BasePart") then
		instance.CFrame = targetCFrame
	end
end

local function get_surface_basis(normal: Vector3): (Vector3, Vector3)
	local tangent = normal:Cross(Vector3.yAxis)
	if tangent.Magnitude < 0.01 then
		tangent = normal:Cross(Vector3.xAxis)
	end

	tangent = tangent.Unit
	local bitangent = normal:Cross(tangent).Unit

	return tangent, bitangent
end

local function spawn_bubbles(session, worldPosition: Vector3, normal: Vector3): ()
	local template = get_bubble_template()
	if not template or not session.effectsFolder or not session.effectsFolder.Parent then
		return
	end

	local tangent, bitangent = get_surface_basis(normal)
	local bubbleCount = bubbleRandom:NextInteger(BUBBLE_COUNT_MIN, BUBBLE_COUNT_MAX)

	for bubbleIndex = 1, bubbleCount do
		local bubbleClone = template:Clone()
		local scale = bubbleRandom:NextNumber(BUBBLE_SIZE_MIN, BUBBLE_SIZE_MAX)
		local offset = (tangent * bubbleRandom:NextNumber(-BUBBLE_SPREAD, BUBBLE_SPREAD))
			+ (bitangent * bubbleRandom:NextNumber(-BUBBLE_SPREAD, BUBBLE_SPREAD))
			+ (normal * bubbleRandom:NextNumber(BUBBLE_SURFACE_OFFSET_MIN, BUBBLE_SURFACE_OFFSET_MAX))
		local targetPosition = worldPosition + offset
		local targetCFrame = CFrame.lookAt(targetPosition, targetPosition + normal)
			* CFrame.Angles(0, 0, math.rad(bubbleRandom:NextNumber(0, 360)))

		bubbleClone.Parent = session.effectsFolder
		scale_instance(bubbleClone, scale)
		place_instance(bubbleClone, targetCFrame)
		session.bubbleClones[#session.bubbleClones + 1] = bubbleClone

		for _, basePart: BasePart in get_base_parts(bubbleClone) do
			basePart.Anchored = true
			basePart.CanCollide = false
			basePart.CanTouch = false
			basePart.CanQuery = false
			basePart.CastShadow = false

			local finalCFrame = basePart.CFrame
			local finalSize = basePart.Size
			local finalTransparency = basePart.Transparency

			basePart.CFrame = finalCFrame + (-normal * 0.04)
			basePart.Size = Vector3.new(
				math.max(finalSize.X * BUBBLE_APPEAR_START_SCALE, 0.01),
				math.max(finalSize.Y * BUBBLE_APPEAR_START_SCALE, 0.01),
				math.max(finalSize.Z * BUBBLE_APPEAR_START_SCALE, 0.01)
			)
			basePart.Transparency = 1

			local appearTween = TweenService:Create(
				basePart,
				TweenInfo.new(BUBBLE_APPEAR_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{
					CFrame = finalCFrame,
					Size = finalSize,
					Transparency = finalTransparency,
				}
			)
			appearTween:Play()
		end
	end
end

local function is_point_on_active_side(session, worldPosition: Vector3): boolean
	local pivot = get_horse_pivot(session.horseVisual)
	local localPosition = pivot:PointToObjectSpace(worldPosition)
	local halfExtents = session.halfExtents
	local normalizedX = localPosition.X / math.max(halfExtents.X, 0.1)
	local normalizedY = localPosition.Y / math.max(halfExtents.Y, 0.1)
	local normalizedZ = localPosition.Z / math.max(halfExtents.Z, 0.1)
	local stageName = get_stage_name(session)

	if stageName == "Right" then
		return normalizedX >= SIDE_THRESHOLD
	end

	if stageName == "Front" then
		return normalizedZ <= -SIDE_THRESHOLD
	end

	if stageName == "Left" then
		return normalizedX <= -SIDE_THRESHOLD
	end

	if stageName == "Back" then
		return normalizedZ >= SIDE_THRESHOLD
	end

	return normalizedY >= SIDE_THRESHOLD
end

local function get_active_side_normal(session): Vector3
	local pivot = get_horse_pivot(session.horseVisual)
	local stageName = get_stage_name(session)

	if stageName == "Right" then
		return pivot.RightVector
	end

	if stageName == "Front" then
		return pivot.LookVector
	end

	if stageName == "Left" then
		return -pivot.RightVector
	end

	if stageName == "Back" then
		return -pivot.LookVector
	end

	return pivot.UpVector
end

local function get_mouse_hit(session)
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local screenRay = camera:ViewportPointToRay(mousePosition.X - inset.X, mousePosition.Y - inset.Y, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { session.horseVisual }
	raycastParams.IgnoreWater = true

	local raycastResult = workspace:Raycast(screenRay.Origin, screenRay.Direction * 400, raycastParams)
	if raycastResult then
		return raycastResult
	end

	local mouse = session.mouse
	if not mouse or not is_descendant_of(mouse.Target, session.horseVisual) then
		return nil
	end

	return {
		Instance = mouse.Target,
		Position = mouse.Hit.Position,
		Normal = get_active_side_normal(session),
	}
end

local function hide_character_part(session, instance: Instance): ()
	if not instance:IsA("BasePart") then
		return
	end

	if session.hiddenCharacterParts[instance] == nil then
		session.hiddenCharacterParts[instance] = instance.LocalTransparencyModifier
	end

	instance.LocalTransparencyModifier = 1
end

local function hide_character(session): ()
	local character = localPlayer.Character
	if not character then
		return
	end

	session.hiddenCharacterParts = {}

	for _, descendant: Instance in character:GetDescendants() do
		hide_character_part(session, descendant)
	end

	session.connections[#session.connections + 1] = character.DescendantAdded:Connect(function(descendant: Instance)
		hide_character_part(session, descendant)
	end)
end

local function restore_character_visibility(session): ()
	if not session.hiddenCharacterParts then
		return
	end

	for basePart: BasePart, localTransparencyModifier: number in session.hiddenCharacterParts do
		if basePart.Parent then
			basePart.LocalTransparencyModifier = localTransparencyModifier
		end
	end

	table.clear(session.hiddenCharacterParts)
end

local function restore_humanoid(session): ()
	if not session.humanoid then
		return
	end

	if session.humanoid.Parent then
		session.humanoid.WalkSpeed = session.savedWalkSpeed
		session.humanoid.JumpPower = session.savedJumpPower
		session.humanoid.JumpHeight = session.savedJumpHeight
		session.humanoid.AutoRotate = session.savedAutoRotate
	end
end

local function restore_camera(session): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = session.savedCameraType
	camera.CameraSubject = session.savedCameraSubject

	if session.savedCameraType == Enum.CameraType.Scriptable then
		camera.CFrame = session.savedCameraCFrame
	end
end

local function get_mouse_rinse_local_z(session): number
	local camera = workspace.CurrentCamera
	if not camera then
		return session.showerLocalZ or 0
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local viewportSize = camera.ViewportSize
	local screenX = math.clamp(mousePosition.X - inset.X, 0, viewportSize.X)
	local screenY = viewportSize.Y * 0.5
	local screenRay = camera:ViewportPointToRay(screenX, screenY, 0)
	local focusPosition = get_focus_position(session)
	local planeNormal = camera.CFrame.LookVector
	local denominator = screenRay.Direction:Dot(planeNormal)

	if math.abs(denominator) < 0.001 then
		return session.showerLocalZ or 0
	end

	local distance = (focusPosition - screenRay.Origin):Dot(planeNormal) / denominator
	local worldPosition = screenRay.Origin + (screenRay.Direction * distance)
	local pivot = get_horse_pivot(session.horseVisual)
	local localPosition = pivot:PointToObjectSpace(worldPosition)
	local halfLength = math.max(session.halfExtents.Z, 0.1)

	return math.clamp(localPosition.Z, -halfLength, halfLength)
end

local function get_shower_cframe(session, localZ: number): CFrame
	local pivot = get_horse_pivot(session.horseVisual)
	local localPosition = Vector3.new(0, session.halfExtents.Y + SHOWER_HEIGHT_OFFSET, localZ)
	local worldPosition = pivot:PointToWorldSpace(localPosition)

	return CFrame.lookAt(worldPosition, worldPosition - pivot.UpVector, pivot.LookVector)
end

local function update_shower(session, deltaTime: number): number
	local targetLocalZ = get_mouse_rinse_local_z(session)
	if not session.showerLocalZ then
		session.showerLocalZ = targetLocalZ
	else
		local alpha = math.clamp(deltaTime * SHOWER_FOLLOW_LERP_SPEED, 0, 1)
		session.showerLocalZ = lerp_number(session.showerLocalZ, targetLocalZ, alpha)
	end

	if session.shower and session.shower.Parent then
		place_instance(session.shower, get_shower_cframe(session, session.showerLocalZ))
	end

	return session.showerLocalZ
end

local function create_shower(session): ()
	local template = get_shower_template()
	if not template then
		return
	end

	local showerClone = template:Clone()
	showerClone.Name = SHOWER_OBJECT_NAME
	showerClone:SetAttribute(IGNORE_REFRESH_ATTRIBUTE, true)
	showerClone.Parent = session.effectsFolder or session.horseVisual

	for _, basePart: BasePart in get_base_parts(showerClone) do
		basePart.Anchored = true
		basePart.CanCollide = false
		basePart.CanTouch = false
		basePart.CanQuery = false
	end

	session.shower = showerClone
	session.instances[#session.instances + 1] = showerClone
	update_shower(session, 1)
end

local function get_rinse_coverage_width(session): number
	return math.max(session.extents.Z * RINSE_COVERAGE_WIDTH_RATIO, RINSE_MINIMUM_COVERAGE_WIDTH)
end

local function get_rinse_bubble_clear_width(session): number
	return math.max(session.extents.Z * RINSE_BUBBLE_CLEAR_WIDTH_RATIO, RINSE_BUBBLE_MINIMUM_CLEAR_WIDTH)
end

local function fade_destroy_instance(instance: Instance): ()
	for _, basePart: BasePart in get_base_parts(instance) do
		local fadeTween = TweenService:Create(
			basePart,
			TweenInfo.new(RINSE_BUBBLE_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Transparency = 1 }
		)
		fadeTween:Play()
	end

	task.delay(RINSE_BUBBLE_FADE_TIME, function()
		if instance.Parent then
			instance:Destroy()
		end
	end)
end

local function rinse_bubbles(session, showerLocalZ: number): ()
	local clearHalfWidth = get_rinse_bubble_clear_width(session) * 0.5
	local horsePivot = get_horse_pivot(session.horseVisual)

	for index = #session.bubbleClones, 1, -1 do
		local bubbleClone = session.bubbleClones[index]
		if not bubbleClone.Parent then
			table.remove(session.bubbleClones, index)
			continue
		end

		local bubbleLocalPosition = horsePivot:PointToObjectSpace(get_horse_pivot(bubbleClone).Position)
		if math.abs(bubbleLocalPosition.Z - showerLocalZ) <= clearHalfWidth then
			table.remove(session.bubbleClones, index)
			bubbleClone:SetAttribute(IGNORE_REFRESH_ATTRIBUTE, true)
			fade_destroy_instance(bubbleClone)
		end
	end
end

local function mark_rinse_coverage(session, showerLocalZ: number): ()
	local halfLength = math.max(session.halfExtents.Z, 0.1)
	local coverageHalfWidth = get_rinse_coverage_width(session) * 0.5
	local changed = false

	for segmentIndex = 1, RINSE_COVERAGE_SEGMENTS do
		local alpha = (segmentIndex - 0.5) / RINSE_COVERAGE_SEGMENTS
		local segmentLocalZ = -halfLength + (alpha * halfLength * 2)

		if math.abs(segmentLocalZ - showerLocalZ) <= coverageHalfWidth and not session.rinseCoverage[segmentIndex] then
			session.rinseCoverage[segmentIndex] = true
			session.rinsedSegmentCount += 1
			changed = true
		end
	end

	if changed then
		session.stageProgress = session.rinsedSegmentCount
		update_progress_ui(session, true)
	end
end

local function render_rinse_session(session, deltaTime: number): ()
	local showerLocalZ = update_shower(session, deltaTime)
	mark_rinse_coverage(session, showerLocalZ)
	rinse_bubbles(session, showerLocalZ)

	if session.stageProgress >= get_progress_goal(session) then
		complete_session(session)
	end
end

local function start_rinse_phase(session): ()
	session.phase = "Rinse"
	session.stageIndex = 1
	session.stageProgress = 0
	session.progressGoal = RINSE_COVERAGE_SEGMENTS
	session.rinseCoverage = {}
	session.rinsedSegmentCount = 0
	session.dragging = false
	session.lastHitPosition = nil
	session.lastBubblePosition = nil
	session.lastMousePosition = nil
	session.targetCameraCFrame = get_stage_camera_cframe(session)

	if session.instructionLabel then
		session.instructionLabel.Text = RINSE_INSTRUCTION_TEXT
	end

	create_shower(session)
	update_progress_ui(session)
end

local function finish_session(session, shouldRefreshPrompts: boolean): ()
	if activeSession ~= session or session.closed then
		return
	end

	session.closed = true
	activeSession = nil

	disconnect_all(session.connections)
	destroy_all(session.instances)
	restore_humanoid(session)
	restore_character_visibility(session)
	restore_camera(session)

	if type(session.finishInteraction) == "function" then
		session.finishInteraction(shouldRefreshPrompts)
	end
end

local function cancel_session(session, shouldRefreshPrompts: boolean): ()
	if session.finishing then
		return
	end

	finish_session(session, shouldRefreshPrompts)
end

complete_session = function(session): ()
	if session.finishing then
		return
	end

	session.finishing = true
	session.dragging = false
	session.lastHitPosition = nil
	session.lastBubblePosition = nil
	session.lastMousePosition = nil

	if session.titleLabel then
		session.titleLabel.Text = FINISHING_TEXT
	end

	if session.progressLabel then
		session.progressLabel.Text = "100.0%"
	end

	if session.instructionLabel then
		session.instructionLabel.Text = COMPLETE_TEXT
	end

	task.delay(FINISH_DELAY, function()
		if activeSession ~= session or session.closed then
			return
		end

		local success = false
		local invokeSuccess, invokeResult = pcall(function()
			return session.invokeServerUse()
		end)

		if invokeSuccess then
			success = invokeResult == true
		end

		finish_session(session, true)

		if not success then
			return
		end
	end)
end

local function advance_stage(session): ()
	session.stageIndex += 1
	session.stageProgress = 0
	session.lastHitPosition = nil
	session.lastBubblePosition = nil
	session.lastMousePosition = nil

	if session.stageIndex > #STAGE_ORDER then
		start_rinse_phase(session)
		return
	end

	session.progressGoal = STAGE_PROGRESS_GOAL
	update_progress_ui(session)
	session.targetCameraCFrame = get_stage_camera_cframe(session)
end

local function update_camera(session, deltaTime: number): ()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camera.CFrame:Lerp(session.targetCameraCFrame, math.clamp(deltaTime * CAMERA_LERP_SPEED, 0, 1))
end

local function render_session(session, deltaTime: number): ()
	if activeSession ~= session or session.closed then
		return
	end

	if not session.horseVisual.Parent then
		cancel_session(session, true)
		return
	end

	if not session.tool.Parent or session.tool.Parent ~= localPlayer.Character then
		cancel_session(session, true)
		return
	end

	update_camera(session, deltaTime)

	if session.phase == "Rinse" then
		render_rinse_session(session, deltaTime)
		return
	end

	if not session.dragging or session.finishing then
		session.lastHitPosition = nil
		session.lastMousePosition = nil
		return
	end

	local hitResult = get_mouse_hit(session)
	if not hitResult or not is_point_on_active_side(session, hitResult.Position) then
		session.lastHitPosition = nil
		session.lastMousePosition = nil
		return
	end

	local currentMousePosition = UserInputService:GetMouseLocation()
	if not session.lastHitPosition then
		session.lastHitPosition = hitResult.Position
		session.lastBubblePosition = hitResult.Position
		session.lastMousePosition = currentMousePosition
		spawn_bubbles(session, hitResult.Position, hitResult.Normal)
		return
	end

	local scrubDistance = (hitResult.Position - session.lastHitPosition).Magnitude
	local mouseDistance = session.lastMousePosition and (currentMousePosition - session.lastMousePosition).Magnitude or 0
	session.lastMousePosition = currentMousePosition

	if scrubDistance < MINIMUM_SCRUB_DISTANCE and mouseDistance < MINIMUM_MOUSE_DRAG_DISTANCE then
		return
	end

	session.lastHitPosition = hitResult.Position
	session.stageProgress = math.min(
		session.stageProgress + ((deltaTime / math.max(PROGRESS_STEP_DURATION, 0.01)) * PROGRESS_GAIN_PER_STEP),
		STAGE_PROGRESS_GOAL
	)
	update_progress_ui(session, true)

	if not session.lastBubblePosition or (hitResult.Position - session.lastBubblePosition).Magnitude >= BUBBLE_SPAWN_DISTANCE then
		session.lastBubblePosition = hitResult.Position
		spawn_bubbles(session, hitResult.Position, hitResult.Normal)
	end

	if session.stageProgress >= STAGE_PROGRESS_GOAL then
		advance_stage(session)
	end
end

local function lock_humanoid(session): ()
	local character = localPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	session.humanoid = humanoid
	session.savedWalkSpeed = humanoid.WalkSpeed
	session.savedJumpPower = humanoid.JumpPower
	session.savedJumpHeight = humanoid.JumpHeight
	session.savedAutoRotate = humanoid.AutoRotate

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false
end

local function create_effects_folder(session): ()
	local effectsFolder = Instance.new("Folder")
	effectsFolder.Name = EFFECTS_FOLDER_NAME
	effectsFolder:SetAttribute(IGNORE_REFRESH_ATTRIBUTE, true)
	effectsFolder.Parent = session.horseVisual

	session.effectsFolder = effectsFolder
	session.instances[#session.instances + 1] = effectsFolder
end

local function create_mouse_hitbox(session): ()
	local boundingCFrame, boundingSize = get_horse_bounding_box(session.horseVisual)
	local padding = Vector3.new(MOUSE_HITBOX_PADDING, MOUSE_HITBOX_PADDING, MOUSE_HITBOX_PADDING)
	local hitbox = Instance.new("Part")

	hitbox.Name = MOUSE_HITBOX_NAME
	hitbox:SetAttribute(IGNORE_REFRESH_ATTRIBUTE, true)
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.CastShadow = false
	hitbox.Transparency = 1
	hitbox.Size = Vector3.new(
		math.max(boundingSize.X + padding.X, 0.1),
		math.max(boundingSize.Y + padding.Y, 0.1),
		math.max(boundingSize.Z + padding.Z, 0.1)
	)
	hitbox.CFrame = boundingCFrame
	hitbox.Parent = session.effectsFolder or session.horseVisual

	session.mouseHitbox = hitbox
	session.instances[#session.instances + 1] = hitbox
end

------------------//MAIN FUNCTIONS
function SoapClient.start(context): boolean
	if activeSession then
		return false
	end

	local focusPart = find_focus_part(context.horseVisual)
	if not focusPart then
		return false
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local session = {
		player = context.player,
		tool = context.tool,
		horseId = context.horseId,
		horseVisual = context.horseVisual,
		focusPart = focusPart,
		invokeServerUse = context.invokeServerUse,
		finishInteraction = context.finishInteraction,
		mouse = localPlayer:GetMouse(),
		phase = "Soap",
		stageIndex = 1,
		stageProgress = 0,
		progressGoal = STAGE_PROGRESS_GOAL,
		dragging = false,
		finishing = false,
		closed = false,
		extents = get_horse_extents(context.horseVisual),
		halfExtents = get_horse_extents(context.horseVisual) * 0.5,
		instances = {},
		connections = {},
		bubbleClones = {},
		savedCameraType = camera.CameraType,
		savedCameraSubject = camera.CameraSubject,
		savedCameraCFrame = camera.CFrame,
	}

	activeSession = session
	session.targetCameraCFrame = get_stage_camera_cframe(session)

	lock_humanoid(session)
	hide_character(session)
	create_effects_folder(session)
	create_mouse_hitbox(session)
	if not create_progress_gui(session) then
		finish_session(session, true)
		return false
	end

	session.connections[#session.connections + 1] = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			session.dragging = true
			return
		end

		if input.UserInputType == Enum.UserInputType.Keyboard and is_cancel_key(input.KeyCode) then
			cancel_session(session, true)
		end
	end)

	session.connections[#session.connections + 1] = UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			session.dragging = false
			session.lastHitPosition = nil
			session.lastMousePosition = nil
		end
	end)

	session.connections[#session.connections + 1] = localPlayer.CharacterRemoving:Connect(function()
		cancel_session(session, false)
	end)

	session.connections[#session.connections + 1] = RunService.RenderStepped:Connect(function(deltaTime: number)
		render_session(session, deltaTime)
	end)

	update_progress_ui(session)

	return true
end

------------------//INIT
return SoapClient
