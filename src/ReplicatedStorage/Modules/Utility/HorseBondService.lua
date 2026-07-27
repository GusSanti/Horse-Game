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

local REWARD_WINDOW_SECONDS = 300
local GOOD_AVERAGE_THRESHOLD = 70
local GOOD_MIN_THRESHOLD = 45
local EXCELLENT_AVERAGE_THRESHOLD = 85
local EXCELLENT_MIN_THRESHOLD = 65
local BASE_XP_PER_WINDOW = 3
local EXCELLENT_XP_BONUS = 2
local BASE_FRIENDSHIP_PER_WINDOW = 1
local EXCELLENT_FRIENDSHIP_BONUS = 1
local STREAK_STEP = 3
local STREAK_XP_BONUS = 1
local MAX_STREAK_BONUS_STEPS = 4
local MAX_LEVEL_XP = 0

local HorseBondService = {}

local function is_player(value): boolean
	return typeof(value) == "Instance" and value:IsA("Player")
end

local function get_definition_for_horse(horse)
	local catalogId = if type(horse) == "table" then horse.CatalogId else nil
	return HorseCatalog.GetDefinition(catalogId) or HorseCatalog.GetDefinition("Default")
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

local function clamp_number(value: number, minValue: number, maxValue: number): number
	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return value
end

local function get_status_snapshot(horse)
	local needs = horse.Needs or {}
	local values = needs.Values or {}
	local maxValues = needs.Max or {}
	local snapshot = {}

	for _, statusName: string in ipairs(STATUS_ORDER) do
		local currentValue = tonumber(values[statusName]) or 0
		local maxValue = math.max(1, tonumber(maxValues[statusName]) or 100)
		snapshot[statusName] = clamp_number(currentValue, 0, maxValue)
	end

	return snapshot
end

local function get_care_quality(horse): (string, number, number)
	local statuses = get_status_snapshot(horse)
	local total = 0
	local count = 0
	local minValue = math.huge

	for _, statusName: string in ipairs(STATUS_ORDER) do
		local value = statuses[statusName]
		total += value
		count += 1
		minValue = math.min(minValue, value)
	end

	local average = if count > 0 then total / count else 0

	if average >= EXCELLENT_AVERAGE_THRESHOLD and minValue >= EXCELLENT_MIN_THRESHOLD then
		return "Excellent", average, minValue
	end

	if average >= GOOD_AVERAGE_THRESHOLD and minValue >= GOOD_MIN_THRESHOLD then
		return "Good", average, minValue
	end

	return "Poor", average, minValue
end

function HorseBondService.GetXPToNextLevel(level: number): number
	return 15 + (math.max(1, math.floor(level)) - 1) * 10
end

function HorseBondService.GetTrustState(friendship: number, maxFriendship: number): string
	local ratio = 0

	if type(maxFriendship) == "number" and maxFriendship > 0 then
		ratio = friendship / maxFriendship
	end

	if ratio >= 0.9 then
		return "Soulbound"
	end

	if ratio >= 0.75 then
		return "Trusted"
	end

	if ratio >= 0.5 then
		return "Bonded"
	end

	if ratio >= 0.25 then
		return "Warming Up"
	end

	return "Wary"
end

function HorseBondService.NormalizeBond(horse, now: number?): boolean
	if type(horse) ~= "table" then
		return false
	end

	local timestamp = if type(now) == "number" then now else os.time()
	local definition = get_definition_for_horse(horse)
	local bonding = definition and definition.Bonding or {}
	local changed = false

	if type(horse.Bond) ~= "table" then
		horse.Bond = {}
		changed = true
	end

	local bond = horse.Bond
	local maxLevel = math.max(1, math.floor(tonumber(bonding.MaxBondLevel) or 10))
	local maxFriendship = math.max(1, tonumber(bonding.MaxFriendship) or 100)
	local startingFriendship = clamp_number(tonumber(bonding.StartingFriendship) or 0, 0, maxFriendship)
	local careBonus = bonding.CareBonus

	if type(bond.Level) ~= "number" then
		bond.Level = 1
		changed = true
	end

	local normalizedLevel = clamp_number(math.floor(bond.Level), 1, maxLevel)
	if bond.Level ~= normalizedLevel then
		bond.Level = normalizedLevel
		changed = true
	end

	if type(bond.MaxLevel) ~= "number" or bond.MaxLevel ~= maxLevel then
		bond.MaxLevel = maxLevel
		changed = true
	end

	local xpToNextLevel = HorseBondService.GetXPToNextLevel(bond.Level)
	if type(bond.XP) ~= "number" then
		bond.XP = 0
		changed = true
	end

	local normalizedXP = clamp_number(bond.XP, 0, if bond.Level >= maxLevel then MAX_LEVEL_XP else xpToNextLevel)
	if bond.XP ~= normalizedXP then
		bond.XP = normalizedXP
		changed = true
	end

	if type(bond.TotalXP) ~= "number" then
		bond.TotalXP = 0
		changed = true
	end

	local normalizedTotalXP = math.max(0, math.floor(bond.TotalXP))
	if bond.TotalXP ~= normalizedTotalXP then
		bond.TotalXP = normalizedTotalXP
		changed = true
	end

	if type(bond.Friendship) ~= "number" then
		bond.Friendship = startingFriendship
		changed = true
	end

	local normalizedFriendship = clamp_number(bond.Friendship, 0, maxFriendship)
	if bond.Friendship ~= normalizedFriendship then
		bond.Friendship = normalizedFriendship
		changed = true
	end

	if type(bond.MaxFriendship) ~= "number" or bond.MaxFriendship ~= maxFriendship then
		bond.MaxFriendship = maxFriendship
		changed = true
	end

	if type(bond.CareBonus) ~= "table" then
		bond.CareBonus = type(careBonus) == "table" and table.clone(careBonus) or {}
		changed = true
	end

	if type(bond.LastProgressAt) ~= "number" or bond.LastProgressAt <= 0 then
		bond.LastProgressAt = timestamp
		changed = true
	end

	if type(bond.AccruedCareSeconds) ~= "number" then
		bond.AccruedCareSeconds = 0
		changed = true
	end

	local normalizedAccruedCareSeconds = math.max(0, bond.AccruedCareSeconds)
	if bond.AccruedCareSeconds ~= normalizedAccruedCareSeconds then
		bond.AccruedCareSeconds = normalizedAccruedCareSeconds
		changed = true
	end

	if type(bond.CareStreak) ~= "number" then
		bond.CareStreak = 0
		changed = true
	end

	local normalizedCareStreak = math.max(0, math.floor(bond.CareStreak))
	if bond.CareStreak ~= normalizedCareStreak then
		bond.CareStreak = normalizedCareStreak
		changed = true
	end

	if type(bond.BestCareStreak) ~= "number" then
		bond.BestCareStreak = bond.CareStreak
		changed = true
	end

	local normalizedBestCareStreak = math.max(bond.CareStreak, math.floor(bond.BestCareStreak))
	if bond.BestCareStreak ~= normalizedBestCareStreak then
		bond.BestCareStreak = normalizedBestCareStreak
		changed = true
	end

	if type(bond.SuccessfulCareWindows) ~= "number" then
		bond.SuccessfulCareWindows = 0
		changed = true
	end

	local normalizedSuccessfulCareWindows = math.max(0, math.floor(bond.SuccessfulCareWindows))
	if bond.SuccessfulCareWindows ~= normalizedSuccessfulCareWindows then
		bond.SuccessfulCareWindows = normalizedSuccessfulCareWindows
		changed = true
	end

	if type(bond.LastQualifiedAt) ~= "number" then
		bond.LastQualifiedAt = 0
		changed = true
	end

	if type(bond.TrustState) ~= "string" or bond.TrustState == "" then
		bond.TrustState = HorseBondService.GetTrustState(bond.Friendship, bond.MaxFriendship)
		changed = true
	end

	return changed
end

local function apply_xp_gain(bond, xpGain: number): number
	local appliedXP = 0

	if bond.Level >= bond.MaxLevel then
		bond.XP = MAX_LEVEL_XP
		return appliedXP
	end

	bond.XP += xpGain
	bond.TotalXP += xpGain
	appliedXP += xpGain

	while bond.Level < bond.MaxLevel do
		local xpToNext = HorseBondService.GetXPToNextLevel(bond.Level)
		if bond.XP < xpToNext then
			break
		end

		bond.XP -= xpToNext
		bond.Level += 1

		if bond.Level >= bond.MaxLevel then
			bond.Level = bond.MaxLevel
			bond.XP = MAX_LEVEL_XP
			break
		end
	end

	return appliedXP
end

function HorseBondService.ApplyPassiveProgress(horse, now: number?): (boolean, number)
	if type(horse) ~= "table" then
		return false, 0
	end

	local timestamp = if type(now) == "number" then now else os.time()
	local changed = HorseBondService.NormalizeBond(horse, timestamp)
	local bond = horse.Bond
	local elapsedSeconds = math.max(0, timestamp - math.min(bond.LastProgressAt, timestamp))

	if elapsedSeconds <= 0 then
		return changed, 0
	end

	local quality = get_care_quality(horse)
	if quality == "Poor" then
		if bond.AccruedCareSeconds ~= 0 then
			bond.AccruedCareSeconds = 0
			changed = true
		end

		if bond.CareStreak ~= 0 then
			bond.CareStreak = 0
			changed = true
		end

		if bond.TrustState ~= HorseBondService.GetTrustState(bond.Friendship, bond.MaxFriendship) then
			bond.TrustState = HorseBondService.GetTrustState(bond.Friendship, bond.MaxFriendship)
			changed = true
		end

		if bond.LastProgressAt ~= timestamp then
			bond.LastProgressAt = timestamp
			changed = true
		end

		return changed, 0
	end

	local totalSeconds = bond.AccruedCareSeconds + elapsedSeconds
	local successfulWindows = math.floor(totalSeconds / REWARD_WINDOW_SECONDS)
	bond.AccruedCareSeconds = totalSeconds % REWARD_WINDOW_SECONDS

	local xpGained = 0
	local friendshipGained = 0

	if successfulWindows > 0 then
		for _ = 1, successfulWindows do
			bond.CareStreak += 1
			bond.BestCareStreak = math.max(bond.BestCareStreak, bond.CareStreak)

			local streakBonusSteps = math.min(MAX_STREAK_BONUS_STEPS, math.floor((bond.CareStreak - 1) / STREAK_STEP))
			local xpForWindow = BASE_XP_PER_WINDOW + (streakBonusSteps * STREAK_XP_BONUS)
			local friendshipForWindow = BASE_FRIENDSHIP_PER_WINDOW

			if quality == "Excellent" then
				xpForWindow += EXCELLENT_XP_BONUS
				friendshipForWindow += EXCELLENT_FRIENDSHIP_BONUS
			end

			xpGained += apply_xp_gain(bond, xpForWindow)
			friendshipGained += friendshipForWindow
		end

		bond.SuccessfulCareWindows += successfulWindows
		bond.LastQualifiedAt = timestamp
		changed = true
	end

	if friendshipGained > 0 then
		local updatedFriendship = clamp_number(bond.Friendship + friendshipGained, 0, bond.MaxFriendship)
		if updatedFriendship ~= bond.Friendship then
			bond.Friendship = updatedFriendship
			changed = true
		end
	end

	local trustState = HorseBondService.GetTrustState(bond.Friendship, bond.MaxFriendship)
	if bond.TrustState ~= trustState then
		bond.TrustState = trustState
		changed = true
	end

	if bond.LastProgressAt ~= timestamp then
		bond.LastProgressAt = timestamp
		changed = true
	end

	return changed, xpGained
end

function HorseBondService.GetHorse(playerOrHorseId, horseId: string?): (any?, string?)
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

	HorseBondService.NormalizeBond(horse)
	return horse, resolvedHorseId
end

function HorseBondService.GetDisplayData(target, horseId: string?)
	local horse = nil

	if type(target) == "table" then
		horse = target
	else
		horse = HorseBondService.GetHorse(target, horseId)
	end

	if not horse then
		return nil
	end

	HorseBondService.NormalizeBond(horse)
	local bond = horse.Bond
	local xpToNext = if bond.Level >= bond.MaxLevel then 0 else HorseBondService.GetXPToNextLevel(bond.Level)
	local progressAlpha = if xpToNext > 0 then bond.XP / xpToNext else 1
	local careQuality = get_care_quality(horse)

	return {
		Level = bond.Level,
		XP = bond.XP,
		XPToNextLevel = xpToNext,
		ProgressAlpha = progressAlpha,
		Friendship = bond.Friendship,
		MaxFriendship = bond.MaxFriendship,
		TrustState = bond.TrustState,
		CareStreak = bond.CareStreak,
		BestCareStreak = bond.BestCareStreak,
		SuccessfulCareWindows = bond.SuccessfulCareWindows,
		CareQuality = careQuality,
	}
end

return HorseBondService
