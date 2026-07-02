------------------//SERVICES
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//CONSTANTS
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local HORSE_BRUSH_ITEM_ID = "horse_brush"

------------------//VARIABLES
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local horseBrush = {
	id = HORSE_BRUSH_ITEM_ID,
	toolNames = {
		HORSE_BRUSH_ITEM_ID,
		"Horse Brush",
	},
	clientHandlerName = "HorseBrushClient",
	prompt = {
		actionText = "Brush",
		objectText = "Your horse",
		holdDuration = 1.5,
		maxActivationDistance = 10,
		requiresLineOfSight = false,
	},
	consumeOnUse = true,
	onUse = function(context)
		local QuestService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("QuestService"))
		local HorseCareService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseCareService"))

		local itemDefinition = ToolItemCatalog.GetItemDefinition(HORSE_BRUSH_ITEM_ID)
		if not itemDefinition then
			return false, "ItemDefinitionMissing"
		end

		local horses = DataUtility.server.get(context.player, "Horses")
		local stats = DataUtility.server.get(context.player, "Stats")
		if not horses or not horses.Owned or not horses.Owned[context.horseId] then
			return false, "HorseNotOwned"
		end

		local horse = horses.Owned[context.horseId]
		local now = os.time()
		HorseCareService.RefreshHorse(horse, now)

		horse.Needs = horse.Needs or {}
		horse.Needs.Values = horse.Needs.Values or {}
		horse.Needs.Max = horse.Needs.Max or {}
		horse.State = horse.State or {}
		horse.Stats = horse.Stats or {}

		local effects = itemDefinition.Effects or {}
		local happinessGain = math.max(0, effects.HappinessGain or 0)
		local maxHappiness = horse.Needs.Max.Happiness or 100

		horse.Needs.Values.Happiness = math.clamp(
			(horse.Needs.Values.Happiness or 0) + happinessGain,
			0,
			maxHappiness
		)
		horse.State.LastGroomedAt = now
		horse.State.LastCareAt = now
		horse.State.Mood = effects.MoodText or "Pampered"
		horse.Stats.CareActions = (horse.Stats.CareActions or 0) + 1

		DataUtility.server.set(context.player, "Horses", horses)

		if stats then
			stats.TotalCareActions = (stats.TotalCareActions or 0) + 1
			stats.TotalGroomActions = (stats.TotalGroomActions or 0) + 1
			DataUtility.server.set(context.player, "Stats", stats)
			QuestService.RefreshDailyQuestProgress(context.player)
		end

		return true, itemDefinition.ResponseCode or "Brushed"
	end,
}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
return horseBrush
