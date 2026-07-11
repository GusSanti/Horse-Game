local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local HorseMountConfig = require(GameData:WaitForChild("HorseMountConfig"))

local HorseMountGeometry = {}
local MOUNT_ROOT_NAME = "HorseMountRoot"
local MOUNT_SEAT_NAME = "HorseMountSeat"

local function should_include_in_ground_offset(basePart)
	return basePart.Name ~= MOUNT_ROOT_NAME and basePart.Name ~= MOUNT_SEAT_NAME
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
		if not should_include_in_ground_offset(instance) then
			return nil
		end

		return get_base_part_lowest_y(instance)
	end

	local lowestY = math.huge
	local foundBasePart = false

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") and should_include_in_ground_offset(descendant) then
			foundBasePart = true
			lowestY = math.min(lowestY, get_base_part_lowest_y(descendant))
		end
	end

	if not foundBasePart then
		return nil
	end

	return lowestY
end

function HorseMountGeometry.captureHorseState(horseVisual, baseParts)
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
			Transparency = descendant.Transparency,
		}
	end

	return partStates
end

function HorseMountGeometry.restoreHorseState(horseVisual, savedState, mountRootName)
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
			part.Transparency = state.Transparency
		end
	end

	if horseVisual:IsA("Model") then
		local primaryPart = savedState.OriginalPrimaryPart
		if primaryPart and primaryPart.Parent then
			horseVisual.PrimaryPart = primaryPart
		elseif horseVisual.PrimaryPart and horseVisual.PrimaryPart.Name == mountRootName then
			horseVisual.PrimaryPart = nil
		end
	end
end

function HorseMountGeometry.stopSavedHorseMotion(savedState)
	for part in pairs(savedState.Parts or {}) do
		if part and part.Parent then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

function HorseMountGeometry.returnHorseToStable(horseVisual, savedState)
	local stablePivot = savedState and savedState.OriginalPivot
	if not horseVisual or not horseVisual.Parent or typeof(stablePivot) ~= "CFrame" then
		return
	end

	horseVisual:PivotTo(stablePivot)
	HorseMountGeometry.stopSavedHorseMotion(savedState)
end

function HorseMountGeometry.getGroundOffset(horseVisual)
	local pivot = horseVisual:GetPivot()
	local lowestY = get_instance_lowest_y(horseVisual)
	if not lowestY then
		return 0
	end

	return pivot.Position.Y - lowestY
end

function HorseMountGeometry.getCharacterLowestY(character, rootPart)
	local lowestY = character and get_instance_lowest_y(character) or nil
	if type(lowestY) == "number" then
		return lowestY
	end

	return rootPart and rootPart.Position.Y or 0
end

function HorseMountGeometry.getHorizontalSeatAlignmentOffset(seatOffset, orientation)
	local localHorizontalOffset = Vector3.new(seatOffset.Position.X, 0, seatOffset.Position.Z)
	return orientation:VectorToWorldSpace(localHorizontalOffset)
end

function HorseMountGeometry.getBoxCFrameAndSize(instance)
	if instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	return instance:GetBoundingBox()
end

function HorseMountGeometry.buildSeatOffset(horseVisual)
	local pivot = horseVisual:GetPivot()
	local boxCFrame, boxSize = HorseMountGeometry.getBoxCFrameAndSize(horseVisual)
	local boxOffset = pivot:ToObjectSpace(boxCFrame)

	return CFrame.new(
		boxOffset.Position.X + (HorseMountConfig.SeatSideOffset or 0),
		boxSize.Y * HorseMountConfig.SeatHeightScale,
		boxOffset.Position.Z + (boxSize.Z * HorseMountConfig.SeatBackwardScale)
	)
end

function HorseMountGeometry.resolveGroundPosition(position, ignoreList, groundOffset)
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

return HorseMountGeometry
