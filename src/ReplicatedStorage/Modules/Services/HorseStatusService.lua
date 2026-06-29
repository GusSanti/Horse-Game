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

local HorseStatusService = {}

HorseStatusService.StatusOrder = TableUtility.DeepCopy(STATUS_ORDER)

local function is_player(value): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
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

local function clamp_status_value(value: number, maxValue: number): number
	local resolvedValue = if type(value) == "number" then value else 0
	local resolvedMax = if type(maxValue) == "number" then math.max(0, maxValue) else DEFAULT_STATUS_MAX

	return math.clamp(resolvedValue, 0, resolvedMax)
end

local function sync_dirty_state(horse): boolean
	if type(horse.State) ~= "table" then
		horse.State = {}
	end

	local maxCleanliness = tonumber(horse.Needs.Max.Cleanliness) or DEFAULT_STATUS_MAX
	local currentCleanliness = tonumber(horse.Needs.Values.Cleanliness) or 0
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

		currentValue = clamp_status_value(currentValue, maxValue)

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

function HorseStatusService.GetComputedStatuses(horse, now: number?)
	if type(horse) ~= "table" then
		return nil
	end

	local timestamp = if type(now) == "number" then now else os.time()
	HorseStatusService.NormalizeHorse(horse, timestamp)

	local needs = horse.Needs
	local lastUpdatedAt = needs.LastUpdatedAt or timestamp
	local elapsedSeconds = math.max(0, timestamp - math.min(lastUpdatedAt, timestamp))
	local elapsedHours = elapsedSeconds / 3600
	local statuses = {}

	for _, statusName: string in ipairs(STATUS_ORDER) do
		local maxValue = tonumber(needs.Max[statusName]) or DEFAULT_STATUS_MAX
		local currentValue = clamp_status_value(needs.Values[statusName], maxValue)
		local decayPerHour = math.max(0, tonumber(needs.DecayPerHour[statusName]) or 0)

		statuses[statusName] = clamp_status_value(currentValue - (decayPerHour * elapsedHours), maxValue)
	end

	return statuses
end

function HorseStatusService.ApplyDecay(horse, now: number?): (boolean, {[string]: number}?)
	if type(horse) ~= "table" then
		return false, nil
	end

	local timestamp = if type(now) == "number" then now else os.time()
	local changed = HorseStatusService.NormalizeHorse(horse, timestamp)
	local statuses = HorseStatusService.GetComputedStatuses(horse, timestamp)
	local needs = horse.Needs

	for _, statusName: string in ipairs(STATUS_ORDER) do
		local nextValue = statuses[statusName]

		if needs.Values[statusName] ~= nextValue then
			needs.Values[statusName] = nextValue
			changed = true
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
