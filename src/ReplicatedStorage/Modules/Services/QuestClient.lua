local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))
local QuestCatalog = require(GameData:WaitForChild("QuestCatalog"))

local gameplayRemotes = ReplicatedStorage:WaitForChild(NetworkConfig.GameplayFolderName)
local claimDailyQuestRemote = gameplayRemotes:WaitForChild(NetworkConfig.Quest.ClaimDailyQuest)

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
	return claimDailyQuestRemote:InvokeServer()
end

return QuestClient
