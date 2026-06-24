------------------//SERVICES
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Camera = workspace.CurrentCamera

------------------//VARIABLES
local Close = {}
local closing_deb = {}

------------------//FUNCTIONS
local function get_blur_effect()
	return Lighting:FindFirstChild("UIBlur") or Lighting:FindFirstChildWhichIsA("BlurEffect")
end

local function tween_blur(targetSize, t)
	local blur = get_blur_effect()
	if blur then
		local info = TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(blur, info, { Size = targetSize }):Play()
	end
end

local function tween_fov(target, t)
	local info = TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(Camera, info, {FieldOfView = target}):Play()
end

local function finish_close(inst, state, hasBlur, t)
	inst.Visible = false

	-- Limpar Efeitos
	if hasBlur then tween_blur(0, t) end
	if inst:GetAttribute("fov") then tween_fov(70, t) end

	-- Restaurar Estado
	if state then
		if state.origSize then inst.Size = state.origSize end
		if state.origPos then inst.Position = state.origPos end

		if inst:IsA("CanvasGroup") then 
			inst.GroupTransparency = 0 
		end
	end

	-- Limpeza segura do debounce
	task.defer(function()
		closing_deb[inst] = nil
		inst:SetAttribute("_is_closing", nil)
	end)
end

------------------//MAIN FUNCTIONS
function Close.run(inst, state, utils, sfx)
	if sfx and sfx.play_for then sfx.play_for(inst, "sfx_close") end

	local kind = inst:GetAttribute("open_anim") or "pop"
	local t = inst:GetAttribute("open_t") or 0.25
	local closeTime = t * 0.8
	local offset = inst:GetAttribute("open_offset_px") or 200
	local hasBlur = inst:GetAttribute("blur") ~= nil

	local easeStyle = Enum.EasingStyle.Back
	local easeDir = Enum.EasingDirection.In

	-- Fade Out
	if inst:IsA("CanvasGroup") then
		local info = TweenInfo.new(closeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(inst, info, { GroupTransparency = 1 }):Play()
	end

	-- Animações
	if kind == "slide_down" then
		local currentPos = state.origPos or inst.Position
		local targetPos = UDim2.new(currentPos.X.Scale, currentPos.X.Offset, currentPos.Y.Scale, currentPos.Y.Offset - (offset * 1.2))

		local tween = utils.tween(inst, { Position = targetPos }, closeTime, easeStyle, easeDir)
		tween:Play()
		tween.Completed:Connect(function() finish_close(inst, state, hasBlur, closeTime) end)

	elseif kind == "slide_up" then
		local currentPos = state.origPos or inst.Position
		local targetPos = UDim2.new(currentPos.X.Scale, currentPos.X.Offset, currentPos.Y.Scale, currentPos.Y.Offset + (offset * 1.2))

		local tween = utils.tween(inst, { Position = targetPos }, closeTime, easeStyle, easeDir)
		tween:Play()
		tween.Completed:Connect(function() finish_close(inst, state, hasBlur, closeTime) end)

	else -- pop
		local targetSize = UDim2.new(0,0,0,0)
		if state and state.origSize then
			targetSize = utils.scale_udim2(state.origSize, 0.001)
		end

		local tween = utils.tween(inst, { Size = targetSize }, closeTime, easeStyle, easeDir)
		tween:Play()
		tween.Completed:Connect(function() finish_close(inst, state, hasBlur, closeTime) end)
	end
end

function Close.bind(inst, state, utils, sfx)
	inst:GetPropertyChangedSignal("Visible"):Connect(function()
		-- Detecta fechamento real
		if inst.Visible == false then

			if not inst:GetAttribute("UIOpen") then return end
			if closing_deb[inst] then return end

			-- Trava e prepara animação
			closing_deb[inst] = true
			inst:SetAttribute("_is_closing", true)
			inst:SetAttribute("skip_open", true) -- Evita loop no Open

			inst.Visible = true
			Close.run(inst, state, utils, sfx)
		end
	end)
end

------------------//INIT
return Close