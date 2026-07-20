local SoundController = {}
SoundController.__index = SoundController

-- SERVICES
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

-- DEPENDENCIES
local DataUtility = require(script.Parent:WaitForChild("DataUtility"))

-- CONSTANTS
local DEFAULT_MUSIC_VOLUME = 0.5
local DEFAULT_SFX_VOLUME = 0.5
local FADE_DURATION = 1
local MAX_SFX_INSTANCES = 3
local REMOTE_SFX_EVENT_NAME = "PlayGameSFX"
local GAME_SFX = {
	Dig = {
		SoundId = "rbxassetid://139911414972673",
		Volume = 1,
		Pitch = 1,
	},
	Watering = {
		SoundId = "rbxassetid://9125409840",
		Volume = 1,
		Pitch = 1,
	},
	MoneyGet = {
		SoundId = "rbxassetid://6809101819",
		Volume = 1,
		Pitch = 1,
	},
	Popup = {
		SoundId = "rbxassetid://85837202919094",
		Volume = 1,
		Pitch = 1,
	},
}
local GAME_SFX_ALIASES = {
	dig = "Dig",
	watering = "Watering",
	moneyget = "MoneyGet",
	money_get = "MoneyGet",
	popup = "Popup",
	pupup = "Popup",
}

-- VARIABLES
local currentMusic = nil
local musicQueue = nil
local musicQueueIndex = 0
local musicVolume = DEFAULT_MUSIC_VOLUME
local sfxVolume = DEFAULT_SFX_VOLUME
local isMusicMuted = false
local isSFXMuted = false
local musicGroup = nil
local sfxGroup = nil
local activeSFX = {}
local musicEndedConnection = nil
local net = nil
local remoteSFXConnection = nil

-- FUNCTIONS
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

local function apply_initial_client_settings()
	if not RunService:IsClient() then
		return
	end

	DataUtility.client.ensure_remotes()

	local settings = DataUtility.client.get("Settings") or {}
	musicVolume = sanitize_volume(settings.MusicVolume, DEFAULT_MUSIC_VOLUME)
	sfxVolume = sanitize_volume(settings.SFXVolume, DEFAULT_SFX_VOLUME)
	isMusicMuted = not sanitize_boolean(settings.Music, true)
	isSFXMuted = not sanitize_boolean(settings.SFX, true)
end

local function get_effective_music_volume()
	if isMusicMuted then
		return 0
	end

	return musicVolume
end

local function get_effective_sfx_volume()
	if isSFXMuted then
		return 0
	end

	return sfxVolume
end

local function ensure_sound_group(groupName)
	local existingGroup = SoundService:FindFirstChild(groupName)

	if existingGroup then
		if existingGroup:IsA("SoundGroup") then
			return existingGroup
		end

		existingGroup:Destroy()
	end

	local soundGroup = Instance.new("SoundGroup")
	soundGroup.Name = groupName
	soundGroup.Parent = SoundService

	return soundGroup
end

local function createSoundGroups()
	musicGroup = ensure_sound_group("MusicGroup")
	sfxGroup = ensure_sound_group("SFXGroup")

	musicGroup.Volume = get_effective_music_volume()
	sfxGroup.Volume = get_effective_sfx_volume()
end

local function createSound(soundId, parent, soundGroup)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.SoundGroup = soundGroup
	sound.Volume = 1
	sound.Parent = parent
	return sound
end

local function fadeSound(sound, targetVolume, duration)
	local startVolume = sound.Volume
	local elapsed = 0

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local alpha = math.min(elapsed / duration, 1)
		sound.Volume = startVolume + (targetVolume - startVolume) * alpha

		if alpha >= 1 then
			connection:Disconnect()
		end
	end)
end

local function cleanupSFX(sound)
	if activeSFX[sound] then
		activeSFX[sound] = nil
	end
end

local function disconnectMusicEndedConnection()
	if musicEndedConnection then
		musicEndedConnection:Disconnect()
		musicEndedConnection = nil
	end
end

local function stopCurrentMusic(fadeOut)
	disconnectMusicEndedConnection()

	if not currentMusic then
		return
	end

	local musicToStop = currentMusic
	currentMusic = nil

	if fadeOut then
		fadeSound(musicToStop, 0, FADE_DURATION)

		task.delay(FADE_DURATION, function()
			if musicToStop and musicToStop.Parent then
				musicToStop:Stop()
				musicToStop:Destroy()
			end
		end)
	else
		musicToStop:Stop()
		musicToStop:Destroy()
	end
end

local function normalizeMusicQueue(soundIds)
	if typeof(soundIds) ~= "table" then
		return nil
	end

	local normalizedQueue = {}

	for _, soundId in ipairs(soundIds) do
		if typeof(soundId) == "string" and soundId ~= "" then
			table.insert(normalizedQueue, soundId)
		end
	end

	if #normalizedQueue == 0 then
		return nil
	end

	return normalizedQueue
end

local function get_net()
	if net then
		return net
	end

	local modules = script:FindFirstAncestor("Modules")
	local libraries = modules and modules:FindFirstChild("Libraries")
	local netModule = libraries and libraries:FindFirstChild("Net")
	if not netModule then
		return nil
	end

	local success, result = pcall(require, netModule)
	if not success then
		warn("[SoundUtility] Failed to require Net: " .. tostring(result))
		return nil
	end

	net = result
	return net
end

local function resolve_game_sfx_name(effectName)
	if type(effectName) ~= "string" then
		return nil
	end

	local trimmedName = string.gsub(effectName, "^%s*(.-)%s*$", "%1")
	if trimmedName == "" then
		return nil
	end

	if GAME_SFX[trimmedName] then
		return trimmedName
	end

	return GAME_SFX_ALIASES[string.lower(trimmedName)]
end

local function get_game_sfx_definition(effectName)
	local resolvedName = resolve_game_sfx_name(effectName)
	if not resolvedName then
		return nil, nil
	end

	return GAME_SFX[resolvedName], resolvedName
end

local function ensure_remote_sfx_event()
	if not RunService:IsServer() then
		return nil
	end

	local resolvedNet = get_net()
	if not resolvedNet then
		return nil
	end

	return resolvedNet.Event[REMOTE_SFX_EVENT_NAME]
end

local function getNextQueueIndex()
	if not musicQueue or #musicQueue == 0 then
		return 0
	end

	return (musicQueueIndex % #musicQueue) + 1
end

local function playMusicTrack(soundId, fadeIn, looped, onEnded)
	currentMusic = createSound(soundId, SoundService, musicGroup)
	currentMusic.Looped = looped
	currentMusic.Volume = fadeIn and 0 or 1
	currentMusic:Play()

	disconnectMusicEndedConnection()

	if onEnded then
		musicEndedConnection = currentMusic.Ended:Connect(onEnded)
	end

	if fadeIn then
		fadeSound(currentMusic, 1, FADE_DURATION)
	end

	return currentMusic
end

local function playMusicQueueTrack(index, fadeIn, fadeOutCurrent)
	if not musicQueue or #musicQueue == 0 then
		return nil
	end

	musicQueueIndex = math.clamp(index, 1, #musicQueue)

	local hasMultipleTracks = #musicQueue > 1
	local soundId = musicQueue[musicQueueIndex]
	local onEnded = nil

	if hasMultipleTracks then
		onEnded = function()
			if not musicQueue or #musicQueue <= 1 then
				return
			end

			playMusicQueueTrack(getNextQueueIndex(), false, false)
		end
	end

	stopCurrentMusic(fadeOutCurrent)

	return playMusicTrack(soundId, fadeIn, not hasMultipleTracks, onEnded)
end

function SoundController.Init()
	createSoundGroups()
	ensure_remote_sfx_event()
end

function SoundController.GetGameSFX(effectName)
	local definition, resolvedName = get_game_sfx_definition(effectName)
	if not definition then
		return nil
	end

	return {
		Name = resolvedName,
		SoundId = definition.SoundId,
		Volume = definition.Volume,
		Pitch = definition.Pitch,
	}
end

function SoundController.PlayGameSFX(effectName, parent, volume, pitch)
	local definition = get_game_sfx_definition(effectName)
	if not definition then
		return nil
	end

	return SoundController.PlaySFX(
		definition.SoundId,
		parent,
		volume or definition.Volume,
		pitch or definition.Pitch
	)
end

function SoundController.InitRemoteSFX()
	return ensure_remote_sfx_event()
end

function SoundController.BindRemoteSFX()
	if not RunService:IsClient() then
		return nil
	end

	if remoteSFXConnection then
		return remoteSFXConnection
	end

	local resolvedNet = get_net()
	if not resolvedNet then
		return nil
	end

	remoteSFXConnection = resolvedNet.Event[REMOTE_SFX_EVENT_NAME]:Connect(function(payload)
		local effectName = payload
		local options = nil

		if type(payload) == "table" then
			effectName = payload.EffectName or payload.Effect or payload.Name
			options = payload
		end

		SoundController.PlayGameSFX(
			effectName,
			nil,
			options and options.Volume or nil,
			options and options.Pitch or nil
		)
	end)

	return remoteSFXConnection
end

function SoundController.PlayGameSFXForPlayer(player, effectName, options)
	if not RunService:IsServer() then
		return false
	end

	if typeof(player) ~= "Instance" or not player:IsA("Player") then
		return false
	end

	local _, resolvedName = get_game_sfx_definition(effectName)
	if not resolvedName then
		return false
	end

	local resolvedNet = get_net()
	if not resolvedNet then
		return false
	end

	if type(options) == "table" then
		resolvedNet.Event[REMOTE_SFX_EVENT_NAME]:Fire(player, {
			EffectName = resolvedName,
			Volume = options.Volume,
			Pitch = options.Pitch,
		})
	else
		resolvedNet.Event[REMOTE_SFX_EVENT_NAME]:Fire(player, resolvedName)
	end

	return true
end

function SoundController.PlayMusic(soundId, fadeIn, loop)
	if typeof(soundId) == "table" then
		return SoundController.PlayMusicQueue(soundId, fadeIn)
	end

	fadeIn = fadeIn or false
	loop = loop ~= false

	musicQueue = nil
	musicQueueIndex = 0
	stopCurrentMusic(fadeIn)

	return playMusicTrack(soundId, fadeIn, loop, nil)
end

function SoundController.PlayMusicQueue(soundIds, fadeIn)
	local normalizedQueue = normalizeMusicQueue(soundIds)
	if not normalizedQueue then
		warn("SoundController.PlayMusicQueue requires at least one valid sound id")
		return nil
	end

	fadeIn = fadeIn or false
	musicQueue = normalizedQueue
	musicQueueIndex = 1

	return playMusicQueueTrack(musicQueueIndex, fadeIn, fadeIn)
end

function SoundController.StopMusic(fadeOut)
	fadeOut = fadeOut or false
	musicQueue = nil
	musicQueueIndex = 0
	stopCurrentMusic(fadeOut)
end

function SoundController.PauseMusic()
	if currentMusic and currentMusic.Playing then
		currentMusic:Pause()
	end
end

function SoundController.ResumeMusic()
	if currentMusic and not currentMusic.Playing then
		currentMusic:Resume()
	end
end

function SoundController.PlaySFX(soundId, parent, volume, pitch)
	if isSFXMuted then return end
	parent = parent or SoundService
	volume = volume or 1
	pitch = pitch or 1

	local instanceCount = 0
	for sfx, _ in pairs(activeSFX) do
		if sfx.SoundId == soundId then
			instanceCount += 1
		end
	end

	if instanceCount >= MAX_SFX_INSTANCES then
		return
	end

	local sound = createSound(soundId, parent, sfxGroup)
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound:Play()

	activeSFX[sound] = true

	sound.Ended:Connect(function()
		cleanupSFX(sound)
		sound:Destroy()
	end)

	return sound
end

function SoundController.StopAllSFX()
	for sound, _ in pairs(activeSFX) do
		if sound and sound.Parent then
			sound:Stop()
			sound:Destroy()
		end
	end
	activeSFX = {}
end

function SoundController.SetMusicVolume(volume)
	musicVolume = math.clamp(volume, 0, 1)
	musicGroup.Volume = get_effective_music_volume()
end

function SoundController.SetSFXVolume(volume)
	sfxVolume = math.clamp(volume, 0, 1)
	sfxGroup.Volume = get_effective_sfx_volume()
end

function SoundController.GetMusicVolume()
	return musicVolume
end

function SoundController.GetSFXVolume()
	return sfxVolume
end

function SoundController.MuteMusic(mute)
	isMusicMuted = mute
	musicGroup.Volume = get_effective_music_volume()
end

function SoundController.MuteSFX(mute)
	isSFXMuted = mute
	sfxGroup.Volume = get_effective_sfx_volume()

	if mute then
		SoundController.StopAllSFX()
	end
end

function SoundController.IsMusicMuted()
	return isMusicMuted
end

function SoundController.IsSFXMuted()
	return isSFXMuted
end

function SoundController.GetCurrentMusic()
	return currentMusic
end

function SoundController.GetMusicSoundGroup()
	return musicGroup
end

function SoundController.GetSFXSoundGroup()
	return sfxGroup
end

-- INIT
apply_initial_client_settings()
SoundController.Init()
if RunService:IsClient() then
	task.defer(function()
		SoundController.BindRemoteSFX()
	end)
end

return SoundController
