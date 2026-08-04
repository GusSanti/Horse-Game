local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local CareItemCatalog = require(GameData:WaitForChild("CareItemCatalog"))

local careToolDefinitions = {}

for _, itemDefinition in ipairs(CareItemCatalog.GetAllItems()) do
	careToolDefinitions[#careToolDefinitions + 1] = {
		id = itemDefinition.ItemId,
		toolNames = {
			itemDefinition.ItemId,
			itemDefinition.DisplayName,
			itemDefinition.ToolName,
		},
		clientHandlerName = if itemDefinition.CareType == "Food" then "HorseFeedClient" else nil,
		prompt = {
			actionText = itemDefinition.PromptActionText or "Use",
			objectText = itemDefinition.PromptObjectText or "Your horse",
			holdDuration = 0.15,
			maxActivationDistance = 10,
			requiresLineOfSight = false,
		},
		consumeOnUse = true,
		onUse = function(context)
			local HorseCareService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("Horse"):WaitForChild("HorseCareService"))
			return HorseCareService.UseCareItem(context.player, context.horseId, itemDefinition.ItemId, context.tool)
		end,
	}
end

return careToolDefinitions
