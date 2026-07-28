local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local saddleDefinitions = {}

for _, itemDefinition in ipairs(ToolItemCatalog.GetItemsByToolCategory("Tack")) do
	if itemDefinition.EquipmentType == "Saddle" then
		saddleDefinitions[#saddleDefinitions + 1] = {
			id = itemDefinition.ItemId,
			toolNames = {
				itemDefinition.ItemId,
				itemDefinition.DisplayName,
			},
			prompt = {
				actionText = "Equip",
				objectText = "Your horse",
				holdDuration = 0.6,
				maxActivationDistance = 10,
				requiresLineOfSight = false,
			},
			interactionDuration = 0.75,
			consumeOnUse = false,
			onUse = function(context)
				local HorseEquipmentService = require(
					ServerStorage:WaitForChild("Modules")
						:WaitForChild("Horse")
						:WaitForChild("HorseEquipmentService")
				)
				return HorseEquipmentService.EquipSaddle(context.player, context.horseId, context.itemId)
			end,
		}
	end
end

return saddleDefinitions
