local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local GameModules = Modules:WaitForChild("Game")

local Network = require(Modules:WaitForChild("Network"))
local StableCleaningConfig = require(GameData:WaitForChild("Horse"):WaitForChild("StableCleaningConfig"))
local ToolRegistry = require(GameModules:WaitForChild("Tools"):WaitForChild("Registry"))

local plotValue = localPlayer:WaitForChild("Plot")

local CLEAN_ANIMATION_ID = "rbxassetid://71026839915576"
local CLEAN_ANIMATION_FADE_SECONDS = 0.1
local CLEAN_ANIMATION_FALLBACK_DURATION_SECONDS = 1.6
local CLEAN_MOVE_REACHED_DISTANCE = 2.75
local CLEAN_STAND_DISTANCE = 2.25
local CLEAN_MOVE_TIMEOUT_PADDING_SECONDS = 1.5
local CLEAN_MOVE_TIMEOUT_MIN_SECONDS = 2
local CLEAN_MOVE_TIMEOUT_MAX_SECONDS = 8
local PLAYER_MODULE_WAIT_SECONDS = 3
local BROOM_TOOL_ITEM_ID = "stable_broom"
local BROOM_VISUAL_NAME = "Broom"
local BROOM_MOTOR_NAME = "Broom"

local activePrompts = {}
local connections = {}
local refreshQueued = false
local requestInFlight = false
local playerControls = nil
local queue_refresh

local function disconnect_all()
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function destroy_prompts()
	for _, prompt in ipairs(activePrompts) do
		prompt:Destroy()
	end

	table.clear(activePrompts)
end

local function get_equipped_cleaning_tool(): (Tool?, string?)
	local character = localPlayer.Character
	if not character then
		return nil, nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local definition, itemId = ToolRegistry.resolve_definition_from_tool(child)
			if definition and definition.target == StableCleaningConfig.TargetType then
				return child, itemId
			end
		end
	end

	return nil, nil
end

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

local function is_tool_still_equipped(tool: Tool?): boolean
	local character = localPlayer.Character
	return tool ~= nil and character ~= nil and tool.Parent == character
end

local function get_prompt_parent(dirtVisual: Instance): BasePart?
	if dirtVisual:IsA("Model") then
		return dirtVisual.PrimaryPart or dirtVisual:FindFirstChildWhichIsA("BasePart", true)
	end

	if dirtVisual:IsA("BasePart") then
		return dirtVisual
	end

	return nil
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

local function load_clean_animation(humanoid: Humanoid): (AnimationTrack?, Animation?)
	local animator = ensure_animator(humanoid)
	if not animator then
		return nil, nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = CLEAN_ANIMATION_ID

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
		track.Looped = false
	end)

	return track, animation
end

local function get_animation_duration(track: AnimationTrack?): number
	if not track then
		return CLEAN_ANIMATION_FALLBACK_DURATION_SECONDS
	end

	local deadline = os.clock() + 1
	while track.Length <= 0 and os.clock() < deadline do
		task.wait()
	end

	return if track.Length > 0 then track.Length else CLEAN_ANIMATION_FALLBACK_DURATION_SECONDS
end

local function get_character_parts(): (Model?, Humanoid?, BasePart?)
	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	if not character
		or not humanoid
		or humanoid.Health <= 0
		or not rootPart
		or not rootPart:IsA("BasePart")
	then
		return nil, nil, nil
	end

	return character, humanoid, rootPart
end

local function find_right_arm(character: Model): BasePart?
	for _, partName in ipairs({ "RightHand", "Right Arm", "RightLowerArm", "RightUpperArm" }) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	local rightHand = character:FindFirstChild("RightHand", true)
	return if rightHand and rightHand:IsA("BasePart") then rightHand else nil
end

local function get_broom_template(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("VFX")
	local objects = vfx and vfx:FindFirstChild("Objects")
	return objects and objects:FindFirstChild(BROOM_VISUAL_NAME)
end

local function find_broom_handle(visual: Instance): BasePart?
	if visual:IsA("BasePart") then
		return visual
	end

	local namedHandle = visual:FindFirstChild("Handle", true)
	if namedHandle and namedHandle:IsA("BasePart") then
		return namedHandle
	end

	return visual:FindFirstChildWhichIsA("BasePart", true)
end

local function get_tool_grip(tool: Tool, rightArm: BasePart): CFrame
	for _, joint in ipairs(rightArm:GetChildren()) do
		if joint:IsA("Motor6D")
			and joint.Part0 == rightArm
			and joint.Part1
			and joint.Part1:IsDescendantOf(tool)
		then
			return joint.C0
		end
	end

	return tool.Grip
end

local function hide_tool_visual(tool: Tool): {any}
	local hiddenVisuals = {}

	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			hiddenVisuals[#hiddenVisuals + 1] = {
				Instance = descendant,
				Value = descendant.LocalTransparencyModifier,
			}
			descendant.LocalTransparencyModifier = 1
		end
	end

	return hiddenVisuals
end

local function restore_tool_visual(hiddenVisuals: {any})
	for _, entry in ipairs(hiddenVisuals) do
		if entry.Instance and entry.Instance.Parent then
			entry.Instance.LocalTransparencyModifier = entry.Value
		end
	end
end

local function attach_broom_visual(character: Model, tool: Tool): (Instance?, {any}?)
	local rightArm = find_right_arm(character)
	local template = get_broom_template()
	if not rightArm or not template then
		return nil, nil
	end

	local cloneSucceeded, visual = pcall(function()
		return template:Clone()
	end)
	if not cloneSucceeded or not visual then
		return nil, nil
	end

	local handle = find_broom_handle(visual)
	if not handle then
		visual:Destroy()
		return nil, nil
	end

	visual.Name = "Handle"
	handle.Name = "Handle"

	local function prepare_part(part: BasePart)
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true

		if part ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "BroomVisualWeld"
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
		end
	end

	if visual:IsA("BasePart") then
		prepare_part(visual)
	end

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			prepare_part(descendant)
		end
	end

	local grip = get_tool_grip(tool, rightArm)
	local targetHandleCFrame = rightArm.CFrame * grip
	if visual:IsA("Model") then
		local handleToPivot = handle.CFrame:ToObjectSpace(visual:GetPivot())
		visual:PivotTo(targetHandleCFrame * handleToPivot)
	else
		handle.CFrame = targetHandleCFrame
	end

	visual.Parent = character

	local motor = Instance.new("Motor6D")
	motor.Name = BROOM_MOTOR_NAME
	motor.Part0 = rightArm
	motor.Part1 = handle
	motor.C0 = grip
	motor.Parent = rightArm

	return visual, hide_tool_visual(tool)
end

local function get_clean_stand_position(rootPart: BasePart, targetPart: BasePart): Vector3
	local targetPosition = targetPart.Position
	local rootPosition = rootPart.Position
	local away = Vector3.new(rootPosition.X - targetPosition.X, 0, rootPosition.Z - targetPosition.Z)

	if away.Magnitude < 0.05 then
		away = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
	end

	if away.Magnitude < 0.05 then
		return targetPosition
	end

	local standPosition = targetPosition + away.Unit * CLEAN_STAND_DISTANCE
	return Vector3.new(standPosition.X, targetPosition.Y, standPosition.Z)
end

local function move_character_to_target(humanoid: Humanoid, rootPart: BasePart, targetPart: BasePart): boolean
	local targetPosition = get_clean_stand_position(rootPart, targetPart)
	local finished = false
	local reached = false
	local connection = humanoid.MoveToFinished:Connect(function(didReach)
		reached = didReach
		finished = true
	end)

	local distance = (rootPart.Position - targetPosition).Magnitude
	local walkSpeed = math.max(tonumber(humanoid.WalkSpeed) or 0, 1)
	local timeout = math.clamp(
		(distance / walkSpeed) + CLEAN_MOVE_TIMEOUT_PADDING_SECONDS,
		CLEAN_MOVE_TIMEOUT_MIN_SECONDS,
		CLEAN_MOVE_TIMEOUT_MAX_SECONDS
	)
	local deadline = os.clock() + timeout

	humanoid:MoveTo(targetPosition)

	while requestInFlight and not finished and os.clock() < deadline do
		if (rootPart.Position - targetPosition).Magnitude <= CLEAN_MOVE_REACHED_DISTANCE then
			reached = true
			break
		end

		task.wait()
	end

	connection:Disconnect()

	pcall(function()
		humanoid:Move(Vector3.zero, false)
	end)

	return reached or (rootPart.Position - targetPosition).Magnitude <= CLEAN_MOVE_REACHED_DISTANCE
end

local function face_root_towards(rootPart: BasePart, targetPosition: Vector3)
	local rootPosition = rootPart.Position
	local lookAt = Vector3.new(targetPosition.X, rootPosition.Y, targetPosition.Z)

	if (lookAt - rootPosition).Magnitude <= 0.01 then
		return
	end

	rootPart.CFrame = CFrame.lookAt(rootPosition, lookAt)
end

local function play_clean_animation(character: Model, humanoid: Humanoid, tool: Tool, toolItemId: string)
	local track, animation = load_clean_animation(humanoid)
	local duration = get_animation_duration(track)
	local broomVisual = nil
	local hiddenToolVisuals = nil

	if toolItemId == BROOM_TOOL_ITEM_ID then
		broomVisual, hiddenToolVisuals = attach_broom_visual(character, tool)
	end

	if track then
		pcall(function()
			track:Play(CLEAN_ANIMATION_FADE_SECONDS, 1, 1)
		end)
	end

	task.wait(duration)

	if track then
		pcall(function()
			track:Stop(CLEAN_ANIMATION_FADE_SECONDS)
		end)
	end

	if animation then
		animation:Destroy()
	end

	if broomVisual then
		broomVisual:Destroy()
	end

	if hiddenToolVisuals then
		restore_tool_visual(hiddenToolVisuals)
	end
end

local function get_dirt_visuals(plot: Instance, toolItemId: string): {Instance}
	local visuals = {}

	for _, descendant in ipairs(plot:GetDescendants()) do
		if descendant:GetAttribute(StableCleaningConfig.DirtAttribute) == true
			and descendant:GetAttribute(StableCleaningConfig.RequiredToolAttribute) == toolItemId
		then
			visuals[#visuals + 1] = descendant
		end
	end

	return visuals
end

local function request_clean(tool: Tool, horseId: string, dirtId: string, targetPart: BasePart): boolean
	if requestInFlight then
		return false
	end

	requestInFlight = true
	set_player_controls_enabled(false)

	local humanoidToRestore = nil
	local savedWalkSpeed = nil
	local savedJumpPower = nil
	local savedJumpHeight = nil
	local savedAutoRotate = nil

	local function finish_request(result: boolean): boolean
		if humanoidToRestore and humanoidToRestore.Parent then
			humanoidToRestore.WalkSpeed = savedWalkSpeed
			humanoidToRestore.JumpPower = savedJumpPower
			humanoidToRestore.JumpHeight = savedJumpHeight
			humanoidToRestore.AutoRotate = savedAutoRotate
		end

		set_player_controls_enabled(true)
		requestInFlight = false
		return result
	end

	if not is_tool_still_equipped(tool) then
		return finish_request(false)
	end

	local character, humanoid, rootPart = get_character_parts()
	if not character or not humanoid or not rootPart or not targetPart.Parent then
		return finish_request(false)
	end

	local reachedTarget = move_character_to_target(humanoid, rootPart, targetPart)
	if not reachedTarget or not targetPart.Parent or not is_tool_still_equipped(tool) then
		return finish_request(false)
	end

	face_root_towards(rootPart, targetPart.Position)

	humanoidToRestore = humanoid
	savedWalkSpeed = humanoid.WalkSpeed
	savedJumpPower = humanoid.JumpPower
	savedJumpHeight = humanoid.JumpHeight
	savedAutoRotate = humanoid.AutoRotate

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false

	play_clean_animation(character, humanoid, tool, toolItemId)

	if not is_tool_still_equipped(tool) or not targetPart.Parent then
		return finish_request(false)
	end

	local callSucceeded, wasCleaned = pcall(function()
		return Network.Horse.CleanStableDirt:Call(tool, horseId, dirtId)
	end)

	return finish_request(callSucceeded and wasCleaned == true)
end

function queue_refresh()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		destroy_prompts()

		local plot = plotValue.Value
		local tool, toolItemId = get_equipped_cleaning_tool()
		if not plot or not tool or not toolItemId then
			return
		end

		for _, dirtVisual in ipairs(get_dirt_visuals(plot, toolItemId)) do
			local promptParent = get_prompt_parent(dirtVisual)
			local dirtId = dirtVisual:GetAttribute(StableCleaningConfig.DirtIdAttribute)
			local dirtTypeId = dirtVisual:GetAttribute(StableCleaningConfig.DirtTypeAttribute)
			local horseId = dirtVisual:GetAttribute("HorseId")
			local dirtDefinition = StableCleaningConfig.GetDirtDefinition(dirtTypeId)

			if promptParent
				and dirtDefinition
				and type(dirtId) == "string"
				and dirtId ~= ""
				and type(horseId) == "string"
				and horseId ~= ""
			then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "StableCleaningPrompt"
				prompt.ActionText = dirtDefinition.ActionText
				prompt.ObjectText = ("%s  |  %s"):format(
					dirtDefinition.DisplayName,
					StableCleaningConfig.GetPenaltySummary(dirtTypeId)
				)
				prompt.HoldDuration = dirtDefinition.HoldDuration
				prompt.MaxActivationDistance = StableCleaningConfig.MaxCleanDistance
				prompt.RequiresLineOfSight = false
				prompt.Style = Enum.ProximityPromptStyle.Default
				prompt.Parent = promptParent

				prompt.Triggered:Connect(function()
					local currentTool, currentItemId = get_equipped_cleaning_tool()
					if currentTool ~= tool or currentItemId ~= toolItemId then
						queue_refresh()
						return
					end

					prompt.Enabled = false
					if not request_clean(tool, horseId, dirtId, promptParent) and prompt.Parent then
						prompt.Enabled = true
					end
				end)

				activePrompts[#activePrompts + 1] = prompt
			end
		end
	end)
end

local function bind_character(character: Model)
	disconnect_all()

	connections[#connections + 1] = character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	connections[#connections + 1] = character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	queue_refresh()
end

plotValue:GetPropertyChangedSignal("Value"):Connect(queue_refresh)
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:GetAttribute(StableCleaningConfig.DirtAttribute) == true then
		queue_refresh()
	end
end)
workspace.DescendantRemoving:Connect(function(descendant)
	if descendant:GetAttribute(StableCleaningConfig.DirtAttribute) == true then
		queue_refresh()
	end
end)

localPlayer.CharacterAdded:Connect(bind_character)
localPlayer.CharacterRemoving:Connect(function()
	requestInFlight = false
	set_player_controls_enabled(true)
	disconnect_all()
	destroy_prompts()
end)

if localPlayer.Character then
	bind_character(localPlayer.Character)
end

queue_refresh()

script:SetAttribute("RuntimeReady", true)
