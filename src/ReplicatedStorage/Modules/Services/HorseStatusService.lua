local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))

local DEFAULT_STATUS_MAX = 100
local STATUS_ORDER = {
	"Happiness",
	"Hunger",
	"Thirst",
	"Cleanliness",
	"Health",
}

local OVERFLOW_ALLOWED_NEEDS = {
	Hunger = true,
	Thirst = true,
}

local ZERO_NEED_DECAY_MULTIPLIER = {
	Happiness = 2,
	Health = 3,
}

local HorseStatusService = {}

HorseStatusService.StatusOrder = TableUtility.DeepCopy(STATUS_ORDER)

local function is_player(value): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function clamp_number(value: number, minValue: number, maxValue: number): number
	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return value
end

local function get_definition_for_horse(horse)
	local catalogId = nil

	if type(horse) == "table" then
		catalogId = horse.CatalogId
	end

	return HorseCatalog.GetDefinition(catalogId) or HorseCatalog.GetDefinition("Default")
end

local function get_definition_status_value(definition, groupName: string, statusName: string, fallback: number): number
	local needs = definition and definition.Needs
	local group = needs and needs[groupName]
	local value = group and group[statusName]

	if type(value) ~= "number" then
		return fallback
	end

	return value
end

local function clamp_to_max(value: number, maxValue: number): number
	local resolvedValue = if type(value) == "number" then value else 0
	local resolvedMax = if type(maxValue) == "number" then math.max(0, maxValue) else DEFAULT_STATUS_MAX

	return math.clamp(resolvedValue, 0, resolvedMax)
end

local function clamp_status_value(statusName: string, value: number, maxValue: number): number
	if OVERFLOW_ALLOWED_NEEDS[statusName] then
		return math.max(0, value)
	end

	return math.clamp(value, 0, maxValue)
end

local function sync_dirty_state(horse): boolean
	if type(horse.State) ~= "table" then
		horse.State = {}
	end

	local needs = horse.Needs or {}
	local maxValues = needs.Max or {}
	local values = needs.Values or {}
	local maxCleanliness = tonumber(maxValues.Cleanliness) or DEFAULT_STATUS_MAX
	local currentCleanliness = tonumber(values.Cleanliness) or 0
	local isDirty = currentCleanliness < maxCleanliness
	local changed = horse.State.IsDirty ~= isDirty

	horse.State.IsDirty = isDirty

	return changed
end

local function get_horses_container(player: Player?)
	if RunService:IsServer() then
		if not is_player(player) then
			return nil
		end

		local horses = DataUtility.server.get(player, "Horses")
		if type(horses) ~= "table" then
			return nil
		end

		return horses
	end

	local horses = DataUtility.client.get("Horses")
	if type(horses) ~= "table" then
		return nil
	end

	return horses
end

local function resolve_default_horse_id(horses): string?
	local ownedHorses = horses.Owned or {}
	local equippedHorseId = horses.EquippedHorseId or ""

	if equippedHorseId ~= "" and ownedHorses[equippedHorseId] then
		return equippedHorseId
	end

	for _, horseId: string in ipairs(horses.OrderedIds or {}) do
		if ownedHorses[horseId] then
			return horseId
		end
	end

	for horseId in ownedHorses do
		return horseId
	end

	return nil
end

local function get_need_max(horse, statusName: string): number
	local needs = horse.Needs or {}
	local maxValues = needs.Max or {}
	local value = maxValues[statusName]

	if type(value) == "number" then
		return math.max(0, value)
	end

	local definition = get_definition_for_horse(horse)
	return math.max(0, get_definition_status_value(definition, "Max", statusName, DEFAULT_STATUS_MAX))
end

local function get_need_value(horse, statusName: string): number
	local needs = horse.Needs or {}
	local values = needs.Values or {}
	local value = values[statusName]

	if type(value) ~= "number" then
		return 0
	end

	if OVERFLOW_ALLOWED_NEEDS[statusName] then
		return math.max(0, value)
	end

	return clamp_to_max(value, get_need_max(horse, statusName))
end

local function get_decay_per_hour(horse, statusName: string): number
	local needs = horse.Needs or {}
	local decayPerHour = needs.DecayPerHour or {}
	local value = decayPerHour[statusName]

	if type(value) == "number" then
		return math.max(0, value)
	end

	local definition = get_definition_for_horse(horse)
	return math.max(0, get_definition_status_value(definition, "DecayPerHour", statusName, 0))
end

local function get_last_updated_at(horse, now: number): number
	local needs = horse.Needs or {}
	local lastUpdatedAt = needs.LastUpdatedAt

	if type(lastUpdatedAt) ~= "number" then
		return now
	end

	return math.min(lastUpdatedAt, now)
end

local function get_active_modifier(horse, statusName: string, lastUpdatedAt: number, now: number)
	local needs = horse.Needs or {}
	local modifiers = needs.Modifiers or {}
	local modifier = modifiers[statusName]

	if type(modifier) ~= "table" then
		return nil
	end

	if type(modifier.ExpiresAt) ~= "number" or modifier.ExpiresAt <= lastUpdatedAt then
		return nil
	end

	return {
		Multiplier = clamp_number(tonumber(modifier.Multiplier) or 1, 0.1, 5),
		ExpiresAt = math.max(lastUpdatedAt, math.min(now, modifier.ExpiresAt)),
	}
end

local function compute_decay(value: number, decayPerHour: number, lastUpdatedAt: number, now: number, modifier): number
	if now <= lastUpdatedAt or decayPerHour <= 0 then
		return value
	end

	if modifier and modifier.ExpiresAt > lastUpdatedAt then
		local modifierEnd = math.min(now, modifier.ExpiresAt)
		local modifierSeconds = math.max(0, modifierEnd - lastUpdatedAt)
		local normalSeconds = math.max(0, now - modifierEnd)

		value -= decayPerHour * modifier.Multiplier * (modifierSeconds / 3600)
		value -= decayPerHour * (normalSeconds / 3600)
		return value
	end

	value -= decayPerHour * ((now - lastUpdatedAt) / 3600)
	return value
end

local function has_zero_other_need(statuses, targetNeed: string): boolean
	for _, statusName: string in ipairs(STATUS_ORDER) do
		if statusName ~= targetNeed and (statuses[statusName] or 0) <= 0 then
			return true
		end
	end

	return false
end

local function apply_zero_need_penalties(horse, statuses, lastUpdatedAt: number, now: number)
	for targetNeed, multiplier in pairs(ZERO_NEED_DECAY_MULTIPLIER) do
		if multiplier > 1 and has_zero_other_need(statuses, targetNeed) then
			local extraDecayPerHour = math.max(0, get_decay_per_hour(horse, targetNeed) * (multiplier - 1))

			if extraDecayPerHour > 0 then
				local maxValue = get_need_max(horse, targetNeed)
				statuses[targetNeed] = clamp_status_value(
					targetNeed,
					compute_decay(
						statuses[targetNeed] or 0,
						extraDecayPerHour,
						lastUpdatedAt,
						now,
						get_active_modifier(horse, targetNeed, lastUpdatedAt, now)
					),
					maxValue
				)
			end
		end
	end
end

local function compute_pending_health_gain(horse, lastUpdatedAt: number, now: number): number
	local needs = horse.Needs or {}
	local activeEffects = needs.ActiveEffects or {}
	local pendingGain = 0

	for _, effect in ipairs(activeEffects) do
		if type(effect) == "table" and effect.Type == "HealthOverTime" then
			local expiresAt = tonumber(effect.ExpiresAt) or now
			local lastTickAt = tonumber(effect.LastTickAt) or lastUpdatedAt
			local remainingGain = math.max(0, tonumber(effect.RemainingGain) or 0)
			local ratePerSecond = math.max(0, tonumber(effect.RatePerSecond) or 0)
			local effectEnd = math.min(now, expiresAt)
			local elapsedSeconds = math.max(0, effectEnd - lastTickAt)

			pendingGain += math.min(remainingGain, ratePerSecond * elapsedSeconds)
		end
	end

	return pendingGain
end

function HorseStatusService.NormalizeHorse(horse, now: number?): boolean
	if type(horse) ~= "table" then
		return false
	end

	local changed = false
	local timestamp = if type(now) == "number" then now else os.time()
	local definition = get_definition_for_horse(horse)

	if type(horse.Acquisition) ~= "table" then
		horse.Acquisition = {}
		changed = true
	end

	if type(horse.Acquisition.ObtainedAt) ~= "number" or horse.Acquisition.ObtainedAt <= 0 then
		horse.Acquisition.ObtainedAt = timestamp
		changed = true
	end

	if type(horse.Needs) ~= "table" then
		horse.Needs = {}
		changed = true
	end

	local needs = horse.Needs

	if type(needs.Values) ~= "table" then
		needs.Values = {}
		changed = true
	end

	if type(needs.Max) ~= "table" then
		needs.Max = {}
		changed = true
	end

	if type(needs.DecayPerHour) ~= "table" then
		needs.DecayPerHour = {}
		changed = true
	end

	if type(needs.Modifiers) ~= "table" then
		needs.Modifiers = {}
		changed = true
	end

	if type(needs.ActiveEffects) ~= "table" then
		needs.ActiveEffects = {}
		changed = true
	end

	if type(needs.LastUpdatedAt) ~= "number" or needs.LastUpdatedAt <= 0 then
		needs.LastUpdatedAt = timestamp
		changed = true
	end

	for _, statusName: string in ipairs(STATUS_ORDER) do
		local maxValue = get_definition_status_value(definition, "Max", statusName, DEFAULT_STATUS_MAX)
		local decayPerHour = math.max(0, get_definition_status_value(definition, "DecayPerHour", statusName, 0))
		local startValue = get_definition_status_value(definition, "Starting", statusName, maxValue)
		local currentValue = needs.Values[statusName]

		if type(currentValue) ~= "number" then
			currentValue = startValue
			changed = true
		end

		currentValue = clamp_status_value(statusName, currentValue, maxValue)

		if needs.Max[statusName] ~= maxValue then
			needs.Max[statusName] = maxValue
			changed = true
		end

		if needs.DecayPerHour[statusName] ~= decayPerHour then
			needs.DecayPerHour[statusName] = decayPerHour
			changed = true
		end

		if needs.Values[statusName] ~= currentValue then
			needs.Values[statusName] = currentValue
			changed = true
		end
	end

	if sync_dirty_state(horse) then
		changed = true
	end

	return changed
end

function HorseStatusService.GetOwnedHorseIds(player: Player?): {string}
	local horses = get_horses_container(player)
	if not horses or type(horses.Owned) ~= "table" then
		return {}
	end

	local orderedHorseIds = {}
	local addedHorseIds = {}

	for _, horseId: string in ipairs(horses.OrderedIds or {}) do
		if horses.Owned[horseId] and not addedHorseIds[horseId] then
			addedHorseIds[horseId] = true
			orderedHorseIds[#orderedHorseIds + 1] = horseId
		end
	end

	for horseId in horses.Owned do
		if not addedHorseIds[horseId] then
			addedHorseIds[horseId] = true
			orderedHorseIds[#orderedHorseIds + 1] = horseId
		end
	end

	return orderedHorseIds
end

function HorseStatusService.GetComputedStatuses(horse, now: number?)
	if type(horse) ~= "table" then
		return nil
	end

	local timestamp = if type(now) == "number" then now else os.time()
	HorseStatusService.NormalizeHorse(horse, timestamp)

	local lastUpdatedAt = get_last_updated_at(horse, timestamp)
	local statuses = {}
	local pendingHealthGain = compute_pending_health_gain(horse, lastUpdatedAt, timestamp)

	for _, statusName: string in ipairs(STATUS_ORDER) do
		local maxValue = get_need_max(horse, statusName)
		local value = get_need_value(horse, statusName)

		if statusName == "Health" and pendingHealthGain > 0 then
			value = math.clamp(value + pendingHealthGain, 0, maxValue)
		end

		value = compute_decay(
			value,
			get_decay_per_hour(horse, statusName),
			lastUpdatedAt,
			timestamp,
			get_active_modifier(horse, statusName, lastUpdatedAt, timestamp)
		)

		statuses[statusName] = clamp_status_value(statusName, value, maxValue)
	end

	apply_zero_need_penalties(horse, statuses, lastUpdatedAt, timestamp)

	return statuses
end

function HorseStatusService.ApplyDecay(horse, now: number?): (boolean, {[string]: number}?)
	if type(horse) ~= "table" then
		return false, nil
	end

	local timestamp = if type(now) == "number" then now else os.time()
	local changed = HorseStatusService.NormalizeHorse(horse, timestamp)
	local lastUpdatedAt = get_last_updated_at(horse, timestamp)
	local statuses = HorseStatusService.GetComputedStatuses(horse, timestamp)
	local needs = horse.Needs

	for _, statusName: string in ipairs(STATUS_ORDER) do
		local nextValue = statuses[statusName]

		if needs.Values[statusName] ~= nextValue then
			needs.Values[statusName] = nextValue
			changed = true
		end
	end

	if type(needs.Modifiers) == "table" then
		for statusName, modifier in pairs(needs.Modifiers) do
			if type(modifier) ~= "table" or type(modifier.ExpiresAt) ~= "number" or modifier.ExpiresAt <= timestamp then
				needs.Modifiers[statusName] = nil
				changed = true
			end
		end
	end

	if type(needs.ActiveEffects) == "table" then
		local keptEffects = {}

		for _, effect in ipairs(needs.ActiveEffects) do
			if type(effect) == "table" and effect.Type == "HealthOverTime" then
				local expiresAt = tonumber(effect.ExpiresAt) or timestamp
				local lastTickAt = tonumber(effect.LastTickAt) or lastUpdatedAt
				local remainingGain = math.max(0, tonumber(effect.RemainingGain) or 0)
				local ratePerSecond = math.max(0, tonumber(effect.RatePerSecond) or 0)
				local effectEnd = math.min(timestamp, expiresAt)
				local elapsedSeconds = math.max(0, effectEnd - lastTickAt)
				local appliedGain = math.min(remainingGain, ratePerSecond * elapsedSeconds)

				if appliedGain > 0 then
					effect.RemainingGain = remainingGain - appliedGain
					changed = true
				end

				if effect.LastTickAt ~= effectEnd then
					effect.LastTickAt = effectEnd
					changed = true
				end

				if (effect.RemainingGain or 0) > 0.05 and expiresAt > effectEnd then
					keptEffects[#keptEffects + 1] = effect
				else
					changed = true
				end
			else
				changed = true
			end
		end

		if #keptEffects ~= #needs.ActiveEffects then
			needs.ActiveEffects = keptEffects
		end
	end

	if needs.LastUpdatedAt ~= timestamp then
		needs.LastUpdatedAt = timestamp
		changed = true
	end

	if sync_dirty_state(horse) then
		changed = true
	end

	return changed, statuses
end

function HorseStatusService.GetHorse(playerOrHorseId, horseId: string?): (any?, string?)
	local horses = nil
	local resolvedHorseId = horseId

	if RunService:IsServer() then
		horses = get_horses_container(playerOrHorseId)
	else
		horses = get_horses_container(nil)

		if type(playerOrHorseId) == "string" and playerOrHorseId ~= "" then
			resolvedHorseId = playerOrHorseId
		end
	end

	if not horses or type(horses.Owned) ~= "table" then
		return nil, nil
	end

	if type(resolvedHorseId) ~= "string" or resolvedHorseId == "" then
		resolvedHorseId = resolve_default_horse_id(horses)
	end

	if not resolvedHorseId then
		return nil, nil
	end

	local horse = horses.Owned[resolvedHorseId]
	if not horse then
		return nil, nil
	end

	HorseStatusService.NormalizeHorse(horse)

	return horse, resolvedHorseId
end

function HorseStatusService.GetStatuses(target, horseIdOrNow, now: number?)
	if type(target) == "table" then
		local resolvedNow = if type(horseIdOrNow) == "number" then horseIdOrNow else now
		return HorseStatusService.GetComputedStatuses(target, resolvedNow)
	end

	local horse = nil
	local resolvedNow = now

	if RunService:IsServer() then
		horse = HorseStatusService.GetHorse(target, horseIdOrNow)
	else
		if type(horseIdOrNow) == "number" then
			resolvedNow = horseIdOrNow
			horse = HorseStatusService.GetHorse(target)
		else
			horse = HorseStatusService.GetHorse(target, horseIdOrNow)
		end
	end

	if not horse then
		return nil
	end

	return HorseStatusService.GetComputedStatuses(horse, resolvedNow)
end

function HorseStatusService.GetStatus(target, horseIdOrStatusName, statusNameOrNow, now: number?): number?
	local statusName = nil
	local statuses = nil

	if type(target) == "table" then
		statusName = horseIdOrStatusName
		local resolvedNow = if type(statusNameOrNow) == "number" then statusNameOrNow else now
		statuses = HorseStatusService.GetComputedStatuses(target, resolvedNow)
	elseif RunService:IsServer() then
		statusName = statusNameOrNow
		statuses = HorseStatusService.GetStatuses(target, horseIdOrStatusName, now)
	else
		statusName = horseIdOrStatusName
		local resolvedNow = if type(statusNameOrNow) == "number" then statusNameOrNow else now
		statuses = HorseStatusService.GetStatuses(target, resolvedNow)
	end

	if type(statusName) ~= "string" or not statuses then
		return nil
	end

	return statuses[statusName]
end

return HorseStatusService
