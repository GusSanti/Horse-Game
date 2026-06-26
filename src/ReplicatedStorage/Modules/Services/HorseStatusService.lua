local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))

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

local HorseStatusService = {
	StatusOrder = table.clone(STATUS_ORDER),
}

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

local function get_horses_container(player: Player?)
	if RunService:IsServer() then
		if not is_player(player) then
			return nil
		end

		return DataUtility.server.get(player, "Horses")
	end

	return DataUtility.client.get("Horses")
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

	local definition = HorseCatalog.GetDefinition(horse.CatalogId or "")
	local fallback = definition and definition.Needs and definition.Needs.Max and definition.Needs.Max[statusName]

	if type(fallback) == "number" then
		return math.max(0, fallback)
	end

	return 100
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

	return clamp_number(value, 0, get_need_max(horse, statusName))
end

local function get_decay_per_hour(horse, statusName: string): number
	local needs = horse.Needs or {}
	local decayPerHour = needs.DecayPerHour or {}
	local value = decayPerHour[statusName]

	if type(value) == "number" then
		return math.max(0, value)
	end

	local definition = HorseCatalog.GetDefinition(horse.CatalogId or "")
	local fallback = definition and definition.Needs and definition.Needs.DecayPerHour and definition.Needs.DecayPerHour[statusName]

	if type(fallback) == "number" then
		return math.max(0, fallback)
	end

	return 0
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
		ExpiresAt = modifier.ExpiresAt,
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

local function clamp_status_value(statusName: string, value: number, maxValue: number): number
	if OVERFLOW_ALLOWED_NEEDS[statusName] then
		return math.max(0, value)
	end

	return math.clamp(value, 0, maxValue)
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

	if type(horses) ~= "table" or type(horses.Owned) ~= "table" then
		return nil, nil
	end

	if type(resolvedHorseId) ~= "string" or resolvedHorseId == "" then
		resolvedHorseId = resolve_default_horse_id(horses)
	end

	if not resolvedHorseId then
		return nil, nil
	end

	return horses.Owned[resolvedHorseId], resolvedHorseId
end

function HorseStatusService.GetOwnedHorseIds(player: Player?): {string}
	local horses = get_horses_container(player)
	if type(horses) ~= "table" or type(horses.Owned) ~= "table" then
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
