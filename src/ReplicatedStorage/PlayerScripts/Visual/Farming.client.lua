local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))
local Trove = require(Libraries:WaitForChild("Trove"))

local localPlayer = Players.LocalPlayer

local rootTrove = Trove.new()
local toolTroves: { [Tool]: any } = {}

local PLANT_ANIMATION_ID = "rbxassetid://93476696796138"
local PLANT_ANIMATION_FADE_SECONDS = 0.1
local PLANT_ANIMATION_FALLBACK_DURATION_SECONDS = 2
local PLANT_SFX_DELAY_SECONDS = 1.55
local PLANT_LEFT_HAND_SEED_APPEAR_DELAY_SECONDS = 1.5
local PLANT_LEFT_HAND_SEED_HIDE_DELAY_SECONDS = 2.08
local PLANT_LEFT_HAND_SEED_FALLBACK_GRIP = CFrame.new(0, -0.12, -0.18) * CFrame.Angles(math.rad(-12), math.rad(8), 0)
local PLANT_LEFT_HAND_SEED_EXTRA_OFFSET = CFrame.new(0, 0, -0.08)
local PLANT_MOVE_REACHED_DISTANCE = 2.5
local PLANT_MOVE_TIMEOUT_PADDING_SECONDS = 1.5
local PLANT_MOVE_TIMEOUT_MIN_SECONDS = 2
local PLANT_MOVE_TIMEOUT_MAX_SECONDS = 8
local PLAYER_MODULE_WAIT_SECONDS = 3

local activeTool: Tool? = nil
local activeToolTrove = nil
local previewPart: Part? = nil
local currentPlacement = nil
local requestInFlight = false
local activePlantingSession = nil
local playerControls = nil

local function get_player_controls()
	if playerControls then
		return playerControls
	end

	local playerScripts = localPlayer:FindFirstChild("PlayerScripts")
		or localPlayer:WaitForChild("PlayerScripts", PLAYER_MODULE_WAIT_SECONDS)
	if not playerScripts then
		return nil
	end

	local playerModule = playerScripts:FindFirstChild("PlayerModule")
		or playerScripts:WaitForChild("PlayerModule", PLAYER_MODULE_WAIT_SECONDS)
	if not playerModule then
		return nil
	end

	local success, result = pcall(require, playerModule)
	if not success or not result or type(result.GetControls) ~= "function" then
		return nil
	end

	playerControls = result:GetControls()
	return playerControls
end

local function set_player_controls_enabled(enabled: boolean)
	local controls = get_player_controls()
	if not controls then
		return
	end

	pcall(function()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

local function ensure_animator(humanoid: Humanoid): Animator?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function load_plant_animation(humanoid: Humanoid): (AnimationTrack?, Animation?)
	local animator = ensure_animator(humanoid)
	if not animator then
		return nil, nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = PLANT_ANIMATION_ID

	pcall(function()
		ContentProvider:PreloadAsync({ animation })
	end)

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not track then
		animation:Destroy()
		return nil, nil
	end

	pcall(function()
		track.Priority = Enum.AnimationPriority.Action4
	end)

	pcall(function()
		track.Looped = false
	end)

	return track, animation
end

local function get_track_duration(track: AnimationTrack?): number
	if not track then
		return PLANT_ANIMATION_FALLBACK_DURATION_SECONDS
	end

	local deadline = os.clock() + 1
	while track.Length <= 0 and os.clock() < deadline do
		task.wait()
	end

	if track.Length > 0 then
		return track.Length
	end

	return PLANT_ANIMATION_FALLBACK_DURATION_SECONDS
end

local function wait_for_session(session, duration: number): boolean
	local deadline = os.clock() + math.max(0, duration)
	while activePlantingSession == session and not session.Cancelled and os.clock() < deadline do
		task.wait()
	end

	return activePlantingSession == session and not session.Cancelled
end

local function disconnect_session_connections(session)
	for _, connection in ipairs(session.Connections) do
		connection:Disconnect()
	end

	table.clear(session.Connections)
end

local function find_left_hand(character: Model?): BasePart?
	if not character then
		return nil
	end

	for _, partName in ipairs({ "LeftHand", "Left Arm", "LeftLowerArm", "LeftUpperArm" }) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	local descendant = character:FindFirstChild("LeftHand", true)
	return if descendant and descendant:IsA("BasePart") then descendant else nil
end

local function find_right_hand(character: Model?): BasePart?
	if not character then
		return nil
	end

	for _, partName in ipairs({ "RightHand", "Right Arm", "RightLowerArm", "RightUpperArm" }) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	local descendant = character:FindFirstChild("RightHand", true)
	return if descendant and descendant:IsA("BasePart") then descendant else nil
end

local function find_visual_handle(root: Instance): BasePart?
	local directHandle = root:FindFirstChild("Handle")
	if directHandle and directHandle:IsA("BasePart") then
		return directHandle
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "Handle" then
			return descendant
		end
	end

	return FarmingUtility.GetFirstBasePart(root)
end

local function get_left_hand_seed_grip(session): CFrame
	local tool = session.Tool
	local rightHand = find_right_hand(session.Character)
	local sourceHandle = tool and find_visual_handle(tool) or nil

	if rightHand and sourceHandle then
		return rightHand.CFrame:ToObjectSpace(sourceHandle.CFrame) * PLANT_LEFT_HAND_SEED_EXTRA_OFFSET
	end

	if tool then
		return tool.Grip * PLANT_LEFT_HAND_SEED_EXTRA_OFFSET
	end

	return PLANT_LEFT_HAND_SEED_FALLBACK_GRIP * PLANT_LEFT_HAND_SEED_EXTRA_OFFSET
end

local function strip_visual_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function hide_seed_tool_visual(session)
	if session.SeedToolVisualHidden then
		return
	end

	local tool = session.Tool
	if not tool then
		return
	end

	session.HiddenSeedVisuals = {}
	session.SeedToolVisualHidden = true

	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			session.HiddenSeedVisuals[#session.HiddenSeedVisuals + 1] = {
				Instance = descendant,
				Property = "LocalTransparencyModifier",
				Value = descendant.LocalTransparencyModifier,
			}
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			session.HiddenSeedVisuals[#session.HiddenSeedVisuals + 1] = {
				Instance = descendant,
				Property = "Transparency",
				Value = descendant.Transparency,
			}
			descendant.Transparency = 1
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			session.HiddenSeedVisuals[#session.HiddenSeedVisuals + 1] = {
				Instance = descendant,
				Property = "Enabled",
				Value = descendant.Enabled,
			}
			descendant.Enabled = false
		end
	end
end

local function restore_seed_tool_visual(session)
	for _, entry in ipairs(session.HiddenSeedVisuals or {}) do
		if entry.Instance and entry.Instance.Parent then
			pcall(function()
				entry.Instance[entry.Property] = entry.Value
			end)
		end
	end

	session.HiddenSeedVisuals = nil
	session.SeedToolVisualHidden = false
end

local function clone_seed_tool_visual(tool: Tool?): Model?
	if not tool then
		return nil
	end

	local cloneSucceeded, toolClone = pcall(function()
		return tool:Clone()
	end)
	if not cloneSucceeded or not toolClone then
		return nil
	end

	strip_visual_scripts(toolClone)

	local visualModel = Instance.new("Model")
	visualModel.Name = "PlantSeedLeftHandVisual"

	for _, child in ipairs(toolClone:GetChildren()) do
		child.Parent = visualModel
	end

	toolClone:Destroy()

	local handle = find_visual_handle(visualModel)
	if not handle then
		visualModel:Destroy()
		return nil
	end

	visualModel.PrimaryPart = handle

	for _, descendant in ipairs(visualModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.LocalTransparencyModifier = 0
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 0
		elseif descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			descendant.Enabled = true
		end
	end

	return visualModel
end

local function show_left_hand_seed_visual(session)
	if session.LeftHandSeedDismissed then
		return
	end

	if session.LeftHandSeedVisual and session.LeftHandSeedVisual.Parent then
		return
	end

	local leftHand = find_left_hand(session.Character)
	local visualModel = session.LeftHandSeedVisual or clone_seed_tool_visual(session.Tool)
	if not leftHand or not visualModel then
		return
	end

	local handle = visualModel.PrimaryPart or find_visual_handle(visualModel)
	if not handle then
		visualModel:Destroy()
		session.LeftHandSeedVisual = nil
		return
	end

	session.LeftHandSeedVisual = visualModel
	visualModel.PrimaryPart = handle
	visualModel.Parent = session.Character
	handle.CFrame = leftHand.CFrame * get_left_hand_seed_grip(session)

	local weld = Instance.new("WeldConstraint")
	weld.Name = "PlantSeedLeftHandWeld"
	weld.Part0 = leftHand
	weld.Part1 = handle
	weld.Parent = handle
end

local function destroy_left_hand_seed_visual(session)
	if session.LeftHandSeedVisual then
		session.LeftHandSeedVisual:Destroy()
		session.LeftHandSeedVisual = nil
	end
end

local function dismiss_left_hand_seed_visual(session)
	session.LeftHandSeedDismissed = true
	destroy_left_hand_seed_visual(session)
end

local function restore_planting_session(session)
	disconnect_session_connections(session)
	destroy_left_hand_seed_visual(session)
	restore_seed_tool_visual(session)

	if session.Track then
		pcall(function()
			session.Track:Stop(PLANT_ANIMATION_FADE_SECONDS)
		end)
	end

	if session.Animation then
		session.Animation:Destroy()
	end

	if session.Humanoid and session.Humanoid.Parent then
		session.Humanoid.WalkSpeed = session.SavedWalkSpeed
		session.Humanoid.JumpPower = session.SavedJumpPower
		session.Humanoid.JumpHeight = session.SavedJumpHeight
		session.Humanoid.AutoRotate = session.SavedAutoRotate
	end

	if session.ControlsDisabled then
		set_player_controls_enabled(true)
	end

	if activePlantingSession == session then
		activePlantingSession = nil
	end

	requestInFlight = false
end

local function cancel_planting_session(session)
	if activePlantingSession ~= session or session.Cancelled then
		return
	end

	session.Cancelled = true
	restore_planting_session(session)
end

local function is_tool_still_equipped(tool: Tool?): boolean
	local character = localPlayer.Character
	return tool ~= nil and character ~= nil and tool.Parent == character
end

local function face_root_towards(rootPart: BasePart, targetPosition: Vector3)
	local rootPosition = rootPart.Position
	local lookAt = Vector3.new(targetPosition.X, rootPosition.Y, targetPosition.Z)

	if (lookAt - rootPosition).Magnitude <= 0.01 then
		return
	end

	rootPart.CFrame = CFrame.lookAt(rootPosition, lookAt)
end

local function move_character_to_position(session, targetPosition: Vector3): boolean
	local humanoid = session.Humanoid
	local rootPart = session.RootPart
	if not humanoid or not humanoid.Parent or not rootPart or not rootPart.Parent then
		return false
	end

	local finished = false
	local reached = false
	local connection = humanoid.MoveToFinished:Connect(function(didReach)
		reached = didReach
		finished = true
	end)
	session.Connections[#session.Connections + 1] = connection

	local distance = (rootPart.Position - targetPosition).Magnitude
	local walkSpeed = math.max(tonumber(humanoid.WalkSpeed) or 0, 1)
	local timeout = math.clamp(
		(distance / walkSpeed) + PLANT_MOVE_TIMEOUT_PADDING_SECONDS,
		PLANT_MOVE_TIMEOUT_MIN_SECONDS,
		PLANT_MOVE_TIMEOUT_MAX_SECONDS
	)
	local deadline = os.clock() + timeout

	humanoid:MoveTo(targetPosition)

	while activePlantingSession == session and not session.Cancelled and not finished and os.clock() < deadline do
		if (rootPart.Position - targetPosition).Magnitude <= PLANT_MOVE_REACHED_DISTANCE then
			reached = true
			break
		end

		task.wait()
	end

	connection:Disconnect()

	for index, existingConnection in ipairs(session.Connections) do
		if existingConnection == connection then
			table.remove(session.Connections, index)
			break
		end
	end

	pcall(function()
		humanoid:Move(Vector3.zero, false)
	end)

	return reached or (rootPart.Position - targetPosition).Magnitude <= PLANT_MOVE_REACHED_DISTANCE
end

local function ensure_preview_part(): Part
	if previewPart then
		return previewPart
	end

	local part = Instance.new("Part")
	part.Name = "SeedPreview"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Size = FarmingUtility.PLANT_FOOTPRINT_SIZE
	part.Transparency = 1
	part.Parent = Workspace

	previewPart = part
	return part
end

local function hide_preview()
	currentPlacement = nil

	if previewPart then
		previewPart.Transparency = 1
	end
end

local function clear_active_tool()
	if activePlantingSession and not activePlantingSession.ServerRequestStarted then
		cancel_planting_session(activePlantingSession)
	end

	activeTool = nil

	if activeToolTrove then
		activeToolTrove:Destroy()
		activeToolTrove = nil
	end

	hide_preview()
end

local function get_mouse_raycast(ignoreFarmPlants: boolean): RaycastResult?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	local filter = {}

	if localPlayer.Character then
		table.insert(filter, localPlayer.Character)
	end

	if previewPart then
		table.insert(filter, previewPart)
	end

	if ignoreFarmPlants then
		local farmFolder = Workspace:FindFirstChild(FarmingUtility.FARM_FOLDER_NAME)
		if farmFolder then
			table.insert(filter, farmFolder)
		end
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filter

	return Workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
end

local function update_seed_preview()
	if activePlantingSession then
		hide_preview()
		return
	end

	local part = ensure_preview_part()
	local raycastResult = get_mouse_raycast(true)

	if not raycastResult then
		hide_preview()
		return
	end

	local placement = FarmingUtility.GetSoilPlacementData(raycastResult.Position, localPlayer, part.Size)
	local isOccupied = false
	if placement then
		isOccupied = FarmingUtility.IsPlacementOccupied(placement, localPlayer.UserId)
	end
	local isValid = placement ~= nil and not isOccupied

	if placement then
		currentPlacement = if isValid then placement else nil
		part.CFrame = placement.Soil.CFrame
			* CFrame.new(
				placement.LocalPoint.X,
				placement.Soil.Size.Y * 0.5 + part.Size.Y * 0.5 + 0.03,
				placement.LocalPoint.Z
			)
	else
		currentPlacement = nil
		part.CFrame = CFrame.new(raycastResult.Position + Vector3.new(0, part.Size.Y * 0.5 + 0.03, 0))
	end

	part.Color = isValid and Color3.fromRGB(92, 214, 102) or Color3.fromRGB(235, 88, 88)
	part.Transparency = 0.4
end

local function start_planting_session(placement): boolean
	if activePlantingSession or requestInFlight or not placement then
		return false
	end

	local tool = activeTool
	if not is_tool_still_equipped(tool) then
		return false
	end

	local soil = placement.Soil
	if not soil or not soil.Parent then
		return false
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 or not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local targetPosition = FarmingUtility.GetWorldTopPosition(soil, placement.LocalPoint)
	local session = {
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
		Tool = tool,
		TargetPosition = targetPosition,
		Connections = {},
		Cancelled = false,
		ControlsDisabled = false,
		ServerRequestStarted = false,
		SavedWalkSpeed = humanoid.WalkSpeed,
		SavedJumpPower = humanoid.JumpPower,
		SavedJumpHeight = humanoid.JumpHeight,
		SavedAutoRotate = humanoid.AutoRotate,
		Track = nil,
		Animation = nil,
		HiddenSeedVisuals = nil,
		SeedToolVisualHidden = false,
		LeftHandSeedVisual = nil,
		LeftHandSeedDismissed = false,
	}

	activePlantingSession = session
	requestInFlight = true
	hide_preview()
	set_player_controls_enabled(false)
	session.ControlsDisabled = true

	session.Connections[#session.Connections + 1] = localPlayer.CharacterRemoving:Connect(function(removingCharacter)
		if removingCharacter == character then
			cancel_planting_session(session)
		end
	end)

	session.Connections[#session.Connections + 1] = tool.Unequipped:Connect(function()
		if not session.ServerRequestStarted then
			cancel_planting_session(session)
		end
	end)

	session.Connections[#session.Connections + 1] = tool.AncestryChanged:Connect(function()
		if not is_tool_still_equipped(tool) and not session.ServerRequestStarted then
			cancel_planting_session(session)
		end
	end)

	task.spawn(function()
		local reached = move_character_to_position(session, targetPosition)
		if activePlantingSession ~= session or session.Cancelled then
			return
		end

		if not reached or not is_tool_still_equipped(tool) then
			restore_planting_session(session)
			return
		end

		face_root_towards(rootPart, targetPosition)
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		humanoid.AutoRotate = false

		local track, animation = load_plant_animation(humanoid)
		session.Track = track
		session.Animation = animation
		local animationDuration = get_track_duration(track)
		session.LeftHandSeedVisual = clone_seed_tool_visual(tool)
		hide_seed_tool_visual(session)

		if track then
			pcall(function()
				track:Play(PLANT_ANIMATION_FADE_SECONDS, 1, 1)
			end)
		end

		local animationStartedAt = os.clock()
		local seedAppearDelay = math.clamp(PLANT_LEFT_HAND_SEED_APPEAR_DELAY_SECONDS, 0, animationDuration)
		task.delay(seedAppearDelay, function()
			if activePlantingSession == session and not session.Cancelled then
				show_left_hand_seed_visual(session)
			end
		end)

		local seedHideDelay = math.clamp(PLANT_LEFT_HAND_SEED_HIDE_DELAY_SECONDS, 0, animationDuration)
		task.delay(seedHideDelay, function()
			if activePlantingSession == session and not session.Cancelled then
				dismiss_left_hand_seed_visual(session)
			end
		end)

		local sfxDelay = math.clamp(PLANT_SFX_DELAY_SECONDS, 0, animationDuration)
		if not wait_for_session(session, sfxDelay) then
			return
		end

		if not is_tool_still_equipped(tool) then
			restore_planting_session(session)
			return
		end

		session.ServerRequestStarted = true
		local success, response = pcall(function()
			return Net.Function.PlantSeed:Call(targetPosition)
		end)

		if activePlantingSession ~= session or session.Cancelled then
			return
		end

		if success and response and response.Success then
			SoundUtility.PlayGameSFX("Dig")
			hide_preview()
		end

		local remainingAnimationTime = animationDuration - (os.clock() - animationStartedAt)
		if remainingAnimationTime > 0 then
			wait_for_session(session, remainingAnimationTime)
		end

		if activePlantingSession == session then
			restore_planting_session(session)
		end
	end)

	return true
end

local function try_place_seed()
	if requestInFlight or not currentPlacement then
		return
	end

	start_planting_session({
		Soil = currentPlacement.Soil,
		LocalPoint = currentPlacement.LocalPoint,
	})
end

local function try_water_plant()
	if requestInFlight then
		return
	end

	local raycastResult = get_mouse_raycast(false)
	if not raycastResult or not raycastResult.Instance then
		return
	end

	requestInFlight = true
	local success, response = pcall(function()
		return Net.Function.WaterPlant:Call(raycastResult.Instance)
	end)
	requestInFlight = false

	if success and response and response.Success then
		SoundUtility.PlayGameSFX("Watering")
	end
end

local function activate_seed_tool(tool: Tool)
	clear_active_tool()

	activeTool = tool
	activeToolTrove = Trove.new()

	activeToolTrove:Add(RunService.RenderStepped:Connect(update_seed_preview))
	activeToolTrove:Add(tool.Activated:Connect(try_place_seed))
	activeToolTrove:Add(function()
		if activeTool == tool then
			activeTool = nil
		end
	end)

	update_seed_preview()
end

local function activate_watering_tool(tool: Tool)
	clear_active_tool()

	activeTool = tool
	activeToolTrove = Trove.new()

	activeToolTrove:Add(tool.Activated:Connect(try_water_plant))
	activeToolTrove:Add(function()
		if activeTool == tool then
			activeTool = nil
		end
	end)
end

local function handle_tool_equipped(tool: Tool)
	if FarmingUtility.IsSeedTool(tool) then
		activate_seed_tool(tool)
		return
	end

	if tool.Name == FarmingUtility.WATERING_TOOL_NAME then
		activate_watering_tool(tool)
	end
end

local function watch_tool(tool: Tool)
	if toolTroves[tool] then
		return
	end

	local trove = Trove.new()
	toolTroves[tool] = trove

	trove:Add(tool.Equipped:Connect(function()
		handle_tool_equipped(tool)
	end))

	trove:Add(tool.Unequipped:Connect(function()
		if activeTool == tool then
			clear_active_tool()
		end
	end))

	trove:Add(tool.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		if activeTool == tool then
			clear_active_tool()
		end

		trove:Destroy()
		toolTroves[tool] = nil
	end))
end

local function watch_tool_container(container: Instance, trove)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			watch_tool(child)
		end
	end

	trove:Add(container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			watch_tool(child)
		end
	end))
end

local function bind_character(character: Model)
	local characterTrove = Trove.new()

	watch_tool_container(character, characterTrove)

	local backpack = localPlayer:WaitForChild("Backpack")
	watch_tool_container(backpack, characterTrove)

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			handle_tool_equipped(child)
		end
	end

	characterTrove:Add(character.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		clear_active_tool()
		characterTrove:Destroy()
	end))
end

rootTrove:Add(localPlayer.CharacterAdded:Connect(bind_character))

if localPlayer.Character then
	bind_character(localPlayer.Character)
end

script:SetAttribute("RuntimeReady", true)
