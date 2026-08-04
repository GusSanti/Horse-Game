------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local TweenService: TweenService = game:GetService("TweenService")

------------------//CONSTANTS
local localPlayer: Player = Players.LocalPlayer
local PLAYER_BRUSH_ANIMATION_ID = "rbxassetid://99003220029388"
local PLAYER_POSITION_TWEEN_DURATION = 0.35
local Network = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Network"))

------------------//VARIABLES
local HorseBrushClient = {}
local activeSession = nil

------------------//FUNCTIONS
local function disconnect_all(connections: {RBXScriptConnection}): ()
	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function ensure_animator(controller: Instance?): Animator?
	if not controller then
		return nil
	end

	local animator = controller:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	if controller:IsA("Humanoid") or controller:IsA("AnimationController") then
		animator = Instance.new("Animator")
		animator.Parent = controller
		return animator
	end

	return nil
end

local function load_animation_track(animator: Animator?, animation: Animation): AnimationTrack?
	if not animator then
		return nil
	end

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success then
		return nil
	end

	pcall(function()
		track.Priority = Enum.AnimationPriority.Action
	end)

	return track
end

local function play_track(track: AnimationTrack?): ()
	if not track then
		return
	end

	pcall(function()
		track:Play(0.1, 1, 1)
	end)
end

local function stop_track(track: AnimationTrack?): ()
	if not track then
		return
	end

	pcall(function()
		track:Stop(0.1)
	end)
end

local function destroy_animation(animation: Animation?): ()
	if not animation then
		return
	end

	animation:Destroy()
end

local function get_animation_duration(track: AnimationTrack?, fallbackDuration: number): number
	if not track then
		return fallbackDuration
	end

	local deadline = os.clock() + 3
	while track.Length <= 0 and os.clock() < deadline do
		task.wait()
	end

	return if track.Length > 0 then track.Length else fallbackDuration
end

local function get_instance_pivot(instance: Instance): CFrame
	if instance:IsA("Model") or instance:IsA("BasePart") then
		return instance:GetPivot()
	end

	return CFrame.new()
end

local function find_right_hand(character: Model): BasePart?
	for _, partName in ipairs({ "RightHand", "Right Arm", "RightLowerArm", "RightUpperArm" }) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	local rightHand = character:FindFirstChild("RightHand", true)
	return if rightHand and rightHand:IsA("BasePart") then rightHand else nil
end

local function find_tool_handle(tool: Tool): BasePart?
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return tool:FindFirstChildWhichIsA("BasePart", true)
end

local function attach_tool_to_hand(character: Model, tool: Tool): Motor6D?
	local rightHand = find_right_hand(character)
	local handle = find_tool_handle(tool)
	if not rightHand or not handle then
		return nil
	end

	for _, joint in ipairs(rightHand:GetChildren()) do
		if joint:IsA("Motor6D") and joint.Part0 == rightHand and joint.Part1 == handle then
			return nil
		end
	end

	local grip = Instance.new("Motor6D")
	grip.Name = "HorseBrushGrip"
	grip.Part0 = rightHand
	grip.Part1 = handle
	grip.C0 = tool.Grip
	grip.Parent = rightHand

	return grip
end

local function get_root_cframe_at_pivot(character: Model, rootPart: BasePart, pivot: CFrame): CFrame
	return pivot * character:GetPivot():ToObjectSpace(rootPart.CFrame)
end

local function tween_root_to(session, targetCFrame: CFrame): Tween?
	local rootPart = session.rootPart
	if not rootPart or not rootPart.Parent then
		return nil
	end

	if session.positionTween then
		session.positionTween:Cancel()
	end

	local tween = TweenService:Create(
		rootPart,
		TweenInfo.new(PLAYER_POSITION_TWEEN_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)
	session.positionTween = tween
	tween:Play()
	return tween
end

local function restore_character(session): ()
	if session.character and session.character.Parent and session.savedCharacterPivot then
		session.character:PivotTo(session.savedCharacterPivot)
	end

	if session.rootPart and session.rootPart.Parent then
		session.rootPart.Anchored = session.savedRootAnchored == true
	end

	if session.humanoid and session.humanoid.Parent then
		session.humanoid.WalkSpeed = session.savedWalkSpeed
		session.humanoid.JumpPower = session.savedJumpPower
		session.humanoid.JumpHeight = session.savedJumpHeight
		session.humanoid.AutoRotate = session.savedAutoRotate
	end
end

local function update_task_ui(session): ()
	if type(session.updateTask) ~= "function" then
		return
	end

	local elapsedTime = os.clock() - session.startedAt
	local actionDuration = math.max(session.actionDuration, 0.05)
	local progressAlpha = math.clamp(elapsedTime / actionDuration, 0, 1)
	local remainingTime = math.max(0, actionDuration - elapsedTime)

	session.updateTask({
		text = session.taskText,
		progress = progressAlpha,
		timerText = ("%.1fs"):format(remainingTime),
	})
end

local function finish_session(session, shouldRefreshPrompts: boolean): ()
	if activeSession ~= session or session.closed then
		return
	end

	session.closed = true
	activeSession = nil

	disconnect_all(session.connections)
	stop_track(session.playerTrack)
	if session.toolGrip then
		session.toolGrip:Destroy()
		session.toolGrip = nil
	end
	pcall(function()
		session.horseAnimationEvent:Fire(session.tool, session.horseId, false)
	end)
	if session.tweenCharacterPosition and session.savedRootCFrame then
		local returnTween = tween_root_to(session, session.savedRootCFrame)
		if returnTween then
			returnTween.Completed:Wait()
		end
	end
	restore_character(session)

	if type(session.hideTask) == "function" then
		session.hideTask()
	end

	destroy_animation(session.playerAnimation)
	session.playerAnimation = nil

	if type(session.finishInteraction) == "function" then
		session.finishInteraction(shouldRefreshPrompts)
	end
end

local function cancel_session(session, shouldRefreshPrompts: boolean): ()
	if session.finishing or session.closed then
		return
	end

	finish_session(session, shouldRefreshPrompts)
end

local function complete_session(session): ()
	if session.finishing or session.closed then
		return
	end

	session.finishing = true

	if type(session.updateTask) == "function" then
		session.updateTask({
			text = session.taskText,
			progress = 1,
			timerText = "0.0s",
		})
	end

	if session.prompt and session.prompt.Parent then
		session.prompt.Enabled = false
	end

	pcall(function()
		session.invokeServerUse()
	end)

	finish_session(session, true)
end

local function start_session(context): boolean
	if activeSession then
		return false
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid then
		return false
	end

	local playerAnimator = ensure_animator(humanoid)
	if not playerAnimator then
		return false
	end

	local resolvedRootPart = nil
	local savedRootAnchored = false
	if rootPart and rootPart:IsA("BasePart") then
		resolvedRootPart = rootPart
		savedRootAnchored = rootPart.Anchored
	end

	local playerAnimation = Instance.new("Animation")
	playerAnimation.AnimationId = context.playerAnimationId or PLAYER_BRUSH_ANIMATION_ID

	local session = {
		character = character,
		humanoid = humanoid,
		horseVisual = context.horseVisual,
		horseId = context.horseId,
		tool = context.tool,
		prompt = context.prompt,
		invokeServerUse = context.invokeServerUse,
		finishInteraction = context.finishInteraction,
		showTask = context.showTask,
		updateTask = context.updateTask,
		hideTask = context.hideTask,
		taskText = context.taskText or "Brushing your horse...",
		playerAnimation = playerAnimation,
		connections = {},
		finishing = false,
		closed = false,
		startedAt = os.clock(),
		actionDuration = math.max(context.actionDuration or 10, 0.05),
		horseAnimationEvent = context.horseAnimationEvent or Network.Horse.BrushAnimation,
		tweenCharacterPosition = context.tweenCharacterPosition == true,
		rootPart = resolvedRootPart,
		savedCharacterPivot = character:GetPivot(),
		savedRootCFrame = resolvedRootPart and resolvedRootPart.CFrame or nil,
		savedWalkSpeed = humanoid.WalkSpeed,
		savedJumpPower = humanoid.JumpPower,
		savedJumpHeight = humanoid.JumpHeight,
		savedAutoRotate = humanoid.AutoRotate,
		savedRootAnchored = savedRootAnchored,
	}

	session.playerTrack = load_animation_track(playerAnimator, playerAnimation)
	if context.matchPlayerAnimationDuration then
		session.actionDuration = math.max(get_animation_duration(session.playerTrack, session.actionDuration), 0.05)
	end
	session.startedAt = os.clock()
	session.toolGrip = attach_tool_to_hand(character, context.tool)

	activeSession = session

	if type(context.beginInteraction) == "function" then
		context.beginInteraction()
	end
	pcall(function()
		session.horseAnimationEvent:Fire(context.tool, context.horseId, true, session.actionDuration)
	end)

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false

	if session.rootPart then
		session.rootPart.Anchored = true
	end

	local horsePivot = get_instance_pivot(context.horseVisual)
	if session.tweenCharacterPosition and session.rootPart then
		tween_root_to(session, get_root_cframe_at_pivot(character, session.rootPart, horsePivot))
	else
		character:PivotTo(horsePivot)
	end

	play_track(session.playerTrack)

	if type(session.showTask) == "function" then
		session.showTask({
			text = session.taskText,
			progress = 0,
			timerText = ("%.1fs"):format(session.actionDuration),
		})
	end

	update_task_ui(session)

	session.connections[#session.connections + 1] = localPlayer.CharacterRemoving:Connect(function()
		cancel_session(session, false)
	end)

	session.connections[#session.connections + 1] = context.tool.AncestryChanged:Connect(function()
		if not context.tool:IsDescendantOf(localPlayer.Character or game) then
			cancel_session(session, false)
		end
	end)

	session.connections[#session.connections + 1] = context.horseVisual.AncestryChanged:Connect(function()
		if not context.horseVisual:IsDescendantOf(workspace) then
			cancel_session(session, true)
		end
	end)

	session.connections[#session.connections + 1] = RunService.RenderStepped:Connect(function()
		if activeSession ~= session or session.closed then
			return
		end

		update_task_ui(session)

		if (os.clock() - session.startedAt) >= session.actionDuration then
			complete_session(session)
		end
	end)

	return true
end

------------------//MAIN FUNCTIONS
function HorseBrushClient.start(context): boolean
	return start_session(context)
end

------------------//INIT
return HorseBrushClient
