------------------//SERVICES

------------------//VARIABLES
local Rotate = {}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS
function Rotate.on_bind(inst, state, utils)
	local rdeg = inst:GetAttribute("rotate_deg") or 0
	local rt = inst:GetAttribute("rotate_t") or 0.15
	if rdeg ~= 0 then
		utils.tween(inst, { Rotation = state.origRot + rdeg }, rt):Play()
	end
end

------------------//INIT
return Rotate
