------------------//VARIABLES
local Open = {}

local SLIDE_DIRECTIONS = {
	slide_down = Vector2.new(0, -1),
	slide_up = Vector2.new(0, 1),
	slide_left = Vector2.new(1, 0),
	slide_right = Vector2.new(-1, 0),
	drop = Vector2.new(0, -1),
	rise = Vector2.new(0, 1),
}

local SCALED_KINDS = {
	pop = true,
	drop = true,
	rise = true,
	flip = true,
	zoom = true,
}

local DEFAULT_ROTATIONS = {
	flip = 14,
	drop = 5,
	rise = -5,
}

local DEFAULT_EASINGS = {
	pop = Enum.EasingStyle.Back,
	drop = Enum.EasingStyle.Back,
	rise = Enum.EasingStyle.Back,
	flip = Enum.EasingStyle.Back,
	zoom = Enum.EasingStyle.Quint,
	fade = Enum.EasingStyle.Sine,
}

local FADED_KINDS = {
	fade = true,
	zoom = true,
	flip = true,
}

------------------//MAIN FUNCTIONS
function Open.get_slide_direction(kind)
	return SLIDE_DIRECTIONS[kind]
end

function Open.get_default_rotation(kind)
	return DEFAULT_ROTATIONS[kind] or 0
end

function Open.get_default_easing(kind)
	return DEFAULT_EASINGS[kind] or Enum.EasingStyle.Quad
end

function Open.wants_fade(kind)
	return FADED_KINDS[kind] == true
end

function Open.apply_start(inst, state, utils, kind, offset, popScale, rotateDeg)
	local basePosition = state.BasePosition or state.origPos or inst.Position
	local baseSize = state.BaseSize or state.origSize or inst.Size
	local baseRotation = state.BaseRotation or state.origRot or inst.Rotation

	local direction = SLIDE_DIRECTIONS[kind]
	if direction then
		inst.Position = utils.offset_udim2(basePosition, direction.X * offset, direction.Y * offset)
	end

	if SCALED_KINDS[kind] then
		local startScale = if kind == "zoom" then math.max(1, 2 - popScale) else popScale
		inst.Size = utils.scale_udim2(baseSize, startScale)
	elseif not direction and kind ~= "fade" and kind ~= "none" then
		inst.Size = utils.scale_udim2(baseSize, popScale)
	end

	local rotation = rotateDeg or Open.get_default_rotation(kind)
	if rotation ~= 0 then
		inst.Rotation = baseRotation + rotation
	end

	if inst:IsA("CanvasGroup") then
		inst.GroupTransparency = 1
	end
end

function Open.get_target(inst, state)
	local properties = {
		Size = state.BaseSize or state.origSize or inst.Size,
		Position = state.BasePosition or state.origPos or inst.Position,
		Rotation = state.BaseRotation or state.origRot or inst.Rotation,
	}

	if inst:IsA("CanvasGroup") then
		properties.GroupTransparency = state.BaseGroupTransparency or 0
	end

	return properties
end

return Open
