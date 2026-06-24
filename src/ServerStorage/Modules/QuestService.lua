local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))
local QuestCatalog = require(GameData:WaitForChild("QuestCatalog"))
local ShopCatalog = require(GameData:WaitForChild("ShopCatalog"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))

local QuestService = {}

local initialized = false
local claimDailyQuestRemote

local function ensure_gameplay_remotes()
	local gameplayRemotes = ReplicatedStorage:FindFirstChild(NetworkConfig.GameplayFolderName)
	if not gameplayRemotes then
		gameplayRemotes = Instance.new("Folder")
		gameplayRemotes.Name = NetworkConfig.GameplayFolderName
		gameplayRemotes.Parent = ReplicatedStorage
	end

	local claimRemote = gameplayRemotes:FindFirstChild(NetworkConfig.Quest.ClaimDailyQuest)
	if not claimRemote then
		claimRemote = Instance.new("RemoteFunction")
		claimRemote.Name = NetworkConfig.Quest.ClaimDailyQuest
		claimRemote.Parent = gameplayRemotes
	end

	return claimRemote
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

local function grant_item_reward(inventory, collection, itemId, amount)
	local itemDefinition = ShopCatalog.GetItemDefinition(itemId)
	if not itemDefinition then
		return nil
	end

	local inventoryBucket = TableUtility.EnsurePath(inventory, itemDefinition.InventoryPath)
	inventoryBucket[itemId] = (inventoryBucket[itemId] or 0) + amount

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
		local inventory = DataUtility.server.get(player, "Inventory")
		local collection = DataUtility.server.get(player, "Collection")

		if inventory and collection then
			for _, itemReward in ipairs(itemRewards) do
				local grantedItem = grant_item_reward(
					inventory,
					collection,
					itemReward.ItemId,
					itemReward.Amount or 1
				)

				if grantedItem then
					grantedRewards.Items[#grantedRewards.Items + 1] = grantedItem
				end
			end

			DataUtility.server.set(player, "Inventory", inventory)
			DataUtility.server.set(player, "Collection", collection)
		end
	end

	return grantedRewards
end

function QuestService.Init()
	if initialized then
		return
	end

	claimDailyQuestRemote = ensure_gameplay_remotes()
	claimDailyQuestRemote.OnServerInvoke = function(player)
		return QuestService.ClaimDailyQuest(player)
	end

	initialized = true
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

	local currentValue = DataUtility.server.get(player, statPath) or 0
	local updatedValue = currentValue + amount

	DataUtility.server.set(player, statPath, updatedValue)
	QuestService.RefreshDailyQuestProgress(player)

	return updatedValue
end

function QuestService.ClaimDailyQuest(player)
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

return QuestService
