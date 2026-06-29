local Shared = {}

local function deep_copy(value)
	if type(value) ~= "table" then
		return value
	end

	local clone = {}

	for key, nestedValue in pairs(value) do
		clone[key] = deep_copy(nestedValue)
	end

	return clone
end

local function append_tags(baseTags, extraTags)
	local tags = {}
	local seen = {}

	for _, tag in ipairs(baseTags or {}) do
		if not seen[tag] then
			seen[tag] = true
			tags[#tags + 1] = tag
		end
	end

	for _, tag in ipairs(extraTags or {}) do
		if not seen[tag] then
			seen[tag] = true
			tags[#tags + 1] = tag
		end
	end

	return tags
end

local function normalize_item(item)
	item.PriceLabel = item.PriceLabel or ("%d coin"):format(item.Price or 0)
	item.MaxStack = item.MaxStack or 99
	item.ToolName = item.ToolName or item.DisplayName
	item.ToolTip = item.ToolTip or ("%s | %s"):format(item.PriceLabel, item.EffectsSummary or item.Description or "")
	item.Tags = item.Tags or {}
	return item
end

local function create_item(defaults, config)
	local item = deep_copy(config)

	for key, value in pairs(defaults) do
		if item[key] == nil then
			item[key] = deep_copy(value)
		end
	end

	item.Tags = append_tags(defaults.Tags or {}, config.Tags or {})
	return normalize_item(item)
end

function Shared.CreateFood(config)
	return create_item({
		ToolCategory = "Food",
		CareType = "Food",
		NeedKey = "Hunger",
		PromptActionText = "Feed",
		PromptObjectText = "Your horse",
		InventoryPath = "Consumables.Food",
		ShopId = "OutdoorStore",
		Tags = { "Food" },
		OverflowBehavior = {
			AllowUseWhenNeedFull = true,
			DiminishingPerUse = 0.2,
			MinimumEffectiveness = 0.15,
			HealthPenalty = 3,
			HappinessMultiplier = 0.25,
		},
	}, config)
end

function Shared.CreateWater(config)
	return create_item({
		ToolCategory = "Water",
		CareType = "Water",
		NeedKey = "Thirst",
		PromptActionText = "Give Water",
		PromptObjectText = "Your horse",
		InventoryPath = "Consumables.Water",
		ShopId = "OutdoorStore",
		Tags = { "Water" },
		OverflowBehavior = {
			AllowUseWhenNeedFull = true,
			DiminishingPerUse = 0.18,
			MinimumEffectiveness = 0.18,
			HealthPenalty = 2,
			HappinessMultiplier = 0.28,
		},
	}, config)
end

function Shared.CreateGrooming(config)
	return create_item({
		ToolCategory = "Grooming",
		UseType = "Grooming",
		PromptActionText = "Groom",
		PromptObjectText = "Your horse",
		InventoryPath = "Consumables.Grooming",
		ShopId = "OutdoorStore",
		Tags = { "Grooming" },
	}, config)
end

function Shared.CreateMisc(config)
	return create_item({
		ToolCategory = "Misc",
		PromptActionText = "Use",
		PromptObjectText = "Your horse",
		InventoryPath = "Consumables.Misc",
		ShopId = "OutdoorStore",
		Tags = { "Misc" },
	}, config)
end

function Shared.CreateMedicine(config)
	return create_item({
		ToolCategory = "Medicine",
		UseType = "Medicine",
		PromptActionText = "Treat",
		PromptObjectText = "Your horse",
		ResponseCode = "Treated",
		InventoryPath = "Consumables.Medical",
		ShopId = "OutdoorStore",
		Tags = { "Medicine" },
	}, config)
end

function Shared.CreateSeeds(config)
	return create_item({
		ToolCategory = "Seeds",
		InventoryPath = "Seeds",
		ShopId = "OutdoorStore",
		Tags = { "Seed" },
	}, config)
end

function Shared.CreateTack(config)
	return create_item({
		ToolCategory = "Tack",
		InventoryPath = "Tack",
		ShopId = "TackShop",
		Tags = { "Tack" },
		MaxStack = 1,
	}, config)
end

function Shared.CreateCosmetic(config)
	return create_item({
		ToolCategory = "Cosmetics",
		InventoryPath = "Cosmetics",
		ShopId = "TackShop",
		Tags = { "Cosmetic" },
		MaxStack = 1,
	}, config)
end

function Shared.CreateStableDecor(config)
	return create_item({
		ToolCategory = "StableDecor",
		InventoryPath = "StableDecor",
		ShopId = "OutdoorStore",
		Tags = { "Decor" },
		MaxStack = 10,
	}, config)
end

return Shared
