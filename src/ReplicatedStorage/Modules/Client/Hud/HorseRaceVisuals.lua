local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")
local HorseMountConfig = require(GameData:WaitForChild("HorseMountConfig"))
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))

local HorseRaceVisuals = {}

local VISUAL_BLEND_SECONDS = 1
local VISUAL_CORRECTION_RATE = 10
local VISUAL_HARD_SNAP_GAP = 8
local VISUAL_MIN_SPEED_BLEND = 0.35
local RACE_MOVEMENT_SOUND_NAME = "HorseMovement"
local RACE_MOVEMENT_SOUND_ID = "rbxassetid://108771044697744"
local RACE_MOVEMENT_SOUND_VOLUME = 0.7

local function extract_rotation(cframe)
	return CFrame.fromMatrix(Vector3.zero, cframe.XVector, cframe.YVector, cframe.ZVector)
end

local function sanitize_horizontal_direction(direction, fallback)
	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.001 then
		direction = fallback
	end

	if typeof(direction) ~= "Vector3" or direction.Magnitude <= 0.001 then
		return Vector3.new(0, 0, -1)
	end

	local horizontalDirection = Vector3.new(direction.X, 0, direction.Z)
	if horizontalDirection.Magnitude <= 0.001 then
		return direction.Unit
	end

	return horizontalDirection.Unit
end

local function get_track_progress_direction(raceFolder, slots, fallback)
	local positionsFolder = raceFolder and raceFolder:FindFirstChild("Positions")
	local startSlot = positionsFolder and (positionsFolder:FindFirstChild("1") or positionsFolder:FindFirstChild("01"))
	if not startSlot and slots then
		startSlot = slots[1]
	end

	if startSlot and startSlot:IsA("BasePart") then
		return sanitize_horizontal_direction(startSlot.CFrame.ZVector, fallback)
	end

	return sanitize_horizontal_direction(fallback)
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

local function get_visual_base_parts(model)
	local parts = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts[#parts + 1] = descendant
		end
	end

	return parts
end

local function get_hoof_node_position(node)
	if node:IsA("BasePart") then
		return node.Position
	end

	return node.WorldPosition
end

local function get_hoof_node_cframe(node)
	if node:IsA("BasePart") then
		return node.CFrame * CFrame.new(0, -(node.Size.Y * 0.45), 0)
	end

	return node.WorldCFrame
end

local function get_rear_hoof_nodes(horseVisual)
	local pivot = horseVisual:GetPivot()
	local rearDirection = 1
	local boneNodes = {}
	local partNodes = {}

	for _, descendant in ipairs(horseVisual:GetDescendants()) do
		if descendant:IsA("Bone") then
			boneNodes[#boneNodes + 1] = descendant
		end
	end

	for _, part in ipairs(get_visual_base_parts(horseVisual)) do
		partNodes[#partNodes + 1] = part
	end

	local sourceNodes = #boneNodes > 0 and boneNodes or partNodes

	for _, node in ipairs(sourceNodes) do
		if string.find(string.lower(node.Name), "tail", 1, true) then
			local tailPosition = pivot:PointToObjectSpace(get_hoof_node_position(node))
			if math.abs(tailPosition.Z) > 0.01 then
				rearDirection = math.sign(tailPosition.Z)
			end
			break
		end
	end

	local candidates = {}
	for _, node in ipairs(sourceNodes) do
		local nodeName = string.lower(node.Name)
		if not string.find(nodeName, "tail", 1, true)
			and not string.find(nodeName, "mane", 1, true)
			and not string.find(nodeName, "body", 1, true)
			and not string.find(nodeName, "chest", 1, true)
			and not string.find(nodeName, "neck", 1, true)
			and not string.find(nodeName, "head", 1, true)
			and not string.find(nodeName, "root", 1, true)
		then
			local localPosition = pivot:PointToObjectSpace(get_hoof_node_position(node))
			local isRear = string.find(nodeName, "hind", 1, true)
				or string.find(nodeName, "rear", 1, true)
				or string.find(nodeName, "back", 1, true)
				or nodeName == "leg_3"
				or nodeName == "leg_4"
			local isHoof = string.find(nodeName, "hoof", 1, true)
				or string.find(nodeName, "foot", 1, true)
				or string.find(nodeName, "leg", 1, true)
			local nameBonus = (isRear and 1000 or 0) + (isHoof and 500 or 0)
			candidates[#candidates + 1] = {
				Node = node,
				Score = nameBonus + (localPosition.Z * rearDirection * 8) - localPosition.Y,
			}
		end
	end

	table.sort(candidates, function(a, b)
		return a.Score > b.Score
	end)

	local hooves = {}
	for index = 1, math.min(2, #candidates) do
		hooves[#hooves + 1] = candidates[index].Node
	end

	return hooves
end

local function create_horse_run_dust(horseVisual)
	local resources = {}
	local emitters = {}
	local anchors = {}
	local texture = HorseMountConfig.HorseRunDustTexture

	if type(texture) ~= "string" or texture == "" then
		return resources, emitters, anchors
	end

	for _, hoof in ipairs(get_rear_hoof_nodes(horseVisual)) do
		local anchor = Instance.new("Part")
		anchor.Name = "HorseRunDustAnchor"
		anchor.Size = Vector3.new(0.1, 0.1, 0.1)
		anchor.Transparency = 1
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.CanTouch = false
		anchor.CFrame = get_hoof_node_cframe(hoof)
		anchor.Parent = horseVisual

		local attachment = Instance.new("Attachment")
		attachment.Name = "HorseRunDustAttachment"
		attachment.Parent = anchor

		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "HorseRunDust"
		emitter.Texture = texture
		emitter.Enabled = false
		emitter.Rate = HorseMountConfig.HorseRunDustRate or 12
		emitter.Lifetime = NumberRange.new(0.35, 0.65)
		emitter.Speed = NumberRange.new(0.8, 1.7)
		emitter.Drag = 3
		emitter.Acceleration = Vector3.new(0, 3, 0)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.SpreadAngle = Vector2.new(24, 24)
		emitter.LightInfluence = 0
		emitter.Color = ColorSequence.new(Color3.fromRGB(184, 178, 168), Color3.fromRGB(224, 220, 214))
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.45),
			NumberSequenceKeypoint.new(1, 1.35),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = attachment

		resources[#resources + 1] = anchor
		emitters[#emitters + 1] = emitter
		anchors[#anchors + 1] = {
			Part = anchor,
			Hoof = hoof,
		}
	end

	return resources, emitters, anchors
end

local function update_horse_run_dust_anchors(anchors)
	for _, entry in ipairs(anchors or {}) do
		local anchor = entry.Part
		local hoof = entry.Hoof
		if anchor and anchor.Parent and hoof and hoof.Parent then
			anchor.CFrame = get_hoof_node_cframe(hoof)
		end
	end
end

local function set_horse_run_dust_enabled(emitters, enabled)
	for _, emitter in ipairs(emitters or {}) do
		if emitter and emitter.Parent then
			emitter.Enabled = enabled == true
		end
	end
end

local function get_sound_parent(model)
	if not model then
		return nil
	end

	if model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function get_race_movement_sound(visual)
	local soundParent = get_sound_parent(visual.Model)
	if not soundParent then
		return nil
	end

	if visual.MovementSound and visual.MovementSound.Parent == soundParent then
		return visual.MovementSound
	end

	if visual.MovementSound then
		visual.MovementSound:Destroy()
		visual.MovementSound = nil
	end

	local existingSound = soundParent:FindFirstChild(RACE_MOVEMENT_SOUND_NAME)
	if existingSound and existingSound:IsA("Sound") then
		visual.MovementSound = existingSound
		return existingSound
	end

	local sound = Instance.new("Sound")
	sound.Name = RACE_MOVEMENT_SOUND_NAME
	sound.SoundId = RACE_MOVEMENT_SOUND_ID
	sound.Looped = true
	sound.Volume = RACE_MOVEMENT_SOUND_VOLUME
	sound.PlaybackSpeed = 1
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 8
	sound.RollOffMaxDistance = 220
	sound.SoundGroup = SoundUtility.GetSFXSoundGroup()
	sound.Parent = soundParent
	visual.MovementSound = sound
	return sound
end

local function set_race_movement_sound_playing(visual, shouldPlay)
	if not shouldPlay then
		if visual.MovementSound and visual.MovementSound.Parent and visual.MovementSound.IsPlaying then
			visual.MovementSound:Stop()
		end
		return
	end

	local sound = get_race_movement_sound(visual)
	if sound and not sound.IsPlaying then
		sound:Play()
	end
end

local function create_race_tag(model, entry)
	local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not adornee then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RaceTag"
	billboard.Size = UDim2.fromOffset(144, 46)
	billboard.StudsOffset = Vector3.new(0, 9, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 260
	billboard.Adornee = adornee

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundColor3 = Color3.fromRGB(37, 28, 20)
	holder.BackgroundTransparency = 0.08
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(234, 190, 115)
	stroke.Transparency = 0.2
	stroke.Parent = holder

	local portrait = Instance.new("ImageLabel")
	portrait.Name = "PlayerPortrait"
	portrait.BackgroundColor3 = Color3.fromRGB(91, 68, 48)
	portrait.BorderSizePixel = 0
	portrait.Position = UDim2.fromOffset(4, 4)
	portrait.Size = UDim2.fromOffset(38, 38)
	portrait.Parent = holder

	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(1, 0)
	portraitCorner.Parent = portrait

	local playerLabel = Instance.new("TextLabel")
	playerLabel.Name = "ItemNameTX"
	playerLabel.BackgroundTransparency = 1
	playerLabel.Size = UDim2.new(1, -52, 1, 0)
	playerLabel.Position = UDim2.fromOffset(48, 0)
	playerLabel.Font = Enum.Font.GothamBold
	playerLabel.TextSize = 13
	playerLabel.TextColor3 = Color3.fromRGB(255, 244, 226)
	playerLabel.TextTruncate = Enum.TextTruncate.AtEnd
	playerLabel.TextXAlignment = Enum.TextXAlignment.Left
	playerLabel.Text = entry.PlayerName or "Player"
	playerLabel.Parent = holder

	billboard.Parent = adornee

	if type(entry.UserId) == "number" then
		task.spawn(function()
			local success, image = pcall(function()
				return Players:GetUserThumbnailAsync(
					entry.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size100x100
				)
			end)

			if success and type(image) == "string" and billboard.Parent then
				portrait.Image = image
			end
		end)
	end

	return billboard
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
	local position = visual.StartPivot.Position + (visual.ProgressDirection * progress)
	return CFrame.new(position) * visual.ProgressRotation
end

local function get_visual_display_progress(visual)
	return visual.DisplayProgress or visual.ServerProgress or 0
end

local function apply_visual_progress(visual, progress)
	visual.DisplayProgress = progress
	if visual.Model and visual.Model.Parent then
		visual.Model:PivotTo(build_visual_pivot(visual, progress))
		update_horse_run_dust_anchors(visual.DustAnchors)
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
	local startRotation = extract_rotation(startPivot)
	local progressDirection = -get_track_progress_direction(raceFolder, slots, startRotation.LookVector)
	local dustResources, dustEmitters, dustAnchors = create_horse_run_dust(model)
	local raceTag = create_race_tag(model, entry)

	return {
		UserId = entry.UserId,
		Model = model,
		SlotIndex = entry.SlotIndex,
		HorseId = entry.HorseId,
		CatalogId = entry.CatalogId,
		PlaceholderModelKey = entry.PlaceholderModelKey,
		StartPivot = startPivot,
		StartRotation = startRotation,
		ProgressDirection = progressDirection,
		ProgressRotation = CFrame.lookAt(Vector3.zero, progressDirection),
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
		MovementSound = nil,
		DustResources = dustResources,
		DustEmitters = dustEmitters,
		DustAnchors = dustAnchors,
		RaceTag = raceTag,
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
	set_race_movement_sound_playing(visual, false)
	set_horse_run_dust_enabled(visual.DustEmitters, false)

	if visual.MovementSound then
		visual.MovementSound:Destroy()
		visual.MovementSound = nil
	end

	if visual.RaceTag then
		visual.RaceTag:Destroy()
		visual.RaceTag = nil
	end

	for _, resource in ipairs(visual.DustResources or {}) do
		if resource then
			resource:Destroy()
		end
	end

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
			local shouldPlayRaceEffects = context.state.Phase == "Race"
			set_run_animation_playing(visual, shouldPlayRaceEffects)
			set_race_movement_sound_playing(visual, shouldPlayRaceEffects)
			set_horse_run_dust_enabled(visual.DustEmitters, shouldPlayRaceEffects)

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
