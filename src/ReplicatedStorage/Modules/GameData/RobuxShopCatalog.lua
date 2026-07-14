local RobuxShopCatalog = {}

RobuxShopCatalog.RemoteNames = {
	GetCatalog = "GetRobuxShopCatalog",
	BeginGiftPurchase = "BeginRobuxGiftPurchase",
	ConfirmGiftPurchase = "ConfirmRobuxGiftPurchase",
	CancelGiftPurchase = "CancelRobuxGiftPurchase",
}

RobuxShopCatalog.UiSections = {
	Horseshoes = {
		StandardProductKeys = {
			"horseshoes_small",
			"horseshoes_mid",
			"horseshoes_grand",
		},
		FeaturedProductKeys = {
			"horseshoes_mega",
		},
	},
}

local function normalize_key(value): string?
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	local normalizedValue = string.lower(trimmedValue)
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function normalize_whole_number(value): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function build_image_uri(imageAssetId, fallbackImage): string
	local normalizedImageAssetId = normalize_whole_number(imageAssetId)
	if normalizedImageAssetId > 0 then
		return ("rbxassetid://%d"):format(normalizedImageAssetId)
	end

	if type(fallbackImage) == "string" then
		return fallbackImage
	end

	return ""
end

local developerProducts = {
	-- ImageAssetId can be changed manually later for your final store art.
	horseshoes_small = {
		Key = "horseshoes_small",
		ProductId = 3609839773,
		DisplayName = "Small Pack",
		SectionId = "Horseshoes",
		UiStyle = "Standard",
		UiSlot = 1,
		SortOrder = 10,
		ImageAssetId = 0,
		Reward = {
			CurrencyId = "Horseshoes",
			Amount = 100,
		},
	},
	horseshoes_mid = {
		Key = "horseshoes_mid",
		ProductId = 3609839980,
		DisplayName = "Mid Pack",
		SectionId = "Horseshoes",
		UiStyle = "Standard",
		UiSlot = 2,
		SortOrder = 20,
		ImageAssetId = 0,
		Reward = {
			CurrencyId = "Horseshoes",
			Amount = 250,
		},
	},
	horseshoes_grand = {
		Key = "horseshoes_grand",
		ProductId = 3609840080,
		DisplayName = "Grand Pack",
		SectionId = "Horseshoes",
		UiStyle = "Standard",
		UiSlot = 3,
		SortOrder = 30,
		ImageAssetId = 0,
		Reward = {
			CurrencyId = "Horseshoes",
			Amount = 750,
		},
	},
	horseshoes_mega = {
		Key = "horseshoes_mega",
		ProductId = 3609840111,
		DisplayName = "Mega Pack",
		SectionId = "Horseshoes",
		UiStyle = "Featured",
		UiSlot = 1,
		SortOrder = 40,
		ImageAssetId = 0,
		Reward = {
			CurrencyId = "Horseshoes",
			Amount = 2000,
		},
	},
}

local gamePasses = {}

local definitionsByKey = {}
local definitionsByProductId = {
	DeveloperProduct = {},
	GamePass = {},
}

local orderedDeveloperProducts = {}
local orderedGamePasses = {}

local function register_definition(definitionBucket, productType: string, definition)
	definition.ProductType = productType
	definition.ProductId = normalize_whole_number(definition.ProductId)
	definition.SectionId = definition.SectionId or ""
	definition.ImageAssetId = normalize_whole_number(definition.ImageAssetId)
	definition.Image = build_image_uri(definition.ImageAssetId, definition.Image)
	definition.SortOrder = normalize_whole_number(definition.SortOrder)
	definition.UiSlot = normalize_whole_number(definition.UiSlot)

	if type(definition.Reward) ~= "table" then
		definition.Reward = {
			CurrencyId = "",
			Amount = 0,
		}
	end

	definition.Reward.CurrencyId = definition.Reward.CurrencyId or ""
	definition.Reward.Amount = normalize_whole_number(definition.Reward.Amount)

	local normalizedKey = normalize_key(definition.Key)
	if not normalizedKey then
		error("RobuxShopCatalog found a product without a valid Key.")
	end

	definitionsByKey[normalizedKey] = definition
	definitionsByProductId[productType][definition.ProductId] = definition
	definitionBucket[#definitionBucket + 1] = definition
end

for _, definition in pairs(developerProducts) do
	register_definition(orderedDeveloperProducts, "DeveloperProduct", definition)
end

for _, definition in pairs(gamePasses) do
	register_definition(orderedGamePasses, "GamePass", definition)
end

table.sort(orderedDeveloperProducts, function(left, right)
	if left.SortOrder == right.SortOrder then
		return left.ProductId < right.ProductId
	end

	return left.SortOrder < right.SortOrder
end)

table.sort(orderedGamePasses, function(left, right)
	if left.SortOrder == right.SortOrder then
		return left.ProductId < right.ProductId
	end

	return left.SortOrder < right.SortOrder
end)

RobuxShopCatalog.DeveloperProducts = developerProducts
RobuxShopCatalog.GamePasses = gamePasses

function RobuxShopCatalog.NormalizeKey(value): string?
	return normalize_key(value)
end

function RobuxShopCatalog.GetDeveloperProductDefinitions()
	return orderedDeveloperProducts
end

function RobuxShopCatalog.GetGamePassDefinitions()
	return orderedGamePasses
end

function RobuxShopCatalog.GetDefinitionByKey(productKey)
	return definitionsByKey[normalize_key(productKey)]
end

function RobuxShopCatalog.GetDefinitionByProductId(productId, productType: string?)
	local normalizedProductId = normalize_whole_number(productId)
	if normalizedProductId <= 0 then
		return nil
	end

	if type(productType) == "string" and definitionsByProductId[productType] then
		return definitionsByProductId[productType][normalizedProductId]
	end

	return definitionsByProductId.DeveloperProduct[normalizedProductId]
		or definitionsByProductId.GamePass[normalizedProductId]
end

function RobuxShopCatalog.GetSectionLayout(sectionId: string)
	return RobuxShopCatalog.UiSections[sectionId]
end

function RobuxShopCatalog.GetRewardLabel(definition): string
	local reward = definition and definition.Reward or nil
	local rewardAmount = normalize_whole_number(reward and reward.Amount or 0)
	local currencyId = reward and reward.CurrencyId or ""

	if currencyId == "Horseshoes" then
		return ("%d Horseshoes"):format(rewardAmount)
	end

	if currencyId ~= "" then
		return ("%d %s"):format(rewardAmount, currencyId)
	end

	return tostring(rewardAmount)
end

function RobuxShopCatalog.ResolveImageUri(definition, fallbackImageAssetId): string
	if not definition then
		return build_image_uri(fallbackImageAssetId, "")
	end

	return build_image_uri(definition.ImageAssetId, build_image_uri(fallbackImageAssetId, definition.Image))
end

function RobuxShopCatalog.BuildStaticProductPayload(definition)
	if not definition then
		return nil
	end

	local reward = definition.Reward or {}

	return {
		Key = definition.Key,
		ProductId = definition.ProductId,
		ProductType = definition.ProductType,
		SupportsGifting = definition.ProductType == "DeveloperProduct",
		DisplayName = definition.DisplayName,
		SectionId = definition.SectionId,
		UiStyle = definition.UiStyle,
		UiSlot = definition.UiSlot,
		SortOrder = definition.SortOrder,
		ImageAssetId = definition.ImageAssetId,
		Image = definition.Image,
		Reward = {
			CurrencyId = reward.CurrencyId or "",
			Amount = normalize_whole_number(reward.Amount or 0),
		},
		RewardLabel = RobuxShopCatalog.GetRewardLabel(definition),
	}
end

function RobuxShopCatalog.GetDefinitionsForSection(sectionId: string, productType: string?)
	local requestedSectionId = normalize_key(sectionId)
	local bucket = if productType == "GamePass" then orderedGamePasses else orderedDeveloperProducts
	local definitions = {}

	for _, definition in ipairs(bucket) do
		if normalize_key(definition.SectionId) == requestedSectionId then
			definitions[#definitions + 1] = definition
		end
	end

	return definitions
end

return RobuxShopCatalog