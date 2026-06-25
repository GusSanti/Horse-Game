local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Network = Modules:WaitForChild("Network")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local Net = require(Network:WaitForChild("Net"))
local QuestCatalog = require(GameData:WaitForChild("QuestCatalog"))

local QuestClient = {}

function QuestClient.GetDailyQuestState()
	return DataUtility.client.get("Quests.Daily")
end

function QuestClient.GetDailyQuestDefinition()
	local dailyQuestState = QuestClient.GetDailyQuestState()
	if not dailyQuestState or dailyQuestState.QuestId == "" then
		return nil
	end

	return QuestCatalog.GetDefinition(dailyQuestState.QuestId)
end

function QuestClient.BindDailyQuestChanged(fn)
	return DataUtility.client.bind("Quests.Daily", fn)
end

function QuestClient.ClaimDailyQuestReward()
	return Net.Function.ClaimDailyQuest:Call()
end

return QuestClient
