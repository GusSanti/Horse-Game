------------------//SERVICES
local Players: Players = game:GetService("Players")
local RunService: RunService = game:GetService("RunService")

------------------//CONSTANTS
local localPlayer: Player = Players.LocalPlayer
local HORSE_BRUSH_ANIMATION_ID = "rbxassetid://294893849"

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

local function get_model_animator(model: Instance?): Animator?
	if not model or not model:IsA("Model") then
		return nil
	end

	local animationController = model:FindFirstChildOfClass("AnimationController")
	if not animationController then
		animationController = model:FindFirstChildWhichIsA("AnimationController", true)
	end

	if animationController then
		return ensure_animator(animationController)
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	end

	if humanoid then
		return ensure_animator(humanoid)
	end

	if not animationController then
		animationController = Instance.new("AnimationController")
		animationController.Name = "HorseBrushAnimationController"
		animationController.Parent = model
	end

	return ensure_animator(animationController)
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

local function get_instance_pivot(instance: Instance): CFrame
	if instance:IsA("Model") or instance:IsA("BasePart") then
		return instance:GetPivot()
	end

	return CFrame.new()
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
	stop_track(session.horseTrack)
	restore_character(session)

	if type(session.hideTask) == "function" then
		session.hideTask()
	end

	if session.animation then
		session.animation:Destroy()
		session.animation = nil
	end

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

	local animation = Instance.new("Animation")
	animation.AnimationId = HORSE_BRUSH_ANIMATION_ID

	local session = {
		character = character,
		humanoid = humanoid,
		horseVisual = context.horseVisual,
		tool = context.tool,
		prompt = context.prompt,
		invokeServerUse = context.invokeServerUse,
		finishInteraction = context.finishInteraction,
		showTask = context.showTask,
		updateTask = context.updateTask,
		hideTask = context.hideTask,
		taskText = context.taskText or "Brushing your horse...",
		animation = animation,
		connections = {},
		finishing = false,
		closed = false,
		startedAt = os.clock(),
		actionDuration = math.max(context.actionDuration or 1.5, 0.05),
		rootPart = resolvedRootPart,
		savedCharacterPivot = character:GetPivot(),
		savedWalkSpeed = humanoid.WalkSpeed,
		savedJumpPower = humanoid.JumpPower,
		savedJumpHeight = humanoid.JumpHeight,
		savedAutoRotate = humanoid.AutoRotate,
		savedRootAnchored = savedRootAnchored,
	}

	session.playerTrack = load_animation_track(playerAnimator, animation)
	session.horseTrack = load_animation_track(get_model_animator(context.horseVisual), animation)

	activeSession = session

	if type(context.beginInteraction) == "function" then
		context.beginInteraction()
	end

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
	humanoid.AutoRotate = false

	character:PivotTo(get_instance_pivot(context.horseVisual))

	if session.rootPart then
		session.rootPart.Anchored = true
	end

	play_track(session.playerTrack)
	play_track(session.horseTrack)

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

function HorseBrushClient.bindPrompt(context): boolean
	local prompt = context.prompt
	if not prompt then
		return false
	end

	local function get_prompt_session()
		if activeSession and activeSession.prompt == prompt then
			return activeSession
		end

		return nil
	end

	prompt.PromptButtonHoldBegan:Connect(function(playerWhoTriggered: Player)
		if playerWhoTriggered ~= localPlayer then
			return
		end

		if activeSession then
			return
		end

		start_session(context)
	end)

	prompt.PromptButtonHoldEnded:Connect(function(playerWhoTriggered: Player)
		if playerWhoTriggered ~= localPlayer then
			return
		end

		local session = get_prompt_session()
		if session then
			cancel_session(session, true)
		end
	end)

	prompt.TriggerEnded:Connect(function(playerWhoTriggered: Player)
		if playerWhoTriggered ~= localPlayer then
			return
		end

		local session = get_prompt_session()
		if session then
			cancel_session(session, true)
		end
	end)

	prompt.Triggered:Connect(function(playerWhoTriggered: Player)
		if playerWhoTriggered ~= localPlayer then
			return
		end

		local session = get_prompt_session()
		if session then
			complete_session(session)
			return
		end

		if not activeSession then
			pcall(function()
				context.invokeServerUse()
			end)
			context.finishInteraction(true)
		end
	end)

	prompt.PromptHidden:Connect(function()
		local session = get_prompt_session()
		if session then
			cancel_session(session, true)
		end
	end)

	return true
end

------------------//INIT
return HorseBrushClient
