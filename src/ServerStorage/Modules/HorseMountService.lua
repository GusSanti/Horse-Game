local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local ToolDictionary = require(Dictionary:WaitForChild("ToolDictionary"))
local HorseMountConfig = require(GameData:WaitForChild("HorseMountConfig"))
local Net = require(Libraries:WaitForChild("Net"))
local RaceVisualFactory = require(Utility:WaitForChild("RaceVisualFactory"))
local HorseMountAnimation = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseMountAnimation"))
local HorseMountCharacter = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseMountCharacter"))
local HorseMountGeometry = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseMountGeometry"))
local HorseService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseService"))

local HorseMountAction = Net.Function.HorseMountAction
local HorseMountInput = Net.Event.HorseMountInput
local HorseMountState = Net.Event.HorseMountState

local PLOT_VALUE_NAME = ToolDictionary.PlotValueName
local HORSE_FOLDER_NAME = ToolDictionary.HorseFolderName
local VISUAL_HORSE_ATTRIBUTE = ToolDictionary.VisualHorseAttribute
local HORSE_ID_ATTRIBUTE = ToolDictionary.HorseIdAttribute
local MOUNTED_USER_ID_ATTRIBUTE = ToolDictionary.MountedUserIdAttribute

local MOUNTED_VISUALS_FOLDER_NAME = "MountedHorseVisuals"
local MOUNT_ROOT_NAME = "HorseMountRoot"
local MOUNT_SEAT_NAME = "HorseMountSeat"
local MOUNT_DRIVER_ATTACHMENT_NAME = "HorseMountDriverAttachment"
local MOUNT_LINEAR_VELOCITY_NAME = "HorseMountLinearVelocity"
local MOUNT_ALIGN_ORIENTATION_NAME = "HorseMountAlignOrientation"
local MOUNT_ANTIGRAVITY_ATTACHMENT_NAME = "HorseMountAntiGravityAttachment"
local MOUNT_ANTIGRAVITY_FORCE_NAME = "HorseMountAntiGravityForce"
local MOUNT_DEBUG_ENABLED = true

local MOUNT_DISABLED_STATES = {
	Enum.HumanoidStateType.Freefall,
	Enum.HumanoidStateType.Jumping,
	Enum.HumanoidStateType.FallingDown,
	Enum.HumanoidStateType.Ragdoll,
	Enum.HumanoidStateType.GettingUp,
}

local HorseMountService = {}

local initialized = false
local activeMountsByPlayer = {}
local playerConnections = {}

local function capture_character_state(character, humanoid) return HorseMountCharacter.captureCharacterState(character, humanoid, MOUNT_DISABLED_STATES) end
local function apply_character_mount_state(character, humanoid) return HorseMountCharacter.applyCharacterMountState(character, humanoid, MOUNT_DISABLED_STATES) end
local restore_character_state, capture_transition_state, apply_character_transition_state, restore_transition_state =
	HorseMountCharacter.restoreCharacterState,
	HorseMountCharacter.captureTransitionState,
	HorseMountCharacter.applyCharacterTransitionState,
	HorseMountCharacter.restoreTransitionState
local build_character_pivot_from_root, smooth_character_to_root_cframe, apply_mounted_humanoid_pose =
	HorseMountCharacter.buildCharacterPivotFromRoot,
	HorseMountCharacter.smoothCharacterToRootCFrame,
	HorseMountCharacter.applyMountedHumanoidPose

local function capture_horse_state(horseVisual, baseParts) return HorseMountGeometry.captureHorseState(horseVisual, baseParts) end
local function restore_horse_state(horseVisual, savedState) return HorseMountGeometry.restoreHorseState(horseVisual, savedState, MOUNT_ROOT_NAME) end
local return_horse_to_stable, get_ground_offset, get_character_lowest_y, get_horizontal_seat_alignment_offset, build_seat_offset, resolve_ground_position =
	HorseMountGeometry.returnHorseToStable,
	HorseMountGeometry.getGroundOffset,
	HorseMountGeometry.getCharacterLowestY,
	HorseMountGeometry.getHorizontalSeatAlignmentOffset,
	HorseMountGeometry.buildSeatOffset,
	HorseMountGeometry.resolveGroundPosition

local create_mount_animation_state, play_horse_idle_animation, destroy_mount_animation_state, update_mount_animation_state, start_mount_animations, stop_mount_animations =
	HorseMountAnimation.createMountAnimationState,
	HorseMountAnimation.playHorseIdleAnimation,
	HorseMountAnimation.destroyMountAnimationState,
	HorseMountAnimation.updateMountAnimationState,
	HorseMountAnimation.startMountAnimations,
	HorseMountAnimation.stopMountAnimations

local function is_finite_number(value) return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge end

local function get_player_plot(player)
	local plotValue = player:FindFirstChild(PLOT_VALUE_NAME)
	return plotValue and plotValue:IsA("ObjectValue") and plotValue.Value or nil
end

local function get_horse_folder(player)
	local plot = get_player_plot(player)
	return plot and plot:FindFirstChild(HORSE_FOLDER_NAME) or nil
end

local function ensure_mounted_visuals_folder(player)
	local horseFolder = get_horse_folder(player)
	if not horseFolder then
		return nil
	end

	local folder = horseFolder:FindFirstChild(MOUNTED_VISUALS_FOLDER_NAME)
	if folder and folder:IsA("Folder") then return folder end
	if folder then folder:Destroy() end

	folder = Instance.new("Folder")
	folder.Name = MOUNTED_VISUALS_FOLDER_NAME
	folder.Parent = horseFolder
	return folder
end

local function get_character_parts(player)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil, nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or not rootPart:IsA("BasePart") then
		return nil, nil, nil
	end

	return character, humanoid, rootPart
end

local function get_visual_base_parts(horseVisual)
	local baseParts = {}

	if horseVisual:IsA("BasePart") then
		baseParts[#baseParts + 1] = horseVisual
		return baseParts
	end

	for _, descendant in ipairs(horseVisual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			baseParts[#baseParts + 1] = descendant
		end
	end

	return baseParts
end

local function build_angle_y(cframe)
	local lookVector = cframe.LookVector
	return math.atan2(-lookVector.X, -lookVector.Z)
end

local function build_yaw_from_direction(direction)
	return math.atan2(-direction.X, -direction.Z)
end

local function wrap_angle(angle)
	return math.atan2(math.sin(angle), math.cos(angle))
end

local function format_debug_value(value)
	local valueType = typeof(value)
	if valueType == "Vector3" then
		return string.format("(%.3f, %.3f, %.3f)", value.X, value.Y, value.Z)
	end

	if valueType == "CFrame" then
		return string.format(
			"pos=(%.3f, %.3f, %.3f) yaw=%.2f",
			value.Position.X,
			value.Position.Y,
			value.Position.Z,
			math.deg(build_angle_y(value))
		)
	end

	if valueType == "number" then
		return string.format("%.3f", value)
	end

	return tostring(value)
end

local function debug_mount_log(player, stage, payload)
	if MOUNT_DEBUG_ENABLED ~= true then
		return
	end

	local playerName = player and player.Name or "?"
	local message = string.format("[HorseMountDebug][%s][%s]", playerName, tostring(stage))

	if type(payload) == "table" then
		local segments = {}
		for key, value in pairs(payload) do
			segments[#segments + 1] = string.format("%s=%s", tostring(key), format_debug_value(value))
		end
		table.sort(segments)

		if #segments > 0 then
			message = message .. " " .. table.concat(segments, " | ")
		end
	end

	warn(message)
end

local function format_mount_local_vector(vector)
	return string.format("sideX=%.3f heightY=%.3f forwardZ=%.3f", vector.X, vector.Y, vector.Z)
end

local function build_horizontal_seat_offset(seatOffset)
	if typeof(seatOffset) ~= "CFrame" then
		return CFrame.identity
	end

	local position = seatOffset.Position
	return CFrame.new(position.X, 0, position.Z)
end

local function convert_offset_to_cframe(configuredOffset)
	if typeof(configuredOffset) == "CFrame" then
		return configuredOffset
	end

	if typeof(configuredOffset) == "Vector3" then
		return CFrame.new(configuredOffset.X, configuredOffset.Y, configuredOffset.Z)
	end

	return CFrame.identity
end

local function get_configured_rider_weld_c0()
	return convert_offset_to_cframe(HorseMountConfig.RiderWeldOffset),
		convert_offset_to_cframe(HorseMountConfig.SprintRiderWeldOffsetDelta)
end

local function get_target_rider_weld_c0(mountState)
	local baseOffset, sprintOffset = get_configured_rider_weld_c0()
	if mountState and mountState.Sprinting == true then
		return baseOffset * sprintOffset
	end

	return baseOffset
end

local function get_target_ground_offset(baseGroundOffset, mountState)
	local groundOffset = baseGroundOffset or 0
	if not mountState or mountState.Sprinting ~= true then
		groundOffset += HorseMountConfig.IdleWalkGroundOffsetDelta or 0
	end

	return groundOffset
end

local function update_rider_weld_offset(mountState, deltaTime)
	local riderWeld = mountState and mountState.RiderWeld
	if not riderWeld or not riderWeld.Parent then
		return
	end

	local targetC0 = get_target_rider_weld_c0(mountState)
	local responsiveness = HorseMountConfig.RiderWeldResponsiveness or 14
	local blendAlpha = 1
	if type(deltaTime) == "number" and deltaTime > 0 and responsiveness > 0 then
		blendAlpha = 1 - math.exp(-responsiveness * deltaTime)
	end

	riderWeld.C0 = riderWeld.C0:Lerp(targetC0, math.clamp(blendAlpha, 0, 1))
end

local function append_mount_alignment_problem(problems, condition, message)
	if condition then
		problems[#problems + 1] = message
	end
end

local function debug_mount_alignment_report(player, stage, payload)
	if MOUNT_DEBUG_ENABLED ~= true then
		return
	end

	payload = payload or {}

	local playerName = player and player.Name or "?"
	local lines = {
		string.format("[HorseMountAlignment][%s][%s]", playerName, tostring(stage)),
		"Reading guide: sideX is left/right on the horse, heightY is up/down, forwardZ is front/back.",
	}
	local problems = {}
	local horseRootCFrame = payload.HorseRootCFrame
	local seatOffset = payload.SeatOffset
	local configuredSeatSideOffset = payload.ConfiguredSeatSideOffset
	local expectedSeatCFrame = payload.ExpectedSeatCFrame
	local actualSeatCFrame = payload.ActualSeatCFrame
	local riderRootCFrame = payload.RiderRootCFrame
	local riderWeldC0 = payload.RiderWeldC0
	local allowRiderHeightOffset = payload.AllowRiderHeightOffset == true

	if typeof(seatOffset) == "CFrame" then
		local seatLocalPosition = seatOffset.Position
		lines[#lines + 1] = "SeatOffset local: " .. format_mount_local_vector(seatLocalPosition)
	end

	if type(configuredSeatSideOffset) == "number" then
		lines[#lines + 1] = string.format("Configured side bias: %.3f", configuredSeatSideOffset)
		append_mount_alignment_problem(
			problems,
			math.abs(configuredSeatSideOffset) > 0.15,
			"Configured side bias is not centered, so the rider will sit to one side of the visual center."
		)
	end

	if typeof(horseRootCFrame) == "CFrame" and typeof(expectedSeatCFrame) == "CFrame" then
		local expectedSeatLocal = horseRootCFrame:PointToObjectSpace(expectedSeatCFrame.Position)
		lines[#lines + 1] = "Expected rider point from horse root: " .. format_mount_local_vector(expectedSeatLocal)
	end

	if typeof(expectedSeatCFrame) == "CFrame" and typeof(actualSeatCFrame) == "CFrame" then
		local localSeatError = expectedSeatCFrame:PointToObjectSpace(actualSeatCFrame.Position)
		local seatDistance = (actualSeatCFrame.Position - expectedSeatCFrame.Position).Magnitude
		local seatYawError = math.deg(wrap_angle(build_angle_y(actualSeatCFrame) - build_angle_y(expectedSeatCFrame)))
		lines[#lines + 1] = string.format(
			"Actual Seat vs expected point: distance=%.3f yawErrorDegrees=%.2f localError=%s",
			seatDistance,
			seatYawError,
			format_mount_local_vector(localSeatError)
		)
		append_mount_alignment_problem(
			problems,
			seatDistance > 0.08,
			"The Seat part is not on the computed rider point."
		)
		append_mount_alignment_problem(
			problems,
			math.abs(seatYawError) > 2,
			"The Seat yaw does not match the horse yaw."
		)
	end

	if typeof(expectedSeatCFrame) == "CFrame" and typeof(riderRootCFrame) == "CFrame" then
		local localRiderError = expectedSeatCFrame:PointToObjectSpace(riderRootCFrame.Position)
		local riderDistance = (riderRootCFrame.Position - expectedSeatCFrame.Position).Magnitude
		local riderHorizontalDistance = Vector3.new(localRiderError.X, 0, localRiderError.Z).Magnitude
		local riderYawError = math.deg(wrap_angle(build_angle_y(riderRootCFrame) - build_angle_y(expectedSeatCFrame)))
		lines[#lines + 1] = string.format(
			"Rider root vs expected point: distance=%.3f horizontalDistance=%.3f yawErrorDegrees=%.2f localError=%s",
			riderDistance,
			riderHorizontalDistance,
			riderYawError,
			format_mount_local_vector(localRiderError)
		)
		append_mount_alignment_problem(
			problems,
			allowRiderHeightOffset and riderHorizontalDistance > 0.25 or riderDistance > 0.25,
			allowRiderHeightOffset
				and "The rider root is horizontally away from the computed rider point."
				or "The rider root is not on the computed rider point when the weld is made."
		)
		append_mount_alignment_problem(
			problems,
			math.abs(riderYawError) > 4,
			"The rider yaw does not match the horse yaw."
		)
	end

	if typeof(riderWeldC0) == "CFrame" then
		local weldLocalPosition = riderWeldC0.Position
		local weldHorizontalOffset = Vector3.new(weldLocalPosition.X, 0, weldLocalPosition.Z).Magnitude
		lines[#lines + 1] = "Rider weld C0 local offset: " .. format_mount_local_vector(weldLocalPosition)
		append_mount_alignment_problem(
			problems,
			allowRiderHeightOffset and weldHorizontalOffset > 0.35 or weldLocalPosition.Magnitude > 0.35,
			allowRiderHeightOffset
				and "The rider weld kept a large horizontal offset from the Seat; check the rider root line above."
				or "The rider weld kept a large offset from the Seat; check the rider root line above."
		)
	end

	if #problems == 0 then
		lines[#lines + 1] = "Diagnosis: Seat, rider root, and horse yaw are aligned within the debug thresholds."
	else
		for index, problem in ipairs(problems) do
			lines[#lines + 1] = string.format("Diagnosis %d: %s", index, problem)
		end
	end

	warn(table.concat(lines, "\n"))
end

local function move_towards(current, target, maxDelta)
	if math.abs(target - current) <= maxDelta then
		return target
	end

	if target > current then
		return current + maxDelta
	end

	return current - maxDelta
end

local function build_horse_summary(horse)
	local movement = horse and horse.Movement or {}

	return {
		Id = horse.Id,
		Name = horse.Nickname ~= "" and horse.Nickname or horse.DisplayName or horse.Id,
		DisplayName = horse.DisplayName or horse.Id,
		Nickname = horse.Nickname or "",
		CatalogId = horse.CatalogId,
		PlaceholderModelKey = horse.PlaceholderModelKey or horse.VisualModelName or horse.CatalogId or "",
		Movement = {
			WalkSpeed = movement.WalkSpeed or 14,
			TrotSpeed = movement.TrotSpeed or 18,
			CanterSpeed = movement.CanterSpeed or 22,
			SprintSpeed = movement.SprintSpeed or 26,
			TurnRate = movement.TurnRate or 0.8,
		},
	}
end

local function find_live_horse_visual(player, horseId)
	local horseFolder = get_horse_folder(player)
	if not horseFolder then
		return nil
	end

	for _, container in ipairs(horseFolder:GetChildren()) do
		for _, child in ipairs(container:GetChildren()) do
			if child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true and child:GetAttribute(HORSE_ID_ATTRIBUTE) == horseId then
				return child
			end
		end
	end

	for _, descendant in ipairs(horseFolder:GetDescendants()) do
		if descendant:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true and descendant:GetAttribute(HORSE_ID_ATTRIBUTE) == horseId then
			return descendant
		end
	end

	return nil
end

local function create_temporary_horse_visual(player, horse)
	local folder = ensure_mounted_visuals_folder(player)
	if not folder then
		return nil, "HorseFolderMissing"
	end

	local model = RaceVisualFactory.CreateRaceModel({
		Id = horse.Id,
		HorseId = horse.Id,
		CatalogId = horse.CatalogId,
		PlaceholderModelKey = horse.PlaceholderModelKey or horse.VisualModelName or horse.CatalogId,
	}, nil, folder)

	model.Name = horse.Id
	model:SetAttribute(VISUAL_HORSE_ATTRIBUTE, true)
	model:SetAttribute(HORSE_ID_ATTRIBUTE, horse.Id)
	model:SetAttribute(MOUNTED_USER_ID_ATTRIBUTE, 0)

	return model, nil
end

local function set_visual_mount_marker(horseVisual, userId)
	if horseVisual then
		horseVisual:SetAttribute(MOUNTED_USER_ID_ATTRIBUTE, userId)
	end
end

local function clear_visual_mount_marker(horseVisual)
	if horseVisual then
		horseVisual:SetAttribute(MOUNTED_USER_ID_ATTRIBUTE, nil)
	end
end


local function get_mount_parent(horseVisual)
	if horseVisual:IsA("Model") then
		return horseVisual
	end

	return horseVisual.Parent
end

local function create_weld(part0, part1, parent)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.Parent = parent or part0
	return weld
end

local function create_offset_weld(part0, part1, c0, c1, parent)
	local weld = Instance.new("Weld")
	weld.Part0 = part0
	weld.Part1 = part1
	weld.C0 = c0 or CFrame.identity
	weld.C1 = c1 or CFrame.identity
	weld.Parent = parent or part0
	return weld
end

local function assign_network_owner(rootPart, player)
	if not rootPart or not rootPart.Parent then
		return
	end

	if rootPart.Anchored then
		return
	end

	pcall(function()
		rootPart:SetNetworkOwner(player)
	end)
end

local function assign_network_owner_to_parts(player, parts)
	for _, part in ipairs(parts or {}) do
		if part and part:IsA("BasePart") and part.Parent and not part.Anchored then
			assign_network_owner(part, player)
		end
	end
end

local function zero_assembly_velocity(basePart)
	if not basePart or not basePart.Parent then
		return
	end

	local linearVelocity = basePart.AssemblyLinearVelocity
	basePart.AssemblyLinearVelocity = Vector3.new(linearVelocity.X, 0, linearVelocity.Z)
	basePart.AssemblyAngularVelocity = Vector3.zero
end

local function stabilize_mount_physics(mountState)
	zero_assembly_velocity(mountState and mountState.MountRoot)
	zero_assembly_velocity(mountState and mountState.RootPart)
end

local function create_anti_gravity_force(mountRoot)
	local attachment = Instance.new("Attachment")
	attachment.Name = MOUNT_ANTIGRAVITY_ATTACHMENT_NAME
	attachment.Parent = mountRoot

	local vectorForce = Instance.new("VectorForce")
	vectorForce.Name = MOUNT_ANTIGRAVITY_FORCE_NAME
	vectorForce.ApplyAtCenterOfMass = true
	vectorForce.RelativeTo = Enum.ActuatorRelativeTo.World
	vectorForce.Attachment0 = attachment
	vectorForce.Parent = mountRoot
	return vectorForce
end

local function create_driver_constraints(mountRoot, initialRootCFrame)
	local attachment = Instance.new("Attachment")
	attachment.Name = MOUNT_DRIVER_ATTACHMENT_NAME
	attachment.Parent = mountRoot

	local linearVelocity = Instance.new("LinearVelocity")
	linearVelocity.Name = MOUNT_LINEAR_VELOCITY_NAME
	linearVelocity.Attachment0 = attachment
	linearVelocity.RelativeTo = Enum.ActuatorRelativeTo.World
	linearVelocity.VectorVelocity = Vector3.zero
	linearVelocity.MaxForce = HorseMountConfig.MountLinearMaxForce or 1000000
	linearVelocity.Parent = mountRoot

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = MOUNT_ALIGN_ORIENTATION_NAME
	alignOrientation.Attachment0 = attachment
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.CFrame = initialRootCFrame.Rotation
	alignOrientation.MaxTorque = HorseMountConfig.MountAlignMaxTorque or 1000000
	alignOrientation.MaxAngularVelocity = HorseMountConfig.MountAlignMaxAngularVelocity or 8
	alignOrientation.Responsiveness = HorseMountConfig.MountAlignResponsiveness or 18
	alignOrientation.RigidityEnabled = false
	alignOrientation.Parent = mountRoot

	return attachment, linearVelocity, alignOrientation
end

local function update_anti_gravity_force(mountState)
	local mountRoot = mountState and mountState.MountRoot
	local antiGravityForce = mountState and mountState.AntiGravityForce
	if not mountRoot or not antiGravityForce or not mountRoot.Parent or not antiGravityForce.Parent then
		return
	end

	antiGravityForce.Force = Vector3.new(0, mountRoot.AssemblyMass * Workspace.Gravity, 0)
end

local function assign_network_owner_to_mount(mountState)
	if not mountState or not mountState.Player then
		return
	end

	assign_network_owner_to_parts(mountState.Player, mountState.MountParts)
end

local function create_mount_assembly(player, horseVisual, baseParts, seatOffset, initialRootCFrame)
	local mountParent = get_mount_parent(horseVisual)
	if not mountParent then
		return nil, nil, nil, nil, nil, nil, nil, nil
	end

	local mountRoot = Instance.new("Part")
	mountRoot.Name = MOUNT_ROOT_NAME
	mountRoot.Transparency = 1
	mountRoot.Size = Vector3.new(2.4, 2.4, 2.4)
	mountRoot.Anchored = false
	mountRoot.CanCollide = false
	mountRoot.CanQuery = false
	mountRoot.CanTouch = false
	mountRoot.CFrame = initialRootCFrame
	mountRoot.Parent = mountParent

	local mountSeat = Instance.new("Seat")
	mountSeat.Name = MOUNT_SEAT_NAME
	mountSeat.Size = HorseMountConfig.SeatSize
	mountSeat.Transparency = 1
	mountSeat.Anchored = false
	mountSeat.CanCollide = false
	mountSeat.CanQuery = false
	mountSeat.CanTouch = false
	mountSeat.CFrame = initialRootCFrame * build_horizontal_seat_offset(seatOffset)
	mountSeat.Parent = mountParent

	local welds = {
		create_weld(mountRoot, mountSeat, mountRoot),
	}

	local mountParts = {
		mountRoot,
		mountSeat,
	}

	for _, basePart in ipairs(baseParts) do
		basePart.Massless = true
		basePart.Anchored = false
		basePart.CanCollide = false
		basePart.CanQuery = false
		basePart.CanTouch = false
		welds[#welds + 1] = create_weld(mountRoot, basePart, mountRoot)
		mountParts[#mountParts + 1] = basePart
	end

	if horseVisual:IsA("Model") then
		horseVisual.PrimaryPart = mountRoot
	end

	local antiGravityForce = create_anti_gravity_force(mountRoot)
	local driverAttachment, linearVelocity, alignOrientation = create_driver_constraints(mountRoot, initialRootCFrame)
	antiGravityForce.Force = Vector3.new(0, mountRoot.AssemblyMass * Workspace.Gravity, 0)
	assign_network_owner_to_parts(player, mountParts)
	return mountRoot, mountSeat, welds, antiGravityForce, mountParts, driverAttachment, linearVelocity, alignOrientation
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
		if nodeName ~= MOUNT_ROOT_NAME:lower()
			and nodeName ~= MOUNT_SEAT_NAME:lower()
			and not string.find(nodeName, "tail", 1, true)
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
		anchor.Parent = horseVisual:IsA("Model") and horseVisual or horseVisual.Parent

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

local function fade_out_horse_visual(mountState, duration)
	if not mountState or not mountState.HorseState then
		return
	end

	local savedParts = mountState.HorseState.Parts or {}
	local fadeDuration = math.max(duration or 0, 0.05)
	local startedAt = os.clock()

	while true do
		local elapsed = os.clock() - startedAt
		local alpha = math.clamp(elapsed / fadeDuration, 0, 1)

		for part, state in pairs(savedParts) do
			if part and part.Parent and state then
				part.Transparency = state.Transparency + ((1 - state.Transparency) * alpha)
			end
		end

		if alpha >= 1 then
			break
		end

		RunService.Heartbeat:Wait()
	end
end

local get_dismount_cframe
local send_unmounted_state

local function cleanup_mount_horse(mountState)
	if not mountState then
		return
	end

	destroy_instances(mountState.DustResources)
	restore_horse_state(mountState.HorseVisual, mountState.HorseState)
	clear_visual_mount_marker(mountState.HorseVisual)
	destroy_instances({ mountState.RiderWeld })
	destroy_instances(mountState.HorseWelds)
	destroy_instances({ mountState.MountSeat, mountState.MountRoot })

	if mountState.IsTemporaryVisual and mountState.HorseVisual and mountState.HorseVisual.Parent then
		mountState.HorseVisual:Destroy()
	else
		return_horse_to_stable(mountState.HorseVisual, mountState.HorseState)
	end
end

local function begin_dismount_transition(player, reason)
	local mountState = activeMountsByPlayer[player]
	if not mountState then
		send_unmounted_state(player, reason)
		return nil
	end

	activeMountsByPlayer[player] = nil

	local dismountCFrame = nil
	if mountState.MountRoot and mountState.MountRoot.Parent then
		dismountCFrame = get_dismount_cframe(mountState)
	end

	if mountState.Humanoid and mountState.Humanoid.Parent then
		mountState.Humanoid.Sit = false
	end

	if mountState.LinearVelocity and mountState.LinearVelocity.Parent then
		mountState.LinearVelocity.VectorVelocity = Vector3.zero
	end

	if mountState.MountRoot and mountState.MountRoot.Parent then
		mountState.MountRoot.AssemblyLinearVelocity = Vector3.zero
		mountState.MountRoot.AssemblyAngularVelocity = Vector3.zero
	end

	stop_mount_animations(mountState)
	set_horse_run_dust_enabled(mountState.DustEmitters, false)
	destroy_instances({ mountState.RiderWeld })

	if mountState.Character and mountState.Character.Parent and mountState.Humanoid and mountState.Humanoid.Parent then
		restore_character_state(mountState.Character, mountState.Humanoid, mountState.CharacterState)
	end

	mountState.DismountCFrame = dismountCFrame

	return mountState
end

get_dismount_cframe = function(mountState)
	local rootCFrame = mountState.MountRoot and mountState.MountRoot.CFrame or mountState.HorseVisual:GetPivot()
	local desiredPosition = rootCFrame.Position + (rootCFrame.RightVector * HorseMountConfig.DismountSideDistance)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {
		mountState.HorseVisual,
		mountState.MountRoot,
		mountState.MountSeat,
		mountState.Character,
	}
	raycastParams.IgnoreWater = false

	local origin = desiredPosition + Vector3.new(0, HorseMountConfig.DismountProbeHeight, 0)
	local direction = Vector3.new(0, -(HorseMountConfig.DismountProbeDistance + HorseMountConfig.DismountProbeHeight), 0)
	local result = Workspace:Raycast(origin, direction, raycastParams)

	if result then
		desiredPosition = Vector3.new(desiredPosition.X, result.Position.Y + 3, desiredPosition.Z)
	else
		desiredPosition += Vector3.new(0, 3, 0)
	end

	return CFrame.new(desiredPosition, desiredPosition + rootCFrame.LookVector)
end

local function build_mount_payload(mountState)
	return {
		Mounted = true,
		HorseId = mountState.HorseId,
		HorseName = mountState.HorseSummary.Name,
		CatalogId = mountState.HorseSummary.CatalogId,
	}
end

send_unmounted_state = function(player, reason)
	HorseMountState:Fire(player, {
		Kind = "Unmounted",
		Reason = reason or "Unmounted",
		Mounted = false,
	})
end

local function convert_seat_to_rider_weld(mountState)
	if not mountState then
		return
	end

	if not mountState.Player or mountState.Player.Parent ~= Players then
		return
	end

	if not mountState.Character or not mountState.Character.Parent then
		return
	end

	if not mountState.Humanoid or not mountState.Humanoid.Parent then
		return
	end

	if not mountState.RootPart or not mountState.RootPart.Parent then
		return
	end

	if not mountState.HorseVisual or not mountState.HorseVisual.Parent then
		return
	end

	if not mountState.MountRoot or not mountState.MountRoot.Parent then
		return
	end

	if not mountState.MountSeat or not mountState.MountSeat.Parent then
		return
	end

	if mountState.RiderWeld and mountState.RiderWeld.Parent then
		return
	end

	local mountSeat = mountState.MountSeat
	local rootPart = mountState.RootPart
	local humanoid = mountState.Humanoid
	if not mountSeat or not rootPart or not humanoid then
		return
	end

	local seatWeld = mountSeat:FindFirstChild("SeatWeld")
	if seatWeld then
		seatWeld:Destroy()
	end

	local riderOffset = get_target_rider_weld_c0(mountState)
	mountSeat.Disabled = true
	mountSeat.CanTouch = false
	mountState.RiderWeld = create_offset_weld(mountSeat, rootPart, riderOffset, CFrame.identity, mountSeat)
	apply_mounted_humanoid_pose(mountState)
	assign_network_owner_to_mount(mountState)
	update_anti_gravity_force(mountState)
	stabilize_mount_physics(mountState)
	debug_mount_alignment_report(mountState.Player, "RiderWeld", {
		HorseRootCFrame = mountState.MountRoot.CFrame,
		SeatOffset = mountState.SeatOffset,
		ConfiguredSeatSideOffset = HorseMountConfig.SeatSideOffset or 0,
		ExpectedSeatCFrame = mountState.MountRoot.CFrame * build_horizontal_seat_offset(mountState.SeatOffset),
		ActualSeatCFrame = mountSeat.CFrame,
		RiderRootCFrame = rootPart.CFrame,
		RiderWeldC0 = mountState.RiderWeld.C0,
		AllowRiderHeightOffset = true,
	})
end

local function clear_mount_state(player, reason, options)
	local mountState = activeMountsByPlayer[player]
	if not mountState then
		send_unmounted_state(player, reason)
		return false
	end

	options = options or {}
	activeMountsByPlayer[player] = nil

	local dismountCFrame = nil
	if options.SkipCharacterPlacement ~= true and mountState.MountRoot and mountState.MountRoot.Parent then
		dismountCFrame = get_dismount_cframe(mountState)
	end

	if mountState.Humanoid and mountState.Humanoid.Parent then
		mountState.Humanoid.Sit = false
	end

	if mountState.LinearVelocity and mountState.LinearVelocity.Parent then
		mountState.LinearVelocity.VectorVelocity = Vector3.zero
	end

	if mountState.MountRoot and mountState.MountRoot.Parent then
		mountState.MountRoot.AssemblyLinearVelocity = Vector3.zero
		mountState.MountRoot.AssemblyAngularVelocity = Vector3.zero
	end

	stop_mount_animations(mountState)
	destroy_instances({ mountState.RiderWeld })
	cleanup_mount_horse(mountState)

	if mountState.Character and mountState.Character.Parent and mountState.Humanoid and mountState.Humanoid.Parent then
		restore_character_state(mountState.Character, mountState.Humanoid, mountState.CharacterState)

		if dismountCFrame then
			mountState.Character:PivotTo(dismountCFrame)
		end
	end

	send_unmounted_state(player, reason)
	return true
end

local function get_forward_start_speed(movement)
	local trotSpeed = movement.TrotSpeed or 18
	local canterSpeed = movement.CanterSpeed or 22
	return math.max(trotSpeed, canterSpeed)
end

local function validate_mount_state(mountState)
	if not mountState then
		return false
	end

	if not mountState.Player or mountState.Player.Parent ~= Players then
		return false
	end

	if not mountState.Character or not mountState.Character.Parent then
		return false
	end

	if not mountState.Humanoid or not mountState.Humanoid.Parent then
		return false
	end

	if not mountState.RootPart or not mountState.RootPart.Parent then
		return false
	end

	if not mountState.HorseVisual or not mountState.HorseVisual.Parent then
		return false
	end

	if not mountState.MountRoot or not mountState.MountRoot.Parent then
		return false
	end

	if not mountState.MountSeat or not mountState.MountSeat.Parent then
		return false
	end

	return true
end

local function update_mount(mountState, deltaTime)
	if not mountState.RiderWeld or not mountState.RiderWeld.Parent then
		convert_seat_to_rider_weld(mountState)
	end

	assign_network_owner_to_mount(mountState)
	update_anti_gravity_force(mountState)
	update_rider_weld_offset(mountState, deltaTime)
	apply_mounted_humanoid_pose(mountState)
	update_mount_animation_state(mountState)
	update_horse_run_dust_anchors(mountState.DustAnchors)
	set_horse_run_dust_enabled(mountState.DustEmitters, mountState.Sprinting)
end

local function mount_player(player, payload)
	local horseId = payload and payload.HorseId
	if type(horseId) ~= "string" or horseId == "" then
		return {
			Success = false,
			Code = "HorseIdRequired",
		}
	end

	local horse = HorseService.GetOwnedHorse(player, horseId)
	if not horse then
		return {
			Success = false,
			Code = "HorseNotOwned",
		}
	end

	local character, humanoid, rootPart = get_character_parts(player)
	if not character or not humanoid or not rootPart then
		return {
			Success = false,
			Code = "CharacterUnavailable",
		}
	end

	if activeMountsByPlayer[player] then
		if activeMountsByPlayer[player].HorseId == horseId then
			return {
				Success = true,
				Code = "AlreadyMounted",
				State = build_mount_payload(activeMountsByPlayer[player]),
			}
		end

		clear_mount_state(player, "SwitchHorse", {
			SkipCharacterPlacement = true,
		})
	end

	local horseVisual = find_live_horse_visual(player, horseId)
	local isTemporaryVisual = false
	local mountAtHorse = payload and payload.MountAtHorse == true
	if not horseVisual then
		if mountAtHorse then
			return {
				Success = false,
				Code = "StableHorseVisualMissing",
			}
		end

		local visualError
		horseVisual, visualError = create_temporary_horse_visual(player, horse)
		if not horseVisual then
			return {
				Success = false,
				Code = visualError or "HorseVisualMissing",
			}
		end

		isTemporaryVisual = true
	end

	local stableHorseRootCFrame = nil
	if mountAtHorse then
		stableHorseRootCFrame = horseVisual:GetPivot()
		local maxPromptDistance = (HorseMountConfig.StableMountPromptMaxActivationDistance or 14) + 2
		if (rootPart.Position - stableHorseRootCFrame.Position).Magnitude > maxPromptDistance then
			return {
				Success = false,
				Code = "HorseTooFar",
			}
		end
	end

	local baseParts = get_visual_base_parts(horseVisual)
	if #baseParts == 0 then
		if isTemporaryVisual and horseVisual.Parent then
			horseVisual:Destroy()
		end

		return {
			Success = false,
			Code = "HorseVisualMissing",
		}
	end

	local horseSummary = build_horse_summary(horse)
	local horseState = capture_horse_state(horseVisual, baseParts)
	local characterState = capture_character_state(character, humanoid)
	local groundOffset = get_ground_offset(horseVisual)
	local seatOffset = build_seat_offset(horseVisual)
	local playerLowestY = get_character_lowest_y(character, rootPart)
	local requestedCameraYaw = payload and payload.CameraYaw
	local cameraYaw = mountAtHorse and build_angle_y(stableHorseRootCFrame)
		or (is_finite_number(requestedCameraYaw) and requestedCameraYaw or build_angle_y(rootPart.CFrame))
	local spawnRotation = CFrame.Angles(0, cameraYaw, 0)
	local alignmentRootCFrame = mountAtHorse and stableHorseRootCFrame or CFrame.new(rootPart.Position) * spawnRotation
	local seatAlignmentOffset = get_horizontal_seat_alignment_offset(seatOffset, spawnRotation)
	local initialPosition = stableHorseRootCFrame and stableHorseRootCFrame.Position or Vector3.new(
		alignmentRootCFrame.Position.X - seatAlignmentOffset.X,
		playerLowestY + get_target_ground_offset(groundOffset, nil),
		alignmentRootCFrame.Position.Z - seatAlignmentOffset.Z
	)
	if not mountAtHorse and HorseMountConfig.StickMountedHorseToGround == true then
		initialPosition = resolve_ground_position(
			Vector3.new(
				alignmentRootCFrame.Position.X - seatAlignmentOffset.X,
				alignmentRootCFrame.Position.Y,
				alignmentRootCFrame.Position.Z - seatAlignmentOffset.Z
			),
			{ horseVisual, character },
			get_target_ground_offset(groundOffset, nil)
		)
	end
	local initialRootCFrame = stableHorseRootCFrame or (CFrame.new(initialPosition) * spawnRotation)
	local seatRootCFrame = initialRootCFrame * build_horizontal_seat_offset(seatOffset)
	local riderRootCFrame = seatRootCFrame * get_target_rider_weld_c0(nil)

	debug_mount_log(player, "MountSetup", {
		AlignmentRoot = alignmentRootCFrame,
		GroundOffset = groundOffset,
		InitialRoot = initialRootCFrame,
		RiderRoot = riderRootCFrame,
		SeatRoot = seatRootCFrame,
		PlayerLowestY = playerLowestY,
		SeatAlignmentOffset = seatAlignmentOffset,
		SeatOffset = seatOffset,
	})

	if not mountAtHorse then
		horseVisual:PivotTo(initialRootCFrame)
	end
	set_visual_mount_marker(horseVisual, player.UserId)
	character:PivotTo(build_character_pivot_from_root(character, rootPart, riderRootCFrame))
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
	debug_mount_alignment_report(player, "MountSetup", {
		HorseRootCFrame = initialRootCFrame,
		SeatOffset = seatOffset,
		ConfiguredSeatSideOffset = HorseMountConfig.SeatSideOffset or 0,
		ExpectedSeatCFrame = seatRootCFrame,
		RiderRootCFrame = rootPart.CFrame,
		AllowRiderHeightOffset = true,
	})

	local mountingAnimationState = create_mount_animation_state(humanoid, horseVisual)
	if mountingAnimationState then
		play_horse_idle_animation(mountingAnimationState)
		debug_mount_log(player, "MountIdlePreview", {
			HorseIdleTrackLoaded = mountingAnimationState.HorseIdleTrack ~= nil,
			HorseWalkTrackLoaded = mountingAnimationState.HorseWalkTrack ~= nil,
		})
	end

	HorseMountState:Fire(player, {
		Kind = "Mounting",
		Duration = HorseMountConfig.MountTransitionDuration or 1.8,
		CameraYaw = cameraYaw,
		HorseId = horseId,
		TargetCFrame = riderRootCFrame,
	})
	apply_character_transition_state(humanoid, rootPart)
	task.wait(HorseMountConfig.MountTransitionDuration or 1.8)

	local currentCharacter, currentHumanoid, currentRootPart = get_character_parts(player)
	if currentCharacter ~= character or currentHumanoid ~= humanoid or currentRootPart ~= rootPart or humanoid.Health <= 0 then
		destroy_mount_animation_state(mountingAnimationState)
		restore_character_state(character, humanoid, characterState)
		restore_horse_state(horseVisual, horseState)
		clear_visual_mount_marker(horseVisual)

		if isTemporaryVisual and horseVisual.Parent then
			horseVisual:Destroy()
		else
			return_horse_to_stable(horseVisual, horseState)
		end

		return {
			Success = false,
			Code = "CharacterUnavailable",
		}
	end

	apply_character_mount_state(character, humanoid)
	character:PivotTo(build_character_pivot_from_root(character, rootPart, riderRootCFrame))
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	local mountRoot, mountSeat, horseWelds, antiGravityForce, mountParts, driverAttachment, linearVelocity, alignOrientation = create_mount_assembly(
		player,
		horseVisual,
		baseParts,
		seatOffset,
		initialRootCFrame
	)
	if not mountRoot or not mountSeat then
		destroy_mount_animation_state(mountingAnimationState)
		restore_character_state(character, humanoid, characterState)
		restore_horse_state(horseVisual, horseState)
		clear_visual_mount_marker(horseVisual)

		if isTemporaryVisual and horseVisual.Parent then
			horseVisual:Destroy()
		else
			return_horse_to_stable(horseVisual, horseState)
		end

		return {
			Success = false,
			Code = "HorseVisualMissing",
		}
	end

	local mountState = {
		Player = player,
		HorseId = horseId,
		HorseSummary = horseSummary,
		HorseVisual = horseVisual,
		HorseState = horseState,
		IsTemporaryVisual = isTemporaryVisual,
		HorseWelds = horseWelds,
		MountParts = mountParts,
		MountRoot = mountRoot,
		MountSeat = mountSeat,
		DriverAttachment = driverAttachment,
		LinearVelocity = linearVelocity,
		AlignOrientation = alignOrientation,
		AntiGravityForce = antiGravityForce,
		RiderWeld = nil,
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
		CharacterState = characterState,
		AnimationState = mountingAnimationState,
		GroundOffset = groundOffset,
		SeatOffset = seatOffset,
		RiderRootCFrame = riderRootCFrame,
		SeatRootCFrame = seatRootCFrame,
		CurrentYaw = cameraYaw,
		CameraYaw = cameraYaw,
		CurrentSpeed = 0,
		ForwardHeldTime = 0,
		InputX = 0,
		InputZ = 0,
		Sprinting = false,
		LastMoveDirection = spawnRotation.LookVector,
	}
	mountState.DustResources, mountState.DustEmitters, mountState.DustAnchors = create_horse_run_dust(horseVisual)

	debug_mount_log(player, "MountAssembly", {
		HorsePivot = horseVisual:GetPivot(),
		MountRoot = mountRoot.CFrame,
		MountSeat = mountSeat.CFrame,
		SeatOffset = seatOffset,
	})
	debug_mount_alignment_report(player, "MountAssembly", {
		HorseRootCFrame = mountRoot.CFrame,
		SeatOffset = seatOffset,
		ConfiguredSeatSideOffset = HorseMountConfig.SeatSideOffset or 0,
		ExpectedSeatCFrame = mountRoot.CFrame * build_horizontal_seat_offset(seatOffset),
		ActualSeatCFrame = mountSeat.CFrame,
		RiderRootCFrame = rootPart.CFrame,
		AllowRiderHeightOffset = true,
	})

	activeMountsByPlayer[player] = mountState
	start_mount_animations(mountState)
	convert_seat_to_rider_weld(mountState)
	assign_network_owner_to_mount(mountState)
	update_anti_gravity_force(mountState)
	stabilize_mount_physics(mountState)
	update_anti_gravity_force(mountState)
	task.defer(function()
		if activeMountsByPlayer[player] == mountState then
			update_anti_gravity_force(mountState)
			stabilize_mount_physics(mountState)
			convert_seat_to_rider_weld(mountState)
		end
	end)

	local responseState = build_mount_payload(mountState)
	HorseMountState:Fire(player, {
		Kind = "Mounted",
		State = responseState,
	})

	return {
		Success = true,
		Code = "Mounted",
		State = responseState,
	}
end

local function dismount_player(player)
	local mountState = begin_dismount_transition(player, "Dismounted")
	local didUnmount = mountState ~= nil

	if didUnmount then
		HorseMountState:Fire(player, {
			Kind = "Dismounting",
			Duration = (HorseMountConfig.DismountTransitionDuration or 0.95)
				+ (HorseMountConfig.DismountSettleDuration or 0.12),
			AnimationDuration = HorseMountConfig.DismountTransitionDuration or 0.95,
			SettleDuration = HorseMountConfig.DismountSettleDuration or 0.12,
			StartCFrame = mountState.RootPart and mountState.RootPart.CFrame or mountState.RiderRootCFrame,
			TargetCFrame = mountState.DismountCFrame,
		})

		task.spawn(function()
			local character = mountState.Character
			local humanoid = mountState.Humanoid
			local rootPart = mountState.RootPart
			local fadeDuration = HorseMountConfig.DismountTransitionDuration or 0.95
			local settleDuration = HorseMountConfig.DismountSettleDuration or 0.12

			task.spawn(function()
				fade_out_horse_visual(mountState, fadeDuration)
			end)

			if character and character.Parent and humanoid and humanoid.Parent and rootPart and rootPart.Parent and humanoid.Health > 0 then
				local transitionState = capture_transition_state(humanoid)
				apply_character_transition_state(humanoid, rootPart)
				task.wait(fadeDuration)

				if character.Parent and rootPart.Parent and mountState.DismountCFrame then
					smooth_character_to_root_cframe(character, rootPart, mountState.DismountCFrame, settleDuration)
				end

				restore_transition_state(humanoid, transitionState)
			end

			cleanup_mount_horse(mountState)
			RunService.Heartbeat:Wait()
			send_unmounted_state(player, "Dismounted")
		end)
	end

	return {
		Success = didUnmount,
		Code = didUnmount and "Dismounted" or "NotMounted",
		State = {
			Mounted = false,
		},
	}
end

local function get_player_mount_state(player)
	local mountState = activeMountsByPlayer[player]
	if mountState then
		return {
			Success = true,
			Code = "Mounted",
			State = build_mount_payload(mountState),
		}
	end

	return {
		Success = true,
		Code = "Unmounted",
		State = {
			Mounted = false,
		},
	}
end

local function disconnect_player_connections(player)
	local connections = playerConnections[player]
	if not connections then
		return
	end

	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	playerConnections[player] = nil
end

local function bind_player(player)
	disconnect_player_connections(player)

	local connections = {}
	playerConnections[player] = connections

	connections[#connections + 1] = player.CharacterAdded:Connect(function()
		clear_mount_state(player, "CharacterChanged", {
			SkipCharacterPlacement = true,
		})
	end)

	connections[#connections + 1] = player.CharacterRemoving:Connect(function()
		clear_mount_state(player, "CharacterRemoving", {
			SkipCharacterPlacement = true,
		})
	end)
end

function HorseMountService.Init()
	if initialized then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		bind_player(player)
	end

	Players.PlayerAdded:Connect(bind_player)
	Players.PlayerRemoving:Connect(function(player)
		clear_mount_state(player, "PlayerRemoving", {
			SkipCharacterPlacement = true,
		})
		disconnect_player_connections(player)
	end)

	HorseMountAction:Respond(function(player, payload)
		if type(payload) ~= "table" then
			return {
				Success = false,
				Code = "InvalidPayload",
			}
		end

		if payload.Action == "Mount" then
			return mount_player(player, payload)
		end

		if payload.Action == "Dismount" then
			return dismount_player(player)
		end

		if payload.Action == "GetState" then
			return get_player_mount_state(player)
		end

		return {
			Success = false,
			Code = "UnknownAction",
		}
	end)

	HorseMountInput:Connect(function(player, payload)
		local mountState = activeMountsByPlayer[player]
		if not mountState or type(payload) ~= "table" then
			return
		end

		if is_finite_number(payload.MoveX) then
			mountState.InputX = math.clamp(payload.MoveX, -1, 1)
		end

		if is_finite_number(payload.MoveZ) then
			mountState.InputZ = math.clamp(payload.MoveZ, -1, 1)
		end

		if type(payload.Sprinting) == "boolean" then
			mountState.Sprinting = payload.Sprinting
		end

		if is_finite_number(payload.CameraYaw) then
			mountState.CameraYaw = payload.CameraYaw
		end
	end)

	RunService.Heartbeat:Connect(function(deltaTime)
		local playersToUnmount = {}

		for player, mountState in pairs(activeMountsByPlayer) do
			if not validate_mount_state(mountState) then
				playersToUnmount[#playersToUnmount + 1] = player
			elseif mountState.Humanoid.Health <= 0 then
				playersToUnmount[#playersToUnmount + 1] = player
			else
				update_mount(mountState, deltaTime)
			end
		end

		for _, player in ipairs(playersToUnmount) do
			clear_mount_state(player, "MountInvalid", {
				SkipCharacterPlacement = true,
			})
		end
	end)

	initialized = true
end

return HorseMountService
