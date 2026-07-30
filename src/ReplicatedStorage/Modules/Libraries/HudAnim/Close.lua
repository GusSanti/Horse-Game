------------------//VARIABLES
local Close = {}

------------------//MAIN FUNCTIONS
function Close.get_target(inst, state, utils, kind, offset)
	local basePosition = state.BasePosition or state.origPos or inst.Position
	local baseSize = state.BaseSize or state.origSize or inst.Size
	local properties = {}

	if kind == "slide_down" then
		properties.Position = utils.offset_udim2(basePosition, 0, -offset)
	elseif kind == "slide_up" then
		properties.Position = utils.offset_udim2(basePosition, 0, offset)
	elseif kind == "slide_left" then
		properties.Position = utils.offset_udim2(basePosition, offset, 0)
	elseif kind == "slide_right" then
		properties.Position = utils.offset_udim2(basePosition, -offset, 0)
	elseif kind ~= "fade" and kind ~= "none" then
		properties.Size = utils.scale_udim2(baseSize, 0.001)
	end

	if inst:IsA("CanvasGroup") then
		properties.GroupTransparency = 1
	end

	return properties
end

------------------//INIT
return Close
