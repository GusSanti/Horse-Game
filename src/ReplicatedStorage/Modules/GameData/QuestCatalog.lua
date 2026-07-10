local QuestCatalog = {}

local DEFAULT_HORSESHOE_REWARD_AMOUNT = 300

local function create_horseshoe_reward(amount)
	local normalizedAmount = math.max(0, math.floor(tonumber(amount) or 0))

	return {
		Horseshoes = normalizedAmount,
		Items = {},
		Display = {
			Type = "Currency",
			CurrencyId = "Horseshoes",
			ShortName = "HS",
			Amount = normalizedAmount,
			TextFormat = "HS $%d",
			IconKey = "Horseshoe",
		},
	}
end

QuestCatalog.DailyPool = {
	"daily_feed_horse",
	"daily_groom_horse",
	"daily_clean_stable",
	"daily_care_combo",
	"daily_harvest_crop",
	"daily_arena_run",
}

QuestCatalog.Definitions = {
	daily_feed_horse = {
		Id = "daily_feed_horse",
		DisplayName = "Breakfast Time",
		Description = "Feed your horse 3 times.",
		Category = "Daily",
		EstimatedMinutes = 5,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalFeedActions",
			Target = 3,
		},
		Rewards = create_horseshoe_reward(DEFAULT_HORSESHOE_REWARD_AMOUNT),
	},
	daily_groom_horse = {
		Id = "daily_groom_horse",
		DisplayName = "Brush And Shine",
		Description = "Groom your horse 2 times.",
		Category = "Daily",
		EstimatedMinutes = 5,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalGroomActions",
			Target = 2,
		},
		Rewards = create_horseshoe_reward(DEFAULT_HORSESHOE_REWARD_AMOUNT),
	},
	daily_clean_stable = {
		Id = "daily_clean_stable",
		DisplayName = "Fresh Stall",
		Description = "Clean your horse or stall 2 times.",
		Category = "Daily",
		EstimatedMinutes = 5,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalCleanActions",
			Target = 2,
		},
		Rewards = create_horseshoe_reward(DEFAULT_HORSESHOE_REWARD_AMOUNT),
	},
	daily_care_combo = {
		Id = "daily_care_combo",
		DisplayName = "Care Routine",
		Description = "Perform 5 total care actions.",
		Category = "Daily",
		EstimatedMinutes = 8,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalCareActions",
			Target = 5,
		},
		Rewards = create_horseshoe_reward(DEFAULT_HORSESHOE_REWARD_AMOUNT),
	},
	daily_harvest_crop = {
		Id = "daily_harvest_crop",
		DisplayName = "Garden Routine",
		Description = "Harvest 1 crop.",
		Category = "Daily",
		EstimatedMinutes = 6,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalCropsHarvested",
			Target = 1,
		},
		Rewards = create_horseshoe_reward(DEFAULT_HORSESHOE_REWARD_AMOUNT),
	},
	daily_arena_run = {
		Id = "daily_arena_run",
		DisplayName = "Track Warmup",
		Description = "Complete 1 arena run.",
		Category = "Daily",
		EstimatedMinutes = 7,
		Objective = {
			Mode = "StatDelta",
			StatPath = "Stats.TotalArenaRuns",
			Target = 1,
		},
		Rewards = create_horseshoe_reward(DEFAULT_HORSESHOE_REWARD_AMOUNT),
	},
}

function QuestCatalog.GetDefinition(questId)
	return QuestCatalog.Definitions[questId]
end

function QuestCatalog.GetDailyQuestIds()
	return QuestCatalog.DailyPool
end

function QuestCatalog.GetDailyQuestIdForPlayer(userId, timestamp)
	local pool = QuestCatalog.GetDailyQuestIds()
	local dayToken = math.floor(timestamp / 86400)
	local index = ((dayToken + math.abs(userId)) % #pool) + 1
	return pool[index]
end

function QuestCatalog.GetRewardDisplayData(questDefinitionOrId)
	local questDefinition = questDefinitionOrId

	if type(questDefinitionOrId) == "string" then
		questDefinition = QuestCatalog.GetDefinition(questDefinitionOrId)
	end

	local rewards = questDefinition and questDefinition.Rewards or {}
	local display = rewards.Display or {}
	local amount = math.max(0, math.floor(tonumber(display.Amount or rewards.Horseshoes or 0) or 0))
	local shortName = display.ShortName or "Reward"
	local displayText = display.Text

	if type(displayText) ~= "string" or displayText == "" then
		if type(display.TextFormat) == "string" and display.TextFormat ~= "" then
			local ok, formattedText = pcall(string.format, display.TextFormat, amount)
			if ok then
				displayText = formattedText
			end
		end

		if type(displayText) ~= "string" or displayText == "" then
			if amount > 0 then
				displayText = ("%s $%d"):format(shortName, amount)
			else
				displayText = shortName
			end
		end
	end

	return {
		Type = display.Type or "Reward",
		CurrencyId = display.CurrencyId,
		ShortName = shortName,
		Amount = amount,
		Text = displayText,
		IconKey = display.IconKey,
	}
end

return QuestCatalog
