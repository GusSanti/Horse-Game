------------------//SERVICES

------------------//VARIABLES
local Click = {}

------------------//FUNCTIONS
local function get_base_size(inst, state)
	if state and (state.BaseSize or state.origSize) then
		return state.BaseSize or state.origSize
	end

	return inst and inst.Size or nil
end

------------------//MAIN FUNCTIONS
function Click.apply_target(inst, state, defaults, utils, properties)
	if not state.Pressed then
		return properties
	end

	local baseSize = get_base_size(inst, state)
	local fallback = defaults and defaults.click_scale or 0.06
	local clickScale = math.max(0, utils.get_number_attribute(inst, "click_scale", fallback))
	properties.Size = utils.scale_udim2(baseSize, math.max(0.01, 1 - clickScale))
	return properties
end

------------------//INIT
return Click
