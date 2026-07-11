local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local SoundController = require(Utility:WaitForChild("SoundUtility"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local rootTrove = Trove.new()
local uiTrove = Trove.new()

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainFrameFR", "MainframeFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local SETTINGS_FRAME_NAMES = { "Settings" }
local SETTINGS_BACKGROUND_NAMES = { "SettingsBG" }
local SCROLLING_FRAME_NAMES = { "ListScrollingFrame", "ScrollingFrame", "ScrollFrame", "Scroll" }
local BUTTON_TEMPLATE_NAMES = { "SettingButton" }
local BAR_TEMPLATE_NAMES = { "SettingBar" }
local BAR_NAMES = { "BarBG" }
local TOGGLE_NAMES = { "ToggleBT" }
local NAME_LABEL_NAMES = { "SettingNameTX" }
local NAME_SHADOW_LABEL_NAMES = { "SettingNameShadowTX" }
local DETAILS_LABEL_NAMES = { "DetailsTX" }
local GENERATED_ATTRIBUTE_NAME = "GeneratedSettingControl"
local UPDATE_REMOTE_NAME = "UpdatePlayerSetting"
local TOGGLE_TWEEN_INFO = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local DEFAULT_SETTINGS = {
	Music = true,
	SFX = true,
	MusicVolume = 0.5,
	SFXVolume = 0.5,
	NoShadows = false,
}

local currentSettings = table.clone(DEFAULT_SETTINGS)
local currentUi = nil
local activeSliderDrag = nil

local function normalize_key(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	local normalizedValue = string.lower(trimmedValue)
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function matches_alias(instance, aliases)
	local normalizedName = normalize_key(instance.Name)
	if not normalizedName then
		return false
	end

	for _, alias in ipairs(aliases or {}) do
		if normalize_key(alias) == normalizedName then
			return true
		end
	end

	return false
end

local function find_named_instance(root, aliases, className, recursive)
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if matches_alias(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	if recursive == false then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if matches_alias(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function find_gui_object(root, aliases, recursive)
	local instance = find_named_instance(root, aliases, "GuiObject", recursive)
	if instance then
		return instance
	end

	return nil
end

local function find_text_label(root, aliases, recursive)
	local instance = find_named_instance(root, aliases, "TextLabel", recursive)
	if instance then
		return instance
	end

	return nil
end

local function find_scrolling_frame(root)
	local instance = find_named_instance(root, SCROLLING_FRAME_NAMES, "ScrollingFrame")
	if instance then
		return instance
	end

	return nil
end

local function sanitize_boolean(value, fallback)
	if type(value) == "boolean" then
		return value
	end

	if type(value) == "number" then
		return value ~= 0
	end

	return fallback
end

local function sanitize_volume(value, fallback)
	local numericValue = tonumber(value)
	if numericValue == nil then
		return fallback
	end

	return math.clamp(numericValue, 0, 1)
end

local function round_volume(value)
	return math.floor((math.clamp(value, 0, 1) * 100) + 0.5) / 100
end

local function apply_sound_settings()
	SoundController.SetMusicVolume(currentSettings.MusicVolume)
	SoundController.SetSFXVolume(currentSettings.SFXVolume)
	SoundController.MuteMusic(not currentSettings.Music)
	SoundController.MuteSFX(not currentSettings.SFX)
end

local function apply_shadow_settings()
	Lighting.GlobalShadows = not currentSettings.NoShadows
end

local function apply_all_settings()
	apply_sound_settings()
	apply_shadow_settings()
end

local settingDefinitions = {
	{
		Id = "MuteMusic",
		Kind = "Toggle",
		Template = "Button",
		Name = "Mutar musica",
		Details = "Desliga toda a musica do jogo.",
		ReadValue = function()
			return not currentSettings.Music
		end,
		Preview = function(value)
			currentSettings.Music = not value
			SoundController.MuteMusic(value)
		end,
		Serialize = function(value)
			return "Music", not value
		end,
	},
	{
		Id = "MusicVolume",
		Kind = "Slider",
		Template = "Bar",
		Name = "Volume da musica",
		Details = "Controla o volume da musica de fundo.",
		ReadValue = function()
			return currentSettings.MusicVolume
		end,
		Preview = function(value)
			local volume = round_volume(value)
			currentSettings.MusicVolume = volume
			SoundController.SetMusicVolume(volume)
		end,
		Serialize = function(value)
			return "MusicVolume", round_volume(value)
		end,
	},
	{
		Id = "MuteSFX",
		Kind = "Toggle",
		Template = "Button",
		Name = "Mutar efeitos sonoros",
		Details = "Desliga os efeitos sonoros e os sons da interface.",
		ReadValue = function()
			return not currentSettings.SFX
		end,
		Preview = function(value)
			currentSettings.SFX = not value
			SoundController.MuteSFX(value)
		end,
		Serialize = function(value)
			return "SFX", not value
		end,
	},
	{
		Id = "SFXVolume",
		Kind = "Slider",
		Template = "Bar",
		Name = "Volume dos efeitos",
		Details = "Controla o volume dos efeitos sonoros do jogo.",
		ReadValue = function()
			return currentSettings.SFXVolume
		end,
		Preview = function(value)
			local volume = round_volume(value)
			currentSettings.SFXVolume = volume
			SoundController.SetSFXVolume(volume)
		end,
		Serialize = function(value)
			return "SFXVolume", round_volume(value)
		end,
	},
	{
		Id = "Shadows",
		Kind = "Toggle",
		Template = "Button",
		Name = "Sombras",
		Details = "Ativa ou desativa as sombras do mundo.",
		ReadValue = function()
			return not currentSettings.NoShadows
		end,
		Preview = function(value)
			currentSettings.NoShadows = not value
			Lighting.GlobalShadows = value
		end,
		Serialize = function(value)
			return "NoShadows", not value
		end,
	},
}

local function set_label_text(root, aliases, text)
	local label = find_text_label(root, aliases, true)
	if label then
		label.Text = text
	end
end

local function update_canvas_size()
	if not currentUi or not currentUi.ListLayout then
		return
	end

	currentUi.List.CanvasSize = UDim2.new(0, 0, 0, currentUi.ListLayout.AbsoluteContentSize.Y)
end

local function get_toggle_track_bounds(record)
	local barWidth = record.Bar.AbsoluteSize.X
	local toggleWidth = record.Toggle.AbsoluteSize.X
	local anchorX = record.Toggle.AnchorPoint.X
	local minX = toggleWidth * anchorX
	local maxX = barWidth - (toggleWidth * (1 - anchorX))

	if maxX < minX then
		local centerX = barWidth * 0.5
		return centerX, centerX
	end

	return minX, maxX
end

local function set_control_alpha(record, alpha, animated)
	alpha = math.clamp(alpha, 0, 1)
	record.LastAlpha = alpha

	local minX, maxX = get_toggle_track_bounds(record)
	local xOffset = minX + ((maxX - minX) * alpha)
	local targetPosition = UDim2.new(0, math.floor(xOffset + 0.5), record.ToggleYScale, record.ToggleYOffset)

	if animated then
		TweenService:Create(record.Toggle, TOGGLE_TWEEN_INFO, {
			Position = targetPosition,
		}):Play()
	else
		record.Toggle.Position = targetPosition
	end
end

local function refresh_control(record, animated)
	local value = record.Descriptor.ReadValue()

	if record.Descriptor.Kind == "Toggle" then
		set_control_alpha(record, value and 1 or 0, animated)
	else
		set_control_alpha(record, value, false)
	end
end

local function refresh_all_controls(animated)
	if not currentUi then
		return
	end

	for _, record in ipairs(currentUi.Controls) do
		refresh_control(record, animated)
	end
end

local function commit_setting(descriptor, value)
	local settingKey, serializedValue = descriptor.Serialize(value)

	task.spawn(function()
		local ok, success, response = pcall(function()
			return Net.Function[UPDATE_REMOTE_NAME]:Call(settingKey, serializedValue)
		end)

		if not ok then
			warn(("[Settings] Falha ao salvar %s: %s"):format(tostring(settingKey), tostring(success)))
			return
		end

		if success ~= true then
			warn(("[Settings] Servidor rejeitou %s: %s"):format(tostring(settingKey), tostring(response)))
		end
	end)
end

local function update_slider_value(record, screenX)
	local barAbsolutePosition = record.Bar.AbsolutePosition.X
	local localX = screenX - barAbsolutePosition
	local minX, maxX = get_toggle_track_bounds(record)
	local clampedX = math.clamp(localX, minX, maxX)

	local alpha = 0
	if maxX > minX then
		alpha = (clampedX - minX) / (maxX - minX)
	end

	alpha = round_volume(alpha)
	record.Descriptor.Preview(alpha)
	set_control_alpha(record, alpha, false)
end

local function finish_slider_drag(shouldCommit)
	local dragState = activeSliderDrag
	if not dragState then
		return
	end

	activeSliderDrag = nil

	if dragState.PreviousScrollingEnabled ~= nil and currentUi and currentUi.List then
		currentUi.List.ScrollingEnabled = dragState.PreviousScrollingEnabled
	end

	if shouldCommit then
		local value = dragState.Record.Descriptor.ReadValue()
		commit_setting(dragState.Record.Descriptor, value)
	end
end

local function start_slider_drag(record, input)
	if activeSliderDrag and activeSliderDrag.Record == record and activeSliderDrag.InputObject == input then
		return
	end

	finish_slider_drag(false)

	local previousScrollingEnabled = nil
	if currentUi and currentUi.List then
		previousScrollingEnabled = currentUi.List.ScrollingEnabled
		currentUi.List.ScrollingEnabled = false
	end

	activeSliderDrag = {
		Record = record,
		InputObject = input,
		InputType = input.UserInputType,
		PreviousScrollingEnabled = previousScrollingEnabled,
	}

	update_slider_value(record, input.Position.X)
end

local function is_press_input(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function bind_toggle_input(guiObject, callback)
	if not guiObject then
		return
	end

	guiObject.Active = true

	uiTrove:Add(guiObject.InputBegan:Connect(function(input)
		if is_press_input(input) then
			callback(input)
		end
	end))
end

local function bind_slider_input(guiObject, record)
	if not guiObject then
		return
	end

	guiObject.Active = true

	uiTrove:Add(guiObject.InputBegan:Connect(function(input)
		if not is_press_input(input) then
			return
		end

		start_slider_drag(record, input)
	end))
end

local function build_control_record(root, descriptor)
	local bar = find_gui_object(root, BAR_NAMES, true)
	local toggle = find_gui_object(root, TOGGLE_NAMES, true)
	if not bar or not toggle then
		return nil
	end

	return {
		Root = root,
		Bar = bar,
		Toggle = toggle,
		ToggleYScale = toggle.Position.Y.Scale,
		ToggleYOffset = toggle.Position.Y.Offset,
		Descriptor = descriptor,
		LastAlpha = 0,
	}
end

local function make_template_source(template)
	local source = template:Clone()
	source.Visible = true
	template.Parent = nil
	return source
end

local function clear_generated_controls(listFrame)
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:GetAttribute(GENERATED_ATTRIBUTE_NAME) == true then
			child:Destroy()
		end
	end
end

local function find_settings_ui()
	local mainUi = find_named_instance(playerGui, MAIN_UI_NAMES, nil, true)
	if not mainUi then
		return nil
	end

	local mainframe = find_named_instance(mainUi, MAINFRAME_NAMES, nil, true)
	if not mainframe then
		return nil
	end

	local framesContainer = find_named_instance(mainframe, FRAMES_CONTAINER_NAMES, nil, true)
	if not framesContainer then
		return nil
	end

	local settingsRoot = find_gui_object(framesContainer, SETTINGS_FRAME_NAMES, true)
	if not settingsRoot then
		return nil
	end

	local settingsBackground = find_gui_object(settingsRoot, SETTINGS_BACKGROUND_NAMES, true) or settingsRoot
	local listFrame = find_scrolling_frame(settingsBackground) or find_scrolling_frame(settingsRoot)
	if not listFrame then
		return nil
	end

	local buttonTemplate = find_gui_object(listFrame, BUTTON_TEMPLATE_NAMES, true)
	local barTemplate = find_gui_object(listFrame, BAR_TEMPLATE_NAMES, true)
	local listLayout = listFrame:FindFirstChildWhichIsA("UIListLayout")

	if not buttonTemplate or not barTemplate then
		return nil
	end

	return {
		Root = settingsRoot,
		List = listFrame,
		ButtonTemplate = buttonTemplate,
		BarTemplate = barTemplate,
		ListLayout = listLayout,
		Controls = {},
	}
end

local function bind_ui(ui)
	finish_slider_drag(false)

	uiTrove:Destroy()
	uiTrove = Trove.new()

	currentUi = ui

	clear_generated_controls(ui.List)

	ui.ButtonTemplate = make_template_source(ui.ButtonTemplate)
	ui.BarTemplate = make_template_source(ui.BarTemplate)

	uiTrove:Add(ui.ButtonTemplate)
	uiTrove:Add(ui.BarTemplate)

	for index, descriptor in ipairs(settingDefinitions) do
		local template = descriptor.Template == "Button" and ui.ButtonTemplate or ui.BarTemplate
		local control = template:Clone()
		control.Name = descriptor.Id
		control.LayoutOrder = index
		control.Visible = true
		control:SetAttribute(GENERATED_ATTRIBUTE_NAME, true)
		control.Parent = ui.List

		set_label_text(control, NAME_LABEL_NAMES, descriptor.Name)
		set_label_text(control, NAME_SHADOW_LABEL_NAMES, descriptor.Name)
		set_label_text(control, DETAILS_LABEL_NAMES, descriptor.Details)

		local record = build_control_record(control, descriptor)
		if record then
			ui.Controls[#ui.Controls + 1] = record

			record.Bar.Active = true
			record.Toggle.Active = true

			uiTrove:Add(record.Bar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				task.defer(function()
					refresh_control(record, false)
				end)
			end))

			uiTrove:Add(record.Toggle:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				task.defer(function()
					refresh_control(record, false)
				end)
			end))

			if descriptor.Kind == "Toggle" then
				local lastToggleInput = nil

				local function handle_toggle(input)
					if input and lastToggleInput == input then
						return
					end

					if input then
						lastToggleInput = input
						task.defer(function()
							if lastToggleInput == input then
								lastToggleInput = nil
							end
						end)
					end

					local nextValue = not descriptor.ReadValue()
					descriptor.Preview(nextValue)
					refresh_control(record, true)
					commit_setting(descriptor, nextValue)
				end

				bind_toggle_input(record.Bar, handle_toggle)
				bind_toggle_input(record.Toggle, handle_toggle)
			else
				bind_slider_input(record.Bar, record)
				bind_slider_input(record.Toggle, record)
			end
		end
	end

	if ui.ListLayout then
		uiTrove:Add(ui.ListLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(update_canvas_size))
	end

	uiTrove:Add(ui.Root.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		if currentUi == ui then
			finish_slider_drag(false)
			currentUi = nil
			uiTrove:Destroy()
			uiTrove = Trove.new()
		end
	end))

	refresh_all_controls(false)
	update_canvas_size()
	task.defer(update_canvas_size)
end

local function try_bind_ui()
	if currentUi and currentUi.Root and currentUi.Root.Parent and currentUi.List and currentUi.List.Parent then
		return
	end

	if currentUi then
		currentUi = nil
		uiTrove:Destroy()
		uiTrove = Trove.new()
	end

	local ui = find_settings_ui()
	if ui then
		bind_ui(ui)
	end
end

local function sync_settings_from_data()
	local settingsData = DataUtility.client.get("Settings") or {}

	currentSettings.Music = sanitize_boolean(settingsData.Music, DEFAULT_SETTINGS.Music)
	currentSettings.SFX = sanitize_boolean(settingsData.SFX, DEFAULT_SETTINGS.SFX)
	currentSettings.MusicVolume = sanitize_volume(settingsData.MusicVolume, DEFAULT_SETTINGS.MusicVolume)
	currentSettings.SFXVolume = sanitize_volume(settingsData.SFXVolume, DEFAULT_SETTINGS.SFXVolume)
	currentSettings.NoShadows = sanitize_boolean(settingsData.NoShadows, DEFAULT_SETTINGS.NoShadows)

	apply_all_settings()
	refresh_all_controls(false)
end

DataUtility.client.ensure_remotes()
sync_settings_from_data()

rootTrove:Add(DataUtility.client.bind("Settings.Music", function(value)
	currentSettings.Music = sanitize_boolean(value, currentSettings.Music)
	apply_sound_settings()
	refresh_all_controls(false)
end))

rootTrove:Add(DataUtility.client.bind("Settings.SFX", function(value)
	currentSettings.SFX = sanitize_boolean(value, currentSettings.SFX)
	apply_sound_settings()
	refresh_all_controls(false)
end))

rootTrove:Add(DataUtility.client.bind("Settings.MusicVolume", function(value)
	currentSettings.MusicVolume = sanitize_volume(value, currentSettings.MusicVolume)
	apply_sound_settings()
	refresh_all_controls(false)
end))

rootTrove:Add(DataUtility.client.bind("Settings.SFXVolume", function(value)
	currentSettings.SFXVolume = sanitize_volume(value, currentSettings.SFXVolume)
	apply_sound_settings()
	refresh_all_controls(false)
end))

rootTrove:Add(DataUtility.client.bind("Settings.NoShadows", function(value)
	currentSettings.NoShadows = sanitize_boolean(value, currentSettings.NoShadows)
	apply_shadow_settings()
	refresh_all_controls(false)
end))

rootTrove:Add(UserInputService.InputChanged:Connect(function(input)
	if not activeSliderDrag then
		return
	end

	if activeSliderDrag.InputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement then
		update_slider_value(activeSliderDrag.Record, input.Position.X)
		return
	end

	if activeSliderDrag.InputType == Enum.UserInputType.Touch and input.UserInputType == Enum.UserInputType.Touch then
		update_slider_value(activeSliderDrag.Record, input.Position.X)
	end
end))

rootTrove:Add(UserInputService.InputEnded:Connect(function(input)
	if not activeSliderDrag then
		return
	end

	if input == activeSliderDrag.InputObject or input.UserInputType == activeSliderDrag.InputType then
		finish_slider_drag(true)
	end
end))

rootTrove:Add(playerGui.DescendantAdded:Connect(function()
	try_bind_ui()
end))

rootTrove:Add(playerGui.DescendantRemoving:Connect(function(instance)
	if currentUi and (instance == currentUi.Root or instance == currentUi.List) then
		task.defer(try_bind_ui)
	end
end))

try_bind_ui()