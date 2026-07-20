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
local running_open = {} 
local exit_connections = {}
local open_connections = {}
local hud_fade_states = {}
local hud_fade_tweens = {}

local EXIT_BUTTON_NAME = "ExitBT"
local BUTTON_SUFFIX = "BT"
local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAMES = { "MainframeFR", "MainFrameFR" }
local HUD_ROOT_NAME = "HUDFR"
local HOTBAR_ROOT_NAME = "BottomFrameFR"
local MONEY_TAB_NAME = "MoneyTabBG"
local FRAMES_CONTAINER_NAME = "Frames"
local INVENTORY_FRAME_NAME = "Inventory"
local SHOP_FRAME_NAMES = {
	SeedShop = true,
	FruitShop = true,
	Seller = true,
	Shop = true,
}
local IGNORE_HUD_ANIM_ATTRIBUTE = "IgnoreHudAnim"
local IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE = "IgnoreAutoFrameButton"
local INVENTORY_HUD_FADE_EXCLUDED_NAMES = {
	[HOTBAR_ROOT_NAME] = true,
}
local SHOP_HUD_FADE_EXCLUDED_NAMES = {
	[MONEY_TAB_NAME] = true,
}

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
	hud_fade_t = 0.15,
}

------------------//FUNCTIONS
local function apply_defaults(inst: GuiObject): ()
	for k, v in DEFAULTS do
		if inst:GetAttribute(k) == nil then
			inst:SetAttribute(k, v)
		end
	end
end

local function has_true_attribute(instance: Instance?, attributeName: string): boolean
	local current = instance

	while current do
		if current:GetAttribute(attributeName) == true then
			return true
		end

		current = current.Parent
	end

	return false
end

local function wants_hover(g: GuiObject): boolean
	if not g.Visible then
		return false
	end

	if has_true_attribute(g, IGNORE_HUD_ANIM_ATTRIBUTE) then
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

local function restore_state(inst: GuiObject, st): ()
	if not inst or not inst.Parent or not st then
		return
	end

	pcall(function()
		inst.Size = st.origSize
		inst.Position = st.origPos
		inst.Rotation = st.origRot

		if st.origBg and (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("Frame")) then
			inst.BackgroundColor3 = st.origBg
		end

		if st.origImg and (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) then
			inst.ImageColor3 = st.origImg
		end
	end)
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

	for _, mainframeName in ipairs(MAINFRAME_NAMES) do
		local directMainframe = mainUi:FindFirstChild(mainframeName)
		if directMainframe then
			return directMainframe
		end
	end

	for _, mainframeName in ipairs(MAINFRAME_NAMES) do
		local nestedMainframe = mainUi:FindFirstChild(mainframeName, true)
		if nestedMainframe then
			return nestedMainframe
		end
	end

	return nil
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

local function find_hud_root(instance: Instance?): GuiObject?
	local mainframe = find_mainframe(instance)
	if not mainframe then
		return nil
	end

	local directHudRoot = mainframe:FindFirstChild(HUD_ROOT_NAME)
	if directHudRoot and directHudRoot:IsA("GuiObject") then
		return directHudRoot
	end

	local nestedHudRoot = mainframe:FindFirstChild(HUD_ROOT_NAME, true)
	if nestedHudRoot and nestedHudRoot:IsA("GuiObject") then
		return nestedHudRoot
	end

	return nil
end

local function get_top_level_frame_in_container(instance: Instance?, framesContainer: Instance?): GuiObject?
	local current = instance

	while current and framesContainer and current ~= framesContainer do
		if current.Parent == framesContainer and current:IsA("GuiObject") then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function is_open_frame(frame: Instance?): boolean
	return frame ~= nil
		and frame:IsA("GuiObject")
		and frame.Visible
		and frame:GetAttribute("_is_closing") ~= true
		and not has_true_attribute(frame, IGNORE_HUD_ANIM_ATTRIBUTE)
end

local function get_open_frame_for_hud(instance: Instance?, forcedOpenFrame: GuiObject?): GuiObject?
	local framesContainer = find_frames_container(instance or forcedOpenFrame)
	if not framesContainer then
		if is_open_frame(forcedOpenFrame) then
			return forcedOpenFrame
		end

		return nil
	end

	local forcedTopLevelFrame = get_top_level_frame_in_container(forcedOpenFrame, framesContainer)
	if forcedTopLevelFrame then
		return forcedTopLevelFrame
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if is_open_frame(child) then
			return child
		end
	end

	if is_open_frame(forcedOpenFrame) then
		return forcedOpenFrame
	end

	return nil
end

local function get_hud_fade_excluded_names(openFrame: GuiObject?): { [string]: boolean }?
	if openFrame and openFrame.Name == INVENTORY_FRAME_NAME then
		return INVENTORY_HUD_FADE_EXCLUDED_NAMES
	end

	if openFrame and SHOP_FRAME_NAMES[openFrame.Name] == true then
		return SHOP_HUD_FADE_EXCLUDED_NAMES
	end

	return nil
end

local function has_hud_fade_exclusions(excludedNames: { [string]: boolean }?): boolean
	if not excludedNames then
		return false
	end

	return next(excludedNames) ~= nil
end

local function get_hud_fade_exclusion_key(excludedNames: { [string]: boolean }?): string
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

local function is_in_excluded_hud_subtree(
	instance: Instance?,
	hudRoot: GuiObject,
	excludedNames: { [string]: boolean }?
): boolean
	if not instance or not excludedNames then
		return false
	end

	local current = instance
	while current and current ~= hudRoot do
		if excludedNames[current.Name] == true then
			return true
		end

		current = current.Parent
	end

	return false
end

local function track_hud_fade_property(records, fadeState, instance: Instance, propertyName: string): ()
	local success, currentValue = pcall(function()
		return instance[propertyName]
	end)

	if not success then
		return
	end

	local originals = fadeState.Originals
	local originalProperties = originals[instance]
	if not originalProperties then
		originalProperties = {}
		originals[instance] = originalProperties
	end

	if originalProperties[propertyName] == nil then
		originalProperties[propertyName] = currentValue
	end

	records[#records + 1] = {
		Instance = instance,
		PropertyName = propertyName,
		Original = originalProperties[propertyName],
	}
end

local function collect_hud_fade_records(
	hudRoot: GuiObject,
	fadeState,
	excludedNames: { [string]: boolean }?,
	forceDescendantFade: boolean?
)
	local records = {}

	if hudRoot:IsA("CanvasGroup") and not has_hud_fade_exclusions(excludedNames) and not forceDescendantFade then
		track_hud_fade_property(records, fadeState, hudRoot, "GroupTransparency")
		return records
	end

	local function track_instance(instance: Instance): ()
		if is_in_excluded_hud_subtree(instance, hudRoot, excludedNames) then
			return
		end

		if instance:IsA("GuiObject") then
			track_hud_fade_property(records, fadeState, instance, "BackgroundTransparency")
		end

		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			track_hud_fade_property(records, fadeState, instance, "TextTransparency")
			track_hud_fade_property(records, fadeState, instance, "TextStrokeTransparency")
		elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
			track_hud_fade_property(records, fadeState, instance, "ImageTransparency")
		elseif instance:IsA("UIStroke") then
			track_hud_fade_property(records, fadeState, instance, "Transparency")
		end
	end

	track_instance(hudRoot)
	for _, descendant in ipairs(hudRoot:GetDescendants()) do
		track_instance(descendant)
	end

	return records
end

local function restore_hud_canvas_group_transparency(hudRoot: GuiObject, fadeState): ()
	if not hudRoot:IsA("CanvasGroup") then
		return
	end

	local originalProperties = fadeState.Originals[hudRoot]
	local originalGroupTransparency = originalProperties and originalProperties.GroupTransparency
	if originalGroupTransparency == nil then
		local success, currentValue = pcall(function()
			return hudRoot.GroupTransparency
		end)

		originalGroupTransparency = if success then currentValue else 0
	end

	pcall(function()
		hudRoot.GroupTransparency = originalGroupTransparency
	end)
end

local function collect_hud_visibility_records(hudRoot: GuiObject, fadeState, excludedNames: { [string]: boolean }?)
	local records = {}
	local visibleOriginals = fadeState.VisibleOriginals
	if not visibleOriginals then
		visibleOriginals = {}
		fadeState.VisibleOriginals = visibleOriginals
	end

	if has_hud_fade_exclusions(excludedNames) then
		for _, child in ipairs(hudRoot:GetChildren()) do
			if child:IsA("GuiObject") and not is_in_excluded_hud_subtree(child, hudRoot, excludedNames) then
				if visibleOriginals[child] == nil then
					visibleOriginals[child] = child.Visible
				end
			end
		end
	end

	for instance, originalVisible in pairs(visibleOriginals) do
		if instance
			and instance.Parent
			and instance:IsDescendantOf(hudRoot)
			and not is_in_excluded_hud_subtree(instance, hudRoot, excludedNames)
		then
			records[#records + 1] = {
				Instance = instance,
				OriginalVisible = originalVisible,
			}
		end
	end

	return records
end

local function restore_excluded_hud_subtrees(
	hudRoot: GuiObject,
	fadeState,
	excludedNames: { [string]: boolean }?
): ()
	if not has_hud_fade_exclusions(excludedNames) then
		return
	end

	local visibleOriginals = fadeState.VisibleOriginals or {}
	for _, child in ipairs(hudRoot:GetChildren()) do
		if child:IsA("GuiObject") and is_in_excluded_hud_subtree(child, hudRoot, excludedNames) then
			local originalVisible = visibleOriginals[child]
			child.Visible = if originalVisible ~= nil then originalVisible else true
		end
	end
end

local function cancel_hud_fade(hudRoot: GuiObject): ()
	local tweens = hud_fade_tweens[hudRoot]
	if not tweens then
		return
	end

	for _, tween in ipairs(tweens) do
		pcall(function()
			tween:Cancel()
		end)
	end

	hud_fade_tweens[hudRoot] = nil
end

local function set_hud_record_value(record, value): ()
	local instance = record.Instance
	if not instance or not instance.Parent then
		return
	end

	pcall(function()
		instance[record.PropertyName] = value
	end)
end

local function set_hud_visibility_records(records, shouldHide: boolean): ()
	for _, record in ipairs(records) do
		local instance = record.Instance
		if instance and instance.Parent then
			pcall(function()
				instance.Visible = if shouldHide then false else record.OriginalVisible
			end)
		end
	end
end

local function fade_hud_root(
	hudRoot: GuiObject?,
	shouldHide: boolean,
	duration: number?,
	excludedNames: { [string]: boolean }?
): ()
	if not hudRoot or not hudRoot.Parent then
		return
	end

	local fadeState = hud_fade_states[hudRoot]
	if not fadeState then
		fadeState = {
			Originals = {},
			VisibleOriginals = {},
			Token = 0,
			TargetHidden = nil,
			ExclusionKey = "",
			DescendantFadeActive = false,
		}
		hud_fade_states[hudRoot] = fadeState
	end

	local previousExclusionKey = fadeState.ExclusionKey or ""
	local exclusionKey = get_hud_fade_exclusion_key(excludedNames)
	if fadeState.TargetHidden == shouldHide and fadeState.ExclusionKey == exclusionKey then
		return
	end

	fadeState.Token += 1
	fadeState.TargetHidden = shouldHide
	fadeState.ExclusionKey = exclusionKey
	local token = fadeState.Token
	local fadeDuration = math.max(0, duration or DEFAULTS.hud_fade_t)
	local hasExclusions = has_hud_fade_exclusions(excludedNames)
	local keepHudRootVisible = shouldHide and hasExclusions
	local useDescendantFade = hasExclusions or previousExclusionKey ~= "" or fadeState.DescendantFadeActive == true
	local visibilityRecords = collect_hud_visibility_records(hudRoot, fadeState, excludedNames)
	if shouldHide and useDescendantFade then
		fadeState.DescendantFadeActive = true
	end

	cancel_hud_fade(hudRoot)
	hudRoot.Visible = true
	if useDescendantFade then
		restore_hud_canvas_group_transparency(hudRoot, fadeState)
	end
	restore_excluded_hud_subtrees(hudRoot, fadeState, excludedNames)

	if not shouldHide then
		set_hud_visibility_records(visibilityRecords, false)
	end

	local records = collect_hud_fade_records(hudRoot, fadeState, excludedNames, useDescendantFade)

	if fadeDuration <= 0 then
		for _, record in ipairs(records) do
			set_hud_record_value(record, if shouldHide then 1 else record.Original)
		end

		if shouldHide then
			set_hud_visibility_records(visibilityRecords, true)
		end

		fadeState.DescendantFadeActive = shouldHide and useDescendantFade
		hudRoot.Visible = keepHudRootVisible or not shouldHide
		return
	end

	local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tweens = {}

	for _, record in ipairs(records) do
		local instance = record.Instance
		if instance and instance.Parent then
			local success, tween = pcall(function()
				return TweenService:Create(instance, tweenInfo, {
					[record.PropertyName] = if shouldHide then 1 else record.Original,
				})
			end)

			if success and tween then
				tweens[#tweens + 1] = tween
				tween:Play()
			end
		end
	end

	hud_fade_tweens[hudRoot] = tweens

	task.delay(fadeDuration, function()
		if fadeState.Token ~= token or not hudRoot or not hudRoot.Parent then
			return
		end

		hud_fade_tweens[hudRoot] = nil

		for _, record in ipairs(records) do
			set_hud_record_value(record, if shouldHide then 1 else record.Original)
		end

		if shouldHide then
			set_hud_visibility_records(visibilityRecords, true)
		end

		fadeState.DescendantFadeActive = shouldHide and useDescendantFade
		hudRoot.Visible = keepHudRootVisible or not shouldHide
	end)
end

local function sync_hud_visibility_for_frame(instance: Instance?, duration: number?, forcedOpenFrame: GuiObject?): ()
	local hudRoot = find_hud_root(instance or forcedOpenFrame)
	if not hudRoot then
		return
	end

	local openFrame = get_open_frame_for_hud(instance or hudRoot, forcedOpenFrame)
	fade_hud_root(hudRoot, openFrame ~= nil, duration, get_hud_fade_excluded_names(openFrame))
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
		sync_hud_visibility_for_frame(target, get_number_attribute(target, "open_t", DEFAULTS.hud_fade_t), target)
		return
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if child ~= target and child:IsA("GuiObject") then
			child.Visible = false
		end
	end

	target.Visible = true
	sync_hud_visibility_for_frame(target, get_number_attribute(target, "open_t", DEFAULTS.hud_fade_t), target)
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

	if has_true_attribute(button, IGNORE_HUD_ANIM_ATTRIBUTE) then
		return
	end

	if not is_hud_button(button) or not get_target_frame_name(button) then
		return
	end

	open_connections[button] = button.Activated:Connect(function()
		if has_true_attribute(button, IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE) then
			return
		end

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

	if has_true_attribute(button, IGNORE_HUD_ANIM_ATTRIBUTE) then
		return
	end

	exit_connections[button] = button.Activated:Connect(function()
		if has_true_attribute(button, IGNORE_AUTO_FRAME_BUTTON_ATTRIBUTE) then
			return
		end

		local target = find_exit_target(button)
		if not target then
			return
		end

		target.Visible = false
		task.defer(function()
			sync_hud_visibility_for_frame(target, get_number_attribute(target, "open_t", DEFAULTS.hud_fade_t))
		end)
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
		if d:IsA("GuiButton") and not has_true_attribute(d, IGNORE_HUD_ANIM_ATTRIBUTE) then
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

function HudAnim.sync_hud_visibility_for_frame(instance: Instance?, duration: number?, forcedOpenFrame: GuiObject?): ()
	sync_hud_visibility_for_frame(instance, duration, forcedOpenFrame)
end

function HudAnim.bind(inst: GuiObject): ()
	if has_true_attribute(inst, IGNORE_HUD_ANIM_ATTRIBUTE) then
		if bound[inst] then
			HudAnim.unbind(inst)
		elseif inst:IsA("GuiButton") then
			cleanup_open_button(inst)
			if inst.Name == EXIT_BUTTON_NAME then
				cleanup_exit_button(inst)
			end
		end

		return
	end

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
		if has_true_attribute(inst, IGNORE_HUD_ANIM_ATTRIBUTE) then
			return
		end

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
		if has_true_attribute(inst, IGNORE_HUD_ANIM_ATTRIBUTE) then
			return
		end

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
		if has_true_attribute(inst, IGNORE_HUD_ANIM_ATTRIBUTE) then
			return
		end

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
			if has_true_attribute(inst, IGNORE_HUD_ANIM_ATTRIBUTE) then
				return
			end

			local st = state[inst]
			if not st then
				return
			end

			Click.on_down(inst, st, Utils, SFX)
		end)
		inst.MouseButton1Up:Connect(function()
			if has_true_attribute(inst, IGNORE_HUD_ANIM_ATTRIBUTE) then
				return
			end

			local st = state[inst]
			if not st then
				return
			end

			Click.on_up(inst, st, Utils, SFX)
		end)
	end

	inst.SelectionGained:Connect(function()
		if has_true_attribute(inst, IGNORE_HUD_ANIM_ATTRIBUTE) then
			return
		end

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
		if has_true_attribute(inst, IGNORE_HUD_ANIM_ATTRIBUTE) then
			return
		end

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
			local openTime = get_number_attribute(inst, "open_t", DEFAULTS.open_t)
			sync_hud_visibility_for_frame(inst, openTime, inst)
			Open.run(inst, state[inst], Utils, SFX)
			task.wait(openTime)
			running_open[inst] = nil
		end)
	end

	inst:GetPropertyChangedSignal("Visible"):Connect(function()
		if not inst:GetAttribute("UIOpen") then
			return
		end

		if has_true_attribute(inst, IGNORE_HUD_ANIM_ATTRIBUTE) then
			return
		end

		if inst:GetAttribute("_is_closing") then
			task.defer(function()
				sync_hud_visibility_for_frame(inst, get_number_attribute(inst, "open_t", DEFAULTS.hud_fade_t))
			end)
			return
		end

		if inst.Visible then
			if inst:GetAttribute("skip_open") then
				inst:SetAttribute("skip_open", nil)
				return
			end

			local openTime = get_number_attribute(inst, "open_t", DEFAULTS.open_t)
			sync_hud_visibility_for_frame(inst, openTime, inst)

			if running_open[inst] then
				task.cancel(running_open[inst])
				running_open[inst] = nil
			end

			running_open[inst] = task.spawn(function()
				Open.run(inst, state[inst], Utils, SFX)
				task.wait(openTime)
				running_open[inst] = nil
			end)
		else
			task.defer(function()
				sync_hud_visibility_for_frame(inst, get_number_attribute(inst, "open_t", DEFAULTS.hud_fade_t))
			end)

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
	restore_state(inst, st)

	task.delay(DEFAULTS.hover_t + DEFAULTS.click_t, function()
		restore_state(inst, st)
	end)

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
