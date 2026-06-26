local Categories = require(script:WaitForChild("Categories"))
local ShopDefinitions = require(script:WaitForChild("ShopDefinitions"))

local ToolItems = {
	Items = {},
	OrderedItems = {},
	ItemsByCategory = {},
	Shops = {},
	CategoryDefinitions = Categories.Definitions,
	CategoryOrder = Categories.Order,
}

local categoryOrderLookup = {}

for index, categoryId in ipairs(ToolItems.CategoryOrder) do
	categoryOrderLookup[categoryId] = index
end

local function compare_items(left, right)
	local leftCategoryIndex = categoryOrderLookup[left.ToolCategory] or math.huge
	local rightCategoryIndex = categoryOrderLookup[right.ToolCategory] or math.huge

	if leftCategoryIndex ~= rightCategoryIndex then
		return leftCategoryIndex < rightCategoryIndex
	end

	local leftSort = left.SortOrder or math.huge
	local rightSort = right.SortOrder or math.huge

	if leftSort ~= rightSort then
		return leftSort < rightSort
	end

	return (left.DisplayName or left.ItemId) < (right.DisplayName or right.ItemId)
end

local function copy_array(values)
	local clone = {}

	for index, value in ipairs(values) do
		clone[index] = value
	end

	return clone
end

local function initialize_shops()
	for shopId, shopDefinition in pairs(ShopDefinitions) do
		ToolItems.Shops[shopId] = {
			ShopId = shopDefinition.ShopId,
			DisplayName = shopDefinition.DisplayName,
			ItemIds = {},
		}
	end
end

local function register_item(itemDefinition)
	local itemId = itemDefinition.ItemId
	local toolCategory = itemDefinition.ToolCategory

	assert(type(itemId) == "string" and itemId ~= "", "Tool item definition is missing ItemId")
	assert(type(toolCategory) == "string" and toolCategory ~= "", ("Tool item '%s' is missing ToolCategory"):format(itemId))
	assert(ToolItems.Items[itemId] == nil, ("Duplicate tool item id '%s'"):format(itemId))

	ToolItems.Items[itemId] = itemDefinition
	ToolItems.OrderedItems[#ToolItems.OrderedItems + 1] = itemDefinition
	ToolItems.ItemsByCategory[toolCategory] = ToolItems.ItemsByCategory[toolCategory] or {}
	ToolItems.ItemsByCategory[toolCategory][#ToolItems.ItemsByCategory[toolCategory] + 1] = itemDefinition

	local shopId = itemDefinition.ShopId
	if shopId ~= nil then
		assert(
			ToolItems.Shops[shopId] ~= nil,
			("Tool item '%s' references unknown shop '%s'"):format(itemId, tostring(shopId))
		)

		ToolItems.Shops[shopId].ItemIds[#ToolItems.Shops[shopId].ItemIds + 1] = itemId
	end
end

local function initialize_items()
	initialize_shops()

	for _, categoryId in ipairs(ToolItems.CategoryOrder) do
		ToolItems.ItemsByCategory[categoryId] = ToolItems.ItemsByCategory[categoryId] or {}

		local moduleScript = script:WaitForChild(categoryId)
		local items = require(moduleScript)

		for _, itemDefinition in ipairs(items) do
			register_item(itemDefinition)
		end
	end

	table.sort(ToolItems.OrderedItems, compare_items)

	for _, categoryId in ipairs(ToolItems.CategoryOrder) do
		table.sort(ToolItems.ItemsByCategory[categoryId], compare_items)
	end

	for _, shopDefinition in pairs(ToolItems.Shops) do
		table.sort(shopDefinition.ItemIds, function(leftId, rightId)
			return compare_items(ToolItems.Items[leftId], ToolItems.Items[rightId])
		end)
	end
end

function ToolItems.GetItemDefinition(itemId)
	return ToolItems.Items[itemId]
end

function ToolItems.GetOrderedItems()
	return copy_array(ToolItems.OrderedItems)
end

function ToolItems.GetToolCategory(itemDefinition)
	return itemDefinition and itemDefinition.ToolCategory or nil
end

function ToolItems.GetCategoryDefinition(categoryId)
	return ToolItems.CategoryDefinitions[categoryId]
end

function ToolItems.GetCategoryFolderName(categoryIdOrItemDefinition)
	local categoryId = categoryIdOrItemDefinition

	if type(categoryIdOrItemDefinition) == "table" then
		categoryId = ToolItems.GetToolCategory(categoryIdOrItemDefinition)
	end

	local categoryDefinition = ToolItems.GetCategoryDefinition(categoryId)
	return categoryDefinition and categoryDefinition.FolderName or tostring(categoryId or "Items")
end

function ToolItems.GetCategories()
	local categories = {}

	for _, categoryId in ipairs(ToolItems.CategoryOrder) do
		categories[#categories + 1] = ToolItems.CategoryDefinitions[categoryId]
	end

	return categories
end

function ToolItems.GetItemsByToolCategory(categoryId)
	return ToolItems.ItemsByCategory[categoryId] or {}
end

function ToolItems.GetShopDefinition(shopId)
	return ToolItems.Shops[shopId]
end

function ToolItems.GetItemsForShop(shopId)
	local shopDefinition = ToolItems.GetShopDefinition(shopId)
	if not shopDefinition then
		return {}
	end

	local items = {}

	for _, itemId in ipairs(shopDefinition.ItemIds) do
		local itemDefinition = ToolItems.GetItemDefinition(itemId)
		if itemDefinition then
			items[#items + 1] = itemDefinition
		end
	end

	return items
end

function ToolItems.ResolveDefinitionFromTool(tool)
	if not tool then
		return nil
	end

	local itemId = tool:GetAttribute("ToolItemId") or tool:GetAttribute("ItemId")
	if type(itemId) ~= "string" or itemId == "" then
		return nil
	end

	return ToolItems.GetItemDefinition(itemId)
end

function ToolItems.ApplyToolMetadata(tool, itemDefinition)
	local categoryId = ToolItems.GetToolCategory(itemDefinition)
	local categoryDefinition = ToolItems.GetCategoryDefinition(categoryId)

	tool.Name = itemDefinition.ToolName or itemDefinition.DisplayName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = itemDefinition.ToolTip or itemDefinition.Description or ""
	tool:SetAttribute("ToolItemId", itemDefinition.ItemId)
	tool:SetAttribute("ItemId", itemDefinition.ItemId)
	tool:SetAttribute("ToolCategory", categoryId or "")
	tool:SetAttribute("CategoryFolder", categoryDefinition and categoryDefinition.FolderName or "")
	tool:SetAttribute("InventoryPath", itemDefinition.InventoryPath or "")
	tool:SetAttribute("PlaceholderPrice", itemDefinition.Price or 0)
	tool:SetAttribute("PlaceholderPriceLabel", itemDefinition.PriceLabel or "")
	tool:SetAttribute("PlaceholderDescription", itemDefinition.Description or "")
	tool:SetAttribute("ShopId", itemDefinition.ShopId or "")
	return tool
end

initialize_items()

return ToolItems
