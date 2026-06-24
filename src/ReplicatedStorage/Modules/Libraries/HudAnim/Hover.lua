------------------//SERVICES

------------------//VARIABLES
local Hover = {}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS
function Hover.on_hover(inst, state, utils, sfx, pulse)
	local hs = inst:GetAttribute("hover_scale") or 0.05
	local ht = inst:GetAttribute("hover_t") or 0.12
	local hrot = inst:GetAttribute("rotate_hover_deg") or 0
	local bgTo = inst:GetAttribute("hover_bg")
	local imgTo = inst:GetAttribute("hover_img")

	utils.tween(inst, { Size = utils.scale_udim2(state.origSize, 1 + hs), Rotation = state.origRot + hrot }, ht, Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()

	if bgTo and inst.BackgroundColor3 then
		utils.tween(inst, { BackgroundColor3 = bgTo }, ht):Play()
	end
	if imgTo and (inst:IsA("ImageButton") or inst:IsA("ImageLabel")) then
		utils.tween(inst, { ImageColor3 = imgTo }, ht):Play()
	end

	if inst:GetAttribute("pulse") then
		pulse.start(inst, state, utils)
	end

	sfx.play_for(inst, "sfx_hover")
end

function Hover.on_rest(inst, state, utils, pulse)
	pulse.stop(inst, state)
	local ht = inst:GetAttribute("hover_t") or 0.12
	utils.tween(inst, {
		Size = state.origSize,
		Position = state.origPos,
		Rotation = state.origRot,
	}, ht):Play()

	if inst:GetAttribute("hover_bg") and state.origBg then
		utils.tween(inst, { BackgroundColor3 = state.origBg }, ht):Play()
	end
	if state.origImg and (inst:IsA("ImageButton") or inst:IsA("ImageLabel")) then
		utils.tween(inst, { ImageColor3 = state.origImg }, ht):Play()
	end
end

------------------//INIT
return Hover
