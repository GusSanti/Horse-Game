------------------//SERVICES
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Camera = workspace.CurrentCamera

------------------//VARIABLES
local Open = {}

------------------//FUNCTIONS
local function get_blur_effect()
	local blur = Lighting:FindFirstChildWhichIsA("BlurEffect")
	if not blur then
		blur = Instance.new("BlurEffect")
		blur.Size = 0
		blur.Name = "UIBlur"
		blur.Parent = Lighting
	end
	return blur
end

local function tween_blur(targetSize, t)
	local blur = get_blur_effect()
	local info = TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(blur, info, { Size = math.max(0, targetSize) })
	tween:Play()
end

local function tween_fov(target, t)
	local info = TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(Camera, info, {FieldOfView = target}):Play()
end

------------------//MAIN FUNCTIONS
function Open.run(inst, state, utils, sfx)
	if not inst:GetAttribute("UIOpen") then
		return
	end

	-- Salva estado original
	if not state.origPos then state.origPos = inst.Position end
	if not state.origSize then state.origSize = inst.Size end

	local kind = inst:GetAttribute("open_anim") or "pop"
	local t = inst:GetAttribute("open_t") or 0.4
	local delay = inst:GetAttribute("open_delay") or 0
	local offset = inst:GetAttribute("open_offset_px") or 150
	local popScale = inst:GetAttribute("open_pop_scale") or 0.7
	local blurAmount = inst:GetAttribute("blur")
	local fovAmount = inst:GetAttribute("fov")

	if delay > 0 then
		task.wait(delay)
	end

	inst.Visible = true

	if kind == "slide_down" then
		local startPos = UDim2.new(state.origPos.X.Scale, state.origPos.X.Offset, state.origPos.Y.Scale, state.origPos.Y.Offset - offset)
		inst.Position = startPos
		utils.tween(inst, { Position = state.origPos }, t, Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()

	elseif kind == "slide_up" then
		local startPos = UDim2.new(state.origPos.X.Scale, state.origPos.X.Offset, state.origPos.Y.Scale, state.origPos.Y.Offset + offset)
		inst.Position = startPos
		utils.tween(inst, { Position = state.origPos }, t, Enum.EasingStyle.Back, Enum.EasingDirection.Out):Play()

	else -- pop
		inst.Size = utils.scale_udim2(state.origSize, popScale)
		inst.Position = state.origPos
		utils.tween(inst, { Size = state.origSize }, t, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out):Play()
	end

	-- Efeitos
	if blurAmount and tonumber(blurAmount) > 0 then
		local ignore = {["BlockInventoryFrame"]=true, ["WeaponInventoryFrame"]=true, ["PaintBlocksFrame"]=true}
		if not ignore[inst.Name] then
			tween_blur(blurAmount, t)
		end
	end

	if fovAmount then
		tween_fov(fovAmount, t)
	end

	if sfx then sfx.play_for(inst, "sfx_open") end
end

return Open