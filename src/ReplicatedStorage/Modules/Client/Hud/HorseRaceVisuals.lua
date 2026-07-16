local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local HorseMountConfig = require(GameData:WaitForChild("HorseMountConfig"))

local HorseRaceVisuals = {}

local VISUAL_BLEND_SECONDS = 1
local VISUAL_CORRECTION_RATE = 10
local VISUAL_HARD_SNAP_GAP = 8
local VISUAL_MIN_SPEED_BLEND = 0.35

local function extract_rotation(cframe)
	return CFrame.fromMatrix(Vector3.zero, cframe.XVector, cframe.YVector, cframe.ZVector)
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
	local controller = model:FindFirstChildWhichIsA("AnimationController", true)
	if controller then
		return ensure_animator(controller)
	end

	local humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	if humanoid then
		return ensure_animator(humanoid)
	end

	controller = Instance.new("AnimationController")
	controller.Name = "HorseRaceAnimationController"
	controller.Parent = model
	return ensure_animator(controller)
end

local function create_run_animation(model)
	local animationId = HorseMountConfig.HorseRunAnimationId
	if type(animationId) ~= "string" or animationId == "" then
		return nil, nil
	end

	local animator = get_model_animator(model)
	if not animator then
		return nil, nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not track then
		animation:Destroy()
		return nil, nil
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	return track, animation
end

local function set_run_animation_playing(visual, shouldPlay)
	local track = visual.RunTrack
	if not track then
		return
	end

	if shouldPlay then
		if not track.IsPlaying then
			track:Play(HorseMountConfig.HorseAnimationBlendTime or 0.12, 1, 1)
		end
		track:AdjustSpeed(1)
	elseif track.IsPlaying then
		track:Stop(HorseMountConfig.HorseAnimationBlendTime or 0.12)
	end
end

local function find_local_entry(state, localPlayer)
	for _, entry in ipairs(state.Entries) do
		if entry.UserId == localPlayer.UserId then
			return entry
		end
	end

	return nil
end

local function get_sorted_race_slots(workspace)
	local raceFolder = workspace:FindFirstChild("Race")
	local positionsFolder = raceFolder and raceFolder:FindFirstChild("Positions")
	if not positionsFolder then
		return nil, nil
	end

	local slots = {}
	for _, child in ipairs(positionsFolder:GetChildren()) do
		if child:IsA("BasePart") then
			slots[#slots + 1] = child
		end
	end

	table.sort(slots, function(a, b)
		local aValue = tonumber(a.Name)
		local bValue = tonumber(b.Name)

		if aValue and bValue then
			return aValue < bValue
		end

		return a.Name < b.Name
	end)

	return raceFolder, slots
end

local function should_render_race_visuals(state, localPlayer)
	if state.LocalJoined or state.LocalWatchingRace then
		return true
	end

	return state.Phase == "Result" and find_local_entry(state, localPlayer) ~= nil
end

local function cancel_visual_tween(tween)
	if tween then
		tween:Cancel()
	end
end

local function destroy_progress_driver(driver)
	if driver then
		driver:Destroy()
	end
end

local function clear_overlay_tween_state(visual)
	visual.BlendToken = (visual.BlendToken or 0) + 1
	cancel_visual_tween(visual.OverlayTween)
	cancel_visual_tween(visual.BlendTween)
	destroy_progress_driver(visual.OverlayProgress)
	destroy_progress_driver(visual.BlendAlpha)
	visual.OverlayTween = nil
	visual.BlendTween = nil
	visual.OverlayProgress = nil
	visual.BlendAlpha = nil
	visual.PendingSegmentIndex = nil
	visual.PendingVisualSpeed = nil
end

local function clear_primary_tween_state(visual)
	cancel_visual_tween(visual.PrimaryTween)
	destroy_progress_driver(visual.PrimaryProgress)
	visual.PrimaryTween = nil
	visual.PrimaryProgress = nil
end

local function create_progress_driver(model, name, value)
	local driver = Instance.new("NumberValue")
	driver.Name = name
	driver.Value = value
	driver.Parent = model
	return driver
end

local function build_visual_pivot(visual, progress)
	local startPosition = visual.StartPivot.Position
	return CFrame.new(
		startPosition.X,
		startPosition.Y,
		startPosition.Z - progress
	) * visual.StartRotation
end

local function get_visual_display_progress(visual)
	return visual.DisplayProgress or visual.ServerProgress or 0
end

local function apply_visual_progress(visual, progress)
	visual.DisplayProgress = progress
	if visual.Model and visual.Model.Parent then
		visual.Model:PivotTo(build_visual_pivot(visual, progress))
	end
end

local function get_visual_target_progress(state, raceConfig, visual, now)
	local distance = visual.Distance or raceConfig.RaceDistance
	local serverProgress = visual.ServerProgress or visual.DisplayProgress or 0

	if state.Phase ~= "Race" then
		return math.clamp(serverProgress, 0, distance)
	end

	local elapsed = math.max(0, now - (visual.ServerUpdatedAt or now))
	local visualSpeed = math.max(0, visual.VisualSpeed or 0)
	return math.clamp(serverProgress + (visualSpeed * elapsed), 0, distance)
end

local function get_finish_tween_duration(progress, distance, speed)
	local remainingDistance = math.max(0, distance - progress)
	local resolvedSpeed = math.max(0.1, speed or 24)
	return math.max(0.05, remainingDistance / resolvedSpeed)
end

local function start_primary_finish_tween(context, visual, progress, distance, speed)
	clear_overlay_tween_state(visual)
	cancel_visual_tween(visual.PrimaryTween)

	if not visual.PrimaryProgress or not visual.PrimaryProgress.Parent then
		visual.PrimaryProgress = create_progress_driver(visual.Model, "PrimaryRaceProgress", progress)
	end

	visual.PrimaryProgress.Value = progress
	visual.PrimaryTween = context.TweenService:Create(
		visual.PrimaryProgress,
		TweenInfo.new(get_finish_tween_duration(progress, distance, speed), Enum.EasingStyle.Linear),
		{ Value = distance }
	)
	visual.PrimaryTween:Play()
	visual.VisualSpeed = speed
end

local function begin_overlay_finish_tween(context, visual, progress, distance, speed, segmentIndex)
	clear_overlay_tween_state(visual)

	visual.OverlayProgress = create_progress_driver(visual.Model, "OverlayRaceProgress", progress)
	visual.BlendAlpha = create_progress_driver(visual.Model, "RaceBlendAlpha", 0)
	visual.OverlayTween = context.TweenService:Create(
		visual.OverlayProgress,
		TweenInfo.new(get_finish_tween_duration(progress, distance, speed), Enum.EasingStyle.Linear),
		{ Value = distance }
	)
	visual.BlendTween = context.TweenService:Create(
		visual.BlendAlpha,
		TweenInfo.new(VISUAL_BLEND_SECONDS, Enum.EasingStyle.Linear),
		{ Value = 1 }
	)
	visual.PendingSegmentIndex = segmentIndex
	visual.PendingVisualSpeed = speed

	local blendToken = (visual.BlendToken or 0) + 1
	visual.BlendToken = blendToken

	visual.OverlayTween:Play()
	visual.BlendTween:Play()

	task.delay(VISUAL_BLEND_SECONDS, function()
		if visual.BlendToken ~= blendToken then
			return
		end

		if context.raceVisuals.ByUserId[visual.UserId] ~= visual or not visual.Model or not visual.Model.Parent then
			return
		end

		local promotedProgress = get_visual_display_progress(visual)
		local promotedDriver = visual.OverlayProgress
		local promotedTween = visual.OverlayTween

		cancel_visual_tween(visual.PrimaryTween)
		destroy_progress_driver(visual.PrimaryProgress)
		cancel_visual_tween(visual.BlendTween)
		destroy_progress_driver(visual.BlendAlpha)

		visual.PrimaryProgress = promotedDriver
		visual.PrimaryTween = promotedTween
		visual.OverlayProgress = nil
		visual.OverlayTween = nil
		visual.BlendAlpha = nil
		visual.BlendTween = nil
		visual.SegmentIndex = visual.PendingSegmentIndex or visual.SegmentIndex
		visual.VisualSpeed = visual.PendingVisualSpeed or visual.VisualSpeed
		visual.PendingSegmentIndex = nil
		visual.PendingVisualSpeed = nil

		if visual.PrimaryProgress then
			visual.PrimaryProgress.Value = promotedProgress
		end
	end)
end

local function create_race_visual(context, entry, raceFolder, slots, folder)
	local slot = slots[entry.SlotIndex or 0]
	if not slot then
		return nil
	end

	local model = context.RaceVisualFactory.CreateRaceModel({
		Id = entry.HorseId,
		HorseId = entry.HorseId,
		CatalogId = entry.CatalogId,
		PlaceholderModelKey = entry.PlaceholderModelKey,
	}, raceFolder, folder)

	local startPivot = context.RaceVisualFactory.GetAlignedSlotPivot(model, slot)
	model:PivotTo(startPivot)
	local runTrack, runAnimation = create_run_animation(model)

	return {
		UserId = entry.UserId,
		Model = model,
		SlotIndex = entry.SlotIndex,
		HorseId = entry.HorseId,
		CatalogId = entry.CatalogId,
		PlaceholderModelKey = entry.PlaceholderModelKey,
		StartPivot = startPivot,
		StartRotation = extract_rotation(startPivot),
		Distance = entry.Distance or context.RaceConfig.RaceDistance,
		ServerProgress = entry.Progress or 0,
		ServerUpdatedAt = os.clock(),
		DisplayProgress = entry.Progress or 0,
		SegmentIndex = entry.SegmentIndex or 0,
		VisualSpeed = entry.VisualSpeed or 24,
		PrimaryProgress = nil,
		PrimaryTween = nil,
		OverlayProgress = nil,
		OverlayTween = nil,
		BlendAlpha = nil,
		BlendTween = nil,
		BlendToken = 0,
		RunTrack = runTrack,
		RunAnimation = runAnimation,
	}
end

local function retarget_race_visual(context, visual, entry)
	local authoritativeProgress = entry.Progress or 0
	local distance = entry.Distance or context.RaceConfig.RaceDistance
	local visualSpeed = math.max(0.1, entry.VisualSpeed or visual.VisualSpeed or 24)
	local segmentIndex = entry.SegmentIndex
	if type(segmentIndex) ~= "number" then
		segmentIndex = math.floor(authoritativeProgress / math.max(1, context.RaceConfig.SegmentLength))
	end

	visual.Distance = distance
	visual.ServerProgress = authoritativeProgress
	visual.ServerUpdatedAt = os.clock()
	visual.SegmentIndex = segmentIndex
	visual.VisualSpeed = visualSpeed

	if context.state.Phase ~= "Race" then
		clear_overlay_tween_state(visual)
		clear_primary_tween_state(visual)
		apply_visual_progress(visual, authoritativeProgress)
		return
	end

	if authoritativeProgress - (visual.DisplayProgress or 0) > VISUAL_HARD_SNAP_GAP then
		apply_visual_progress(visual, authoritativeProgress)
	end
end

function HorseRaceVisuals.updateRaceVisualMotion(context, visual, deltaTime, now)
	local targetProgress = get_visual_target_progress(context.state, context.RaceConfig, visual, now)
	local currentProgress = visual.DisplayProgress or targetProgress

	if context.state.Phase ~= "Race" then
		apply_visual_progress(visual, targetProgress)
		return
	end

	if targetProgress - currentProgress > VISUAL_HARD_SNAP_GAP then
		apply_visual_progress(visual, targetProgress)
		return
	end

	local visualSpeed = math.max(0, visual.VisualSpeed or 0)
	local predictedProgress = currentProgress + (visualSpeed * deltaTime)
	local correctionAlpha = math.clamp(deltaTime * VISUAL_CORRECTION_RATE, 0, 1)
	local correctedProgress = predictedProgress + ((targetProgress - predictedProgress) * correctionAlpha)
	local minimumForwardProgress = currentProgress + (visualSpeed * deltaTime * VISUAL_MIN_SPEED_BLEND)
	local nextProgress = math.max(
		currentProgress,
		correctedProgress,
		math.min(targetProgress, minimumForwardProgress)
	)

	apply_visual_progress(visual, math.min(visual.Distance or context.RaceConfig.RaceDistance, nextProgress))
end

function HorseRaceVisuals.destroyRaceVisual(context, userId)
	local visual = context.raceVisuals.ByUserId[userId]
	if not visual then
		return
	end

	clear_overlay_tween_state(visual)
	clear_primary_tween_state(visual)
	set_run_animation_playing(visual, false)

	if visual.RunAnimation then
		visual.RunAnimation:Destroy()
		visual.RunAnimation = nil
	end

	if visual.Model then
		visual.Model:Destroy()
	end

	context.raceVisuals.ByUserId[userId] = nil
end

function HorseRaceVisuals.clearRaceVisuals(context)
	local userIds = {}
	for userId in pairs(context.raceVisuals.ByUserId) do
		userIds[#userIds + 1] = userId
	end

	for _, userId in ipairs(userIds) do
		HorseRaceVisuals.destroyRaceVisual(context, userId)
	end

	if context.raceVisuals.Folder then
		context.raceVisuals.Folder:Destroy()
		context.raceVisuals.Folder = nil
	end
end

function HorseRaceVisuals.syncRaceVisuals(context)
	if not should_render_race_visuals(context.state, context.localPlayer) or #context.state.Entries == 0 then
		HorseRaceVisuals.clearRaceVisuals(context)
		return
	end

	local raceFolder, slots = get_sorted_race_slots(context.Workspace)
	if not raceFolder or not slots or #slots == 0 then
		HorseRaceVisuals.clearRaceVisuals(context)
		return
	end

	local folder = context.raceVisuals.Folder
	if not folder or folder.Parent ~= raceFolder then
		if folder then
			folder:Destroy()
		end

		folder = Instance.new("Folder")
		folder.Name = ("ClientRaceHorses_%d"):format(context.localPlayer.UserId)
		folder.Parent = raceFolder
		context.raceVisuals.Folder = folder
	end

	local activeUserIds = {}

	for _, entry in ipairs(context.state.Entries) do
		local userId = entry.UserId
		activeUserIds[userId] = true

		local visual = context.raceVisuals.ByUserId[userId]
		local needsRebuild = visual == nil
			or visual.SlotIndex ~= entry.SlotIndex
			or visual.HorseId ~= entry.HorseId
			or visual.CatalogId ~= entry.CatalogId
			or visual.PlaceholderModelKey ~= entry.PlaceholderModelKey
			or not visual.Model
			or visual.Model.Parent ~= folder

		if needsRebuild then
			HorseRaceVisuals.destroyRaceVisual(context, userId)
			visual = create_race_visual(context, entry, raceFolder, slots, folder)
			if visual then
				context.raceVisuals.ByUserId[userId] = visual
			end
		end

		if visual then
			retarget_race_visual(context, visual, entry)
			set_run_animation_playing(visual, context.state.Phase == "Race")

			if context.state.Phase == "Result" and entry.Finished == true then
				local progress = get_visual_display_progress(visual)
				local distance = entry.Distance or context.RaceConfig.RaceDistance
				local speed = math.max(0.1, entry.VisualSpeed or visual.VisualSpeed or 24)
				local segmentIndex = entry.SegmentIndex or visual.SegmentIndex or 0

				if not visual.PrimaryTween and not visual.OverlayTween then
					start_primary_finish_tween(context, visual, progress, distance, speed)
				elseif segmentIndex ~= visual.SegmentIndex then
					begin_overlay_finish_tween(context, visual, progress, distance, speed, segmentIndex)
				end
			end
		end
	end

	local staleUserIds = {}
	for userId in pairs(context.raceVisuals.ByUserId) do
		if not activeUserIds[userId] then
			staleUserIds[#staleUserIds + 1] = userId
		end
	end

	for _, userId in ipairs(staleUserIds) do
		HorseRaceVisuals.destroyRaceVisual(context, userId)
	end
end

return HorseRaceVisuals
