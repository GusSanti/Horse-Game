------------------//SERVICES
local SoundService = game:GetService("SoundService")

-----------------//DEPENDENCIES
local SoundController = require(script.Parent.Parent.Parent.Utility.SoundUtility)


------------------//VARIABLES
local SFX = {}
local cache = {}
local defaults = {
	sfx_volume = 0.8,
	sfx_speed = 1.0,
	sfx_hover = "",
	sfx_down = "",
	sfx_up = "",
	sfx_click = "",
	sfx_select = "",
	sfx_deselect = "",
	sfx_open = "",
}

------------------//FUNCTIONS
local function get(id)
	if id == "" then return nil end
	local s = cache[id]
	if s and s.Parent then return s end
	s = Instance.new("Sound")
	s.SoundId = id
	s.Name = "HudSFX"
	s.Parent = SoundService
	cache[id] = s
	return s
end

------------------//MAIN FUNCTIONS
function SFX.set_defaults(opts)
	for k, v in opts do defaults[k] = v end
end

function SFX.play_for(inst, key)
	if SoundController.IsSFXMuted() then return end
	
	local id = inst:GetAttribute(key) or defaults[key] or ""
	if id == "" or id == "rbxassetid://0" then return end
	local s = get(id)
	if not s then return end
	s.Volume = inst:GetAttribute("sfx_volume") or defaults.sfx_volume
	s.PlaybackSpeed = inst:GetAttribute("sfx_speed") or defaults.sfx_speed
	SoundService:PlayLocalSound(s)
end

------------------//INIT
return SFX
