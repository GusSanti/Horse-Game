local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local HorseRoamingConfig = require(GameData:WaitForChild("Horse"):WaitForChild("HorseRoamingConfig"))
local HorseMountConfig = require(GameData:WaitForChild("Horse"):WaitForChild("HorseMountConfig"))
local ToolDictionary = require(Dictionary:WaitForChild("ToolDictionary"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseCareService = require(script.Parent:WaitForChild("HorseCareService"))
local HorseMountGeometry = require(script.Parent:WaitForChild("HorseMountGeometry"))
local HorseRoamingHold = require(script.Parent:WaitForChild("HorseRoamingHold"))
local HorseService = require(script.Parent:WaitForChild("HorseService"))

local PLOT_VALUE_NAME = ToolDictionary.PlotValueName
local HORSE_FOLDER_NAME = ToolDictionary.HorseFolderName
local HORSE_ID_ATTRIBUTE = ToolDictionary.HorseIdAttribute
local VISUAL_HORSE_ATTRIBUTE = ToolDictionary.VisualHorseAttribute
local MOUNTED_USER_ID_ATTRIBUTE = ToolDictionary.MountedUserIdAttribute
local ROAMING_ATTRIBUTE = ToolDictionary.RoamingHorseAttribute or HorseRoamingConfig.RoamingAttribute
local FREE_ATTRIBUTE = ToolDictionary.FreeHorseAttribute or HorseRoamingConfig.FreeAttribute
local BEHAVIOR_ATTRIBUTE = ToolDictionary.RoamingBehaviorAttribute or HorseRoamingConfig.BehaviorAttribute
local PLAYER_SPAWN_NAME = "PlayerSpawn"
local HORSE_POSITION_NAME = "HorsePosition"

local HorseRoamingService = {}
local freeStateChanged = Instance.new("BindableEvent")
HorseRoamingService.FreeStateChanged = freeStateChanged.Event

local initialized = false
local random = Random.new()
local activeByVisual = {}
local activeByPlayer = {}
local freeHorseIdsByPlayer = {}
local needsUpdateAccumulator = 0

local function random_range(numberRange: NumberRange): number
	return random:NextNumber(numberRange.Min, numberRange.Max)
end

local function wrap_angle(angle: number): number
	return math.atan2(math.sin(angle), math.cos(angle))
end

local function get_yaw(cframe: CFrame): number
	local lookVector = cframe.LookVector
	return math.atan2(-lookVector.X, -lookVector.Z)
end

local function get_player_plot(player: Player): Instance?
	local plotValue = player:FindFirstChild(PLOT_VALUE_NAME)
	if plotValue and plotValue:IsA("ObjectValue") then
		return plotValue.Value
	end

	return nil
end

local function get_horse_folder(player: Player): Instance?
	local plot = get_player_plot(player)
	return plot and plot:FindFirstChild(HORSE_FOLDER_NAME) or nil
end

local function get_roaming_folder(player: Player): Folder?
	local horseFolder = get_horse_folder(player)
	if not horseFolder then
		return nil
	end

	local folder = horseFolder:FindFirstChild(HorseRoamingConfig.FolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = HorseRoamingConfig.FolderName
	folder.Parent = horseFolder
	return folder
end

local function get_player_spawn(player: Player): BasePart?
	local plot = get_player_plot(player)
	local playerSpawn = plot and plot:FindFirstChild(PLAYER_SPAWN_NAME)
	if playerSpawn and playerSpawn:IsA("BasePart") then
		return playerSpawn
	end

	return nil
end

local function get_spawn_position(player: Player, fallback: Vector3): Vector3
	local playerSpawn = get_player_spawn(player)
	if playerSpawn then
		return playerSpawn.Position
	end

	return fallback
end

local function find_stable_slot(player: Player, horseId: string): Instance?
	local stable = DataUtility.server.get(player, "Stable")
	local horseSlots = type(stable) == "table" and stable.HorseSlots or nil
	local horseFolder = get_horse_folder(player)
	if type(horseSlots) ~= "table" or not horseFolder then
		return nil
	end

	for slotName, assignedHorseId in horseSlots do
		if assignedHorseId == horseId then
			return horseFolder:FindFirstChild(slotName)
		end
	end

	return nil
end

local function get_free_horse_ids(player: Player, createIfMissing: boolean): {[string]: boolean}?
	local horseIds = freeHorseIdsByPlayer[player]
	if not horseIds and createIfMissing then
		horseIds = {}
		freeHorseIdsByPlayer[player] = horseIds
	end

	return horseIds
end

local function set_free_state(player: Player, horseId: string, isFree: boolean): ()
	local horseIds = get_free_horse_ids(player, isFree)
	if not horseIds then
		return
	end
	local wasFree = horseIds[horseId] == true

	if isFree then
		horseIds[horseId] = true
	else
		horseIds[horseId] = nil
		if not next(horseIds) then
			freeHorseIdsByPlayer[player] = nil
		end
	end

	if wasFree ~= isFree then
		freeStateChanged:Fire(player, horseId, isFree)
	end
end

local function is_visual_mounted(visual: Instance?): boolean
	return visual ~= nil and (tonumber(visual:GetAttribute(MOUNTED_USER_ID_ATTRIBUTE)) or 0) > 0
end

local function find_live_horse_visual(player: Player, horseId: string): Instance?
	local playerStates = activeByPlayer[player]
	local activeState = playerStates and playerStates[horseId]
	if activeState and activeState.Visual and activeState.Visual.Parent then
		return activeState.Visual
	end

	local horseFolder = get_horse_folder(player)
	if not horseFolder then
		return nil
	end

	local fallback
	for _, descendant in horseFolder:GetDescendants() do
		if descendant:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true
			and descendant:GetAttribute(HORSE_ID_ATTRIBUTE) == horseId
		then
			if is_visual_mounted(descendant) then
				return descendant
			end

			fallback = fallback or descendant
		end
	end

	return fallback
end

local function is_active(state): boolean
	return state.Active == true
		and activeByVisual[state.Visual] == state
		and state.Player.Parent == Players
		and state.Visual.Parent ~= nil
end

local function set_behavior(state, behavior: string?): ()
	if state.Visual and state.Visual.Parent then
		state.Visual:SetAttribute(BEHAVIOR_ATTRIBUTE, behavior)
	end
end

local function unregister_state(state): ()
	if activeByVisual[state.Visual] == state then
		activeByVisual[state.Visual] = nil
	end

	local playerStates = activeByPlayer[state.Player]
	if playerStates and playerStates[state.HorseId] == state then
		playerStates[state.HorseId] = nil
		if not next(playerStates) then
			activeByPlayer[state.Player] = nil
		end
	end
end

local function stop_state(state, preserveVisualState: boolean?): ()
	if not state then
		return
	end

	state.Active = false
	HorseRoamingHold.Clear(state)
	unregister_state(state)

	local visual = state.Visual
	if visual and visual.Parent and preserveVisualState ~= true then
		visual:SetAttribute(ROAMING_ATTRIBUTE, nil)
		visual:SetAttribute(BEHAVIOR_ATTRIBUTE, nil)
	end
end

local function wait_while_active(state, duration: number): boolean
	local remainingTime = math.max(0, duration)
	while is_active(state) and remainingTime > 0 do
		local deltaTime = RunService.Heartbeat:Wait()
		if not HorseRoamingHold.IsHeld(state) then
			remainingTime -= deltaTime
		end
	end

	return is_active(state)
end

local function wait_while_held(state): number
	if not HorseRoamingHold.IsHeld(state) then
		return 0
	end

	local startedAt = os.clock()
	set_behavior(state, "Idle")

	while is_active(state) and HorseRoamingHold.IsHeld(state) do
		RunService.Heartbeat:Wait()
	end

	return os.clock() - startedAt
end

local function anchor_visual(visual: Instance): ()
	local baseParts = if visual:IsA("BasePart") then { visual } else visual:GetDescendants()
	for _, instance in baseParts do
		if instance:IsA("BasePart") then
			instance.AssemblyLinearVelocity = Vector3.zero
			instance.AssemblyAngularVelocity = Vector3.zero
			instance.Anchored = true
		end
	end
end

local function move_visual_to_stable(player: Player, horseId: string, visual: Instance): boolean
	local slotFolder = find_stable_slot(player, horseId)
	if not slotFolder then
		if visual.Parent then
			visual:Destroy()
		end
		return false
	end

	for _, child in slotFolder:GetChildren() do
		if child ~= visual and child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end

	visual.Parent = slotFolder
	visual:SetAttribute(MOUNTED_USER_ID_ATTRIBUTE, nil)
	visual:SetAttribute(ROAMING_ATTRIBUTE, nil)
	visual:SetAttribute(FREE_ATTRIBUTE, nil)
	visual:SetAttribute(BEHAVIOR_ATTRIBUTE, nil)
	anchor_visual(visual)

	local horsePosition = slotFolder:FindFirstChild(HORSE_POSITION_NAME)
	if horsePosition and horsePosition:IsA("BasePart") then
		HorseService.PositionVisualHorseInStable(visual, horsePosition)
	end

	return true
end

local function clamp_to_roaming_range(state, position: Vector3): Vector3
	local offset = Vector3.new(
		position.X - state.AnchorPosition.X,
		0,
		position.Z - state.AnchorPosition.Z
	)
	local maxDistance = HorseRoamingConfig.MaxDistanceFromPlayerSpawn
	if offset.Magnitude <= maxDistance then
		return position
	end

	local clampedOffset = offset.Unit * maxDistance
	return Vector3.new(
		state.AnchorPosition.X + clampedOffset.X,
		position.Y,
		state.AnchorPosition.Z + clampedOffset.Z
	)
end

local function resolve_ground_position(state, position: Vector3): Vector3
	return HorseMountGeometry.resolveGroundPosition(
		position,
		{ state.Visual },
		state.GroundOffset
	)
end

local function constrain_movement_step(state, currentPosition: Vector3, nextPosition: Vector3): Vector3
	local maxDistance = HorseRoamingConfig.MaxDistanceFromPlayerSpawn
	local currentOffset = Vector3.new(
		currentPosition.X - state.AnchorPosition.X,
		0,
		currentPosition.Z - state.AnchorPosition.Z
	)
	local nextOffset = Vector3.new(
		nextPosition.X - state.AnchorPosition.X,
		0,
		nextPosition.Z - state.AnchorPosition.Z
	)

	-- A horse released outside the plot radius is allowed to walk back normally;
	-- clamping that first step would look exactly like the teleport we are avoiding.
	if currentOffset.Magnitude > maxDistance and nextOffset.Magnitude < currentOffset.Magnitude then
		return nextPosition
	end

	return clamp_to_roaming_range(state, nextPosition)
end

local function pivot_visual(state, position: Vector3, yaw: number): ()
	if not is_active(state) then
		return
	end

	state.Visual:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0))
end

local function turn_to(state, targetYaw: number): boolean
	set_behavior(state, "Looking")
	local currentPivot = state.Visual:GetPivot()
	local currentYaw = get_yaw(currentPivot)
	local maxTurnSpeed = math.rad(HorseRoamingConfig.TurnSpeedDegrees)

	while is_active(state) do
		if wait_while_held(state) > 0 then
			set_behavior(state, "Looking")
		end

		local angleDelta = wrap_angle(targetYaw - currentYaw)
		if math.abs(angleDelta) <= math.rad(1) then
			break
		end

		local deltaTime = RunService.Heartbeat:Wait()
		currentYaw += math.clamp(angleDelta, -maxTurnSpeed * deltaTime, maxTurnSpeed * deltaTime)
		pivot_visual(state, state.Visual:GetPivot().Position, currentYaw)
	end

	return is_active(state)
end

local function move_to_point(state, targetPosition: Vector3): boolean
	set_behavior(state, "Walking")
	local arrivalDistance = HorseRoamingConfig.ArrivalDistance
	local walkSpeed = HorseRoamingConfig.WalkSpeed
	local maxTurnSpeed = math.rad(HorseRoamingConfig.TurnSpeedDegrees)
	local currentYaw = get_yaw(state.Visual:GetPivot())

	while is_active(state) do
		local heldDuration = wait_while_held(state)
		if heldDuration > 0 then
			if state.MovementDeadline then
				state.MovementDeadline += heldDuration
			end

			set_behavior(state, "Walking")
		end

		if state.MovementDeadline and os.clock() >= state.MovementDeadline then
			return false
		end

		local currentPosition = state.Visual:GetPivot().Position
		local flatOffset = Vector3.new(
			targetPosition.X - currentPosition.X,
			0,
			targetPosition.Z - currentPosition.Z
		)
		local distance = flatOffset.Magnitude
		if distance <= arrivalDistance then
			return true
		end

		local deltaTime = RunService.Heartbeat:Wait()
		local direction = flatOffset.Unit
		local targetYaw = math.atan2(-direction.X, -direction.Z)
		local angleDelta = wrap_angle(targetYaw - currentYaw)
		currentYaw += math.clamp(angleDelta, -maxTurnSpeed * deltaTime, maxTurnSpeed * deltaTime)

		local stepDistance = math.min(walkSpeed * deltaTime, distance)
		local nextPosition = currentPosition + (direction * stepDistance)
		nextPosition = constrain_movement_step(state, currentPosition, nextPosition)
		nextPosition = resolve_ground_position(state, nextPosition)
		pivot_visual(state, nextPosition, currentYaw)
	end

	return false
end

local function get_path_points(state, targetPosition: Vector3): {Vector3}
	local points = {}
	local path = PathfindingService:CreatePath({
		AgentRadius = HorseRoamingConfig.PathAgentRadius,
		AgentHeight = HorseRoamingConfig.PathAgentHeight,
		AgentCanJump = false,
		WaypointSpacing = HorseRoamingConfig.PathWaypointSpacing,
	})

	local success = pcall(function()
		path:ComputeAsync(state.Visual:GetPivot().Position, targetPosition)
	end)

	if success and path.Status == Enum.PathStatus.Success then
		for waypointIndex, waypoint in path:GetWaypoints() do
			if waypointIndex > 1 then
				points[#points + 1] = clamp_to_roaming_range(state, waypoint.Position)
			end
		end
	end

	if #points == 0 then
		points[1] = targetPosition
	end

	return points
end

local function walk_to_position(state, targetPosition: Vector3): boolean
	for _, pathPoint in get_path_points(state, targetPosition) do
		if not move_to_point(state, pathPoint) then
			return false
		end
	end

	return is_active(state)
end

local function face_position(state, targetPosition: Vector3): boolean
	local currentPosition = state.Visual:GetPivot().Position
	local flatOffset = Vector3.new(
		targetPosition.X - currentPosition.X,
		0,
		targetPosition.Z - currentPosition.Z
	)
	if flatOffset.Magnitude <= 0.05 then
		return is_active(state)
	end

	return turn_to(state, math.atan2(-flatOffset.X, -flatOffset.Z))
end

local function perform_repeated_behavior(state, behavior: string, options): boolean
	local repeatCount = math.max(1, math.floor(tonumber(options.RepeatCount) or 1))
	local repeatDuration = tonumber(options.RepeatDuration)
	if repeatDuration and repeatDuration > 0 then
		for repeatIndex = 1, repeatCount do
			if repeatIndex > 1 then
				set_behavior(state, "Idle")
				if not wait_while_active(state, 0.05) then
					return false
				end
			end

			set_behavior(state, behavior)
			if not wait_while_active(state, repeatDuration) then
				return false
			end
		end

		return is_active(state)
	end

	set_behavior(state, behavior)
	return wait_while_active(state, math.max(tonumber(options.Duration) or 0, 0))
end

local function choose_wander_target(state): Vector3
	local currentPosition = state.Visual:GetPivot().Position
	local fromAnchor = Vector3.new(
		currentPosition.X - state.AnchorPosition.X,
		0,
		currentPosition.Z - state.AnchorPosition.Z
	)
	local maxDistance = HorseRoamingConfig.MaxDistanceFromPlayerSpawn
	local targetPosition

	if fromAnchor.Magnitude > maxDistance then
		local returnOffset = fromAnchor.Unit * (maxDistance * 0.65)
		targetPosition = state.AnchorPosition + returnOffset
	else
		local angle = random:NextNumber(0, math.pi * 2)
		local distance = random:NextNumber(
			HorseRoamingConfig.MinWanderDistance,
			HorseRoamingConfig.MaxWanderDistance
		)
		targetPosition = currentPosition + Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
	end

	return resolve_ground_position(state, clamp_to_roaming_range(state, targetPosition))
end

local function walk_somewhere(state): boolean
	local targetPosition = choose_wander_target(state)
	local currentPosition = state.Visual:GetPivot().Position
	local distanceFromAnchor = Vector3.new(
		currentPosition.X - state.AnchorPosition.X,
		0,
		currentPosition.Z - state.AnchorPosition.Z
	).Magnitude
	if distanceFromAnchor > HorseRoamingConfig.MaxDistanceFromPlayerSpawn then
		return move_to_point(state, targetPosition)
	end

	return walk_to_position(state, targetPosition)
end

local function idle(state): boolean
	set_behavior(state, "Idle")
	return wait_while_active(state, random_range(HorseRoamingConfig.IdleDuration))
end

local function look_around(state): boolean
	local startingYaw = get_yaw(state.Visual:GetPivot())
	local angle = math.rad(random_range(HorseRoamingConfig.LookAngleDegrees))
	local firstDirection = if random:NextInteger(0, 1) == 0 then -1 else 1

	if not turn_to(state, startingYaw + (angle * firstDirection)) then
		return false
	end
	if not wait_while_active(state, random_range(HorseRoamingConfig.LookPauseDuration)) then
		return false
	end
	if not turn_to(state, startingYaw - (angle * firstDirection * 0.65)) then
		return false
	end
	if not wait_while_active(state, random_range(HorseRoamingConfig.LookPauseDuration)) then
		return false
	end

	return turn_to(state, startingYaw)
end

local function graze(state): boolean
	set_behavior(state, "Eating")
	local duration = random_range(HorseRoamingConfig.GrazeDuration)
	if not wait_while_active(state, duration * 0.5) then
		return false
	end

	state.PendingHungerGain += HorseRoamingConfig.HungerPerGraze
	if not wait_while_active(state, duration * 0.5) then
		return false
	end

	state.NextGrazeAt = os.clock() + random_range(HorseRoamingConfig.GrazeInterval)
	return true
end

local function run_behavior(state): ()
	if state.WalkToPlayerSpawnFirst == true then
		local spawnTarget = resolve_ground_position(state, state.AnchorPosition)
		walk_to_position(state, spawnTarget)
		state.MovementDeadline = nil
		if not is_active(state) then
			return
		end

		state.Visual:SetAttribute(FREE_ATTRIBUTE, HorseRoamingService.IsHorseFree(state.Player, state.HorseId))
	end

	-- After the optional exit walk, normal roaming always begins with another
	-- visible walk rather than waiting at PlayerSpawn.
	while is_active(state) do
		wait_while_held(state)

		if not walk_somewhere(state) or not idle(state) then
			break
		end

		if os.clock() >= state.NextGrazeAt then
			if not graze(state) then
				break
			end
		elseif random:NextNumber() <= 0.6 then
			if not look_around(state) then
				break
			end
		else
			if not idle(state) then
				break
			end
		end
	end

	if state.Active then
		stop_state(state)
	end
end

local function apply_passive_needs(state, horses, elapsedSeconds: number): boolean
	local horse = horses and horses.Owned and horses.Owned[state.HorseId]
	if not horse then
		return false
	end

	local changed = HorseCareService.RefreshHorse(horse, os.time())
	local needs = horse.Needs
	local values = needs and needs.Values
	local maxValues = needs and needs.Max
	if not values or not maxValues then
		return changed
	end

	local happinessBefore = tonumber(values.Happiness) or 0
	values.Happiness = math.clamp(
		happinessBefore + (HorseRoamingConfig.HappinessPerSecond * elapsedSeconds),
		0,
		tonumber(maxValues.Happiness) or 100
	)
	changed = changed or values.Happiness ~= happinessBefore

	local pendingHungerGain = state.PendingHungerGain
	if pendingHungerGain > 0 then
		state.PendingHungerGain = 0
		local hungerBefore = tonumber(values.Hunger) or 0
		values.Hunger = math.clamp(
			hungerBefore + pendingHungerGain,
			0,
			tonumber(maxValues.Hunger) or 100
		)
		changed = changed or values.Hunger ~= hungerBefore
	end

	return changed
end

local function update_player_needs(player: Player, playerStates): ()
	local horses = DataUtility.server.get(player, "Horses")
	if not horses or type(horses.Owned) ~= "table" then
		return
	end

	local now = os.clock()
	local changed = false
	for _, state in playerStates do
		if is_active(state) then
			local elapsedSeconds = math.max(0, now - state.LastNeedsUpdateAt)
			state.LastNeedsUpdateAt = now
			changed = apply_passive_needs(state, horses, elapsedSeconds) or changed
		end
	end

	if changed then
		-- Send one consolidated update per player, even when several owned horses
		-- are roaming at the same time.
		DataUtility.server.set(player, "Horses.Owned", horses.Owned)
	end
end

local function begin_movement_state(player: Player, horseId: string, visual: Instance, options)
	local roamingFolder = get_roaming_folder(player)
	if not roamingFolder then
		return nil, "HorseFolderMissing"
	end

	local currentState = activeByVisual[visual]
	if currentState then
		stop_state(currentState)
	end

	local playerStates = activeByPlayer[player]
	if not playerStates then
		playerStates = {}
		activeByPlayer[player] = playerStates
	end

	local previousState = playerStates[horseId]
	if previousState and previousState.Visual ~= visual then
		stop_state(previousState)
		if previousState.Visual and previousState.Visual.Parent then
			previousState.Visual:Destroy()
		end
	end

	local freeHorseIds = get_free_horse_ids(player, false)
	local isFree = freeHorseIds ~= nil and freeHorseIds[horseId] == true
	local initialFreeAttribute = if options and options.InitialFreeAttribute ~= nil
		then options.InitialFreeAttribute == true
		else isFree

	visual.Parent = roamingFolder
	visual:SetAttribute(VISUAL_HORSE_ATTRIBUTE, true)
	visual:SetAttribute(HORSE_ID_ATTRIBUTE, horseId)
	visual:SetAttribute(MOUNTED_USER_ID_ATTRIBUTE, nil)
	visual:SetAttribute(ROAMING_ATTRIBUTE, true)
	visual:SetAttribute(FREE_ATTRIBUTE, initialFreeAttribute)
	anchor_visual(visual)

	local pivot = visual:GetPivot()
	local state = {
		Active = true,
		Player = player,
		HorseId = horseId,
		Visual = visual,
		AnchorPosition = get_spawn_position(player, pivot.Position),
		GroundOffset = HorseMountGeometry.getGroundOffset(visual),
		PendingHungerGain = 0,
		NextGrazeAt = os.clock() + random_range(HorseRoamingConfig.GrazeInterval),
		LastNeedsUpdateAt = os.clock(),
		WalkToPlayerSpawnFirst = options and options.WalkToPlayerSpawnFirst == true,
		MovementDeadline = options and options.MovementDeadline or nil,
	}

	activeByVisual[visual] = state
	playerStates[horseId] = state
	set_behavior(state, "Walking")
	return state, "Ready"
end

local function get_visual_bounds(visual: Instance): (CFrame, Vector3)
	if visual:IsA("BasePart") then
		return visual.CFrame, visual.Size
	elseif visual:IsA("Model") then
		local succeeded, boundsCFrame, boundsSize = pcall(function()
			return visual:GetBoundingBox()
		end)
		if succeeded then
			return boundsCFrame, boundsSize
		end
	end

	return visual:GetPivot(), Vector3.new(4, 6, 7)
end

local function has_clear_mount_overhead(state, candidatePosition: Vector3, character: Model?): boolean
	local boundsCFrame, boundsSize = get_visual_bounds(state.Visual)
	local pivotPosition = state.Visual:GetPivot().Position
	local topOffset = math.max((boundsCFrame.Position.Y + boundsSize.Y * 0.5) - pivotPosition.Y, 1)
	local clearance = math.max(HorseMountConfig.MountPreparationOverheadClearance or 7, 1)
	local halfX = math.max(boundsSize.X * 0.3, 1)
	local halfZ = math.max(boundsSize.Z * 0.3, 1.5)
	local rayOriginY = candidatePosition.Y + topOffset + 0.1
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignoredInstances = { state.Visual }
	if character then
		ignoredInstances[#ignoredInstances + 1] = character
	end
	raycastParams.FilterDescendantsInstances = ignoredInstances
	raycastParams.IgnoreWater = false

	for _, offset in {
		Vector3.zero,
		Vector3.new(halfX, 0, halfZ),
		Vector3.new(halfX, 0, -halfZ),
		Vector3.new(-halfX, 0, halfZ),
		Vector3.new(-halfX, 0, -halfZ),
	} do
		local origin = Vector3.new(
			candidatePosition.X + offset.X,
			rayOriginY,
			candidatePosition.Z + offset.Z
		)
		if Workspace:Raycast(origin, Vector3.new(0, clearance, 0), raycastParams) then
			return false
		end
	end

	return true
end

local function find_clear_mount_target(state, character: Model?): Vector3?
	local playerSpawn = get_player_spawn(state.Player)
	if not playerSpawn then
		return nil
	end

	local maxRadius = math.max(HorseMountConfig.MountPreparationSearchRadius or 18, 0)
	local ringStep = math.max(HorseMountConfig.MountPreparationRingStep or 4, 1)
	local angleSteps = math.max(math.floor(HorseMountConfig.MountPreparationAngleSteps or 10), 4)
	local ignoredInstances = { state.Visual }
	if character then
		ignoredInstances[#ignoredInstances + 1] = character
	end

	local radius = 0
	while radius <= maxRadius do
		local candidatesOnRing = if radius == 0 then 1 else angleSteps
		for candidateIndex = 1, candidatesOnRing do
			local angle = if radius == 0
				then 0
				else ((candidateIndex - 1) / candidatesOnRing) * math.pi * 2
			local localOffset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			local worldOffset = playerSpawn.CFrame:VectorToWorldSpace(localOffset)
			local desiredPosition = playerSpawn.Position + worldOffset
			local groundedPosition = HorseMountGeometry.resolveGroundPosition(
				desiredPosition,
				ignoredInstances,
				state.GroundOffset
			)
			if has_clear_mount_overhead(state, groundedPosition, character) then
				return groundedPosition
			end
		end

		radius += ringStep
	end

	return nil
end

function HorseRoamingService.IsRoaming(visual: Instance?): boolean
	return visual ~= nil and activeByVisual[visual] ~= nil
end

function HorseRoamingService.IsHorseFree(player: Player, horseId: string): boolean
	local horseIds = get_free_horse_ids(player, false)
	return horseIds ~= nil and horseIds[horseId] == true
end

function HorseRoamingService.GetLiveVisual(player: Player, horseId: string): Instance?
	if player.Parent ~= Players or type(horseId) ~= "string" or horseId == "" then
		return nil
	end

	return find_live_horse_visual(player, horseId)
end

function HorseRoamingService.TakeControl(visual: Instance?, preserveVisualState: boolean?): boolean
	local state = visual and activeByVisual[visual] or nil
	if not state then
		return false
	end

	-- During mounting, keeping the last roaming pose until MountedUserId replicates
	-- prevents the client idle controller from restarting a track in the middle of
	-- the hop-on transition. The AI is still unregistered immediately.
	stop_state(state, preserveVisualState)
	return true
end

function HorseRoamingService.SetInteractionHold(player: Player, horseId: string, active: boolean): boolean
	if type(horseId) ~= "string" or horseId == "" then
		return false
	end

	local playerStates = activeByPlayer[player]
	local state = playerStates and playerStates[horseId] or nil
	if not state then
		return false
	end

	HorseRoamingHold.Set(state, active)

	if active then
		set_behavior(state, "Idle")
	end

	return true
end

function HorseRoamingService.ReleaseInteractionHolds(player: Player): ()
	local playerStates = activeByPlayer[player]
	if not playerStates then
		return
	end

	for _, state in playerStates do
		HorseRoamingHold.Set(state, false)
	end
end

function HorseRoamingService.Release(player: Player, horseId: string, visual: Instance, options): (boolean, string)
	if player.Parent ~= Players or type(horseId) ~= "string" or horseId == "" or not visual or not visual.Parent then
		return false, "HorseUnavailable"
	end

	local movementOptions = options or {}
	if movementOptions.WalkToPlayerSpawnFirst == true then
		movementOptions.InitialFreeAttribute = false
	end

	local state, stateReason = begin_movement_state(player, horseId, visual, movementOptions)
	if not state then
		return false, stateReason
	end

	local pivot = visual:GetPivot()

	if options and options.ClampIfTooFar == true then
		local currentPosition = visual:GetPivot().Position
		local flatOffset = Vector3.new(
			currentPosition.X - state.AnchorPosition.X,
			0,
			currentPosition.Z - state.AnchorPosition.Z
		)
		if flatOffset.Magnitude > HorseRoamingConfig.MaxDistanceFromPlayerSpawn then
			local maxRadius = math.min(
				HorseRoamingConfig.FarReleaseTeleportMaxRadius,
				HorseRoamingConfig.MaxDistanceFromPlayerSpawn
			)
			local minRadius = math.min(HorseRoamingConfig.FarReleaseTeleportMinRadius, maxRadius)
			local angle = random:NextNumber(0, math.pi * 2)
			local radius = random:NextNumber(minRadius, maxRadius)
			local targetPosition = state.AnchorPosition + Vector3.new(
				math.cos(angle) * radius,
				currentPosition.Y - state.AnchorPosition.Y,
				math.sin(angle) * radius
			)
			targetPosition = resolve_ground_position(state, targetPosition)
			visual:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, get_yaw(pivot), 0))
		end
	end

	task.spawn(run_behavior, state)
	return true, "Released"
end

function HorseRoamingService.ReleaseOnDismount(player: Player, horseId: string, visual: Instance): (boolean, string)
	if player.Parent ~= Players or type(horseId) ~= "string" or horseId == "" or not visual or not visual.Parent then
		return false, "HorseUnavailable"
	end

	local playerSpawn = get_player_spawn(player)
	if not playerSpawn then
		return false, "PlayerSpawnMissing"
	end

	local currentPosition = visual:GetPivot().Position
	local offsetFromSpawn = Vector3.new(
		currentPosition.X - playerSpawn.Position.X,
		0,
		currentPosition.Z - playerSpawn.Position.Z
	)
	local isWithinRoamingRange = offsetFromSpawn.Magnitude <= HorseRoamingConfig.MaxDistanceFromPlayerSpawn
	local wasFree = HorseRoamingService.IsHorseFree(player, horseId)

	-- Dismounting inside the plot roaming radius leaves the horse where it is.
	-- A horse that was not already free becomes free before its roaming state starts.
	if not wasFree and not isWithinRoamingRange then
		return false, "OutsideRoamingRange"
	end

	if not wasFree then
		set_free_state(player, horseId, true)
		visual:SetAttribute(FREE_ATTRIBUTE, true)
	end

	local released, releaseReason = HorseRoamingService.Release(player, horseId, visual, {
		ClampIfTooFar = not isWithinRoamingRange,
	})
	if not released and not wasFree then
		set_free_state(player, horseId, false)
		visual:SetAttribute(FREE_ATTRIBUTE, nil)
	end

	return released, releaseReason
end

function HorseRoamingService.PrepareForMount(
	player: Player,
	horseId: string,
	visual: Instance,
	character: Model?
): (boolean, string, boolean)
	if player.Parent ~= Players or type(horseId) ~= "string" or horseId == "" or not visual or not visual.Parent then
		return false, "HorseUnavailable", false
	end

	local wasRoaming = HorseRoamingService.IsRoaming(visual)
	local state, stateReason = begin_movement_state(player, horseId, visual, {
		MovementDeadline = os.clock() + math.max(HorseMountConfig.MountPreparationTimeoutSeconds or 24, 1),
	})
	if not state then
		return false, stateReason, wasRoaming
	end

	while is_active(state) do
		local targetPosition = find_clear_mount_target(state, character)
		if not targetPosition then
			stop_state(state)
			return false, "MountAreaBlocked", wasRoaming
		end

		local reachedTarget = walk_to_position(state, targetPosition)
		if not reachedTarget then
			local wasCancelled = not is_active(state)
			if state.Active then
				stop_state(state)
			end
			local failureCode = if wasCancelled then "MountApproachCancelled" else "MountApproachTimedOut"
			return false, failureCode, wasRoaming
		end

		-- Check again after arriving because doors, other horses, or moving props may
		-- have changed the clearance while this horse was walking toward the point.
		if has_clear_mount_overhead(state, targetPosition, character) then
			break
		end

		RunService.Heartbeat:Wait()
	end

	state.MovementDeadline = nil
	if not is_active(state) then
		return false, "MountApproachCancelled", wasRoaming
	end

	set_behavior(state, "Idle")
	stop_state(state, true)
	return true, "MountAreaReady", wasRoaming
end

function HorseRoamingService.PerformStableAction(
	player: Player,
	horseId: string,
	visual: Instance,
	options
): (boolean, string)
	if player.Parent ~= Players or type(horseId) ~= "string" or horseId == "" or not visual or not visual.Parent then
		return false, "HorseUnavailable"
	end
	if is_visual_mounted(visual) then
		return false, "HorseMounted"
	end
	if not HorseRoamingService.IsHorseFree(player, horseId) then
		return false, "HorseNotFree"
	end

	local actionOptions = options or {}
	local targetPosition = actionOptions.TargetPosition
	if typeof(targetPosition) ~= "Vector3" then
		return false, "TargetMissing"
	end

	local wasFree = HorseRoamingService.IsHorseFree(player, horseId)
	local state, stateReason = begin_movement_state(player, horseId, visual, {
		InitialFreeAttribute = wasFree,
		MovementDeadline = os.clock() + math.max(tonumber(actionOptions.MoveTimeout) or 24, 1),
	})
	if not state then
		return false, stateReason
	end

	local actionSucceeded = false
	local reason = "TargetUnreachable"
	local groundedTarget = resolve_ground_position(state, clamp_to_roaming_range(state, targetPosition))
	if walk_to_position(state, groundedTarget) then
		local faceTarget = actionOptions.FacePosition
		if typeof(faceTarget) == "Vector3" then
			face_position(state, faceTarget)
		end

		if is_active(state) then
			local behavior = if type(actionOptions.Behavior) == "string" and actionOptions.Behavior ~= ""
				then actionOptions.Behavior
				else "Idle"
			actionSucceeded = perform_repeated_behavior(state, behavior, actionOptions)
			reason = if actionSucceeded then "Completed" else "ActionCancelled"
		else
			reason = "ActionCancelled"
		end
	elseif not is_active(state) then
		reason = "ActionCancelled"
	end

	if state.Active then
		stop_state(state, true)
	end

	if visual.Parent and not is_visual_mounted(visual) then
		if wasFree and actionOptions.ReturnToStable ~= true then
			HorseRoamingService.Release(player, horseId, visual, {
				InitialFreeAttribute = true,
			})
		else
			move_visual_to_stable(player, horseId, visual)
		end
	end

	return actionSucceeded, reason
end

function HorseRoamingService.ReturnHorseToStable(player: Player, horseId: string): (boolean, string)
	if type(horseId) ~= "string" or horseId == "" then
		return false, "HorseUnavailable"
	end

	set_free_state(player, horseId, false)
	local playerStates = activeByPlayer[player]
	local state = playerStates and playerStates[horseId]
	local visual = state and state.Visual or find_live_horse_visual(player, horseId)
	if visual and visual.Parent then
		visual:SetAttribute(FREE_ATTRIBUTE, nil)
	end

	-- A mounted horse finishes returning as soon as the rider dismounts. Moving it
	-- while the mount assembly owns the model would pull the rider into the stall.
	if is_visual_mounted(visual) then
		return true, "ReturnsOnDismount"
	end

	if state then
		stop_state(state)
	end

	if not visual or not visual.Parent then
		return false, "HorseUnavailable"
	end

	return move_visual_to_stable(player, horseId, visual), "Returned"
end

function HorseRoamingService.ToggleHorseFree(player: Player, horseId: string): (boolean, string)
	if player.Parent ~= Players or type(horseId) ~= "string" or horseId == "" then
		return false, "HorseUnavailable"
	end
	if not find_stable_slot(player, horseId) then
		return false, "HorseNotAssigned"
	end

	if HorseRoamingService.IsHorseFree(player, horseId) then
		local _, code = HorseRoamingService.ReturnHorseToStable(player, horseId)
		return false, code
	end

	set_free_state(player, horseId, true)
	local visual = find_live_horse_visual(player, horseId)
	if not visual or not visual.Parent then
		set_free_state(player, horseId, false)
		return false, "HorseUnavailable"
	end

	visual:SetAttribute(FREE_ATTRIBUTE, true)
	if is_visual_mounted(visual) then
		return true, "ReleasedOnDismount"
	end

	local released, code = HorseRoamingService.Release(player, horseId, visual, {
		WalkToPlayerSpawnFirst = true,
	})
	if not released then
		set_free_state(player, horseId, false)
		visual:SetAttribute(FREE_ATTRIBUTE, nil)
		return false, code
	end

	return true, code
end

function HorseRoamingService.ReturnPlayerHorsesToStable(player: Player): ()
	local hadFreeHorses = freeHorseIdsByPlayer[player] ~= nil
	local playerStates = activeByPlayer[player]
	local states = {}
	if playerStates then
		for _, state in playerStates do
			states[#states + 1] = state
		end
	end

	for _, state in states do
		local visual = state.Visual
		stop_state(state)

		if visual and visual.Parent then
			move_visual_to_stable(player, state.HorseId, visual)
		end
	end

	freeHorseIdsByPlayer[player] = nil
	if hadFreeHorses then
		freeStateChanged:Fire(player, nil, false)
	end
end

function HorseRoamingService.Init(): ()
	if initialized then
		return
	end

	initialized = true
	Players.PlayerRemoving:Connect(function(player)
		HorseRoamingService.ReturnPlayerHorsesToStable(player)
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		needsUpdateAccumulator += deltaTime
		if needsUpdateAccumulator < HorseRoamingConfig.NeedUpdateInterval then
			return
		end

		needsUpdateAccumulator = 0
		for player, playerStates in activeByPlayer do
			update_player_needs(player, playerStates)
		end
	end)
end

return HorseRoamingService
