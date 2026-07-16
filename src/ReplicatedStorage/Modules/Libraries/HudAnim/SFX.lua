------------------//SERVICES
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")

-----------------//DEPENDENCIES
local SoundController = require(script.Parent.Parent.Parent.Utility.SoundUtility)

------------------//VARIABLES
local SFX = {}

-- Put your default UI sound ids here.
-- Use this format: "rbxassetid://1234567890"
local SOUND_IDS = {
	Hover = "rbxassetid://119354387183704",
	Click = "rbxassetid://139719503904449",
	ClickDown = "",
	ClickUp = "",
	Select = "",
	Deselect = "",
	Open = "",
}

local defaults = {
	sfx_volume = 0.8,
	sfx_speed = 1.0,
	sfx_hover_volume = 0.7,
	sfx_click_volume = 1.4,
	sfx_down_volume = 1.0,
	sfx_up_volume = 1.0,
	sfx_select_volume = 0.9,
	sfx_deselect_volume = 0.9,
	sfx_open_volume = 0.9,
	sfx_hover = SOUND_IDS.Hover,
	sfx_down = SOUND_IDS.ClickDown,
	sfx_up = SOUND_IDS.ClickUp,
	sfx_click = SOUND_IDS.Click,
	sfx_select = SOUND_IDS.Select,
	sfx_deselect = SOUND_IDS.Deselect,
	sfx_open = SOUND_IDS.Open,
}

local volume_attributes_by_key = {
	sfx_hover = "sfx_hover_volume",
	sfx_down = "sfx_down_volume",
	sfx_up = "sfx_up_volume",
	sfx_click = "sfx_click_volume",
	sfx_select = "sfx_select_volume",
	sfx_deselect = "sfx_deselect_volume",
	sfx_open = "sfx_open_volume",
}

local cache = {}

------------------//FUNCTIONS
local function normalize_sound_id(value)
	if type(value) == "number" then
		value = tostring(value)
	end

	if type(value) ~= "string" then
		return ""
	end

	local id = string.gsub(value, "^%s*(.-)%s*$", "%1")
	if id == "" or id == "0" or id == "rbxassetid://0" then
		return ""
	end

	if string.find(id, "rbxassetid://", 1, true) then
		return id
	end

	return "rbxassetid://" .. id
end

local function get_number_attribute(inst, name)
	local value = inst:GetAttribute(name)
	local numberValue = tonumber(value)
	if numberValue == nil then
		return nil
	end

	return numberValue
end

local function get_volume(inst, key)
	local volumeAttribute = volume_attributes_by_key[key]
	local keyedVolume = volumeAttribute and get_number_attribute(inst, volumeAttribute) or nil
	if keyedVolume ~= nil then
		return math.clamp(keyedVolume, 0, 10)
	end

	local sharedVolume = get_number_attribute(inst, "sfx_volume")
	if sharedVolume ~= nil then
		return math.clamp(sharedVolume, 0, 10)
	end

	return math.clamp(defaults[volumeAttribute] or defaults.sfx_volume, 0, 10)
end

local function get_speed(inst)
	local speed = get_number_attribute(inst, "sfx_speed") or defaults.sfx_speed
	return math.clamp(speed, 0.05, 10)
end

local function get_sound(id)
	local sound = cache[id]
	if sound and sound.Parent then
		return sound
	end

	sound = Instance.new("Sound")
	sound.Name = "HudSFX"
	sound.SoundId = id
	sound.SoundGroup = SoundController.GetSFXSoundGroup()
	sound.Volume = 1
	sound.Parent = SoundService
	cache[id] = sound

	task.spawn(function()
		pcall(function()
			ContentProvider:PreloadAsync({ sound })
		end)
	end)

	return sound
end

local function preload_defaults()
	local sounds = {}

	for soundKey in volume_attributes_by_key do
		local normalizedId = normalize_sound_id(defaults[soundKey])
		if normalizedId ~= "" then
			sounds[#sounds + 1] = get_sound(normalizedId)
		end
	end

	if #sounds > 0 then
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(sounds)
			end)
		end)
	end
end

------------------//MAIN FUNCTIONS
function SFX.set_defaults(opts)
	if type(opts) ~= "table" then
		return
	end

	for k, v in opts do
		defaults[k] = v
	end

	preload_defaults()
end

function SFX.play_for(inst, key)
	if not inst then
		return
	end

	local id = normalize_sound_id(inst:GetAttribute(key) or defaults[key])
	if id == "" then
		return
	end

	if SoundController.IsSFXMuted() then
		return
	end

	local sound = get_sound(id)
	sound.SoundGroup = SoundController.GetSFXSoundGroup()
	sound.Volume = get_volume(inst, key)
	sound.PlaybackSpeed = get_speed(inst)
	SoundService:PlayLocalSound(sound)
end

------------------//INIT
preload_defaults()

return SFX