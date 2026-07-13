local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local InventoryLoadout = {}

InventoryLoadout.HOTBAR_ITEM_IDS_PATH = "SavedTools.HotbarItemIds"
InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH = "SavedTools.HotbarGenericToolNames"
InventoryLoadout.HOTBAR_INITIALIZED_PATH = "SavedTools.HotbarLoadoutInitialized"

InventoryLoadout.DEFAULT_GENERIC_TOOL_DEFINITIONS = {
	{
		ToolName = "Regadera",
		DisplayName = "Watering Can",
		Description = "A default watering tool that can be added to your hotbar whenever you need it.",
		SortOrder = 5,
	},
}

InventoryLoadout.DEFAULT_ITEM_IDS = {
	"soap",
	"horse_brush",
}

local function normalize_item_id(value)
	return ToolItemCatalog.NormalizeKey(value)
end

local function normalize_generic_tool_name(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	if trimmedValue == "" then
		return nil
	end

	return trimmedValue
end

local function contains_value(values, targetValue, normalizer)
	local normalizedTargetValue = normalizer(targetValue)
	if not normalizedTargetValue then
		return false
	end

	for _, value in ipairs(values or {}) do
		if normalizer(value) == normalizedTargetValue then
			return true
		end
	end

	return false
end

local function set_value_equipped(values, targetValue, isEquipped, normalizer)
	local normalizedTargetValue = normalizer(targetValue)
	local nextValues = {}
	local alreadyPresent = false

	if not normalizedTargetValue then
		return nextValues
	end

	for _, value in ipairs(values or {}) do
		local normalizedValue = normalizer(value)
		if normalizedValue and normalizedValue ~= normalizedTargetValue then
			nextValues[#nextValues + 1] = value
		elseif normalizedValue == normalizedTargetValue then
			alreadyPresent = true
			if isEquipped then
				nextValues[#nextValues + 1] = value
			end
		end
	end

	if isEquipped and not alreadyPresent then
		nextValues[#nextValues + 1] = targetValue
	end

	return nextValues
end

function InventoryLoadout.NormalizeItemId(value)
	return normalize_item_id(value)
end

function InventoryLoadout.NormalizeGenericToolName(value)
	return normalize_generic_tool_name(value)
end

function InventoryLoadout.IsItemEquipped(itemIds, itemId)
	return contains_value(itemIds, itemId, normalize_item_id)
end

function InventoryLoadout.IsGenericToolEquipped(toolNames, toolName)
	return contains_value(toolNames, toolName, normalize_generic_tool_name)
end

function InventoryLoadout.SetItemEquipped(itemIds, itemId, isEquipped)
	return set_value_equipped(itemIds, itemId, isEquipped, normalize_item_id)
end

function InventoryLoadout.SetGenericToolEquipped(toolNames, toolName, isEquipped)
	return set_value_equipped(toolNames, toolName, isEquipped, normalize_generic_tool_name)
end

function InventoryLoadout.IsDefaultItemId(itemId)
	for _, defaultItemId in ipairs(InventoryLoadout.DEFAULT_ITEM_IDS) do
		if normalize_item_id(defaultItemId) == normalize_item_id(itemId) then
			return true
		end
	end

	return false
end

function InventoryLoadout.GetDefaultItemIds()
	local itemIds = {}

	for index, itemId in ipairs(InventoryLoadout.DEFAULT_ITEM_IDS) do
		itemIds[index] = itemId
	end

	return itemIds
end

function InventoryLoadout.IsDefaultGenericToolName(toolName)
	for _, definition in ipairs(InventoryLoadout.DEFAULT_GENERIC_TOOL_DEFINITIONS) do
		if normalize_generic_tool_name(definition.ToolName) == normalize_generic_tool_name(toolName) then
			return true
		end
	end

	return false
end

function InventoryLoadout.GetDefaultGenericToolDefinitions()
	local definitions = {}

	for index, definition in ipairs(InventoryLoadout.DEFAULT_GENERIC_TOOL_DEFINITIONS) do
		definitions[index] = {
			ToolName = definition.ToolName,
			DisplayName = definition.DisplayName,
			Description = definition.Description,
			SortOrder = definition.SortOrder,
		}
	end

	return definitions
end

return InventoryLoadout