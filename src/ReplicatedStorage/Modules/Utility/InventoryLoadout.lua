local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local InventoryLoadout = {}

InventoryLoadout.MAX_HOTBAR_SLOTS = 9
InventoryLoadout.HOTBAR_ITEM_IDS_PATH = "SavedTools.HotbarItemIds"
InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH = "SavedTools.HotbarGenericToolNames"
InventoryLoadout.HOTBAR_ORDER_PATH = "SavedTools.HotbarOrder"
InventoryLoadout.HOTBAR_INITIALIZED_PATH = "SavedTools.HotbarLoadoutInitialized"

InventoryLoadout.DEFAULT_GENERIC_TOOL_DEFINITIONS = {
	{
		ToolName = "Regadera",
		DisplayName = "Watering Can",
		Description = "A default watering tool that can be added to your hotbar whenever you need it.",
		IconImage = "rbxassetid://83258208986073",
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

local function copy_normalized_values(values, normalizer)
	local nextValues = {}
	local seen = {}

	for _, value in ipairs(values or {}) do
		local normalizedValue = normalizer(value)
		if normalizedValue and not seen[normalizedValue] then
			seen[normalizedValue] = true
			nextValues[#nextValues + 1] = value
		end
	end

	return nextValues
end

local function get_entry_normalizer(kind)
	if kind == "item" then
		return normalize_item_id
	end

	if kind == "generic" then
		return normalize_generic_tool_name
	end

	return nil
end

function InventoryLoadout.GetEntryKey(kind, value): string?
	local normalizer = get_entry_normalizer(kind)
	local normalizedValue = normalizer and normalizer(value) or nil
	return if normalizedValue then ("%s:%s"):format(kind, normalizedValue) else nil
end

function InventoryLoadout.GetOrderedEntries(itemIds, genericToolNames, preferredEntries)
	local sourceItemIds = if type(itemIds) == "table" then itemIds else {}
	local sourceToolNames = if type(genericToolNames) == "table" then genericToolNames else {}
	local sourcePreferredEntries = if type(preferredEntries) == "table" then preferredEntries else {}
	local allowed = {}
	local result = {}
	local seen = {}

	local function allow(kind, value)
		local key = InventoryLoadout.GetEntryKey(kind, value)
		if key then
			allowed[key] = value
		end
	end

	local function push(kind, value)
		local key = InventoryLoadout.GetEntryKey(kind, value)
		local allowedValue = key and allowed[key] or nil
		if not key or allowedValue == nil or seen[key] then
			return
		end

		seen[key] = true
		result[#result + 1] = {
			Kind = kind,
			Value = allowedValue,
		}
	end

	for _, itemId in ipairs(sourceItemIds) do
		allow("item", itemId)
	end
	for _, toolName in ipairs(sourceToolNames) do
		allow("generic", toolName)
	end

	for _, entry in ipairs(sourcePreferredEntries) do
		if type(entry) == "table" then
			push(entry.Kind, entry.Value)
		end
	end

	for _, itemId in ipairs(sourceItemIds) do
		push("item", itemId)
	end
	for _, toolName in ipairs(sourceToolNames) do
		push("generic", toolName)
	end

	return result
end

function InventoryLoadout.SplitEntries(entries)
	local sourceEntries = if type(entries) == "table" then entries else {}
	local itemIds = {}
	local genericToolNames = {}

	for _, entry in ipairs(sourceEntries) do
		if type(entry) == "table" and entry.Kind == "item" then
			itemIds[#itemIds + 1] = entry.Value
		elseif type(entry) == "table" and entry.Kind == "generic" then
			genericToolNames[#genericToolNames + 1] = entry.Value
		end
	end

	return itemIds, genericToolNames
end

function InventoryLoadout.AreEntriesEqual(firstEntries, secondEntries): boolean
	if type(firstEntries) ~= "table" or type(secondEntries) ~= "table" then
		return false
	end

	if #firstEntries ~= #secondEntries then
		return false
	end

	for index, firstEntry in ipairs(firstEntries) do
		local secondEntry = secondEntries[index]
		if type(secondEntry) ~= "table"
			or InventoryLoadout.GetEntryKey(firstEntry.Kind, firstEntry.Value)
				~= InventoryLoadout.GetEntryKey(secondEntry.Kind, secondEntry.Value)
		then
			return false
		end
	end

	return true
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

function InventoryLoadout.CountHotbarSlots(itemIds, genericToolNames)
	return #copy_normalized_values(itemIds, normalize_item_id)
		+ #copy_normalized_values(genericToolNames, normalize_generic_tool_name)
end

function InventoryLoadout.GetLastHotbarEntry(itemIds, genericToolNames)
	local normalizedGenericToolNames = copy_normalized_values(genericToolNames, normalize_generic_tool_name)
	if #normalizedGenericToolNames > 0 then
		return "generic", normalizedGenericToolNames[#normalizedGenericToolNames]
	end

	local normalizedItemIds = copy_normalized_values(itemIds, normalize_item_id)
	if #normalizedItemIds > 0 then
		return "item", normalizedItemIds[#normalizedItemIds]
	end

	return nil, nil
end

function InventoryLoadout.RemoveHotbarEntry(itemIds, genericToolNames, kind, value)
	if kind == "item" then
		return InventoryLoadout.SetItemEquipped(itemIds, value, false), copy_normalized_values(genericToolNames, normalize_generic_tool_name)
	end

	if kind == "generic" then
		return copy_normalized_values(itemIds, normalize_item_id), InventoryLoadout.SetGenericToolEquipped(genericToolNames, value, false)
	end

	return copy_normalized_values(itemIds, normalize_item_id), copy_normalized_values(genericToolNames, normalize_generic_tool_name)
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

function InventoryLoadout.GetDefaultGenericToolDefinitions()
	local definitions = {}

	for index, definition in ipairs(InventoryLoadout.DEFAULT_GENERIC_TOOL_DEFINITIONS) do
		definitions[index] = {
			ToolName = definition.ToolName,
			DisplayName = definition.DisplayName,
			Description = definition.Description,
			IconImage = definition.IconImage,
			IconImageId = definition.IconImageId,
			Image = definition.Image,
			ImageId = definition.ImageId,
			SortOrder = definition.SortOrder,
		}
	end

	return definitions
end

return InventoryLoadout
