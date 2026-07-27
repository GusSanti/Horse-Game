local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local Net = require(Libraries:WaitForChild("Net"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local PlayerSettingsService = {}

local initialized = false

local BOOLEAN_SETTINGS = {
	Music = true,
	SFX = true,
	NoShadows = true,
}

local NUMBER_SETTINGS = {
	MusicVolume = true,
	SFXVolume = true,
}

local function normalize_boolean(value)
	if type(value) == "boolean" then
		return value
	end

	if type(value) == "number" then
		return value ~= 0
	end

	if type(value) == "string" then
		local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
		local normalizedValue = string.lower(trimmedValue)
		if normalizedValue == "true" or normalizedValue == "1" or normalizedValue == "yes" then
			return true
		end

		if normalizedValue == "false" or normalizedValue == "0" or normalizedValue == "no" then
			return false
		end
	end

	return nil
end

local function normalize_number(value)
	local numericValue = tonumber(value)
	if numericValue == nil then
		return nil
	end

	return math.clamp(numericValue, 0, 1)
end

local function get_setting_path(settingKey)
	if BOOLEAN_SETTINGS[settingKey] or NUMBER_SETTINGS[settingKey] then
		return "Settings." .. settingKey
	end

	return nil
end

function PlayerSettingsService.UpdateSetting(player, settingKey, value)
	if not player or not player:IsA("Player") then
		return false, "InvalidPlayer"
	end

	local settingPath = get_setting_path(settingKey)
	if not settingPath then
		return false, "InvalidSetting"
	end

	local normalizedValue = nil

	if BOOLEAN_SETTINGS[settingKey] then
		normalizedValue = normalize_boolean(value)
	else
		normalizedValue = normalize_number(value)
	end

	if normalizedValue == nil then
		return false, "InvalidValue"
	end

	if not DataUtility.server.get(player) then
		return false, "ProfileUnavailable"
	end

	DataUtility.server.set(player, settingPath, normalizedValue)

	return true, normalizedValue
end

function PlayerSettingsService.Init()
	if initialized then
		return
	end

	initialized = true

	Net.Function.UpdatePlayerSetting:Respond(function(player, settingKey, value)
		return PlayerSettingsService.UpdateSetting(player, settingKey, value)
	end)
end

return PlayerSettingsService
