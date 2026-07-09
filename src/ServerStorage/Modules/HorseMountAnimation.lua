local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local HorseMountConfig = require(GameData:WaitForChild("HorseMountConfig"))

local HorseMountAnimation = {}

local function normalize_animation_id(animationId)
	if type(animationId) ~= "string" or animationId == "" then
		return nil
	end

	if string.find(animationId, "rbxassetid://", 1, true) == 1 then
		return animationId
	end

	return "rbxassetid://" .. animationId
end

local function destroy_instances(instances)
	for _, instance in ipairs(instances or {}) do
		if instance then
			pcall(function()
				instance:Destroy()
			end)
		end
	end
end

local function ensure_animator(controller)
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

local function get_model_animator(model)
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

	animationController = Instance.new("AnimationController")
	animationController.Name = "HorseMountAnimationController"
	animationController.Parent = model
	return ensure_animator(animationController)
end

local function load_animation_track(animator, animationId, priority, looped)
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
		track.Priority = priority or Enum.AnimationPriority.Action
	end)

	pcall(function()
		track.Looped = looped == true
	end)

	return track, animation
end

local function play_track(track, fadeTime, weight, speed)
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

local function stop_track(track, fadeTime)
	if not track then
		return
	end

	pcall(function()
		track:Stop(fadeTime or HorseMountConfig.AnimationFadeTime or 0.12)
	end)
end

local function adjust_track_weight(track, weight, fadeTime)
	if not track then
		return
	end

	pcall(function()
		track:AdjustWeight(weight or 1, fadeTime or HorseMountConfig.AnimationFadeTime or 0.12)
	end)
end

local function is_mount_moving(mountState)
	if not mountState then
		return false
	end

	local inputMagnitude = math.sqrt((mountState.InputX * mountState.InputX) + (mountState.InputZ * mountState.InputZ))
	return mountState.Sprinting == true or inputMagnitude > (HorseMountConfig.ForwardInputDeadzone or 0.05)
end

local function is_mount_running(mountState)
	return mountState and mountState.Sprinting == true or false
end

local function set_horse_animation_mode(animationState, mode)
	if not animationState or animationState.HorseMode == mode then
		return
	end

	local blendTime = HorseMountConfig.HorseAnimationBlendTime or HorseMountConfig.AnimationFadeTime or 0.12

	if mode == "Walk" then
		if animationState.HorseWalkTrack and not animationState.HorseWalkTrack.IsPlaying then
			play_track(animationState.HorseWalkTrack, blendTime, 1, 1)
		end
		adjust_track_weight(animationState.HorseWalkTrack, 1, blendTime)
		adjust_track_weight(animationState.HorseIdleTrack, 0, blendTime)
		adjust_track_weight(animationState.HorseRunTrack, 0, blendTime)
	elseif mode == "Run" then
		if animationState.HorseRunTrack and not animationState.HorseRunTrack.IsPlaying then
			play_track(animationState.HorseRunTrack, blendTime, 1, 1)
		end
		adjust_track_weight(animationState.HorseRunTrack, 1, blendTime)
		adjust_track_weight(animationState.HorseIdleTrack, 0, blendTime)
		adjust_track_weight(animationState.HorseWalkTrack, 0, blendTime)
	elseif mode == "Idle" then
		if animationState.HorseIdleTrack and not animationState.HorseIdleTrack.IsPlaying then
			play_track(animationState.HorseIdleTrack, blendTime, 1, 1)
		end
		adjust_track_weight(animationState.HorseIdleTrack, 1, blendTime)
		adjust_track_weight(animationState.HorseWalkTrack, 0, blendTime)
		adjust_track_weight(animationState.HorseRunTrack, 0, blendTime)
	else
		stop_track(animationState.HorseIdleTrack)
		stop_track(animationState.HorseWalkTrack)
		stop_track(animationState.HorseRunTrack)
	end

	animationState.HorseMode = mode
end

function HorseMountAnimation.createMountAnimationState(humanoid, horseVisual)
	local animationState = {
		HorseMode = "None",
		LastMovingAt = 0,
		Resources = {},
	}

	local horseAnimator = get_model_animator(horseVisual)

	animationState.HorseIdleTrack, animationState.HorseIdleAnimation = load_animation_track(
		horseAnimator,
		HorseMountConfig.HorseIdleAnimationId,
		Enum.AnimationPriority.Action,
		true
	)
	animationState.HorseWalkTrack, animationState.HorseWalkAnimation = load_animation_track(
		horseAnimator,
		HorseMountConfig.HorseWalkAnimationId,
		Enum.AnimationPriority.Action,
		true
	)
	animationState.HorseRunTrack, animationState.HorseRunAnimation = load_animation_track(
		horseAnimator,
		HorseMountConfig.HorseRunAnimationId,
		Enum.AnimationPriority.Action,
		true
	)

	for _, animation in ipairs({
		animationState.HorseIdleAnimation,
		animationState.HorseWalkAnimation,
		animationState.HorseRunAnimation,
	}) do
		if animation then
			animationState.Resources[#animationState.Resources + 1] = animation
		end
	end

	return animationState
end

function HorseMountAnimation.playHorseIdleAnimation(animationState)
	if not animationState then
		return
	end

	if animationState.HorseIdleTrack and not animationState.HorseIdleTrack.IsPlaying then
		play_track(animationState.HorseIdleTrack, 0.08, 1, 1)
	end

	adjust_track_weight(animationState.HorseIdleTrack, 1, HorseMountConfig.HorseAnimationBlendTime or 0.24)
	adjust_track_weight(animationState.HorseWalkTrack, 0, 0)
	adjust_track_weight(animationState.HorseRunTrack, 0, 0)
	animationState.HorseMode = "Idle"
end

function HorseMountAnimation.destroyMountAnimationState(animationState)
	if not animationState then
		return
	end

	animationState.Destroyed = true
	stop_track(animationState.HorseIdleTrack)
	stop_track(animationState.HorseWalkTrack)
	stop_track(animationState.HorseRunTrack)
	destroy_instances(animationState.Resources)
end

function HorseMountAnimation.updateMountAnimationState(mountState)
	local animationState = mountState and mountState.AnimationState
	if not animationState then
		return
	end

	local moving = is_mount_moving(mountState)
	local now = os.clock()

	if moving then
		animationState.LastMovingAt = now
	end

	local recentlyMoving = moving
	local stopHoldTime = HorseMountConfig.AnimationStopHoldTime or 0.12

	if not recentlyMoving and (animationState.LastMovingAt or 0) > 0 then
		recentlyMoving = (now - animationState.LastMovingAt) <= stopHoldTime
	end

	local mode = "Idle"
	if recentlyMoving then
		mode = is_mount_running(mountState) and "Run" or "Walk"
	end

	set_horse_animation_mode(animationState, mode)
end

function HorseMountAnimation.startMountAnimations(mountState)
	if not mountState then
		return
	end

	local animationState = mountState.AnimationState
	if not animationState then
		animationState = HorseMountAnimation.createMountAnimationState(mountState.Humanoid, mountState.HorseVisual)
		mountState.AnimationState = animationState
	end

	if animationState then
		HorseMountAnimation.playHorseIdleAnimation(animationState)
	end

	HorseMountAnimation.updateMountAnimationState(mountState)
end

function HorseMountAnimation.stopMountAnimations(mountState)
	local animationState = mountState and mountState.AnimationState
	if not animationState then
		return
	end

	HorseMountAnimation.destroyMountAnimationState(animationState)
	mountState.AnimationState = nil
end

return HorseMountAnimation
