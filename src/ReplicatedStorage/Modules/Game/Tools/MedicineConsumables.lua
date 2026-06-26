local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local medicineToolDefinitions = {}

for _, itemDefinition in ipairs(ToolItemCatalog.GetItemsByToolCategory("Medicine")) do
	medicineToolDefinitions[#medicineToolDefinitions + 1] = {
		id = itemDefinition.ItemId,
		toolNames = {
			itemDefinition.ItemId,
			itemDefinition.DisplayName,
		},
		prompt = {
			actionText = itemDefinition.PromptActionText or "Treat",
			objectText = itemDefinition.PromptObjectText or "Your horse",
			holdDuration = 0.2,
			maxActivationDistance = 10,
			requiresLineOfSight = false,
		},
		consumeOnUse = true,
		onUse = function(context)
			local HorseCareService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseCareService"))
			return HorseCareService.UseMedicalItem(context.player, context.horseId, itemDefinition.ItemId)
		end,
	}
end

return medicineToolDefinitions
