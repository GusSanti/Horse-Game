local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local plotValue = localPlayer:WaitForChild("Plot")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local Net = require(Libraries:WaitForChild("Net"))
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))

local WELL_WATER_FUNCTION_NAME = "WellWaterAction"
local WELL_PROMPT_ATTRIBUTE = "WellWaterPrompt"
local SERVER_PROMPT_ENABLED_ATTRIBUTE = "WellWaterPromptEnabled"
local BUCKET_READY_ATTRIBUTE = "WellWaterBucketReady"
local REQUIRED_TURNS_ATTRIBUTE = "WellWaterRequiredTurns"
local WELL_NAME = "Well"
local WELL_HANDLE_NAME = "WellHandle"
local CAMERA_PART_NAME = "Cam"
local PIVOT_NAME = "Pivot"
local HANDLE_NAME = "Handle"
local GUI_NAME = "WellCrankProgressGui"

local DEFAULT_REQUIRED_TURNS = 3
local DEFAULT_CAMERA_OFFSET = Vector3.new(-8, 2.8, 1.5)
local DEFAULT_CAMERA_FOCUS_OFFSET = Vector3.new(0, 0.35, 0)
local HANDLE_SCREEN_RADIUS = 88
local CAMERA_TWEEN_TIME = 0.65
local CAMERA_RETURN_TIME = 0.45
local COMPLETE_DELAY = 0.2

local activeInteraction = nil
local requestInFlight = false
local trackedPromptConnections = {}

local function is_primary_input(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

local function get_pointer_position(input)
	local position = input.Position
	return Vector2.new(position.X, position.Y)
end

local function wrap_angle(angle)
	return math.atan2(math.sin(angle), math.cos(angle))
end

local function find_named_descendant(root, names, className)
	if not root then
		return nil
	end

	for _, name in ipairs(names) do
		local descendant = root:FindFirstChild(name, true)
		if descendant and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function get_well_from_instance(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	local current = instance
	while current and current ~= Workspace do
		if current:IsA("Model")
			and (current.Name == WELL_NAME or current:GetAttribute("WellWaterSource") == true)
			and current:FindFirstChild(WELL_HANDLE_NAME, true)
		then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function is_well_in_own_plot(well)
	local plot = plotValue.Value
	return plot ~= nil and well ~= nil and well:IsDescendantOf(plot)
end

local function get_handle_root(well)
	return find_named_descendant(well, { WELL_HANDLE_NAME }, nil)
end

local function find_pivot(well)
	local handleRoot = get_handle_root(well)
	return find_named_descendant(handleRoot, { PIVOT_NAME }, "BasePart")
		or find_named_descendant(well, { PIVOT_NAME }, "BasePart")
end

local function find_handle(well)
	local handleRoot = get_handle_root(well)
	return find_named_descendant(handleRoot, { HANDLE_NAME }, "BasePart")
		or find_named_descendant(well, { HANDLE_NAME }, "BasePart")
end

local function collect_crank_parts(well, pivot)
	local handleRoot = get_handle_root(well)
	local parts = {}
	local seen = {}

	local function add_part(part)
		if part and part:IsA("BasePart") and part ~= pivot and not seen[part] then
			seen[part] = true
			parts[#parts + 1] = part
		end
	end

	for _, name in ipairs({ "CrankArm", "Handle" }) do
		local part = find_named_descendant(handleRoot, { name }, "BasePart")
			or find_named_descendant(well, { name }, "BasePart")
		add_part(part)
	end

	if handleRoot then
		for _, descendant in ipairs(handleRoot:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant:GetAttribute("WellCrankRotates") == true then
				add_part(descendant)
			end
		end
	end

	if #parts == 0 and handleRoot then
		for _, descendant in ipairs(handleRoot:GetDescendants()) do
			if descendant:IsA("BasePart") and descendant.Name ~= PIVOT_NAME then
				add_part(descendant)
			end
		end
	end

	return parts
end

local function get_axis_rotation(well, pivot, angle)
	local axisName = well:GetAttribute("WellCrankAxis")
		or pivot:GetAttribute("WellCrankAxis")
		or "X"
	axisName = string.upper(tostring(axisName))

	if axisName == "Y" then
		return CFrame.Angles(0, angle, 0)
	elseif axisName == "Z" then
		return CFrame.Angles(0, 0, angle)
	end

	return CFrame.Angles(angle, 0, 0)
end

local function apply_crank_angle(context, angle)
	local pivotCFrame = context.Pivot.CFrame
	local rotation = get_axis_rotation(context.Well, context.Pivot, angle)

	for part, originalCFrame in pairs(context.OriginalCFrames) do
		if part.Parent then
			local relativeCFrame = context.OriginalPivotCFrame:ToObjectSpace(originalCFrame)
			part.CFrame = pivotCFrame * rotation * relativeCFrame
		end
	end
end

local function request_well_action(action, well)
	if requestInFlight then
		return { Success = false, Code = "Busy" }
	end

	requestInFlight = true
	local callSucceeded, response = pcall(function()
		return Net.Function[WELL_WATER_FUNCTION_NAME]:Call({
			Action = action,
			Well = well,
		})
	end)
	requestInFlight = false

	if not callSucceeded or type(response) ~= "table" then
		return { Success = false, Code = "RemoteError" }
	end

	return response
end

local function create_progress_gui()
	local existingGui = playerGui:FindFirstChild(GUI_NAME)
	if existingGui then
		existingGui:Destroy()
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = GUI_NAME
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 80
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Name = "ProgressPanel"
	container.AnchorPoint = Vector2.new(0.5, 1)
	container.Position = UDim2.new(0.5, 0, 1, -84)
	container.Size = UDim2.new(0.86, 0, 0, 74)
	container.BackgroundColor3 = Color3.fromRGB(28, 31, 34)
	container.BackgroundTransparency = 0.08
	container.BorderSizePixel = 0
	container.Parent = screenGui

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(240, 74)
	sizeConstraint.MaxSize = Vector2.new(360, 74)
	sizeConstraint.Parent = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(18, 10)
	title.Size = UDim2.new(1, -36, 0, 22)
	title.Font = Enum.Font.GothamSemibold
	title.Text = "Turn the crank"
	title.TextColor3 = Color3.fromRGB(238, 242, 245)
	title.TextSize = 18
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = container

	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Position = UDim2.fromOffset(18, 42)
	barBackground.Size = UDim2.new(1, -36, 0, 14)
	barBackground.BackgroundColor3 = Color3.fromRGB(67, 75, 82)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = container

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 7)
	barCorner.Parent = barBackground

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(98, 175, 255)
	fill.BorderSizePixel = 0
	fill.Parent = barBackground

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 7)
	fillCorner.Parent = fill

	return {
		ScreenGui = screenGui,
		Fill = fill,
		Title = title,
	}
end

local function update_progress_gui(context)
	if not context.ProgressGui or not context.ProgressGui.Fill then
		return
	end

	local alpha = math.clamp(context.Progress, 0, 1)
	context.ProgressGui.Fill.Size = UDim2.fromScale(alpha, 1)
end

local function destroy_progress_gui(context)
	if context and context.ProgressGui and context.ProgressGui.ScreenGui then
		context.ProgressGui.ScreenGui:Destroy()
	end
end

local function get_camera_offset(well)
	local offset = well:GetAttribute("WellCrankCameraOffset")
	return if typeof(offset) == "Vector3" then offset else DEFAULT_CAMERA_OFFSET
end

local function get_camera_focus_offset(well)
	local offset = well:GetAttribute("WellCrankCameraFocusOffset")
	return if typeof(offset) == "Vector3" then offset else DEFAULT_CAMERA_FOCUS_OFFSET
end

local function build_camera_cframe(well, pivot)
	local cameraPart = find_named_descendant(well, { CAMERA_PART_NAME }, "BasePart")
	if cameraPart then
		return cameraPart.CFrame
	end

	local wellCFrame = well:GetPivot()
	local cameraPosition = wellCFrame:PointToWorldSpace(get_camera_offset(well))
	local focusPosition = pivot.CFrame:PointToWorldSpace(get_camera_focus_offset(well))

	return CFrame.lookAt(cameraPosition, focusPosition)
end

local function tween_camera_to(cframe, fov, duration)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	camera.CameraType = Enum.CameraType.Scriptable
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			CFrame = cframe,
			FieldOfView = fov,
		}
	)
	tween:Play()
	return tween
end

local function disable_controls(context)
	local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
	local playerModule = playerScripts and playerScripts:FindFirstChild("PlayerModule")
	if playerModule then
		local success, controls = pcall(function()
			return require(playerModule):GetControls()
		end)
		if success and controls then
			context.Controls = controls
			pcall(function()
				controls:Disable()
			end)
		end
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		context.Humanoid = humanoid
		context.PreviousWalkSpeed = humanoid.WalkSpeed
		context.PreviousJumpPower = humanoid.JumpPower
		context.PreviousJumpHeight = humanoid.JumpHeight
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
	end
end

local function restore_controls(context)
	if context and context.Controls then
		pcall(function()
			context.Controls:Enable()
		end)
	end

	local humanoid = context and context.Humanoid
	if humanoid and humanoid.Parent then
		if context.PreviousWalkSpeed then
			humanoid.WalkSpeed = context.PreviousWalkSpeed
		end
		if context.PreviousJumpPower then
			humanoid.JumpPower = context.PreviousJumpPower
		end
		if context.PreviousJumpHeight then
			humanoid.JumpHeight = context.PreviousJumpHeight
		end
	end
end

local function restore_camera(context)
	local camera = Workspace.CurrentCamera
	if not camera or not context or not context.PreviousCamera then
		return
	end

	local previous = context.PreviousCamera
	camera.CameraType = Enum.CameraType.Scriptable
	local tween = TweenService:Create(
		camera,
		TweenInfo.new(CAMERA_RETURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			CFrame = previous.CFrame,
			FieldOfView = previous.FieldOfView,
		}
	)
	tween:Play()
	local completedConnection
	completedConnection = tween.Completed:Connect(function()
		if completedConnection then
			completedConnection:Disconnect()
			completedConnection = nil
		end

		if activeInteraction then
			return
		end

		local fallbackSubject = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
		local restoredSubject = if previous.Subject and previous.Subject.Parent then previous.Subject else fallbackSubject
		if restoredSubject then
			camera.CameraSubject = restoredSubject
		end
		camera.CameraType = previous.Type or Enum.CameraType.Custom
	end)
end

local function restore_crank_parts(context)
	if not context or not context.OriginalCFrames then
		return
	end

	for part, originalCFrame in pairs(context.OriginalCFrames) do
		if part.Parent then
			part.CFrame = originalCFrame
		end
	end
end

local function disconnect_context(context)
	if not context then
		return
	end

	for _, connection in ipairs(context.Connections or {}) do
		connection:Disconnect()
	end
	table.clear(context.Connections)
end

local function finish_interaction(sendCancel)
	local context = activeInteraction
	if not context then
		return
	end

	activeInteraction = nil
	disconnect_context(context)
	destroy_progress_gui(context)
	restore_crank_parts(context)
	restore_controls(context)
	restore_camera(context)

	if context.Prompt and context.Prompt.Parent then
		context.Prompt.Enabled = true
	end

	if sendCancel then
		task.spawn(function()
			request_well_action("CancelCrank", context.Well)
		end)
	end
end

local function complete_interaction()
	local context = activeInteraction
	if not context or context.Finishing then
		return
	end

	context.Finishing = true
	context.Progress = 1
	update_progress_gui(context)
	apply_crank_angle(context, context.RequiredRotation)

	task.delay(COMPLETE_DELAY, function()
		if activeInteraction ~= context then
			return
		end

		local response = request_well_action("CompleteCrank", context.Well)
		if response.Success then
			SoundUtility.PlayGameSFX("Watering")
			finish_interaction(false)
		else
			finish_interaction(true)
		end
	end)
end

local function get_pointer_angle(context, pointerPosition)
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local pivotScreenPosition = camera:WorldToViewportPoint(context.Pivot.Position)
	local offset = pointerPosition - Vector2.new(pivotScreenPosition.X, pivotScreenPosition.Y)
	if offset.Magnitude < 4 then
		return nil
	end

	return math.atan2(offset.Y, offset.X)
end

local function is_pointer_on_handle(context, input)
	local camera = Workspace.CurrentCamera
	if not camera then
		return false
	end

	local pointerPosition = get_pointer_position(input)
	local ray = camera:ViewportPointToRay(pointerPosition.X, pointerPosition.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { context.Handle }

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
	if result then
		return true
	end

	local handleScreenPosition, onScreen = camera:WorldToViewportPoint(context.Handle.Position)
	if not onScreen then
		return false
	end

	return (pointerPosition - Vector2.new(handleScreenPosition.X, handleScreenPosition.Y)).Magnitude <= HANDLE_SCREEN_RADIUS
end

local function update_drag(context, input)
	local pointerAngle = get_pointer_angle(context, get_pointer_position(input))
	if not pointerAngle then
		return
	end

	if not context.LastPointerAngle then
		context.LastPointerAngle = pointerAngle
		return
	end

	local delta = wrap_angle(pointerAngle - context.LastPointerAngle)
	context.LastPointerAngle = pointerAngle

	if math.abs(delta) > math.pi * 0.75 then
		return
	end

	context.TotalRotation += delta
	context.ProgressRotation += math.abs(delta)
	context.Progress = math.clamp(context.ProgressRotation / context.RequiredRotation, 0, 1)

	apply_crank_angle(context, context.TotalRotation)
	update_progress_gui(context)

	if context.Progress >= 1 then
		complete_interaction()
	end
end

local function bind_interaction_input(context)
	context.Connections[#context.Connections + 1] = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if activeInteraction ~= context or context.Finishing then
			return
		end

		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB then
			finish_interaction(true)
			return
		end

		if gameProcessed or not is_primary_input(input) then
			return
		end

		if not is_pointer_on_handle(context, input) then
			return
		end

		context.Dragging = true
		context.LastPointerAngle = get_pointer_angle(context, get_pointer_position(input))
	end)

	context.Connections[#context.Connections + 1] = UserInputService.InputChanged:Connect(function(input, gameProcessed)
		if gameProcessed or activeInteraction ~= context or context.Finishing or not context.Dragging then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			update_drag(context, input)
		end
	end)

	context.Connections[#context.Connections + 1] = UserInputService.InputEnded:Connect(function(input)
		if activeInteraction ~= context or not is_primary_input(input) then
			return
		end

		context.Dragging = false
		context.LastPointerAngle = nil
	end)

	context.Connections[#context.Connections + 1] = localPlayer.CharacterRemoving:Connect(function()
		if activeInteraction == context then
			finish_interaction(true)
		end
	end)

	context.Connections[#context.Connections + 1] = RunService.RenderStepped:Connect(function()
		if activeInteraction ~= context then
			return
		end

		if not context.Well.Parent or not context.Pivot.Parent or not context.Handle.Parent then
			finish_interaction(true)
		end
	end)
end

local function start_crank(prompt, well)
	if activeInteraction or requestInFlight then
		return
	end

	if not is_well_in_own_plot(well) then
		return
	end

	local pivot = find_pivot(well)
	local handle = find_handle(well)
	if not pivot or not handle then
		return
	end

	local rotatingParts = collect_crank_parts(well, pivot)
	if #rotatingParts == 0 then
		return
	end

	local response = request_well_action("BeginCrank", well)
	if not response.Success then
		return
	end

	local camera = Workspace.CurrentCamera
	if not camera then
		request_well_action("CancelCrank", well)
		return
	end

	local requiredTurns = tonumber(response.RequiredTurns)
		or tonumber(well:GetAttribute(REQUIRED_TURNS_ATTRIBUTE))
		or DEFAULT_REQUIRED_TURNS
	requiredTurns = math.max(1, requiredTurns)

	local originalCFrames = {}
	for _, part in ipairs(rotatingParts) do
		originalCFrames[part] = part.CFrame
	end

	local context = {
		Well = well,
		Prompt = prompt,
		Pivot = pivot,
		Handle = handle,
		Parts = rotatingParts,
		OriginalCFrames = originalCFrames,
		OriginalPivotCFrame = pivot.CFrame,
		RequiredRotation = math.pi * 2 * requiredTurns,
		ProgressRotation = 0,
		TotalRotation = 0,
		Progress = 0,
		Dragging = false,
		Finishing = false,
		LastPointerAngle = nil,
		Connections = {},
		ProgressGui = nil,
		PreviousCamera = {
			Type = camera.CameraType,
			Subject = camera.CameraSubject,
			CFrame = camera.CFrame,
			FieldOfView = camera.FieldOfView,
		},
	}

	activeInteraction = context
	if prompt and prompt.Parent then
		prompt.Enabled = false
	end

	disable_controls(context)
	context.ProgressGui = create_progress_gui()
	update_progress_gui(context)
	tween_camera_to(build_camera_cframe(well, pivot), 50, CAMERA_TWEEN_TIME)
	bind_interaction_input(context)
end

local function collect_bucket(prompt, well)
	if requestInFlight then
		return
	end

	if not is_well_in_own_plot(well) then
		return
	end

	if prompt and prompt.Parent then
		prompt.Enabled = false
	end

	local response = request_well_action("CollectBucket", well)
	if not response.Success and prompt and prompt.Parent then
		prompt.Enabled = true
	end
end

local function apply_prompt_access(prompt)
	if not prompt or not prompt.Parent then
		return
	end

	local well = get_well_from_instance(prompt)
	local serverEnabled = prompt:GetAttribute(SERVER_PROMPT_ENABLED_ATTRIBUTE) == true
	prompt.Enabled = is_well_in_own_plot(well) and serverEnabled
end

local function track_well_prompt(prompt)
	if not prompt:IsA("ProximityPrompt") then
		return
	end

	if prompt.Name ~= "WellWaterPrompt" and prompt:GetAttribute(WELL_PROMPT_ATTRIBUTE) ~= true then
		return
	end

	if trackedPromptConnections[prompt] then
		apply_prompt_access(prompt)
		return
	end

	local connections = {}
	trackedPromptConnections[prompt] = connections

	connections[#connections + 1] = prompt:GetAttributeChangedSignal(WELL_PROMPT_ATTRIBUTE):Connect(function()
		apply_prompt_access(prompt)
	end)

	connections[#connections + 1] = prompt:GetAttributeChangedSignal(SERVER_PROMPT_ENABLED_ATTRIBUTE):Connect(function()
		apply_prompt_access(prompt)
	end)

	connections[#connections + 1] = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
		task.defer(apply_prompt_access, prompt)
	end)

	connections[#connections + 1] = prompt.AncestryChanged:Connect(function()
		if prompt.Parent then
			apply_prompt_access(prompt)
			return
		end

		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		trackedPromptConnections[prompt] = nil
	end)

	apply_prompt_access(prompt)
end

local function refresh_well_prompts()
	for prompt in pairs(trackedPromptConnections) do
		apply_prompt_access(prompt)
	end

	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			track_well_prompt(descendant)
		end
	end
end

ProximityPromptService.PromptTriggered:Connect(function(prompt)
	if prompt:GetAttribute(WELL_PROMPT_ATTRIBUTE) ~= true then
		return
	end

	local well = get_well_from_instance(prompt)
	if not well or not is_well_in_own_plot(well) then
		return
	end

	if well:GetAttribute(BUCKET_READY_ATTRIBUTE) == true then
		collect_bucket(prompt, well)
	else
		start_crank(prompt, well)
	end
end)

Workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("ProximityPrompt") then
		track_well_prompt(descendant)
	end
end)

plotValue:GetPropertyChangedSignal("Value"):Connect(refresh_well_prompts)

refresh_well_prompts()

script:SetAttribute("RuntimeReady", true)
