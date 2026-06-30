local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local ToolItems = require(GameData:WaitForChild("ToolItems"))

local CareItemCatalog = {}

local orderedDefinitions = {}
local categoryOrder = { "Food", "Water" }

local function should_include_in_care_catalog(categoryId, itemDefinition)
	if categoryId == "Food" or categoryId == "Water" then
		return itemDefinition.CareType == categoryId
	end

	return true
end

for _, categoryId in ipairs(categoryOrder) do
	for _, itemDefinition in ipairs(ToolItems.GetItemsByToolCategory(categoryId)) do
		if should_include_in_care_catalog(categoryId, itemDefinition) then
			orderedDefinitions[#orderedDefinitions + 1] = itemDefinition
		end
	end
end

CareItemCatalog.Items = {}
CareItemCatalog.OrderedIds = {}

for _, itemDefinition in ipairs(orderedDefinitions) do
	CareItemCatalog.Items[itemDefinition.ItemId] = itemDefinition
	CareItemCatalog.OrderedIds[#CareItemCatalog.OrderedIds + 1] = itemDefinition.ItemId
end

function CareItemCatalog.GetItemDefinition(itemId)
	return CareItemCatalog.Items[itemId]
end

function CareItemCatalog.GetOrderedIds()
	local orderedIds = {}

	for index, itemId in ipairs(CareItemCatalog.OrderedIds) do
		orderedIds[index] = itemId
	end

	return orderedIds
end

function CareItemCatalog.GetAllItems()
	local items = {}

	for _, itemId in ipairs(CareItemCatalog.OrderedIds) do
		items[#items + 1] = CareItemCatalog.Items[itemId]
	end

	return items
end

function CareItemCatalog.GetItemsByCareType(careType)
	local items = {}

	for _, itemId in ipairs(CareItemCatalog.OrderedIds) do
		local itemDefinition = CareItemCatalog.Items[itemId]
		if itemDefinition and itemDefinition.CareType == careType then
			items[#items + 1] = itemDefinition
		end
	end

	return items
end

function CareItemCatalog.IsCareItem(itemId)
	return CareItemCatalog.Items[itemId] ~= nil
end

return CareItemCatalog
