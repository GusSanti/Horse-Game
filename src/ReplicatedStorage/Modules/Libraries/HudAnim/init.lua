local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Utils = require(script.Utils)
local SFX = require(script.SFX)
local Pulse = require(script.Pulse)
local Hover = require(script.Hover)
local Click = require(script.Click)
local Open = require(script.Open)
local Close = require(script.Close)
local Fade = require(script.Fade)
local Stagger = require(script.Stagger)
local Punch = require(script.Punch)
local UIRouter = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Client"):WaitForChild("Hud"):WaitForChild("UIRouter")
)

local HudAnim = {}

local BUTTON_SUFFIX = "BT"
local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAMES = { "MainframeFR", "MainFrameFR" }
local HUD_ROOT_NAME = "HUDFR"
local HOTBAR_ROOT_NAME = "BottomFrameFR"
local MONEY_TAB_NAME = "MoneyTabBG"
local FRAMES_CONTAINER_NAME = "Frames"
local IGNORE_HUD_ANIM_ATTRIBUTE = "IgnoreHudAnim"
local IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE = "IgnoreAutoFrameButton"
local HUD_FADE_EXCLUSIONS_ATTRIBUTE = "HudFadeExclusions"
local TARGET_FRAME_ATTRIBUTE = "TargetFrame"
local CLOSE_TARGET_ATTRIBUTE = "CloseTarget"

local CLOSE_BUTTON_NAMES = {
	ExitBT = true,
	CloseBT = true,
}

-- Legacy defaults stay data-driven; any frame can override them with
-- HudFadeExclusions="NameA,NameB".
local DEFAULT_HUD_EXCLUSIONS_BY_FRAME = {
	Inventory = { [HOTBAR_ROOT_NAME] = true },
	SeedShop = { [MONEY_TAB_NAME] = true },
	FruitShop = { [MONEY_TAB_NAME] = true },
	Seller = { [MONEY_TAB_NAME] = true },
	Shop = { [MONEY_TAB_NAME] = true },
}

local DEFAULTS = {
	hover_scale = 0.05,
	click_scale = 0.06,
	hover_t = 0.16,
	click_t = 0.08,
	hover_lift_px = 2,
	click_sink_px = 1,
	rotate_hover_deg = 0,
	pulse = false,
	open_t = 0.26,
	open_offset_px = 36,
	open_pop_scale = 0.9,
	blur = 12,
	blur_t = 0.22,
	hud_fade_t = 0.14,
	open_stagger = 0,
	stagger_t = 0.26,
	stagger_delay = 0.035,
	stagger_scale = 0.86,
}

local states = setmetatable({}, { __mode = "k" })
local hudFadeStates = setmetatable({}, { __mode = "k" })
local hudFadeTweens = setmetatable({}, { __mode = "k" })

local bind_instance
local sync_hud_visibility_for_frame

local function get_player_gui()
	local localPlayer = Players.LocalPlayer
	return localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui") or nil
end

local function has_true_attribute(instance, attributeName)
	local current = instance
	while current do
		if current:GetAttribute(attributeName) == true then
			return true
		end
		current = current.Parent
	end
	return false
end

local function get_number_attribute(instance, attributeName, fallback)
	return Utils.get_number_attribute(instance, attributeName, fallback)
end

local function get_optional_number_attribute(instance, attributeName)
	return Utils.get_optional_number_attribute(instance, attributeName)
end

local function safe_play_sound(instance, soundKey)
	if SFX and type(SFX.play_for) == "function" then
		SFX.play_for(instance, soundKey)
	end
end

local function make_tween(instance, properties, duration, easingStyle, easingDirection)
	return Utils.tween(
		instance,
		properties,
		math.max(0, duration or 0),
		easingStyle or Enum.EasingStyle.Quad,
		easingDirection or Enum.EasingDirection.Out
	)
end

local function disconnect_connections(connections)
	for _, connection in ipairs(connections or {}) do
		if connection then
			connection:Disconnect()
		end
	end
	table.clear(connections)
end

local function cancel_state_tweens(state)
	Pulse.stop(state)

	for tween in pairs(state.Tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	table.clear(state.Tweens)
	state.ActiveTweenCount = 0
end

local function play_state_tween(instance, state, properties, duration, easingStyle, easingDirection, completed)
	if not instance or not instance.Parent then
		return nil
	end

	local tween = make_tween(instance, properties, duration, easingStyle, easingDirection)
	state.Tweens[tween] = true
	state.ActiveTweenCount += 1

	local connection
	connection = tween.Completed:Connect(function(playbackState)
		if connection then
			connection:Disconnect()
			connection = nil
		end

		if state.Tweens[tween] then
			state.Tweens[tween] = nil
			state.ActiveTweenCount = math.max(0, state.ActiveTweenCount - 1)
		end

		if type(completed) == "function" then
			completed(playbackState)
		end
	end)

	tween:Play()
	return tween
end

local function apply_defaults(instance)
	for key, value in pairs(DEFAULTS) do
		if instance:GetAttribute(key) == nil then
			instance:SetAttribute(key, value)
		end
	end
end

local function capture_base_state(instance, state, force)
	if not instance or not instance:IsA("GuiObject") then
		return
	end

	if not force and state.BaseCaptured then
		return
	end

	state.BaseCaptured = true
	state.BaseSize = instance.Size
	state.BasePosition = instance.Position
	state.BaseRotation = instance.Rotation
	state.BaseBackgroundColor = instance.BackgroundColor3

	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		state.BaseImageColor = instance.ImageColor3
	end

	if instance:IsA("CanvasGroup") then
		state.BaseGroupTransparency = instance.GroupTransparency
	end
end

local function refresh_base_property(instance, state, propertyName)
	if state.ActiveTweenCount > 0 or state.Hovered or state.Pressed or state.Opening or state.Closing then
		return
	end

	if propertyName == "Size" then
		state.BaseSize = instance.Size
	elseif propertyName == "Position" then
		state.BasePosition = instance.Position
	elseif propertyName == "Rotation" then
		state.BaseRotation = instance.Rotation
	elseif propertyName == "BackgroundColor3" then
		state.BaseBackgroundColor = instance.BackgroundColor3
	elseif propertyName == "ImageColor3" and (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
		state.BaseImageColor = instance.ImageColor3
	elseif propertyName == "GroupTransparency" and instance:IsA("CanvasGroup") then
		state.BaseGroupTransparency = instance.GroupTransparency
	end
end

local function track_base_changes(instance, state)
	if state.BaseConnectionsBound then
		return
	end

	state.BaseConnectionsBound = true
	for _, propertyName in ipairs({ "Size", "Position", "Rotation", "BackgroundColor3" }) do
		state.Connections[#state.Connections + 1] = instance:GetPropertyChangedSignal(propertyName):Connect(function()
			refresh_base_property(instance, state, propertyName)
		end)
	end

	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		state.Connections[#state.Connections + 1] = instance:GetPropertyChangedSignal("ImageColor3"):Connect(function()
			refresh_base_property(instance, state, "ImageColor3")
		end)
	end

	if instance:IsA("CanvasGroup") then
		state.Connections[#state.Connections + 1] = instance:GetPropertyChangedSignal("GroupTransparency"):Connect(function()
			refresh_base_property(instance, state, "GroupTransparency")
		end)
	end
end

local function get_or_create_state(instance)
	local state = states[instance]
	if state then
		return state
	end

	state = {
		BaseCaptured = false,
		BaseSize = nil,
		BasePosition = nil,
		BaseRotation = nil,
		BaseBackgroundColor = nil,
		BaseImageColor = nil,
		BaseGroupTransparency = nil,
		Hovered = false,
		Pressed = false,
		Opening = false,
		Closing = false,
		TransitionToken = 0,
		IgnoreVisibleChanges = 0,
		IgnoreRouteVisibleChanges = 0,
		LastVisible = instance:IsA("GuiObject") and instance.Visible or nil,
		ActiveTweenCount = 0,
		Tweens = {},
		Connections = {},
		BoundButton = false,
		BoundOpen = false,
		BoundAutoOpenButton = false,
		BoundExitButton = false,
		RouteRegistered = false,
		RouteCleanup = nil,
	}

	states[instance] = state
	return state
end

local function restore_instance(instance, state)
	if not instance or not instance.Parent or not state then
		return
	end

	pcall(function()
		if state.BaseSize then
			instance.Size = state.BaseSize
		end
		if state.BasePosition then
			instance.Position = state.BasePosition
		end
		if state.BaseRotation then
			instance.Rotation = state.BaseRotation
		end
		if state.BaseBackgroundColor then
			instance.BackgroundColor3 = state.BaseBackgroundColor
		end
		if state.BaseImageColor and (instance:IsA("ImageLabel") or instance:IsA("ImageButton")) then
			instance.ImageColor3 = state.BaseImageColor
		end
		if state.BaseGroupTransparency and instance:IsA("CanvasGroup") then
			instance.GroupTransparency = state.BaseGroupTransparency
		end
	end)

	if state.FadeRecords then
		Fade.restore(state.FadeRecords)
		state.FadeRecords = nil
	end
end

local function is_visible_in_hierarchy(instance)
	local current = instance
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return instance ~= nil and instance.Parent ~= nil
end

local function should_animate_button(button)
	if not button or not button:IsA("GuiButton") then
		return false
	end

	if has_true_attribute(button, IGNORE_HUD_ANIM_ATTRIBUTE) then
		return false
	end

	return button:GetAttribute("UIAnim") == true or button:GetAttribute("UIAnimPreset") ~= nil
end

local function update_button_visual(button, state, duration)
	if not button or not button.Parent then
		return
	end

	capture_base_state(button, state, false)
	cancel_state_tweens(state)

	local properties = Hover.get_target(button, state, DEFAULTS, Utils)
	Click.apply_target(button, state, DEFAULTS, Utils, properties)

	local easingStyle = Enum.EasingStyle.Quad
	if state.Pressed then
		easingStyle = Enum.EasingStyle.Sine
	elseif state.Hovered then
		easingStyle = Enum.EasingStyle.Back
	end

	play_state_tween(
		button,
		state,
		properties,
		duration or get_number_attribute(button, "hover_t", DEFAULTS.hover_t),
		Utils.get_easing_style(button, "hover_ease", easingStyle),
		Enum.EasingDirection.Out,
		function(playbackState)
			if playbackState == Enum.PlaybackState.Completed
				and states[button] == state
				and state.Hovered
				and not state.Pressed
				and button:GetAttribute("pulse") == true
			then
				Pulse.start(button, state, Utils)
			end
		end
	)
end

local function bind_button_animation(button, state)
	if state.BoundButton or not should_animate_button(button) then
		return
	end

	state.BoundButton = true
	capture_base_state(button, state, false)
	track_base_changes(button, state)

	state.Connections[#state.Connections + 1] = button.MouseEnter:Connect(function()
		if not should_animate_button(button) or not is_visible_in_hierarchy(button) then
			return
		end

		state.Hovered = true
		update_button_visual(button, state, get_number_attribute(button, "hover_t", DEFAULTS.hover_t))
		safe_play_sound(button, "sfx_hover")
	end)

	state.Connections[#state.Connections + 1] = button.MouseLeave:Connect(function()
		if not should_animate_button(button) then
			return
		end

		state.Hovered = false
		state.Pressed = false
		update_button_visual(button, state, get_number_attribute(button, "hover_t", DEFAULTS.hover_t))
	end)

	state.Connections[#state.Connections + 1] = button.MouseButton1Down:Connect(function()
		if not should_animate_button(button) or not is_visible_in_hierarchy(button) then
			return
		end

		state.Pressed = true
		update_button_visual(button, state, get_number_attribute(button, "click_t", DEFAULTS.click_t))
		safe_play_sound(button, "sfx_down")
	end)

	state.Connections[#state.Connections + 1] = button.MouseButton1Up:Connect(function()
		if not should_animate_button(button) then
			return
		end

		state.Pressed = false
		update_button_visual(button, state, get_number_attribute(button, "click_t", DEFAULTS.click_t))
		safe_play_sound(button, "sfx_up")
		safe_play_sound(button, "sfx_click")
	end)

	state.Connections[#state.Connections + 1] = button.SelectionGained:Connect(function()
		if not should_animate_button(button) or not is_visible_in_hierarchy(button) then
			return
		end

		state.Hovered = true
		update_button_visual(button, state, get_number_attribute(button, "hover_t", DEFAULTS.hover_t))
		safe_play_sound(button, "sfx_select")
	end)

	state.Connections[#state.Connections + 1] = button.SelectionLost:Connect(function()
		if not should_animate_button(button) then
			return
		end

		state.Hovered = false
		state.Pressed = false
		update_button_visual(button, state, get_number_attribute(button, "hover_t", DEFAULTS.hover_t))
		safe_play_sound(button, "sfx_deselect")
	end)
end

local function get_blur_effect(shouldCreate)
	local blur = Lighting:FindFirstChild("UIBlur") or Lighting:FindFirstChildWhichIsA("BlurEffect")
	if not blur and shouldCreate then
		blur = Instance.new("BlurEffect")
		blur.Name = "UIBlur"
		blur.Size = 0
		blur.Parent = Lighting
	end
	return blur
end

local function tween_blur(size, duration)
	local blur = get_blur_effect(size > 0)
	if not blur then
		return
	end

	make_tween(blur, { Size = math.max(0, size) }, duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out):Play()
end

local function tween_camera_fov(target, duration)
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end

	make_tween(camera, { FieldOfView = target }, duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out):Play()
end

local function set_visible_silent(instance, state, isVisible)
	if not instance or not instance:IsA("GuiObject") then
		return
	end

	if instance.Visible == isVisible then
		state.LastVisible = isVisible
		return
	end

	if state.BoundOpen then
		state.IgnoreVisibleChanges += 1
	end
	if state.RouteRegistered then
		state.IgnoreRouteVisibleChanges += 1
	end
	instance.Visible = isVisible
	state.LastVisible = isVisible
end

local function finish_open(instance, state, token)
	if states[instance] ~= state or state.TransitionToken ~= token then
		return
	end

	state.Opening = false
	state.Closing = false
	restore_instance(instance, state)
end

local function finish_close(instance, state, token)
	if states[instance] ~= state or state.TransitionToken ~= token then
		return
	end

	state.Opening = false
	state.Closing = false
	restore_instance(instance, state)
	set_visible_silent(instance, state, false)
	instance:SetAttribute("_is_closing", nil)
end

local function reset_transition(instance, state)
	if not state then
		return
	end

	state.TransitionToken += 1
	cancel_state_tweens(state)
	state.Opening = false
	state.Closing = false
	restore_instance(instance, state)

	if instance and instance.Parent then
		instance:SetAttribute("_is_closing", nil)
	end
end

local function apply_open_start(instance, state, openKind, offset, popScale, rotateDeg)
	Open.apply_start(instance, state, Utils, openKind, offset, popScale, rotateDeg)
end

local function build_open_target_properties(instance, state)
	return Open.get_target(instance, state)
end

local function build_close_target_properties(instance, state, openKind, offset, rotateDeg)
	return Close.get_target(instance, state, Utils, openKind, offset, rotateDeg)
end

local function should_fade_contents(instance, openKind)
	if instance:IsA("CanvasGroup") then
		return false
	end

	local configuredFade = instance:GetAttribute("open_fade")
	if configuredFade ~= nil then
		return configuredFade == true
	end

	return Open.wants_fade(openKind)
end

local function play_content_fade(instance, state, duration, isOpening)
	local records = state.FadeRecords
	if not records then
		records = Fade.collect(instance)
		state.FadeRecords = records
	end

	if #records == 0 then
		return
	end

	if isOpening then
		Fade.set_hidden(records)
	end

	local fadeDuration = math.max(0.01, duration)
	local easingDirection = if isOpening then Enum.EasingDirection.Out else Enum.EasingDirection.In

	for _, record in ipairs(records) do
		local targetValue = if isOpening then record.Base else 1
		play_state_tween(
			record.Instance,
			state,
			{ [record.Property] = targetValue },
			fadeDuration,
			Enum.EasingStyle.Sine,
			easingDirection
		)
	end
end

local function play_open_stagger(instance)
	local stepDelay = get_number_attribute(instance, "open_stagger", DEFAULTS.open_stagger)
	if not stepDelay or stepDelay <= 0 then
		return
	end

	local container = instance
	local targetName = instance:GetAttribute("stagger_target")
	if type(targetName) == "string" and targetName ~= "" then
		local found = instance:FindFirstChild(targetName, true)
		if found and found:IsA("GuiObject") then
			container = found
		end
	end

	Stagger.play(container, {
		Delay = stepDelay,
		Duration = get_number_attribute(instance, "stagger_t", DEFAULTS.stagger_t),
		StartScale = get_number_attribute(instance, "stagger_scale", DEFAULTS.stagger_scale),
	})
end

local function play_open(instance, state, force)
	if not instance or not instance.Parent or has_true_attribute(instance, IGNORE_HUD_ANIM_ATTRIBUTE) then
		return
	end

	if instance:GetAttribute("UIOpen") ~= true and not force then
		return
	end

	capture_base_state(instance, state, false)
	track_base_changes(instance, state)
	state.TransitionToken += 1
	local token = state.TransitionToken
	cancel_state_tweens(state)

	state.Opening = true
	state.Closing = false
	instance:SetAttribute("_is_closing", nil)
	set_visible_silent(instance, state, true)

	local duration = math.max(0, get_number_attribute(instance, "open_t", DEFAULTS.open_t))
	local openKind = instance:GetAttribute("open_anim") or "pop"
	local offset = get_number_attribute(instance, "open_offset_px", DEFAULTS.open_offset_px)
	local popScale = math.clamp(get_number_attribute(instance, "open_pop_scale", DEFAULTS.open_pop_scale), 0.001, 1)
	local rotateDeg = get_number_attribute(instance, "open_rotate_deg", Open.get_default_rotation(openKind))
	local blurAmount = get_optional_number_attribute(instance, "blur")
	local fovAmount = get_optional_number_attribute(instance, "fov")

	if sync_hud_visibility_for_frame then
		sync_hud_visibility_for_frame(instance, get_number_attribute(instance, "hud_fade_t", DEFAULTS.hud_fade_t), instance)
	end

	if duration <= 0 or openKind == "none" then
		finish_open(instance, state, token)
		return
	end

	apply_open_start(instance, state, openKind, offset, popScale, rotateDeg)

	if should_fade_contents(instance, openKind) then
		play_content_fade(instance, state, duration * 0.85, true)
	end

	if blurAmount and blurAmount > 0 then
		tween_blur(blurAmount, get_number_attribute(instance, "blur_t", duration))
	end

	if fovAmount then
		tween_camera_fov(fovAmount, duration)
	end

	safe_play_sound(instance, "sfx_open")
	play_open_stagger(instance)
	play_state_tween(
		instance,
		state,
		build_open_target_properties(instance, state),
		duration,
		Utils.get_easing_style(instance, "open_ease", Open.get_default_easing(openKind)),
		Enum.EasingDirection.Out,
		function()
			finish_open(instance, state, token)
		end
	)
end

local function request_close(instance, state, force)
	if not instance or not instance.Parent or has_true_attribute(instance, IGNORE_HUD_ANIM_ATTRIBUTE) then
		return
	end

	if instance:GetAttribute("UIOpen") ~= true and not force then
		set_visible_silent(instance, state, false)
		return
	end

	if state.Closing then
		set_visible_silent(instance, state, true)
		return
	end

	capture_base_state(instance, state, false)
	track_base_changes(instance, state)
	state.TransitionToken += 1
	local token = state.TransitionToken
	cancel_state_tweens(state)

	state.Opening = false
	state.Closing = true
	instance:SetAttribute("_is_closing", true)
	set_visible_silent(instance, state, true)

	local duration = math.max(0, get_number_attribute(instance, "open_t", DEFAULTS.open_t) * 0.75)
	local openKind = instance:GetAttribute("open_anim") or "pop"
	local offset = get_number_attribute(instance, "open_offset_px", DEFAULTS.open_offset_px) * 1.15
	local rotateDeg = get_number_attribute(instance, "open_rotate_deg", Open.get_default_rotation(openKind))
	local blurAmount = get_optional_number_attribute(instance, "blur")

	if sync_hud_visibility_for_frame then
		task.defer(function()
			sync_hud_visibility_for_frame(instance, get_number_attribute(instance, "hud_fade_t", DEFAULTS.hud_fade_t))
		end)
	end

	if blurAmount and blurAmount > 0 then
		tween_blur(0, get_number_attribute(instance, "blur_t", duration))
	end

	if get_optional_number_attribute(instance, "fov") then
		tween_camera_fov(70, duration)
	end

	safe_play_sound(instance, "sfx_close")

	if duration <= 0 or openKind == "none" then
		finish_close(instance, state, token)
		return
	end

	if should_fade_contents(instance, openKind) then
		play_content_fade(instance, state, duration, false)
	end

	play_state_tween(
		instance,
		state,
		build_close_target_properties(instance, state, openKind, offset, rotateDeg),
		duration,
		Utils.get_easing_style(instance, "close_ease", Enum.EasingStyle.Quint),
		Enum.EasingDirection.In,
		function()
			finish_close(instance, state, token)
		end
	)
end

local function is_modal_frame(instance)
	return instance
		and instance:IsA("GuiObject")
		and instance.Parent ~= nil
		and instance.Parent.Name == FRAMES_CONTAINER_NAME
end

local function register_modal_route(instance, state)
	if state.RouteRegistered or not is_modal_frame(instance) then
		return
	end

	state.RouteRegistered = true
	state.RouteCleanup = UIRouter.Register(instance.Name, {
		Layer = "Modal",
		Exclusive = true,
		SetOpen = function(isOpen, animate)
			if states[instance] ~= state or not instance.Parent then
				return
			end

			if has_true_attribute(instance, IGNORE_HUD_ANIM_ATTRIBUTE) then
				instance.Visible = isOpen
				return
			end

			if animate == false or instance:GetAttribute("UIOpen") ~= true then
				reset_transition(instance, state)
				set_visible_silent(instance, state, isOpen)
				if sync_hud_visibility_for_frame then
					sync_hud_visibility_for_frame(
						instance,
						get_number_attribute(instance, "hud_fade_t", DEFAULTS.hud_fade_t),
						if isOpen then instance else nil
					)
				end
			elseif isOpen then
				play_open(instance, state, true)
			else
				request_close(instance, state, true)
			end
		end,
	}, instance.Visible)

	state.Connections[#state.Connections + 1] = instance:GetPropertyChangedSignal("Visible"):Connect(function()
		if state.IgnoreRouteVisibleChanges > 0 then
			state.IgnoreRouteVisibleChanges -= 1
			return
		end

		UIRouter.Sync(instance.Name, instance.Visible)
	end)
end

local function bind_open_animation(instance, state)
	if state.BoundOpen or instance:GetAttribute("UIOpen") ~= true then
		return
	end

	state.BoundOpen = true
	capture_base_state(instance, state, false)
	track_base_changes(instance, state)

	state.Connections[#state.Connections + 1] = instance:GetPropertyChangedSignal("Visible"):Connect(function()
		if state.IgnoreVisibleChanges > 0 then
			state.IgnoreVisibleChanges -= 1
			state.LastVisible = instance.Visible
			return
		end

		if has_true_attribute(instance, IGNORE_HUD_ANIM_ATTRIBUTE) or instance:GetAttribute("UIOpen") ~= true then
			state.LastVisible = instance.Visible
			return
		end

		if instance.Visible then
			if instance:GetAttribute("skip_open") then
				instance:SetAttribute("skip_open", nil)
				reset_transition(instance, state)
				state.LastVisible = true
				sync_hud_visibility_for_frame(
					instance,
					get_number_attribute(instance, "hud_fade_t", DEFAULTS.hud_fade_t),
					instance
				)
				return
			end

			state.LastVisible = true
			play_open(instance, state)
		else
			if instance:GetAttribute("skip_close") then
				instance:SetAttribute("skip_close", nil)
				reset_transition(instance, state)
				state.LastVisible = false
				task.defer(function()
					sync_hud_visibility_for_frame(instance, get_number_attribute(instance, "hud_fade_t", DEFAULTS.hud_fade_t))
				end)
				return
			end

			state.LastVisible = false
			request_close(instance, state)
		end
	end)

	if instance:GetAttribute("open_on_bind") == true and instance.Visible then
		task.defer(function()
			if states[instance] == state and instance.Parent and instance.Visible then
				play_open(instance, state, true)
			end
		end)
	end
end

local function find_named_ancestor(instance, targetName)
	local current = instance
	while current do
		if current.Name == targetName then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function find_main_ui(instance)
	local ancestor = find_named_ancestor(instance, MAIN_UI_NAME)
	if ancestor then
		return ancestor
	end

	local playerGui = get_player_gui()
	if playerGui then
		return playerGui:FindFirstChild(MAIN_UI_NAME) or playerGui:FindFirstChild(MAIN_UI_NAME, true)
	end

	return nil
end

local function find_mainframe(instance)
	local mainUi = find_main_ui(instance)
	if not mainUi then
		return nil
	end

	for _, mainframeName in ipairs(MAINFRAME_NAMES) do
		local direct = mainUi:FindFirstChild(mainframeName)
		if direct then
			return direct
		end
	end

	for _, mainframeName in ipairs(MAINFRAME_NAMES) do
		local nested = mainUi:FindFirstChild(mainframeName, true)
		if nested then
			return nested
		end
	end

	return nil
end

local function find_frames_container(instance)
	local mainframe = find_mainframe(instance)
	if not mainframe then
		return nil
	end

	return mainframe:FindFirstChild(FRAMES_CONTAINER_NAME) or mainframe:FindFirstChild(FRAMES_CONTAINER_NAME, true)
end

local function find_hud_root(instance)
	local mainframe = find_mainframe(instance)
	if not mainframe then
		return nil
	end

	local direct = mainframe:FindFirstChild(HUD_ROOT_NAME)
	if direct and direct:IsA("GuiObject") then
		return direct
	end

	local nested = mainframe:FindFirstChild(HUD_ROOT_NAME, true)
	if nested and nested:IsA("GuiObject") then
		return nested
	end

	return nil
end

local function get_top_level_frame_in_container(instance, framesContainer)
	local current = instance
	while current and framesContainer and current ~= framesContainer do
		if current.Parent == framesContainer and current:IsA("GuiObject") then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function is_open_frame(frame)
	local state = frame and states[frame]
	return frame ~= nil
		and frame:IsA("GuiObject")
		and frame.Visible
		and not (state and state.Closing)
		and not has_true_attribute(frame, IGNORE_HUD_ANIM_ATTRIBUTE)
end

local function get_open_frame_for_hud(instance, forcedOpenFrame)
	local framesContainer = find_frames_container(instance or forcedOpenFrame)
	if not framesContainer then
		return if is_open_frame(forcedOpenFrame) then forcedOpenFrame else nil
	end

	local forcedTopLevelFrame = get_top_level_frame_in_container(forcedOpenFrame, framesContainer)
	if forcedTopLevelFrame and is_open_frame(forcedTopLevelFrame) then
		return forcedTopLevelFrame
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if is_open_frame(child) then
			return child
		end
	end

	return if is_open_frame(forcedOpenFrame) then forcedOpenFrame else nil
end

local function parse_name_set(value)
	if type(value) ~= "string" then
		return nil
	end

	local names = {}
	for name in string.gmatch(value, "[^,%s;]+") do
		names[name] = true
	end

	return if next(names) then names else nil
end

local function get_hud_fade_excluded_names(openFrame)
	if not openFrame then
		return nil
	end

	local configuredValue = openFrame:GetAttribute(HUD_FADE_EXCLUSIONS_ATTRIBUTE)
	if type(configuredValue) == "string" then
		return parse_name_set(configuredValue) or {}
	end

	return DEFAULT_HUD_EXCLUSIONS_BY_FRAME[openFrame.Name]
end

local function has_exclusions(excludedNames)
	return excludedNames ~= nil and next(excludedNames) ~= nil
end

local function get_exclusion_key(excludedNames)
	if not excludedNames then
		return ""
	end

	local names = {}
	for name in pairs(excludedNames) do
		names[#names + 1] = name
	end
	table.sort(names)
	return table.concat(names, "|")
end

local function get_hud_fade_state(hudRoot)
	local fadeState = hudFadeStates[hudRoot]
	if fadeState then
		return fadeState
	end

	fadeState = {
		Originals = setmetatable({}, { __mode = "k" }),
		Token = 0,
		TargetHidden = nil,
		ExclusionKey = "",
	}
	hudFadeStates[hudRoot] = fadeState
	return fadeState
end

local function get_original_property(fadeState, instance, propertyName, fallback)
	local originals = fadeState.Originals[instance]
	if not originals then
		originals = {}
		fadeState.Originals[instance] = originals
	end

	if originals[propertyName] == nil then
		local success, value = pcall(function()
			return instance[propertyName]
		end)
		originals[propertyName] = if success then value else fallback
	end

	return originals[propertyName]
end

local function push_fade_record(records, fadeState, instance, propertyName, targetValue)
	local originalValue = get_original_property(fadeState, instance, propertyName, 0)
	records[#records + 1] = {
		Instance = instance,
		PropertyName = propertyName,
		OriginalValue = originalValue,
		TargetValue = targetValue,
	}
end

local function get_hud_fade_targets(hudRoot, fadeState, shouldHide)
	if shouldHide or not fadeState.Targets then
		fadeState.Targets = Fade.collect(hudRoot)
		return fadeState.Targets
	end

	local validTargets = {}
	for _, target in ipairs(fadeState.Targets) do
		if target.Instance and target.Instance.Parent then
			validTargets[#validTargets + 1] = target
		end
	end

	fadeState.Targets = validTargets
	return validTargets
end

local function collect_hud_fade_records(hudRoot, fadeState, shouldHide, excludedNames)
	local records = {}

	if has_exclusions(excludedNames) then
		return records
	end

	if hudRoot:IsA("CanvasGroup") then
		push_fade_record(records, fadeState, hudRoot, "GroupTransparency", if shouldHide then 1 else nil)
	else
		for _, target in ipairs(get_hud_fade_targets(hudRoot, fadeState, shouldHide)) do
			records[#records + 1] = {
				Instance = target.Instance,
				PropertyName = target.Property,
				OriginalValue = target.Base,
				TargetValue = if shouldHide then 1 else target.Base,
			}
		end
	end

	for _, record in ipairs(records) do
		if not shouldHide then
			record.TargetValue = record.OriginalValue
		end
	end

	return records
end

local function cancel_hud_fade(hudRoot)
	local tweens = hudFadeTweens[hudRoot]
	if not tweens then
		return
	end

	for _, tween in ipairs(tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end
	hudFadeTweens[hudRoot] = nil
end

local function set_record_value(record, useTarget)
	local instance = record.Instance
	if not instance or not instance.Parent then
		return
	end

	local value = if useTarget then record.TargetValue else record.OriginalValue
	pcall(function()
		instance[record.PropertyName] = value
	end)
end

local function fade_hud_root(hudRoot, shouldHide, duration, excludedNames)
	if not hudRoot or not hudRoot.Parent then
		return
	end

	local hasExclusions = has_exclusions(excludedNames)
	local fadeState = get_hud_fade_state(hudRoot)
	local exclusionKey = get_exclusion_key(excludedNames)
	if fadeState.TargetHidden == shouldHide and fadeState.ExclusionKey == exclusionKey then
		if not shouldHide or hasExclusions then
			hudRoot.Visible = true
		end
		return
	end

	fadeState.Token += 1
	local token = fadeState.Token
	fadeState.TargetHidden = shouldHide
	fadeState.ExclusionKey = exclusionKey

	cancel_hud_fade(hudRoot)
	hudRoot.Visible = true

	local fadeDuration = math.max(0, duration or DEFAULTS.hud_fade_t)
	local records = collect_hud_fade_records(hudRoot, fadeState, shouldHide, excludedNames)
	local keepHudVisible = shouldHide and hasExclusions

	if fadeDuration <= 0 or #records == 0 then
		for _, record in ipairs(records) do
			set_record_value(record, true)
		end
		hudRoot.Visible = keepHudVisible or not shouldHide
		return
	end

	local tweens = {}
	for _, record in ipairs(records) do
		local instance = record.Instance
		if instance and instance.Parent then
			local success, tween = pcall(function()
				return make_tween(
					instance,
					{ [record.PropertyName] = record.TargetValue },
					fadeDuration,
					Enum.EasingStyle.Quad,
					Enum.EasingDirection.Out
				)
			end)

			if success and tween then
				tweens[#tweens + 1] = tween
				tween:Play()
			end
		end
	end
	hudFadeTweens[hudRoot] = tweens

	task.delay(fadeDuration, function()
		if fadeState.Token ~= token or not hudRoot.Parent then
			return
		end

		hudFadeTweens[hudRoot] = nil
		for _, record in ipairs(records) do
			set_record_value(record, true)
		end
		hudRoot.Visible = keepHudVisible or not shouldHide
	end)
end

sync_hud_visibility_for_frame = function(instance, duration, forcedOpenFrame)
	local hudRoot = find_hud_root(instance or forcedOpenFrame)
	if not hudRoot then
		return
	end

	local openFrame = get_open_frame_for_hud(instance or hudRoot, forcedOpenFrame)
	fade_hud_root(hudRoot, openFrame ~= nil, duration, get_hud_fade_excluded_names(openFrame))
end

local function is_hud_button(button)
	if find_named_ancestor(button, HUD_ROOT_NAME) then
		return true
	end

	local mainUi = find_main_ui(button)
	if not mainUi then
		return false
	end

	local hudRoot = mainUi:FindFirstChild(HUD_ROOT_NAME) or mainUi:FindFirstChild(HUD_ROOT_NAME, true)
	return hudRoot ~= nil and button:IsDescendantOf(hudRoot)
end

local function get_target_frame_name(button)
	local buttonName = button.Name
	if CLOSE_BUTTON_NAMES[buttonName] then
		return nil
	end

	local configuredTarget = button:GetAttribute(TARGET_FRAME_ATTRIBUTE)
	if type(configuredTarget) == "string" and configuredTarget ~= "" then
		return configuredTarget
	end

	if #buttonName <= #BUTTON_SUFFIX or string.sub(buttonName, -#BUTTON_SUFFIX) ~= BUTTON_SUFFIX then
		return nil
	end

	return string.sub(buttonName, 1, #buttonName - #BUTTON_SUFFIX)
end

local function find_open_target(button)
	local frameName = get_target_frame_name(button)
	if not frameName then
		return nil
	end

	local framesContainer = find_frames_container(button)
	if not framesContainer then
		return nil
	end

	local target = framesContainer:FindFirstChild(frameName)
	return if target and target:IsA("GuiObject") then target else nil
end

local function hide_sibling_frames_without_animation(target)
	local framesContainer = target and target.Parent
	if not framesContainer then
		return
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if child ~= target and child:IsA("GuiObject") and child.Visible then
			local childState = states[child]
			if childState then
				reset_transition(child, childState)
				set_visible_silent(child, childState, false)
			else
				child.Visible = false
			end
		end
	end
end

local function show_target_frame(target)
	if not target or not target:IsA("GuiObject") then
		return
	end

	bind_instance(target)
	if UIRouter.Open(target.Name, true) then
		return
	end

	hide_sibling_frames_without_animation(target)

	local targetState = states[target]
	if targetState and targetState.Closing then
		play_open(target, targetState, true)
	elseif target.Visible then
		-- Already open; only refresh HUD visibility below.
	else
		target.Visible = true
	end

	sync_hud_visibility_for_frame(target, get_number_attribute(target, "hud_fade_t", DEFAULTS.hud_fade_t), target)
end

local function find_exit_target(button)
	local framesContainer = find_frames_container(button)
	local configuredTarget = button:GetAttribute(CLOSE_TARGET_ATTRIBUTE)
	if framesContainer and type(configuredTarget) == "string" and configuredTarget ~= "" then
		local target = framesContainer:FindFirstChild(configuredTarget)
		if target and target:IsA("GuiObject") then
			return target
		end
	end

	local mainframe = find_mainframe(button)
	if not mainframe then
		return nil
	end

	local current = button.Parent
	while current and current ~= mainframe do
		if framesContainer and current.Parent == framesContainer and current:IsA("GuiObject") then
			return current
		end

		if current.Parent == mainframe and current:IsA("GuiObject") then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function bind_auto_open_button(button, state)
	if state.BoundAutoOpenButton or not is_hud_button(button) or not get_target_frame_name(button) then
		return
	end

	state.BoundAutoOpenButton = true
	state.Connections[#state.Connections + 1] = button.Activated:Connect(function()
		if has_true_attribute(button, IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE)
			or has_true_attribute(button, IGNORE_HUD_ANIM_ATTRIBUTE)
		then
			return
		end

		local target = find_open_target(button)
		if target then
			show_target_frame(target)
		end
	end)
end

local function bind_exit_button(button, state)
	if state.BoundExitButton or not CLOSE_BUTTON_NAMES[button.Name] then
		return
	end

	state.BoundExitButton = true
	state.Connections[#state.Connections + 1] = button.Activated:Connect(function()
		if has_true_attribute(button, IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE)
			or has_true_attribute(button, IGNORE_HUD_ANIM_ATTRIBUTE)
		then
			return
		end

		local target = find_exit_target(button)
		if not target then
			return
		end

		if has_true_attribute(target, IGNORE_HUD_ANIM_ATTRIBUTE) then
			target.Visible = false
		else
			bind_instance(target)
			if not UIRouter.Close(target.Name, true) then
				local targetState = states[target] or get_or_create_state(target)
				request_close(target, targetState, true)
			end
		end

		task.defer(function()
			sync_hud_visibility_for_frame(target, DEFAULTS.hud_fade_t)
		end)
	end)
end

bind_instance = function(instance)
	if not instance or not instance:IsA("GuiObject") then
		return
	end

	if has_true_attribute(instance, IGNORE_HUD_ANIM_ATTRIBUTE) then
		HudAnim.unbind(instance)
		return
	end

	local isButton = instance:IsA("GuiButton")
	local hasButtonAnimation = isButton and should_animate_button(instance)
	local hasOpenAnimation = instance:GetAttribute("UIOpen") == true
	local hasModalRoute = is_modal_frame(instance)
	local hasAutoButton = isButton
		and (CLOSE_BUTTON_NAMES[instance.Name] or (is_hud_button(instance) and get_target_frame_name(instance)))

	if not hasButtonAnimation and not hasOpenAnimation and not hasAutoButton and not hasModalRoute then
		return
	end

	local state = get_or_create_state(instance)
	register_modal_route(instance, state)

	if isButton then
		if CLOSE_BUTTON_NAMES[instance.Name] then
			bind_exit_button(instance, state)
		else
			bind_auto_open_button(instance, state)
		end
		bind_button_animation(instance, state)
	end

	bind_open_animation(instance, state)

	if not state.AncestryConnectionBound then
		state.AncestryConnectionBound = true
		state.Connections[#state.Connections + 1] = instance.AncestryChanged:Connect(function(_, parent)
			if not parent then
				HudAnim.unbind(instance)
			end
		end)
	end
end

function HudAnim.set_defaults(options)
	if type(options) ~= "table" then
		return
	end

	for key, value in pairs(options) do
		DEFAULTS[key] = value
	end

	if SFX and type(SFX.set_defaults) == "function" then
		SFX.set_defaults(options)
	end
end

function HudAnim.preload_sfx()
	if SFX and type(SFX.preload_defaults) == "function" then
		return SFX.preload_defaults()
	end

	return true
end

function HudAnim.apply_defaults_to_buttons(root, extra)
	if not root then
		return
	end

	local function apply_to_button(button)
		if button:IsA("GuiButton") and not has_true_attribute(button, IGNORE_HUD_ANIM_ATTRIBUTE) then
			button:SetAttribute("UIAnim", true)
			apply_defaults(button)

			if type(extra) == "table" then
				for key, value in pairs(extra) do
					button:SetAttribute(key, value)
				end
			end
		end
	end

	apply_to_button(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		apply_to_button(descendant)
	end
end

function HudAnim.stagger_children(container, options)
	Stagger.play(container, options)
end

function HudAnim.cancel_stagger(container)
	Stagger.cancel(container)
end

function HudAnim.punch(instance, options)
	Punch.play(instance, options)
end

function HudAnim.get_ui_scale(instance, name)
	return Utils.get_ui_scale(instance, name)
end

function HudAnim.sync_hud_visibility_for_frame(instance, duration, forcedOpenFrame)
	sync_hud_visibility_for_frame(instance, duration, forcedOpenFrame)
end

function HudAnim.bind(instance)
	bind_instance(instance)
end

function HudAnim.unbind(instance)
	if not instance or not instance:IsA("GuiObject") then
		return
	end

	local state = states[instance]
	if not state then
		return
	end

	states[instance] = nil
	if state.RouteCleanup then
		state.RouteCleanup()
		state.RouteCleanup = nil
		state.RouteRegistered = false
	end
	state.TransitionToken += 1
	cancel_state_tweens(state)
	disconnect_connections(state.Connections)
	restore_instance(instance, state)
	instance:SetAttribute("_is_closing", nil)
end

function HudAnim.bind_all(root)
	if not root then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			bind_instance(descendant)
		end
	end
end

function HudAnim.unbind_all(root)
	if not root then
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			HudAnim.unbind(descendant)
		end
	end
end

function HudAnim.refresh_baseline(instance)
	if not instance or not instance:IsA("GuiObject") then
		return
	end

	local state = get_or_create_state(instance)
	capture_base_state(instance, state, true)
end

function HudAnim.play_open(instance)
	if not instance or not instance:IsA("GuiObject") then
		return
	end

	bind_instance(instance)
	if is_modal_frame(instance) and UIRouter.Open(instance.Name, true) then
		return
	end
	local state = states[instance] or get_or_create_state(instance)
	play_open(instance, state, true)
end

function HudAnim.play_close(instance)
	if not instance or not instance:IsA("GuiObject") then
		return
	end

	bind_instance(instance)
	if is_modal_frame(instance) and UIRouter.Close(instance.Name, true) then
		return
	end
	local state = states[instance] or get_or_create_state(instance)
	request_close(instance, state, true)
end

function HudAnim.set_visible(instance, isVisible, animate)
	if not instance or not instance:IsA("GuiObject") then
		return
	end

	bind_instance(instance)
	local state = states[instance] or get_or_create_state(instance)
	if is_modal_frame(instance) and UIRouter.IsRegistered(instance.Name) then
		if isVisible then
			UIRouter.Open(instance.Name, animate ~= false)
		else
			UIRouter.Close(instance.Name, animate ~= false)
		end
		return
	end

	if animate == false then
		reset_transition(instance, state)
		set_visible_silent(instance, state, isVisible == true)
	elseif isVisible then
		play_open(instance, state, true)
	else
		request_close(instance, state, true)
	end
end

return HudAnim
