local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local ToolItems = require(GameData:WaitForChild("ToolItems"))

local ToolItemCatalog = {
	Items = ToolItems.Items,
	Shops = ToolItems.Shops,
	CategoryDefinitions = ToolItems.CategoryDefinitions,
	CategoryOrder = ToolItems.CategoryOrder,
}

local orderedDefinitions = ToolItems.GetOrderedItems()
local definitionsById = {}
local definitionsByDisplayName = {}

local function normalize_key(value)
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function get_tool_category(itemDefinition)
	if type(itemDefinition.ToolCategory) == "string" and itemDefinition.ToolCategory ~= "" then
		return itemDefinition.ToolCategory
	end

	if type(itemDefinition.CareType) == "string" and itemDefinition.CareType ~= "" then
		return itemDefinition.CareType
	end

	if type(itemDefinition.UseType) == "string" and itemDefinition.UseType ~= "" then
		return itemDefinition.UseType
	end

	return "Misc"
end

local function build_tool_tip(itemDefinition)
	if type(itemDefinition.ToolTip) == "string" and itemDefinition.ToolTip ~= "" then
		return itemDefinition.ToolTip
	end

	local priceLabel = itemDefinition.PriceLabel or ((itemDefinition.Price or 0) .. " coin")
	local effects = itemDefinition.Effects or {}

	if itemDefinition.NeedKey and effects.NeedGain then
		return string.format(
			"%s | %s +%d | Happiness +%d",
			priceLabel,
			itemDefinition.NeedKey,
			effects.NeedGain or 0,
			effects.HappinessGain or 0
		)
	end

	if effects.HealthGain then
		return string.format(
			"%s | Health +%d | Happiness %+d",
			priceLabel,
			effects.HealthGain or 0,
			effects.HappinessGain or 0
		)
	end

	if type(itemDefinition.Description) == "string" and itemDefinition.Description ~= "" then
		return string.format("%s | %s", priceLabel, itemDefinition.Description)
	end

	return priceLabel
end

for _, definition in ipairs(orderedDefinitions) do
	local itemId = normalize_key(definition.ItemId or definition.id)
	if itemId then
		definition.ItemId = itemId
		definition.id = itemId
		definition.ToolCategory = get_tool_category(definition)
		definition.ToolTip = build_tool_tip(definition)

		if type(definition.DisplayName) ~= "string" or definition.DisplayName == "" then
			definition.DisplayName = definition.ItemId
		end

		definitionsById[itemId] = definition
		definitionsByDisplayName[normalize_key(definition.DisplayName)] = definition
	end
end

function ToolItemCatalog.NormalizeKey(value)
	return normalize_key(value)
end

function ToolItemCatalog.GetItemDefinition(itemId)
	local normalizedItemId = normalize_key(itemId)
	if not normalizedItemId then
		return nil
	end

	return definitionsById[normalizedItemId]
end

function ToolItemCatalog.GetAllItems()
	local items = {}

	for index, itemDefinition in ipairs(orderedDefinitions) do
		items[index] = itemDefinition
	end

	return items
end

function ToolItemCatalog.GetItemsByToolCategory(categoryName)
	local items = {}
	local normalizedCategoryName = normalize_key(categoryName)

	for _, itemDefinition in ipairs(orderedDefinitions) do
		if normalize_key(get_tool_category(itemDefinition)) == normalizedCategoryName then
			items[#items + 1] = itemDefinition
		end
	end

	return items
end

function ToolItemCatalog.GetToolCategory(itemDefinition)
	return get_tool_category(itemDefinition)
end

function ToolItemCatalog.IsToolItem(itemId)
	return ToolItemCatalog.GetItemDefinition(itemId) ~= nil
end

function ToolItemCatalog.GetCategories()
	return ToolItems.GetCategories()
end

function ToolItemCatalog.GetCategoryFolderName(categoryIdOrItemDefinition)
	return ToolItems.GetCategoryFolderName(categoryIdOrItemDefinition)
end

function ToolItemCatalog.GetShopDefinition(shopId)
	return ToolItems.GetShopDefinition(shopId)
end

function ToolItemCatalog.GetItemsForShop(shopId)
	return ToolItems.GetItemsForShop(shopId)
end

function ToolItemCatalog.ResolveDefinitionFromTool(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local explicitItemId = normalize_key(tool:GetAttribute("ToolItemId"))
	if explicitItemId and definitionsById[explicitItemId] then
		return definitionsById[explicitItemId]
	end

	local legacyItemId = normalize_key(tool:GetAttribute("ItemId"))
	if legacyItemId and definitionsById[legacyItemId] then
		return definitionsById[legacyItemId]
	end

	local normalizedToolName = normalize_key(tool.Name)
	if normalizedToolName and definitionsByDisplayName[normalizedToolName] then
		return definitionsByDisplayName[normalizedToolName]
	end

	return ToolItemCatalog.GetItemDefinition(tool.Name)
end

function ToolItemCatalog.ApplyToolMetadata(tool, itemDefinition)
	tool.Name = itemDefinition.DisplayName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = itemDefinition.ToolTip
	tool:SetAttribute("ToolItemId", itemDefinition.ItemId)
	tool:SetAttribute("ItemId", itemDefinition.ItemId)
	tool:SetAttribute("ToolCategory", itemDefinition.ToolCategory)
	tool:SetAttribute("CategoryFolder", ToolItems.GetCategoryFolderName(itemDefinition))
	tool:SetAttribute("InventoryPath", itemDefinition.InventoryPath or "")
	tool:SetAttribute("PlaceholderPrice", itemDefinition.Price or 0)
	tool:SetAttribute("PlaceholderPriceLabel", itemDefinition.PriceLabel or "")
	tool:SetAttribute("PlaceholderDescription", itemDefinition.Description or "")
	tool:SetAttribute("ShopId", itemDefinition.ShopId or "")

	if itemDefinition.CareType then
		tool:SetAttribute("CareType", itemDefinition.CareType)
	end

	if itemDefinition.UseType then
		tool:SetAttribute("UseType", itemDefinition.UseType)
	end

	return tool
end

return ToolItemCatalog
