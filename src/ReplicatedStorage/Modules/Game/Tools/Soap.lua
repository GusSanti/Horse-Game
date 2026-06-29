------------------//SERVICES
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//VARIABLES
local soap = {
	id = "soap",
	toolNames = {
		"soap",
	},
	clientHandlerName = "SoapClient",
	prompt = {
		actionText = "Wash",
		objectText = "Your horse",
		holdDuration = 0.2,
		maxActivationDistance = 10,
		requiresLineOfSight = false,
	},
	consumeOnUse = true,
	onUse = function(context)
		local modules: Folder = ReplicatedStorage:WaitForChild("Modules")
		local utility: Folder = modules:WaitForChild("Utility")
		local DataUtility = require(utility:WaitForChild("DataUtility"))
		local QuestService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("QuestService"))

		local horses = DataUtility.server.get(context.player, "Horses")
		local stats = DataUtility.server.get(context.player, "Stats")
		if not horses or not horses.Owned or not horses.Owned[context.horseId] then
			return false, "HorseNotOwned"
		end

		local horse = horses.Owned[context.horseId]
		local now = os.time()
		local cleanBonus = 0

		if horse.Bond and horse.Bond.CareBonus then
			cleanBonus = horse.Bond.CareBonus.Clean or 0
		end

		if horse.Needs and horse.Needs.Values and horse.Needs.Max then
			horse.Needs.Values.Cleanliness = horse.Needs.Max.Cleanliness or horse.Needs.Values.Cleanliness
			horse.Needs.Values.Happiness = math.clamp(
				(horse.Needs.Values.Happiness or 0) + math.max(2, math.floor(cleanBonus * 0.5)),
				0,
				horse.Needs.Max.Happiness or 100
			)
		end

		if horse.State then
			horse.State.IsDirty = false
			horse.State.LastCleanedAt = now
			horse.State.LastCareAt = now
			horse.State.Mood = "Fresh"
		end

		if horse.Stats then
			horse.Stats.CareActions = (horse.Stats.CareActions or 0) + 1
		end

		if horse.Bond then
			horse.Bond.Friendship = math.clamp(
				(horse.Bond.Friendship or 0) + cleanBonus,
				0,
				horse.Bond.MaxFriendship or 100
			)
		end

		DataUtility.server.set(context.player, "Horses", horses)

		if stats then
			stats.TotalCareActions = (stats.TotalCareActions or 0) + 1
			stats.TotalCleanActions = (stats.TotalCleanActions or 0) + 1
			DataUtility.server.set(context.player, "Stats", stats)
			QuestService.RefreshDailyQuestProgress(context.player)
		end

		return true, "Cleaned"
	end,
}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
return soap
