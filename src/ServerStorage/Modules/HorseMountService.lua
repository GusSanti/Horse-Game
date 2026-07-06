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
local SEAT_CAPTURE_DELAY = 0.08

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

local function is_finite_number(value)
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function get_player_plot(player)
	local plotValue = player:FindFirstChild(PLOT_VALUE_NAME)
	if plotValue and plotValue:IsA("ObjectValue") then
		return plotValue.Value
	end

	return nil
end

local function get_horse_folder(player)
	local plot = get_player_plot(player)
	if not plot then
		return nil
	end

	return plot:FindFirstChild(HORSE_FOLDER_NAME)
end

local function ensure_mounted_visuals_folder(player)
	local horseFolder = get_horse_folder(player)
	if not horseFolder then
		return nil
	end

	local folder = horseFolder:FindFirstChild(MOUNTED_VISUALS_FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

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

local function get_base_part_lowest_y(basePart)
	local cframe = basePart.CFrame
	local halfSizeX = cframe.RightVector * (basePart.Size.X * 0.5)
	local halfSizeY = cframe.UpVector * (basePart.Size.Y * 0.5)
	local halfSizeZ = cframe.LookVector * (basePart.Size.Z * 0.5)
	local lowestY = math.huge

	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local cornerPosition = cframe.Position + (halfSizeX * xSign) + (halfSizeY * ySign) + (halfSizeZ * zSign)
				lowestY = math.min(lowestY, cornerPosition.Y)
			end
		end
	end

	return lowestY
end

local function get_instance_lowest_y(instance)
	if instance:IsA("BasePart") then
		return get_base_part_lowest_y(instance)
	end

	local lowestY = math.huge
	local foundBasePart = false

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			foundBasePart = true
			lowestY = math.min(lowestY, get_base_part_lowest_y(descendant))
		end
	end

	if not foundBasePart then
		return nil
	end

	return lowestY
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

local function capture_character_state(character, humanoid)
	local collisionStates = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			collisionStates[descendant] = descendant.CanCollide
		end
	end

	local stateEnabled = {}
	for _, stateType in ipairs(MOUNT_DISABLED_STATES) do
		stateEnabled[stateType] = humanoid:GetStateEnabled(stateType)
	end

	return {
		AutoRotate = humanoid.AutoRotate,
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		UseJumpPower = humanoid.UseJumpPower,
		PlatformStand = humanoid.PlatformStand,
		CollisionStates = collisionStates,
		StateEnabled = stateEnabled,
	}
end

local function apply_character_mount_state(character, humanoid)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end

	humanoid.AutoRotate = false
	humanoid.PlatformStand = false
	humanoid.WalkSpeed = 0

	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	for _, stateType in ipairs(MOUNT_DISABLED_STATES) do
		humanoid:SetStateEnabled(stateType, false)
	end
end

local function restore_character_state(character, humanoid, savedState)
	if not savedState then
		return
	end

	for part, canCollide in pairs(savedState.CollisionStates or {}) do
		if part and part.Parent then
			part.CanCollide = canCollide
		end
	end

	if humanoid and humanoid.Parent then
		humanoid.Sit = false
		humanoid.AutoRotate = savedState.AutoRotate
		humanoid.UseJumpPower = savedState.UseJumpPower
		humanoid.PlatformStand = savedState.PlatformStand
		humanoid.WalkSpeed = savedState.WalkSpeed

		if savedState.UseJumpPower then
			humanoid.JumpPower = savedState.JumpPower
		else
			humanoid.JumpHeight = savedState.JumpHeight
		end

		for stateType, enabled in pairs(savedState.StateEnabled or {}) do
			humanoid:SetStateEnabled(stateType, enabled)
		end
	end
end

local function capture_horse_state(horseVisual, baseParts)
	local partStates = {
		Parts = {},
		OriginalPivot = horseVisual:GetPivot(),
		OriginalPrimaryPart = horseVisual:IsA("Model") and horseVisual.PrimaryPart or nil,
	}

	for _, descendant in ipairs(baseParts) do
		partStates.Parts[descendant] = {
			Anchored = descendant.Anchored,
			CanCollide = descendant.CanCollide,
			CanQuery = descendant.CanQuery,
			CanTouch = descendant.CanTouch,
			Massless = descendant.Massless,
		}
	end

	return partStates
end

local function restore_horse_state(horseVisual, savedState)
	if not savedState then
		return
	end

	for part, state in pairs(savedState.Parts or {}) do
		if part and part.Parent and state then
			part.Anchored = state.Anchored
			part.CanCollide = state.CanCollide
			part.CanQuery = state.CanQuery
			part.CanTouch = state.CanTouch
			part.Massless = state.Massless
		end
	end

	if horseVisual:IsA("Model") then
		local primaryPart = savedState.OriginalPrimaryPart
		if primaryPart and primaryPart.Parent then
			horseVisual.PrimaryPart = primaryPart
		elseif horseVisual.PrimaryPart and horseVisual.PrimaryPart.Name == MOUNT_ROOT_NAME then
			horseVisual.PrimaryPart = nil
		end
	end
end

local function stop_saved_horse_motion(savedState)
	for part in pairs(savedState.Parts or {}) do
		if part and part.Parent then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function return_horse_to_stable(horseVisual, savedState)
	local stablePivot = savedState and savedState.OriginalPivot
	if not horseVisual or not horseVisual.Parent or typeof(stablePivot) ~= "CFrame" then
		return
	end

	horseVisual:PivotTo(stablePivot)
	stop_saved_horse_motion(savedState)
end

local function get_ground_offset(horseVisual)
	local pivot = horseVisual:GetPivot()
	local lowestY = get_instance_lowest_y(horseVisual)
	if not lowestY then
		return 0
	end

	return pivot.Position.Y - lowestY
end

local function build_seat_offset(horseVisual)
	local pivot = horseVisual:GetPivot()
	local boxCFrame
	local boxSize

	if horseVisual:IsA("BasePart") then
		boxCFrame = horseVisual.CFrame
		boxSize = horseVisual.Size
	else
		boxCFrame, boxSize = horseVisual:GetBoundingBox()
	end

	local boxOffset = pivot:ToObjectSpace(boxCFrame)

	return boxOffset * CFrame.new(
		0,
		boxSize.Y * HorseMountConfig.SeatHeightScale,
		boxSize.Z * HorseMountConfig.SeatBackwardScale
	)
end

local function resolve_ground_position(position, ignoreList, groundOffset)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignoreList
	raycastParams.IgnoreWater = false

	local origin = position + Vector3.new(0, HorseMountConfig.GroundProbeHeight, 0)
	local direction = Vector3.new(0, -(HorseMountConfig.GroundProbeDistance + HorseMountConfig.GroundProbeHeight), 0)
	local result = Workspace:Raycast(origin, direction, raycastParams)

	if result then
		return Vector3.new(
			position.X,
			result.Position.Y + groundOffset + HorseMountConfig.GroundClearance,
			position.Z
		)
	end

	return position
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
	mountSeat.CFrame = initialRootCFrame * seatOffset
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
		if instance and instance.Parent then
			instance:Destroy()
		end
	end
end

local function get_dismount_cframe(mountState)
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

local function send_unmounted_state(player, reason)
	HorseMountState:Fire(player, {
		Kind = "Unmounted",
		Reason = reason or "Unmounted",
		Mounted = false,
	})
end

local function force_seat_occupant(mountState)
	if not mountState.MountSeat or not mountState.MountSeat.Parent then
		return
	end

	if not mountState.Humanoid or not mountState.Humanoid.Parent then
		return
	end

	if mountState.MountSeat.Occupant ~= mountState.Humanoid then
		mountState.MountSeat:Sit(mountState.Humanoid)
	end

	mountState.Humanoid.Sit = true
	pcall(function()
		mountState.Humanoid:ChangeState(Enum.HumanoidStateType.Seated)
	end)
end

local function apply_mounted_humanoid_pose(mountState)
	local humanoid = mountState and mountState.Humanoid
	if not humanoid or not humanoid.Parent then
		return
	end

	humanoid.Sit = true
	humanoid.PlatformStand = false

	if humanoid:GetState() ~= Enum.HumanoidStateType.Seated then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Seated)
		end)
	end
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
	if not seatWeld then
		return
	end

	local riderOffset = mountSeat.CFrame:ToObjectSpace(rootPart.CFrame)
	seatWeld:Destroy()
	mountSeat.Disabled = true
	mountSeat.CanTouch = false
	mountState.RiderWeld = create_offset_weld(mountSeat, rootPart, riderOffset, CFrame.identity, mountSeat)
	apply_mounted_humanoid_pose(mountState)
	assign_network_owner_to_mount(mountState)
	update_anti_gravity_force(mountState)
	stabilize_mount_physics(mountState)
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

local function update_mount(mountState, _deltaTime)
	if not mountState.RiderWeld or not mountState.RiderWeld.Parent then
		force_seat_occupant(mountState)
		convert_seat_to_rider_weld(mountState)
	end

	assign_network_owner_to_mount(mountState)
	update_anti_gravity_force(mountState)
	apply_mounted_humanoid_pose(mountState)
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
	if not horseVisual then
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
	local requestedCameraYaw = payload and payload.CameraYaw
	local cameraYaw = is_finite_number(requestedCameraYaw) and requestedCameraYaw or build_angle_y(rootPart.CFrame)
	local spawnRotation = CFrame.Angles(0, cameraYaw, 0)
	local initialRootCFrame = CFrame.new(rootPart.Position) * spawnRotation
	local initialPosition = resolve_ground_position(
		initialRootCFrame.Position,
		{ horseVisual, character },
		groundOffset
	)
	initialRootCFrame = CFrame.new(initialPosition) * spawnRotation

	horseVisual:PivotTo(initialRootCFrame)
	apply_character_mount_state(character, humanoid)
	set_visual_mount_marker(horseVisual, player.UserId)

	local mountRoot, mountSeat, horseWelds, antiGravityForce, mountParts, driverAttachment, linearVelocity, alignOrientation = create_mount_assembly(
		player,
		horseVisual,
		baseParts,
		seatOffset,
		initialRootCFrame
	)
	if not mountRoot or not mountSeat then
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
		GroundOffset = groundOffset,
		SeatOffset = seatOffset,
		CurrentYaw = cameraYaw,
		CameraYaw = cameraYaw,
		CurrentSpeed = 0,
		ForwardHeldTime = 0,
		InputX = 0,
		InputZ = 0,
		Sprinting = false,
		LastMoveDirection = spawnRotation.LookVector,
	}

	activeMountsByPlayer[player] = mountState
	assign_network_owner_to_mount(mountState)
	update_anti_gravity_force(mountState)
	stabilize_mount_physics(mountState)
	force_seat_occupant(mountState)
	update_anti_gravity_force(mountState)
	task.defer(function()
		if activeMountsByPlayer[player] == mountState then
			update_anti_gravity_force(mountState)
			stabilize_mount_physics(mountState)
			force_seat_occupant(mountState)
		end
	end)
	task.delay(SEAT_CAPTURE_DELAY, function()
		if activeMountsByPlayer[player] == mountState then
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
	local didUnmount = clear_mount_state(player, "Dismounted")
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
