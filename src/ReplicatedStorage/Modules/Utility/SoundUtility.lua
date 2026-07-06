local SoundController = {}
SoundController.__index = SoundController

-- SERVICES
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

-- CONSTANTS
local DEFAULT_MUSIC_VOLUME = 0.5
local DEFAULT_SFX_VOLUME = 0.5
local FADE_DURATION = 1
local MAX_SFX_INSTANCES = 3

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

-- FUNCTIONS
local function createSoundGroups()
	musicGroup = Instance.new("SoundGroup")
	musicGroup.Name = "MusicGroup"
	musicGroup.Parent = SoundService
	musicGroup.Volume = musicVolume

	sfxGroup = Instance.new("SoundGroup")
	sfxGroup.Name = "SFXGroup"
	sfxGroup.Parent = SoundService
	sfxGroup.Volume = sfxVolume
end

local function createSound(soundId, parent, soundGroup)
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.SoundGroup = soundGroup
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

local function getNextQueueIndex()
	if not musicQueue or #musicQueue == 0 then
		return 0
	end

	return (musicQueueIndex % #musicQueue) + 1
end

local function getCurrentMusicVolume()
	if isMusicMuted then
		return 0
	end

	return musicVolume
end

local function playMusicTrack(soundId, fadeIn, looped, onEnded)
	currentMusic = createSound(soundId, SoundService, musicGroup)
	currentMusic.Looped = looped
	currentMusic.Volume = fadeIn and 0 or getCurrentMusicVolume()
	currentMusic:Play()

	disconnectMusicEndedConnection()

	if onEnded then
		musicEndedConnection = currentMusic.Ended:Connect(onEnded)
	end

	if fadeIn then
		fadeSound(currentMusic, getCurrentMusicVolume(), FADE_DURATION)
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
end

function SoundController.PlayMusic(soundId, fadeIn, loop)
	if typeof(soundId) == "table" then
		return SoundController.PlayMusicQueue(soundId, fadeIn)
	end

	if isMusicMuted then return end

	fadeIn = fadeIn or false
	loop = loop ~= false

	musicQueue = nil
	musicQueueIndex = 0
	stopCurrentMusic(fadeIn)

	return playMusicTrack(soundId, fadeIn, loop, nil)
end

function SoundController.PlayMusicQueue(soundIds, fadeIn)
	if isMusicMuted then return end

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
	sound.Volume = volume * sfxVolume
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
	musicGroup.Volume = musicVolume

	if currentMusic and not isMusicMuted then
		currentMusic.Volume = musicVolume
	end
end

function SoundController.SetSFXVolume(volume)
	sfxVolume = math.clamp(volume, 0, 1)
	sfxGroup.Volume = sfxVolume
end

function SoundController.GetMusicVolume()
	return musicVolume
end

function SoundController.GetSFXVolume()
	return sfxVolume
end

function SoundController.MuteMusic(mute)
	isMusicMuted = mute

	if mute then
		if currentMusic then
			currentMusic.Volume = 0
		end
	else
		if currentMusic then
			currentMusic.Volume = musicVolume
		end
	end
end

function SoundController.MuteSFX(mute)
	print(mute)
	isSFXMuted = mute

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

-- INIT
SoundController.Init()

return SoundController
