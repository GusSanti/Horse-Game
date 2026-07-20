local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local QuestCatalog = require(GameData:WaitForChild("QuestCatalog"))
local ShopCatalog = require(GameData:WaitForChild("ShopCatalog"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))

local QuestService = {}

local initialized = false
local claimInFlight = {}
local DAILY_ROLLOVER_CHECK_SECONDS = 30

local function normalize_inventory_path(path: string?): string?
	if type(path) ~= "string" then
		return nil
	end

	local trimmedPath = string.gsub(path, "^%s*(.-)%s*$", "%1")
	if trimmedPath == "" then
		return nil
	end

	if string.sub(trimmedPath, 1, #"Inventory.") == "Inventory." then
		return trimmedPath
	end

	return ("Inventory.%s"):format(trimmedPath)
end

local function get_inventory_path(itemDefinition): string?
	if not itemDefinition then
		return nil
	end

	return normalize_inventory_path(itemDefinition.InventoryPath)
end

local function get_item_count(player: Player, itemDefinition): number
	local inventoryPath = get_inventory_path(itemDefinition)
	if not inventoryPath then
		return 0
	end

	local bucket = DataUtility.server.get(player, inventoryPath)
	if type(bucket) ~= "table" then
		return 0
	end

	return bucket[itemDefinition.ItemId] or 0
end

local function set_item_count(player: Player, itemDefinition, amount: number): number
	local inventoryPath = get_inventory_path(itemDefinition)
	local profileData = DataUtility.server.get(player)

	if not inventoryPath or not profileData then
		return 0
	end

	local bucket = TableUtility.EnsurePath(profileData, inventoryPath)
	local normalizedAmount = math.max(0, math.floor(amount or 0))

	if normalizedAmount > 0 then
		bucket[itemDefinition.ItemId] = normalizedAmount
	else
		bucket[itemDefinition.ItemId] = nil
	end

	DataUtility.server.set(player, inventoryPath, bucket)
	return normalizedAmount
end

local function add_item_count(player: Player, itemDefinition, amount: number): number
	return set_item_count(player, itemDefinition, get_item_count(player, itemDefinition) + (amount or 0))
end

local function build_daily_quest_state(player, questId, now)
	local questDefinition = QuestCatalog.GetDefinition(questId)
	local startValue = 0

	if questDefinition and questDefinition.Objective and questDefinition.Objective.StatPath then
		startValue = DataUtility.server.get(player, questDefinition.Objective.StatPath) or 0
	end

	return {
		QuestId = questId,
		AssignedAt = now,
		ExpiresAt = (math.floor(now / 86400) + 1) * 86400,
		StartValue = startValue,
		Progress = 0,
		Goal = questDefinition and questDefinition.Objective.Target or 0,
		Completed = false,
		Claimed = false,
	}
end

local function resolve_daily_progress(player, questState)
	local questDefinition = QuestCatalog.GetDefinition(questState.QuestId)
	if not questDefinition or not questDefinition.Objective then
		return 0, false
	end

	local objective = questDefinition.Objective

	if objective.Mode == "StatDelta" then
		local currentValue = DataUtility.server.get(player, objective.StatPath) or 0
		local startValue = questState.StartValue or 0
		local progress = math.max(0, currentValue - startValue)
		return math.min(progress, objective.Target), progress >= objective.Target
	end

	return 0, false
end

local function grant_item_reward(player, collection, itemId, amount)
	local itemDefinition = ShopCatalog.GetItemDefinition(itemId)
	if not itemDefinition then
		return nil
	end

	add_item_count(player, itemDefinition, amount)

	if itemDefinition.InventoryPath == "Cosmetics" then
		TableUtility.InsertUnique(collection.UnlockedCosmeticIds, itemId)
	end

	return {
		ItemId = itemId,
		Amount = amount,
	}
end

local function grant_rewards(player, rewardDefinition)
	local grantedRewards = {
		Horseshoes = 0,
		Items = {},
	}

	local horseshoesReward = rewardDefinition.Horseshoes or 0
	if horseshoesReward > 0 then
		local currentHorseshoes = DataUtility.server.get(player, "Currencies.Horseshoes") or 0
		local updatedHorseshoes = currentHorseshoes + horseshoesReward

		DataUtility.server.set(player, "Currencies.Horseshoes", updatedHorseshoes)
		grantedRewards.Horseshoes = horseshoesReward
	end

	local itemRewards = rewardDefinition.Items or {}
	if #itemRewards > 0 then
		local collection = DataUtility.server.get(player, "Collection")

		if collection then
			for _, itemReward in ipairs(itemRewards) do
				local grantedItem = grant_item_reward(
					player,
					collection,
					itemReward.ItemId,
					itemReward.Amount or 1
				)

				if grantedItem then
					grantedRewards.Items[#grantedRewards.Items + 1] = grantedItem
				end
			end

			DataUtility.server.set(player, "Collection", collection)
		end
	end

	return grantedRewards
end

function QuestService.Init()
	if initialized then
		return
	end

	Net.Function.ClaimDailyQuest:Respond(function(player)
		return QuestService.ClaimDailyQuest(player)
	end)

	initialized = true

	Players.PlayerRemoving:Connect(function(player)
		claimInFlight[player] = nil
	end)

	task.spawn(function()
		while initialized do
			task.wait(DAILY_ROLLOVER_CHECK_SECONDS)
			for _, player in ipairs(Players:GetPlayers()) do
				QuestService.EnsureDailyQuest(player)
			end
		end
	end)
end

function QuestService.EnsureDailyQuest(player)
	local quests = DataUtility.server.get(player, "Quests")
	if not quests then
		return nil
	end

	local now = os.time()
	local dailyQuest = quests.Daily or {}
	local needsNewQuest = dailyQuest.QuestId == "" or now >= (dailyQuest.ExpiresAt or 0)

	if needsNewQuest then
		local questId = QuestCatalog.GetDailyQuestIdForPlayer(player.UserId, now)
		dailyQuest = build_daily_quest_state(player, questId, now)
		DataUtility.server.set(player, "Quests.Daily", dailyQuest)
		return dailyQuest
	end

	return QuestService.RefreshDailyQuestProgress(player)
end

function QuestService.RefreshDailyQuestProgress(player)
	local dailyQuest = DataUtility.server.get(player, "Quests.Daily")
	if not dailyQuest or dailyQuest.QuestId == "" then
		return nil
	end
	if os.time() >= (dailyQuest.ExpiresAt or 0) then
		return QuestService.EnsureDailyQuest(player)
	end

	local questDefinition = QuestCatalog.GetDefinition(dailyQuest.QuestId)
	local progress, completed = resolve_daily_progress(player, dailyQuest)
	dailyQuest.Progress = progress
	dailyQuest.Completed = completed
	dailyQuest.Goal = questDefinition and questDefinition.Objective.Target or dailyQuest.Goal or 0

	DataUtility.server.set(player, "Quests.Daily", dailyQuest)

	return dailyQuest
end

function QuestService.IncrementStat(player, statPath, amount)
	amount = amount or 1
	QuestService.EnsureDailyQuest(player)

	local currentValue = DataUtility.server.get(player, statPath) or 0
	local updatedValue = currentValue + amount

	DataUtility.server.set(player, statPath, updatedValue)
	QuestService.RefreshDailyQuestProgress(player)

	return updatedValue
end

local function claim_daily_quest_unlocked(player)
	local dailyQuest = QuestService.EnsureDailyQuest(player)
	if not dailyQuest or dailyQuest.QuestId == "" then
		return {
			Success = false,
			Code = "NoActiveQuest",
		}
	end

	dailyQuest = QuestService.RefreshDailyQuestProgress(player)
	if not dailyQuest then
		return {
			Success = false,
			Code = "NoActiveQuest",
		}
	end

	if dailyQuest.Claimed then
		return {
			Success = false,
			Code = "QuestAlreadyClaimed",
			DailyQuest = TableUtility.DeepCopy(dailyQuest),
		}
	end

	if not dailyQuest.Completed then
		return {
			Success = false,
			Code = "QuestNotComplete",
			DailyQuest = TableUtility.DeepCopy(dailyQuest),
		}
	end

	local questDefinition = QuestCatalog.GetDefinition(dailyQuest.QuestId)
	if not questDefinition then
		return {
			Success = false,
			Code = "QuestDefinitionMissing",
		}
	end

	local grantedRewards = grant_rewards(player, questDefinition.Rewards or {})

	dailyQuest.Claimed = true
	DataUtility.server.set(player, "Quests.Daily", dailyQuest)

	local history = DataUtility.server.get(player, "Quests.History")
	if history then
		local lastCompletedDay = math.floor((history.LastCompletedAt or 0) / 86400)
		local currentDay = math.floor(os.time() / 86400)

		history.LastCompletedQuestId = dailyQuest.QuestId
		history.LastCompletedAt = os.time()
		history.CompletedCount = (history.CompletedCount or 0) + 1

		if lastCompletedDay == currentDay - 1 then
			history.CurrentStreak = (history.CurrentStreak or 0) + 1
		elseif lastCompletedDay ~= currentDay then
			history.CurrentStreak = 1
		else
			history.CurrentStreak = math.max(1, history.CurrentStreak or 0)
		end

		history.BestStreak = math.max(history.BestStreak or 0, history.CurrentStreak)
		DataUtility.server.set(player, "Quests.History", history)
	end

	local totalCompleted = (DataUtility.server.get(player, "Stats.TotalQuestsCompleted") or 0) + 1
	DataUtility.server.set(player, "Stats.TotalQuestsCompleted", totalCompleted)

	return {
		Success = true,
		Code = "QuestClaimed",
		QuestId = dailyQuest.QuestId,
		DailyQuest = TableUtility.DeepCopy(dailyQuest),
		Rewards = grantedRewards,
	}
end

function QuestService.ClaimDailyQuest(player)
	if claimInFlight[player] then
		return {
			Success = false,
			Code = "ClaimInProgress",
		}
	end

	claimInFlight[player] = true
	local success, result = pcall(claim_daily_quest_unlocked, player)
	claimInFlight[player] = nil

	if not success then
		warn(("[QuestService] failed to claim daily quest for %s: %s"):format(player.Name, tostring(result)))
		return {
			Success = false,
			Code = "ClaimFailed",
		}
	end

	return result
end

return QuestService
