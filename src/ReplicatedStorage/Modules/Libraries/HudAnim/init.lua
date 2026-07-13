local Players: Players = game:GetService("Players")
local GuiService: GuiService = game:GetService("GuiService")
local UserInputService: UserInputService = game:GetService("UserInputService")
local TweenService: TweenService = game:GetService("TweenService")

------------------//VARIABLES
local localPlayer: Player = Players.LocalPlayer
local playerGui: PlayerGui = localPlayer.PlayerGui

local Utils = require(script.Utils)
local SFX = require(script.SFX)
local Pulse = require(script.Pulse)
local Rotate = require(script.Rotate)
local Hover = require(script.Hover)
local Click = require(script.Click)
local Open = require(script.Open)
local Close = require(script.Close)

local HudAnim = {}
local bound = {}
local state = {}
local running_open = {} -- Armazena as tasks de abertura
local exit_connections = {}
local open_connections = {}

local EXIT_BUTTON_NAME = "ExitBT"
local BUTTON_SUFFIX = "BT"
local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"
local HUD_ROOT_NAME = "HUDFR"
local FRAMES_CONTAINER_NAME = "Frames"

local DEFAULTS = {
	hover_scale = 0.08,
	click_scale = 0.1,
	hover_t = 0.3,
	click_t = 0.15,
	rotate_hover_deg = 3,
	pulse = false,
	open_t = 0.5,
	open_offset_px = 50,
	open_pop_scale = 0.85,
	blur = 18,
	blur_t = 0.5,
}

------------------//FUNCTIONS
local function apply_defaults(inst: GuiObject): ()
	for k, v in DEFAULTS do
		if inst:GetAttribute(k) == nil then
			inst:SetAttribute(k, v)
		end
	end
end

local function wants_hover(g: GuiObject): boolean
	if not g.Visible then
		return false
	end

	if g:GetAttribute("UIAnim") ~= true and g:GetAttribute("UIAnimPreset") == nil then
		return false
	end

	if g.AbsoluteSize.X <= 0 or g.AbsoluteSize.Y <= 0 then
		return false
	end

	return true
end

local function screen_point(): Vector2
	local mouse = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	return Vector2.new(mouse.X - inset.X, mouse.Y - inset.Y)
end

local function visible_in_hierarchy(g: GuiObject): boolean
	local cur: Instance? = g
	while cur and cur:IsA("GuiObject") do
		if not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	local sg = g:FindFirstAncestorWhichIsA("ScreenGui")
	if sg and sg.Enabled == false then
		return false
	end
	return true
end

local function topmost_gui_at_pointer(): GuiObject?
	local p = screen_point()
	local list = playerGui:GetGuiObjectsAtPosition(p.X, p.Y)
	for _, g in list do
		if g and visible_in_hierarchy(g) and wants_hover(g) then
			return g
		end
	end
	return nil
end

local function should_run_hover_for(inst: GuiObject): boolean
	local top = topmost_gui_at_pointer()
	if not top then
		return false
	end
	if top == inst then
		return true
	end
	if top:IsDescendantOf(inst) then
		return true
	end
	return false
end

local function safe_play(inst: Instance, key: string): ()
	if not SFX or not SFX.play_for then
		return
	end

	SFX.play_for(inst, key)
end

local function get_number_attribute(inst: Instance, attributeName: string, fallback: number): number
	local value = inst:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	local convertedValue = tonumber(value)
	if convertedValue ~= nil then
		return convertedValue
	end

	return fallback
end

local function cleanup_exit_button(button: GuiButton): ()
	local connection = exit_connections[button]
	if not connection then
		return
	end

	connection:Disconnect()
	exit_connections[button] = nil
end

local function cleanup_open_button(button: GuiButton): ()
	local connection = open_connections[button]
	if not connection then
		return
	end

	connection:Disconnect()
	open_connections[button] = nil
end

local function find_named_ancestor(instance: Instance?, targetName: string): Instance?
	local current = instance

	while current do
		if current.Name == targetName then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function find_main_ui(instance: Instance?): Instance?
	local ancestor = find_named_ancestor(instance, MAIN_UI_NAME)
	if ancestor then
		return ancestor
	end

	local directMainUi = playerGui:FindFirstChild(MAIN_UI_NAME)
	if directMainUi then
		return directMainUi
	end

	return playerGui:FindFirstChild(MAIN_UI_NAME, true)
end

local function find_mainframe(instance: Instance?): Instance?
	local mainUi = find_main_ui(instance)
	if not mainUi then
		return nil
	end

	local directMainframe = mainUi:FindFirstChild(MAINFRAME_NAME)
	if directMainframe then
		return directMainframe
	end

	return mainUi:FindFirstChild(MAINFRAME_NAME, true)
end

local function find_frames_container(instance: Instance?): Instance?
	local mainframe = find_mainframe(instance)
	if not mainframe then
		return nil
	end

	local directFrames = mainframe:FindFirstChild(FRAMES_CONTAINER_NAME)
	if directFrames then
		return directFrames
	end

	return mainframe:FindFirstChild(FRAMES_CONTAINER_NAME, true)
end

local function is_hud_button(button: GuiButton): boolean
	local hudRoot = find_named_ancestor(button, HUD_ROOT_NAME)
	if hudRoot then
		return true
	end

	local mainUi = find_main_ui(button)
	if not mainUi then
		return false
	end

	local directHudRoot = mainUi:FindFirstChild(HUD_ROOT_NAME)
	if directHudRoot and button:IsDescendantOf(directHudRoot) then
		return true
	end

	local nestedHudRoot = mainUi:FindFirstChild(HUD_ROOT_NAME, true)
	return nestedHudRoot ~= nil and button:IsDescendantOf(nestedHudRoot)
end

local function get_target_frame_name(button: GuiButton): string?
	local buttonName = button.Name
	if buttonName == EXIT_BUTTON_NAME then
		return nil
	end

	if string.len(buttonName) <= string.len(BUTTON_SUFFIX) then
		return nil
	end

	if string.sub(buttonName, -string.len(BUTTON_SUFFIX)) ~= BUTTON_SUFFIX then
		return nil
	end

	return string.sub(buttonName, 1, #buttonName - string.len(BUTTON_SUFFIX))
end

local function find_open_target(button: GuiButton): GuiObject?
	local frameName = get_target_frame_name(button)
	if not frameName then
		return nil
	end

	local framesContainer = find_frames_container(button)
	if not framesContainer then
		return nil
	end

	local target = framesContainer:FindFirstChild(frameName)
	if target and target:IsA("GuiObject") then
		return target
	end

	return nil
end

local function show_target_frame(target: GuiObject): ()
	local framesContainer = target.Parent
	if not framesContainer then
		target.Visible = true
		return
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if child ~= target and child:IsA("GuiObject") then
			child.Visible = false
		end
	end

	target.Visible = true
end

local function find_exit_target(button: GuiButton): GuiObject?
	local mainframe = find_mainframe(button)
	if not mainframe then
		return nil
	end

	local framesContainer = find_frames_container(button)
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

local function bind_open_button(button: GuiButton): ()
	if open_connections[button] then
		return
	end

	if not is_hud_button(button) or not get_target_frame_name(button) then
		return
	end

	open_connections[button] = button.Activated:Connect(function()
		local target = find_open_target(button)
		if not target then
			return
		end

		show_target_frame(target)
	end)

	button.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		cleanup_open_button(button)
	end)
end

local function bind_exit_button(button: GuiButton): ()
	if exit_connections[button] then
		return
	end

	exit_connections[button] = button.Activated:Connect(function()
		local target = find_exit_target(button)
		if not target then
			return
		end

		target.Visible = false
	end)

	button.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		cleanup_exit_button(button)
	end)
end

------------------//MAIN FUNCTIONS
function HudAnim.set_defaults(opts: {}): ()
	for k, v in opts do
		DEFAULTS[k] = v
	end
	SFX.set_defaults(opts)
end

function HudAnim.apply_defaults_to_buttons(root: Instance, extra: {}?): ()
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") then
			d:SetAttribute("UIAnim", true)
			apply_defaults(d)
			if extra then
				for k, v in extra do
					d:SetAttribute(k, v)
				end
			end
		end
	end
end

function HudAnim.bind(inst: GuiObject): ()
	if inst:IsA("GuiButton") then
		if inst.Name == EXIT_BUTTON_NAME then
			bind_exit_button(inst)
		else
			bind_open_button(inst)
		end
	end

	if bound[inst] then
		return
	end
	if not (inst:GetAttribute("UIAnim") or inst:GetAttribute("UIAnimPreset") or inst:GetAttribute("UIOpen")) then
		return
	end
	bound[inst] = true

	state[inst] = {
		origSize = inst.Size,
		origPos = inst.Position,
		origRot = inst.Rotation,
		origBg = (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("Frame")) and inst.BackgroundColor3 or nil,
		origImg = (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) and inst.ImageColor3 or nil,
		hovering = false,
	}

	apply_defaults(inst)
	Rotate.on_bind(inst, state[inst], Utils)

	Close.bind(inst, state[inst], Utils, SFX)

	if inst:IsA("GuiObject") then
		inst.Active = true
	end

	inst.MouseEnter:Connect(function()
		local st = state[inst]
		if not st then
			return
		end
		if should_run_hover_for(inst) and wants_hover(inst) and not st.hovering then
			st.hovering = true
			Hover.on_hover(inst, st, Utils, SFX, Pulse)
		end
	end)

	inst.MouseLeave:Connect(function()
		local st = state[inst]
		if not st then
			return
		end
		if st.hovering and wants_hover(inst) then
			st.hovering = false
			Hover.on_rest(inst, st, Utils, Pulse)
		end
	end)

	inst.MouseMoved:Connect(function()
		local st = state[inst]
		if not st then
			return
		end

		if should_run_hover_for(inst) and wants_hover(inst) then
			if not st.hovering then
				st.hovering = true
				Hover.on_hover(inst, st, Utils, SFX, Pulse)
			end
		else
			if st.hovering then
				st.hovering = false
				Hover.on_rest(inst, st, Utils, Pulse)
			end
		end
	end)

	if inst:IsA("GuiButton") then
		inst.MouseButton1Down:Connect(function()
			local st = state[inst]
			if not st then
				return
			end

			Click.on_down(inst, st, Utils, SFX)
		end)
		inst.MouseButton1Up:Connect(function()
			local st = state[inst]
			if not st then
				return
			end

			Click.on_up(inst, st, Utils, SFX)
		end)
	end

	inst.SelectionGained:Connect(function()
		if not wants_hover(inst) then
			return
		end

		local st = state[inst]
		if not st then
			return
		end

		safe_play(inst, "sfx_select")

		if not st.hovering then
			st.hovering = true
			Hover.on_hover(inst, st, Utils, SFX, Pulse)
		end
	end)

	inst.SelectionLost:Connect(function()
		if not wants_hover(inst) then
			return
		end

		local st = state[inst]
		if not st then
			return
		end

		safe_play(inst, "sfx_deselect")

		if st.hovering then
			st.hovering = false
			Hover.on_rest(inst, st, Utils, Pulse)
		end
	end)

	if inst:GetAttribute("UIOpen") and inst:GetAttribute("open_on_bind") then
		inst.Visible = false
		inst:SetAttribute("skip_open", true)

		if running_open[inst] then
			task.cancel(running_open[inst])
		end

		running_open[inst] = task.spawn(function()
			Open.run(inst, state[inst], Utils, SFX)
			task.wait(get_number_attribute(inst, "open_t", DEFAULTS.open_t))
			running_open[inst] = nil
		end)
	end

	inst:GetPropertyChangedSignal("Visible"):Connect(function()
		if not inst:GetAttribute("UIOpen") then
			return
		end

		if inst.Visible then
			if inst:GetAttribute("skip_open") then
				inst:SetAttribute("skip_open", nil)
				return
			end

			if running_open[inst] then
				task.cancel(running_open[inst])
				running_open[inst] = nil
			end

			running_open[inst] = task.spawn(function()
				Open.run(inst, state[inst], Utils, SFX)
				task.wait(get_number_attribute(inst, "open_t", DEFAULTS.open_t))
				running_open[inst] = nil
			end)
		else
			if running_open[inst] then
				task.cancel(running_open[inst])
				running_open[inst] = nil
			end
		end
	end)

	inst.AncestryChanged:Connect(function(_, p)
		if not p then
			HudAnim.unbind(inst)
		end
	end)
end

function HudAnim.unbind(inst: GuiObject): ()
	if inst:IsA("GuiButton") then
		cleanup_open_button(inst)
		if inst.Name == EXIT_BUTTON_NAME then
			cleanup_exit_button(inst)
		end
	end

	local st = state[inst]
	if not st then
		return
	end

	Pulse.stop(inst, st)

	if running_open[inst] then
		task.cancel(running_open[inst])
		running_open[inst] = nil
	end

	state[inst] = nil
	bound[inst] = nil
end

function HudAnim.bind_all(root: Instance): ()
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			HudAnim.bind(d)
		end
	end
end

function HudAnim.unbind_all(root: Instance): ()
	for _, d in root:GetDescendants() do
		if d:IsA("GuiObject") then
			HudAnim.unbind(d)
		end
	end
end

------------------//INIT
return HudAnim