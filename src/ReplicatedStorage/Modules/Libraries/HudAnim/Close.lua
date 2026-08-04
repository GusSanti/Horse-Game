------------------//VARIABLES
local Close = {}

local Open = require(script.Parent.Open)

local SHRINK_SCALE = 0.001
local SOFT_SHRINK_SCALE = 0.88

------------------//MAIN FUNCTIONS
function Close.get_target(inst, state, utils, kind, offset, rotateDeg)
	local basePosition = state.BasePosition or state.origPos or inst.Position
	local baseSize = state.BaseSize or state.origSize or inst.Size
	local baseRotation = state.BaseRotation or state.origRot or inst.Rotation
	local properties = {}

	local direction = Open.get_slide_direction(kind)
	if direction then
		properties.Position = utils.offset_udim2(basePosition, direction.X * offset, direction.Y * offset)
		properties.Size = utils.scale_udim2(baseSize, SOFT_SHRINK_SCALE)
	elseif kind == "zoom" then
		properties.Size = utils.scale_udim2(baseSize, math.max(1, 2 - SOFT_SHRINK_SCALE))
	elseif kind ~= "fade" and kind ~= "none" then
		properties.Size = utils.scale_udim2(baseSize, SHRINK_SCALE)
	end

	local rotation = rotateDeg or Open.get_default_rotation(kind)
	if rotation ~= 0 then
		properties.Rotation = baseRotation - rotation
	end

	if inst:IsA("CanvasGroup") then
		properties.GroupTransparency = 1
	end

	return properties
end

------------------//INIT
return Close
