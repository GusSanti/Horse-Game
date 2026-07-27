local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local ToolItems = require(GameData:WaitForChild("ToolItems"))

local CareItemCatalog = {}

local orderedDefinitions = {}
local definitionsById = {}

for _, categoryId in ipairs({ "Food", "Water" }) do
	for _, itemDefinition in ipairs(ToolItems.GetItemsByToolCategory(categoryId)) do
		if itemDefinition.CareType == categoryId then
			orderedDefinitions[#orderedDefinitions + 1] = itemDefinition
			definitionsById[itemDefinition.ItemId] = itemDefinition
		end
	end
end

function CareItemCatalog.GetItemDefinition(itemId)
	return definitionsById[itemId]
end

function CareItemCatalog.GetAllItems()
	local items = {}

	for index, itemDefinition in ipairs(orderedDefinitions) do
		items[index] = itemDefinition
	end

	return items
end

return CareItemCatalog
