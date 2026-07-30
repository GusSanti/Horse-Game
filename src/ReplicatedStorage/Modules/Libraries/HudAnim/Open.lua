------------------//VARIABLES
local Open = {}

------------------//MAIN FUNCTIONS
function Open.apply_start(inst, state, utils, kind, offset, popScale)
	local basePosition = state.BasePosition or state.origPos or inst.Position
	local baseSize = state.BaseSize or state.origSize or inst.Size

	if kind == "slide_down" then
		inst.Position = utils.offset_udim2(basePosition, 0, -offset)
	elseif kind == "slide_up" then
		inst.Position = utils.offset_udim2(basePosition, 0, offset)
	elseif kind == "slide_left" then
		inst.Position = utils.offset_udim2(basePosition, offset, 0)
	elseif kind == "slide_right" then
		inst.Position = utils.offset_udim2(basePosition, -offset, 0)
	elseif kind ~= "fade" and kind ~= "none" then
		inst.Size = utils.scale_udim2(baseSize, popScale)
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
