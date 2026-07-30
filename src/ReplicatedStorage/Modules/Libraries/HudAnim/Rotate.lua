------------------//VARIABLES
local Rotate = {}

------------------//MAIN FUNCTIONS
function Rotate.get_hover_rotation(inst, state, defaults)
	local baseRotation = state.BaseRotation or state.origRot or inst.Rotation
	local fallback = defaults and defaults.rotate_hover_deg or 0
	local rotation = tonumber(inst:GetAttribute("rotate_hover_deg"))
	if rotation == nil then
		rotation = fallback
	end

	return baseRotation + (state.Hovered and rotation or 0)
end

------------------//INIT
return Rotate
