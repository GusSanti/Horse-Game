local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local Net = require(Libraries:WaitForChild("Net"))

local QuestClient = {}

function QuestClient.GetDailyQuestState()
	return DataUtility.client.get("Quests.Daily")
end

function QuestClient.BindDailyQuestChanged(fn)
	return DataUtility.client.bind("Quests.Daily", fn)
end

function QuestClient.ClaimDailyQuestReward()
	return Net.Function.ClaimDailyQuest:Call()
end

return QuestClient
