------------------//SERVICES

------------------//VARIABLES
local Click = {}

------------------//FUNCTIONS
local function get_base_size(inst, state)
	if state and state.origSize then
		return state.origSize
	end

	return inst and inst.Size or nil
end

local function get_base_position(inst, state)
	if state and state.origPos then
		return state.origPos
	end

	return inst and inst.Position or nil
end

------------------//MAIN FUNCTIONS
function Click.on_down(inst, state, utils, sfx)
	if not inst or not inst.Parent then
		return
	end

	local origSize = get_base_size(inst, state)
	if not origSize then
		return
	end

	local cs = inst:GetAttribute("click_scale") or 0.08
	local ct = inst:GetAttribute("click_t") or 0.08
	utils.tween(inst, { Size = utils.scale_udim2(origSize, 1 - cs) }, ct):Play()
	sfx.play_for(inst, "sfx_down")
end

function Click.on_up(inst, state, utils, sfx)
	if not inst or not inst.Parent then
		return
	end

	local origSize = get_base_size(inst, state)
	if not origSize then
		return
	end

	local ct = inst:GetAttribute("click_t") or 0.08
	utils.tween(inst, { Size = origSize }, ct):Play()

	local shake = inst:GetAttribute("shake_px") or 0
	if shake > 0 then
		local p = get_base_position(inst, state)
		if not p then
			return
		end
		local seq = {
			UDim2.new(p.X.Scale, p.X.Offset + shake, p.Y.Scale, p.Y.Offset),
			UDim2.new(p.X.Scale, p.X.Offset - shake, p.Y.Scale, p.Y.Offset),
			p,
		}
		for i ,v in seq do
			utils.tween(inst, { Position = v }, 0.04, Enum.EasingStyle.Linear, Enum.EasingDirection.Out):Play()
			task.wait(0.045)
		end
	end

	sfx.play_for(inst, "sfx_up")
	sfx.play_for(inst, "sfx_click")
end

------------------//INIT
return Click