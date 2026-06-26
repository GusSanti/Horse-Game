local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local CareItemCatalog = require(GameData:WaitForChild("CareItemCatalog"))
local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local QuestService = require(script.Parent:WaitForChild("QuestService"))

local HorseCareService = {}

local CARE_TYPE_TO_NEED = {
	Food = "Hunger",
	Water = "Thirst",
}

local CARE_TYPE_TO_RESPONSE = {
	Food = "Fed",
	Water = "Watered",
}

local CARE_TYPE_TO_STAT_KEY = {
	Food = "TotalFeedActions",
	Water = "TotalWaterActions",
}

local CARE_TYPE_TO_LAST_USED_KEY = {
	Food = "LastFedAt",
	Water = "LastWateredAt",
}

local TRACKED_NEEDS = {
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

local function clamp_number(value, minValue, maxValue)
	if type(value) ~= "number" then
		return minValue
	end

	if value < minValue then
		return minValue
	end

	if value > maxValue then
		return maxValue
	end

	return value
end

local function ensure_state_field(state, fieldName)
	if type(state[fieldName]) ~= "number" then
		state[fieldName] = 0
		return true
	end

	return false
end

local function ensure_horse_shape(horse, now)
	local changed = false
	local definition = HorseCatalog.GetDefinition(horse.CatalogId or "") or HorseCatalog.GetDefinition("Default")
	local definitionNeeds = definition and definition.Needs or nil
	local definitionMax = definitionNeeds and definitionNeeds.Max or {}
	local definitionDecay = definitionNeeds and definitionNeeds.DecayPerHour or {}

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

	for _, needKey in ipairs(TRACKED_NEEDS) do
		local expectedMax = type(definitionMax[needKey]) == "number" and definitionMax[needKey] or 100
		local expectedDecay = type(definitionDecay[needKey]) == "number" and definitionDecay[needKey] or 0

		if needs.Max[needKey] ~= expectedMax then
			needs.Max[needKey] = expectedMax
			changed = true
		end

		if type(needs.Values[needKey]) ~= "number" then
			needs.Values[needKey] = needs.Max[needKey]
			changed = true
		end

		if needs.DecayPerHour[needKey] ~= expectedDecay then
			needs.DecayPerHour[needKey] = expectedDecay
			changed = true
		end
	end

	if type(needs.LastUpdatedAt) ~= "number" then
		needs.LastUpdatedAt = now
		changed = true
	end

	if type(horse.State) ~= "table" then
		horse.State = {}
		changed = true
	end

	local state = horse.State
	changed = ensure_state_field(state, "LastCareAt") or changed
	changed = ensure_state_field(state, "LastFedAt") or changed
	changed = ensure_state_field(state, "LastWateredAt") or changed
	changed = ensure_state_field(state, "LastMedicatedAt") or changed
	changed = ensure_state_field(state, "LastGroomedAt") or changed
	changed = ensure_state_field(state, "LastCleanedAt") or changed

	if type(state.Mood) ~= "string" or state.Mood == "" then
		state.Mood = "Curious"
		changed = true
	end

	if type(horse.Stats) ~= "table" then
		horse.Stats = {}
		changed = true
	end

	if type(horse.Stats.CareActions) ~= "number" then
		horse.Stats.CareActions = 0
		changed = true
	end

	return changed
end

local function get_active_modifier(needs, needKey, lastUpdatedAt, now)
	local modifier = needs.Modifiers[needKey]
	if type(modifier) ~= "table" then
		needs.Modifiers[needKey] = nil
		return nil, false
	end

	if type(modifier.ExpiresAt) ~= "number" then
		needs.Modifiers[needKey] = nil
		return nil, true
	end

	modifier.Multiplier = clamp_number(modifier.Multiplier or 1, 0.1, 5)

	if modifier.ExpiresAt <= lastUpdatedAt then
		needs.Modifiers[needKey] = nil
		return nil, true
	end

	return modifier, modifier.ExpiresAt <= now
end

local function compute_segment_decay(baseDecayPerHour, elapsedSeconds, multiplier)
	if elapsedSeconds <= 0 or baseDecayPerHour <= 0 then
		return 0
	end

	return baseDecayPerHour * multiplier * (elapsedSeconds / 3600)
end

local function apply_decay(currentValue, baseDecayPerHour, lastUpdatedAt, now, modifier)
	if now <= lastUpdatedAt or baseDecayPerHour <= 0 then
		return currentValue
	end

	if modifier and modifier.ExpiresAt > lastUpdatedAt then
		local modifierEnd = math.min(now, modifier.ExpiresAt)
		local modifierSeconds = math.max(0, modifierEnd - lastUpdatedAt)
		local normalSeconds = math.max(0, now - modifierEnd)

		currentValue -= compute_segment_decay(baseDecayPerHour, modifierSeconds, modifier.Multiplier or 1)
		currentValue -= compute_segment_decay(baseDecayPerHour, normalSeconds, 1)
		return currentValue
	end

	currentValue -= compute_segment_decay(baseDecayPerHour, now - lastUpdatedAt, 1)
	return currentValue
end

local function has_zero_other_need(valuesByNeed, targetNeed): boolean
	for _, needKey in ipairs(TRACKED_NEEDS) do
		if needKey ~= targetNeed and (valuesByNeed[needKey] or 0) <= 0 then
			return true
		end
	end

	return false
end

local function clamp_need_value(needKey, value, maxValues)
	if OVERFLOW_ALLOWED_NEEDS[needKey] then
		return math.max(0, value)
	end

	return math.clamp(value, 0, maxValues[needKey] or 100)
end

local function apply_zero_need_penalties(updatedValues, decayPerHour, lastUpdatedAt, now, modifiersByNeed, maxValues)
	for targetNeed, multiplier in pairs(ZERO_NEED_DECAY_MULTIPLIER) do
		if multiplier > 1 and has_zero_other_need(updatedValues, targetNeed) then
			local extraDecayPerHour = math.max(0, (decayPerHour[targetNeed] or 0) * (multiplier - 1))

			if extraDecayPerHour > 0 then
				updatedValues[targetNeed] = clamp_need_value(
					targetNeed,
					apply_decay(updatedValues[targetNeed] or 0, extraDecayPerHour, lastUpdatedAt, now, modifiersByNeed[targetNeed]),
					maxValues
				)
			end
		end
	end
end

local function is_item_favorite(horse, itemDefinition)
	local dependencies = horse.Dependencies
	if type(dependencies) ~= "table" then
		return false
	end

	local careType = itemDefinition.CareType
	local favoriteList

	if careType == "Food" then
		favoriteList = dependencies.FavoriteFoods
	elseif careType == "Water" then
		favoriteList = dependencies.FavoriteWaters
	end

	if type(favoriteList) ~= "table" then
		return false
	end

	for _, favoriteItemId in ipairs(favoriteList) do
		if favoriteItemId == itemDefinition.ItemId then
			return true
		end
	end

	return false
end

local function get_overflow_limit(itemDefinition, maxValue)
	local effects = itemDefinition.Effects or {}
	local overflowCap = effects.OverflowCap

	if type(overflowCap) ~= "number" then
		overflowCap = math.max(30, math.floor(maxValue * 0.6))
	end

	return maxValue + overflowCap
end

local function apply_decay_modifier(horse, itemDefinition, now)
	local effects = itemDefinition.Effects or {}
	local decayBuff = effects.DecayBuff
	if type(decayBuff) ~= "table" then
		return false
	end

	local needKey = itemDefinition.NeedKey or CARE_TYPE_TO_NEED[itemDefinition.CareType]
	if type(needKey) ~= "string" or needKey == "" then
		return false
	end

	local durationMinutes = decayBuff.DurationMinutes or 0
	if durationMinutes <= 0 then
		return false
	end

	local newModifier = {
		Multiplier = clamp_number(decayBuff.Multiplier or 1, 0.1, 1),
		ExpiresAt = now + math.floor(durationMinutes * 60),
		SourceItemId = itemDefinition.ItemId,
		SourceDisplayName = itemDefinition.DisplayName,
	}

	local currentModifier = horse.Needs.Modifiers[needKey]
	if type(currentModifier) ~= "table" or (currentModifier.ExpiresAt or 0) <= now then
		horse.Needs.Modifiers[needKey] = newModifier
		return true
	end

	local shouldReplace = newModifier.Multiplier < (currentModifier.Multiplier or 1)
		or newModifier.ExpiresAt > (currentModifier.ExpiresAt or 0)

	if shouldReplace then
		currentModifier.Multiplier = math.min(currentModifier.Multiplier or 1, newModifier.Multiplier)
		currentModifier.ExpiresAt = math.max(currentModifier.ExpiresAt or 0, newModifier.ExpiresAt)
		currentModifier.SourceItemId = newModifier.SourceItemId
		currentModifier.SourceDisplayName = newModifier.SourceDisplayName
		return true
	end

	return false
end

local function update_horse_mood(horse, moodText, healthPenalty)
	if healthPenalty > 0 then
		horse.State.Mood = "Overloaded"
		return
	end

	if type(moodText) == "string" and moodText ~= "" then
		horse.State.Mood = moodText
		return
	end

	horse.State.Mood = "Content"
end

local function apply_active_effects(horse, lastUpdatedAt, now)
	local changed = false
	local needs = horse.Needs
	local values = needs.Values
	local maxValues = needs.Max
	local activeEffects = needs.ActiveEffects
	local keptEffects = {}

	for _, effect in ipairs(activeEffects) do
		if type(effect) == "table" and effect.Type == "HealthOverTime" then
			local expiresAt = effect.ExpiresAt or now
			local lastTickAt = effect.LastTickAt or lastUpdatedAt
			local remainingGain = effect.RemainingGain or 0
			local ratePerSecond = effect.RatePerSecond or 0
			local effectEnd = math.min(now, expiresAt)
			local elapsedSeconds = math.max(0, effectEnd - lastTickAt)
			local appliedGain = math.min(remainingGain, ratePerSecond * elapsedSeconds)

			if appliedGain > 0 then
				values.Health = math.clamp(
					(values.Health or 0) + appliedGain,
					0,
					maxValues.Health or 100
				)
				effect.RemainingGain = remainingGain - appliedGain
				changed = true
			end

			effect.LastTickAt = effectEnd

			if (effect.RemainingGain or 0) > 0.05 and expiresAt > effectEnd then
				keptEffects[#keptEffects + 1] = effect
			else
				changed = true
			end
		else
			changed = true
		end
	end

	if #keptEffects ~= #activeEffects then
		needs.ActiveEffects = keptEffects
		return true
	end

	return changed
end

local function add_health_over_time_effect(horse, itemDefinition, now)
	local effects = itemDefinition.Effects or {}
	local healthRegen = effects.HealthRegen
	if type(healthRegen) ~= "table" then
		return false
	end

	local totalGain = healthRegen.TotalGain or 0
	local durationMinutes = healthRegen.DurationMinutes or 0
	local durationSeconds = math.max(1, math.floor(durationMinutes * 60))

	if totalGain <= 0 or durationMinutes <= 0 then
		return false
	end

	horse.Needs.ActiveEffects[#horse.Needs.ActiveEffects + 1] = {
		Type = "HealthOverTime",
		SourceItemId = itemDefinition.ItemId,
		SourceDisplayName = itemDefinition.DisplayName,
		RemainingGain = totalGain,
		RatePerSecond = totalGain / durationSeconds,
		StartedAt = now,
		LastTickAt = now,
		ExpiresAt = now + durationSeconds,
	}

	return true
end

local function apply_secondary_need_adjustments(values, maxValues, adjustments)
	if type(adjustments) ~= "table" then
		return false
	end

	local changed = false

	for needKey, delta in pairs(adjustments) do
		if type(delta) == "number" and type(values[needKey]) == "number" then
			local updatedValue = math.clamp(
				values[needKey] + delta,
				0,
				maxValues[needKey] or 100
			)

			if updatedValue ~= values[needKey] then
				values[needKey] = updatedValue
				changed = true
			end
		end
	end

	return changed
end

local function apply_overflow_relief(values, maxValues, overflowReliefList)
	if type(overflowReliefList) ~= "table" then
		return 0
	end

	local relievedAmount = 0

	for _, needKey in ipairs(overflowReliefList) do
		local currentValue = values[needKey]
		local maxValue = maxValues[needKey]

		if type(currentValue) == "number" and type(maxValue) == "number" and currentValue > maxValue then
			relievedAmount += currentValue - maxValue
			values[needKey] = maxValue
		end
	end

	return relievedAmount
end

function HorseCareService.RefreshHorse(horse, now)
	now = now or os.time()

	local changed = ensure_horse_shape(horse, now)
	local needs = horse.Needs
	local values = needs.Values
	local maxValues = needs.Max
	local decayPerHour = needs.DecayPerHour
	local lastUpdatedAt = needs.LastUpdatedAt or now

	if now <= lastUpdatedAt then
		return changed
	end

	if apply_active_effects(horse, lastUpdatedAt, now) then
		changed = true
	end

	local updatedValues = {}
	local modifiersByNeed = {}
	local shouldClearModifierByNeed = {}

	for _, needKey in ipairs(TRACKED_NEEDS) do
		local modifier, shouldClearModifier = get_active_modifier(needs, needKey, lastUpdatedAt, now)
		local currentValue = values[needKey] or 0

		modifiersByNeed[needKey] = modifier
		shouldClearModifierByNeed[needKey] = shouldClearModifier
		updatedValues[needKey] = clamp_need_value(
			needKey,
			apply_decay(currentValue, decayPerHour[needKey] or 0, lastUpdatedAt, now, modifier),
			maxValues
		)
	end

	apply_zero_need_penalties(updatedValues, decayPerHour, lastUpdatedAt, now, modifiersByNeed, maxValues)

	for _, needKey in ipairs(TRACKED_NEEDS) do
		local currentValue = values[needKey] or 0
		local updatedValue = updatedValues[needKey]

		if updatedValue ~= currentValue then
			values[needKey] = updatedValue
			changed = true
		end

		if shouldClearModifierByNeed[needKey] then
			needs.Modifiers[needKey] = nil
			changed = true
		end
	end

	needs.LastUpdatedAt = now
	return true
end

function HorseCareService.RefreshPlayerHorse(player, horseId)
	local horses = DataUtility.server.get(player, "Horses")
	if not horses or not horses.Owned or not horses.Owned[horseId] then
		return nil, false
	end

	local horse = horses.Owned[horseId]
	local changed = HorseCareService.RefreshHorse(horse, os.time())
	if changed then
		DataUtility.server.set(player, "Horses", horses)
	end

	return horse, changed
end

function HorseCareService.RefreshAllPlayerHorses(player)
	local horses = DataUtility.server.get(player, "Horses")
	if not horses or not horses.Owned then
		return false
	end

	local changed = false
	local now = os.time()

	for _, horse in pairs(horses.Owned) do
		if HorseCareService.RefreshHorse(horse, now) then
			changed = true
		end
	end

	if changed then
		DataUtility.server.set(player, "Horses", horses)
	end

	return changed
end

function HorseCareService.UseCareItem(player, horseId, itemId)
	local itemDefinition = CareItemCatalog.GetItemDefinition(itemId)
	if not itemDefinition then
		return false, "ItemDefinitionMissing"
	end

	local needKey = itemDefinition.NeedKey or CARE_TYPE_TO_NEED[itemDefinition.CareType]
	if type(needKey) ~= "string" then
		return false, "InvalidCareType"
	end

	local horses = DataUtility.server.get(player, "Horses")
	local stats = DataUtility.server.get(player, "Stats")
	if not horses or not horses.Owned or not horses.Owned[horseId] then
		return false, "HorseNotOwned"
	end

	local horse = horses.Owned[horseId]
	local now = os.time()
	HorseCareService.RefreshHorse(horse, now)

	local needs = horse.Needs
	local values = needs.Values
	local maxValues = needs.Max
	local targetValue = values[needKey] or 0
	local maxValue = maxValues[needKey] or 100
	local effects = itemDefinition.Effects or {}

	local baseNeedGain = math.max(0, effects.NeedGain or 0)
	local normalCapacity = math.max(0, maxValue - targetValue)
	local normalGain = math.min(baseNeedGain, normalCapacity)
	local overflowInput = math.max(0, baseNeedGain - normalGain)

	local overflowLimit = get_overflow_limit(itemDefinition, maxValue)
	local overflowAlready = math.max(0, targetValue - maxValue)
	local overflowRange = math.max(1, overflowLimit - maxValue)
	local overflowDepthRatio = math.clamp(overflowAlready / overflowRange, 0, 1)
	local overflowYield = clamp_number(
		(effects.OverflowYield or 0.25) * (1 - (overflowDepthRatio * 0.75)),
		0.05,
		0.65
	)

	local remainingOverflowCapacity = math.max(0, overflowLimit - (targetValue + normalGain))
	local overflowGain = math.min(remainingOverflowCapacity, overflowInput * overflowYield)
	local totalNeedGain = normalGain + overflowGain
	local updatedNeedValue = math.min(overflowLimit, targetValue + totalNeedGain)
	values[needKey] = updatedNeedValue

	local overflowShare = 0
	if baseNeedGain > 0 then
		overflowShare = math.clamp(overflowInput / baseNeedGain, 0, 1)
	end

	local favoriteBonus = is_item_favorite(horse, itemDefinition) and 1 or 0
	local overflowHappinessFactor = clamp_number(effects.OverflowHappinessFactor or 0.3, 0.1, 1)
	local happinessGain = (effects.HappinessGain or 0)
		* ((1 - overflowShare) + (overflowHappinessFactor * overflowShare))
		+ (favoriteBonus * 2)

	values.Happiness = math.clamp(
		(values.Happiness or 0) + happinessGain,
		0,
		maxValues.Happiness or 100
	)

	local overflowPressure = math.max(0, updatedNeedValue - maxValue)
	local healthPenalty = overflowPressure * (effects.OverflowHealthPenalty or 0.12)
	local healthDelta = (effects.HealthGain or 0) - healthPenalty
	values.Health = math.clamp(
		(values.Health or 0) + healthDelta,
		0,
		maxValues.Health or 100
	)

	local friendshipGain = math.max(1, math.floor((effects.FriendshipGain or 1) * (overflowPressure > 0 and 0.6 or 1)))
	if favoriteBonus > 0 then
		friendshipGain += 1
	end

	if type(horse.Bond) == "table" then
		horse.Bond.Friendship = math.clamp(
			(horse.Bond.Friendship or 0) + friendshipGain,
			0,
			horse.Bond.MaxFriendship or 100
		)
	end

	apply_decay_modifier(horse, itemDefinition, now)

	local lastUsedStateKey = CARE_TYPE_TO_LAST_USED_KEY[itemDefinition.CareType]
	if lastUsedStateKey then
		horse.State[lastUsedStateKey] = now
	end

	horse.State.LastCareAt = now
	update_horse_mood(horse, effects.MoodText, healthPenalty)

	if type(horse.Stats) == "table" then
		horse.Stats.CareActions = (horse.Stats.CareActions or 0) + 1
	end

	DataUtility.server.set(player, "Horses", horses)

	if stats then
		stats.TotalCareActions = (stats.TotalCareActions or 0) + 1

		local statKey = CARE_TYPE_TO_STAT_KEY[itemDefinition.CareType]
		if statKey then
			stats[statKey] = (stats[statKey] or 0) + 1
		end

		DataUtility.server.set(player, "Stats", stats)
		QuestService.RefreshDailyQuestProgress(player)
	end

	return true, CARE_TYPE_TO_RESPONSE[itemDefinition.CareType] or "Used"
end

function HorseCareService.UseMedicalItem(player, horseId, itemId)
	local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
	if not itemDefinition or itemDefinition.UseType ~= "Medicine" then
		return false, "ItemDefinitionMissing"
	end

	local horses = DataUtility.server.get(player, "Horses")
	local stats = DataUtility.server.get(player, "Stats")
	if not horses or not horses.Owned or not horses.Owned[horseId] then
		return false, "HorseNotOwned"
	end

	local horse = horses.Owned[horseId]
	local now = os.time()
	HorseCareService.RefreshHorse(horse, now)

	local needs = horse.Needs
	local values = needs.Values
	local maxValues = needs.Max
	local effects = itemDefinition.Effects or {}

	values.Health = math.clamp(
		(values.Health or 0) + math.max(0, effects.HealthGain or 0),
		0,
		maxValues.Health or 100
	)

	values.Happiness = math.clamp(
		(values.Happiness or 0) + (effects.HappinessGain or 0),
		0,
		maxValues.Happiness or 100
	)

	apply_secondary_need_adjustments(values, maxValues, effects.SecondaryNeedAdjustments)
	apply_overflow_relief(values, maxValues, effects.OverflowRelief)
	add_health_over_time_effect(horse, itemDefinition, now)

	local friendshipGain = math.max(1, effects.FriendshipGain or 1)
	if type(horse.Bond) == "table" then
		horse.Bond.Friendship = math.clamp(
			(horse.Bond.Friendship or 0) + friendshipGain,
			0,
			horse.Bond.MaxFriendship or 100
		)
	end

	horse.State.LastMedicatedAt = now
	horse.State.LastCareAt = now
	update_horse_mood(horse, effects.MoodText, 0)

	if type(horse.Stats) == "table" then
		horse.Stats.CareActions = (horse.Stats.CareActions or 0) + 1
	end

	DataUtility.server.set(player, "Horses", horses)

	if stats then
		stats.TotalCareActions = (stats.TotalCareActions or 0) + 1
		stats.TotalMedicalActions = (stats.TotalMedicalActions or 0) + 1
		DataUtility.server.set(player, "Stats", stats)
		QuestService.RefreshDailyQuestProgress(player)
	end

	return true, itemDefinition.ResponseCode or "Treated"
end

return HorseCareService
