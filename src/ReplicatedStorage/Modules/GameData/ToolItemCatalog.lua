local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local CareItemCatalog = require(GameData:WaitForChild("CareItemCatalog"))

local ToolItemCatalog = {}

local orderedDefinitions = {}
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

local function shallow_copy(source)
	local copy = {}

	for key, value in pairs(source) do
		copy[key] = value
	end

	return copy
end

local function get_tool_category(itemDefinition)
	if type(itemDefinition.ToolCategory) == "string" and itemDefinition.ToolCategory ~= "" then
		return itemDefinition.ToolCategory
	end

	if type(itemDefinition.CareType) == "string" and itemDefinition.CareType ~= "" then
		return itemDefinition.CareType
	end

	return "Misc"
end

local function build_tool_tip(itemDefinition)
	if type(itemDefinition.ToolTip) == "string" and itemDefinition.ToolTip ~= "" then
		return itemDefinition.ToolTip
	end

	local priceLabel = itemDefinition.PriceLabel or ((itemDefinition.Price or 0) .. " coin")

	if itemDefinition.NeedKey and itemDefinition.Effects then
		return string.format(
			"%s | %s +%d | Happiness +%d",
			priceLabel,
			itemDefinition.NeedKey,
			itemDefinition.Effects.NeedGain or 0,
			itemDefinition.Effects.HappinessGain or 0
		)
	end

	if type(itemDefinition.Description) == "string" and itemDefinition.Description ~= "" then
		return string.format("%s | %s", priceLabel, itemDefinition.Description)
	end

	return priceLabel
end

local function register_definition(sourceDefinition)
	local itemId = normalize_key(sourceDefinition.ItemId or sourceDefinition.id)
	if not itemId then
		return
	end

	local definition = shallow_copy(sourceDefinition)
	definition.ItemId = itemId
	definition.id = itemId
	definition.ToolCategory = get_tool_category(definition)
	definition.ToolTip = build_tool_tip(definition)

	if type(definition.DisplayName) ~= "string" or definition.DisplayName == "" then
		definition.DisplayName = definition.ItemId
	end

	definitionsById[itemId] = definition
	definitionsByDisplayName[normalize_key(definition.DisplayName)] = definition
	orderedDefinitions[#orderedDefinitions + 1] = definition
end

for _, careItemDefinition in ipairs(CareItemCatalog.GetAllItems()) do
	register_definition(careItemDefinition)
end

register_definition({
	ItemId = "soap",
	DisplayName = "Soap",
	Description = "Basic soap used to wash your horse and restore cleanliness.",
	Price = 2,
	PriceLabel = "2 coin",
	InventoryPath = "Consumables.Grooming",
	ShopId = "OutdoorStore",
	Tags = { "Grooming", "Cleaning", "Misc" },
	MaxStack = 99,
	ToolCategory = "Misc",
	ToolTip = "2 coin | Wash tool | Cleanliness restore",
})

register_definition({
	ItemId = "basic_bandage",
	DisplayName = "Basic Bandage",
	Description = "A simple wrap for light injuries and quick stable care.",
	Price = 2,
	PriceLabel = "2 coin",
	InventoryPath = "Consumables.Medical",
	ShopId = "OutdoorStore",
	Tags = { "Medical", "Bandage", "Starter" },
	MaxStack = 99,
	ToolCategory = "Medicine",
	UseType = "Medicine",
	PromptActionText = "Treat",
	PromptObjectText = "Your horse",
	ResponseCode = "Treated",
	Effects = {
		HealthGain = 12,
		HappinessGain = 1,
		FriendshipGain = 2,
		MoodText = "Patched Up",
	},
	ToolTip = "2 coin | Health +12 | Small safe heal",
})

register_definition({
	ItemId = "herbal_poultice",
	DisplayName = "Herbal Poultice",
	Description = "A gentle herbal blend that heals while helping the horse relax.",
	Price = 4,
	PriceLabel = "4 coin",
	InventoryPath = "Consumables.Medical",
	ShopId = "OutdoorStore",
	Tags = { "Medical", "Herbal", "Comfort" },
	MaxStack = 99,
	ToolCategory = "Medicine",
	UseType = "Medicine",
	PromptActionText = "Treat",
	PromptObjectText = "Your horse",
	ResponseCode = "Treated",
	Effects = {
		HealthGain = 10,
		HappinessGain = 5,
		FriendshipGain = 4,
		SecondaryNeedAdjustments = {
			Cleanliness = 4,
		},
		MoodText = "Calmed",
	},
	ToolTip = "4 coin | Health +10 | Happiness +5 | Gentle herbs",
})

register_definition({
	ItemId = "bitter_syrup",
	DisplayName = "Bitter Syrup",
	Description = "A strong emergency medicine that works well, even if the horse hates it.",
	Price = 5,
	PriceLabel = "5 coin",
	InventoryPath = "Consumables.Medical",
	ShopId = "OutdoorStore",
	Tags = { "Medical", "Emergency", "Strong" },
	MaxStack = 99,
	ToolCategory = "Medicine",
	UseType = "Medicine",
	PromptActionText = "Treat",
	PromptObjectText = "Your horse",
	ResponseCode = "Treated",
	Effects = {
		HealthGain = 22,
		HappinessGain = -4,
		FriendshipGain = 1,
		MoodText = "Recovered",
	},
	ToolTip = "5 coin | Health +22 | Happiness -4 | Emergency cure",
})

register_definition({
	ItemId = "digestive_relief",
	DisplayName = "Digestive Relief",
	Description = "Settles the stomach and clears excess food or water overload.",
	Price = 6,
	PriceLabel = "6 coin",
	InventoryPath = "Consumables.Medical",
	ShopId = "OutdoorStore",
	Tags = { "Medical", "Digestive", "Overflow" },
	MaxStack = 99,
	ToolCategory = "Medicine",
	UseType = "Medicine",
	PromptActionText = "Treat",
	PromptObjectText = "Your horse",
	ResponseCode = "Treated",
	Effects = {
		HealthGain = 14,
		HappinessGain = 2,
		FriendshipGain = 3,
		OverflowRelief = { "Hunger", "Thirst" },
		MoodText = "Settled",
	},
	ToolTip = "6 coin | Health +14 | Clears food/water overflow",
})

register_definition({
	ItemId = "recovery_tonic",
	DisplayName = "Recovery Tonic",
	Description = "A premium tonic with instant healing and a slower recovery effect over time.",
	Price = 8,
	PriceLabel = "8 coin",
	InventoryPath = "Consumables.Medical",
	ShopId = "OutdoorStore",
	Tags = { "Medical", "Tonic", "Recovery" },
	MaxStack = 99,
	ToolCategory = "Medicine",
	UseType = "Medicine",
	PromptActionText = "Treat",
	PromptObjectText = "Your horse",
	Effects = {
		HealthGain = 8,
		HappinessGain = 2,
		FriendshipGain = 4,
		HealthRegen = {
			TotalGain = 12,
			DurationMinutes = 10,
		},
		MoodText = "Recovering",
	},
	ToolTip = "8 coin | Health +8 now | +12 over time",
})

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

	for _, itemDefinition in ipairs(orderedDefinitions) do
		if itemDefinition.ToolCategory == categoryName then
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
	tool.ToolTip = itemDefinition.ToolTip
	tool:SetAttribute("ToolItemId", itemDefinition.ItemId)
	tool:SetAttribute("ItemId", itemDefinition.ItemId)
	tool:SetAttribute("ToolCategory", itemDefinition.ToolCategory)
	tool:SetAttribute("PlaceholderPrice", itemDefinition.Price or 0)
	tool:SetAttribute("PlaceholderPriceLabel", itemDefinition.PriceLabel or "")
	tool:SetAttribute("PlaceholderDescription", itemDefinition.Description or "")

	if itemDefinition.CareType then
		tool:SetAttribute("CareType", itemDefinition.CareType)
	end
end

return ToolItemCatalog
