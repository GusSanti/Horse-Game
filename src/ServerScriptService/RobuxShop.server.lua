local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local serverModules = ServerStorage:WaitForChild("Modules")

local Net = require(Libraries:WaitForChild("Net"))
local RobuxShopCatalog = require(GameData:WaitForChild("RobuxShopCatalog"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))
local ProfileSessionService = require(serverModules:WaitForChild("ProfileSessionService"))

local GIFT_MESSAGE_TYPE = "RobuxProductGift"
local GIFT_INTENT_EXPIRATION_SECONDS = 180
local MAX_PENDING_GIFT_INTENTS = 8
local PROCESSED_RECEIPT_LIMIT = 100
local RECEIVED_GIFT_RECEIPT_LIMIT = 100

local function normalize_whole_number(value): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function get_info_type(productType: string)
	if productType == "GamePass" then
		return Enum.InfoType.GamePass
	end

	return Enum.InfoType.Product
end

local function build_live_product_payload(definition)
	local payload = RobuxShopCatalog.BuildStaticProductPayload(definition)
	local success, productInfo = pcall(
		MarketplaceService.GetProductInfo,
		MarketplaceService,
		definition.ProductId,
		get_info_type(definition.ProductType)
	)

	payload.IsForSale = false
	payload.PriceInRobux = nil
	payload.MarketplaceName = definition.DisplayName

	if success and type(productInfo) == "table" then
		payload.IsForSale = productInfo.IsForSale ~= false
		payload.PriceInRobux = tonumber(productInfo.PriceInRobux)
		payload.MarketplaceName = productInfo.Name or payload.MarketplaceName
		payload.Image = RobuxShopCatalog.ResolveImageUri(definition, productInfo.IconImageAssetId)
	end

	return payload
end

local function build_catalog_response()
	local response = {
		Success = true,
		DeveloperProducts = {},
		GamePasses = {},
	}

	for _, definition in ipairs(RobuxShopCatalog.GetDeveloperProductDefinitions()) do
		response.DeveloperProducts[definition.Key] = build_live_product_payload(definition)
	end

	for _, definition in ipairs(RobuxShopCatalog.GetGamePassDefinitions()) do
		response.GamePasses[definition.Key] = build_live_product_payload(definition)
	end

	return response
end

local function ensure_live_ops_tables(profileData)
	if type(profileData.Currencies) ~= "table" then
		profileData.Currencies = {}
	end

	if type(profileData.LiveOps) ~= "table" then
		profileData.LiveOps = {}
	end

	local liveOps = profileData.LiveOps

	if type(liveOps.ProcessedDeveloperReceipts) ~= "table" then
		liveOps.ProcessedDeveloperReceipts = {}
	end

	if type(liveOps.ProcessedDeveloperReceiptOrder) ~= "table" then
		liveOps.ProcessedDeveloperReceiptOrder = {}
	end

	if type(liveOps.PendingGiftPurchases) ~= "table" then
		liveOps.PendingGiftPurchases = {}
	end

	if type(liveOps.ReceivedGiftReceipts) ~= "table" then
		liveOps.ReceivedGiftReceipts = {}
	end

	if type(liveOps.ReceivedGiftReceiptOrder) ~= "table" then
		liveOps.ReceivedGiftReceiptOrder = {}
	end

	return liveOps
end

local function ensure_profile_data(player: Player)
	local profileData = DataUtility.server.get(player)
	if type(profileData) ~= "table" then
		return nil
	end

	ensure_live_ops_tables(profileData)
	return profileData
end

local function trim_receipt_history(receiptLookup, receiptOrder, maxEntries: number)
	while #receiptOrder > maxEntries do
		local expiredReceiptId = table.remove(receiptOrder, 1)
		if expiredReceiptId then
			receiptLookup[expiredReceiptId] = nil
		end
	end
end

local function prune_pending_gift_intents(profileData, nowTimestamp: number)
	local liveOps = ensure_live_ops_tables(profileData)
	local pendingGiftPurchases = liveOps.PendingGiftPurchases
	local prunedGiftPurchases = {}

	for _, giftIntent in ipairs(pendingGiftPurchases) do
		if type(giftIntent) == "table" then
			local expiresAt = normalize_whole_number(giftIntent.ExpiresAt)
			if expiresAt > nowTimestamp then
				prunedGiftPurchases[#prunedGiftPurchases + 1] = giftIntent
			end
		end
	end

	liveOps.PendingGiftPurchases = prunedGiftPurchases
	return prunedGiftPurchases
end

local function get_gift_intent_by_id(pendingGiftPurchases, intentId: string)
	for _, giftIntent in ipairs(pendingGiftPurchases) do
		if type(giftIntent) == "table" and giftIntent.IntentId == intentId then
			return giftIntent
		end
	end

	return nil
end

local function remove_gift_intent_by_id(pendingGiftPurchases, intentId: string): boolean
	for index, giftIntent in ipairs(pendingGiftPurchases) do
		if type(giftIntent) == "table" and giftIntent.IntentId == intentId then
			table.remove(pendingGiftPurchases, index)
			return true
		end
	end

	return false
end

local function get_active_confirmed_gift_intent(profileData, nowTimestamp: number)
	local pendingGiftPurchases = prune_pending_gift_intents(profileData, nowTimestamp)

	for _, giftIntent in ipairs(pendingGiftPurchases) do
		if giftIntent.State == "Confirmed" and normalize_whole_number(giftIntent.ExpiresAt) > nowTimestamp then
			return giftIntent
		end
	end

	return nil
end

local function consume_matching_gift_intent(profileData, productId: number, nowTimestamp: number)
	local pendingGiftPurchases = prune_pending_gift_intents(profileData, nowTimestamp)

	for index, giftIntent in ipairs(pendingGiftPurchases) do
		if giftIntent.State == "Confirmed"
			and normalize_whole_number(giftIntent.ProductId) == productId
			and normalize_whole_number(giftIntent.ExpiresAt) > nowTimestamp
		then
			table.remove(pendingGiftPurchases, index)
			return giftIntent
		end
	end

	return nil
end

local function save_live_ops(player: Player, profileData)
	DataUtility.server.set(player, "LiveOps", profileData.LiveOps)
end

local function can_grant_reward(reward): boolean
	if type(reward) ~= "table" then
		return false
	end

	local rewardAmount = normalize_whole_number(reward.Amount)
	if rewardAmount <= 0 then
		return true
	end

	return reward.CurrencyId == "Horseshoes"
end

local function commit_reward(player: Player, profileData, reward): boolean
	if not can_grant_reward(reward) then
		return false
	end

	local rewardAmount = normalize_whole_number(reward.Amount)
	if rewardAmount <= 0 then
		save_live_ops(player, profileData)
		return true
	end

	if reward.CurrencyId == "Horseshoes" then
		local currentHorseshoes = normalize_whole_number(DataUtility.server.get(player, "Currencies.Horseshoes"))
		DataUtility.server.set(player, "Currencies.Horseshoes", currentHorseshoes + rewardAmount)
		SoundUtility.PlayGameSFXForPlayer(player, "MoneyGet")
		return true
	end

	return false
end

local function handle_gift_message(player: Player, profile, message, processed)
	if type(message) ~= "table" or message.Type ~= GIFT_MESSAGE_TYPE then
		return false
	end

	local profileData = profile and profile.Data
	if type(profileData) ~= "table" then
		return false
	end

	local liveOps = ensure_live_ops_tables(profileData)
	local purchaseId = tostring(message.PurchaseId or "")

	if purchaseId == "" then
		processed()
		return true
	end

	if liveOps.ReceivedGiftReceipts[purchaseId] then
		processed()
		return true
	end

	if not can_grant_reward(message.Reward) then
		return false
	end

	liveOps.ReceivedGiftReceipts[purchaseId] = true
	liveOps.ReceivedGiftReceiptOrder[#liveOps.ReceivedGiftReceiptOrder + 1] = purchaseId
	trim_receipt_history(
		liveOps.ReceivedGiftReceipts,
		liveOps.ReceivedGiftReceiptOrder,
		RECEIVED_GIFT_RECEIPT_LIMIT
	)

	if not commit_reward(player, profileData, message.Reward) then
		return false
	end

	processed()
	return true
end

local function create_gift_response(success: boolean, code: string, extraData)
	local response = {
		Success = success,
		Code = code,
	}

	if type(extraData) == "table" then
		for key, value in pairs(extraData) do
			response[key] = value
		end
	end

	return response
end

local function begin_gift_purchase(player: Player, productKey, recipientUserId)
	local definition = RobuxShopCatalog.GetDefinitionByKey(productKey)
	if not definition or definition.ProductType ~= "DeveloperProduct" then
		return create_gift_response(false, "UnsupportedGiftProduct")
	end

	local profileData = ensure_profile_data(player)
	if not profileData then
		return create_gift_response(false, "ProfileNotReady")
	end

	local normalizedRecipientUserId = normalize_whole_number(recipientUserId)
	if normalizedRecipientUserId <= 0 or normalizedRecipientUserId == player.UserId then
		return create_gift_response(false, "InvalidGiftRecipient")
	end

	local recipientPlayer = Players:GetPlayerByUserId(normalizedRecipientUserId)
	if not recipientPlayer then
		return create_gift_response(false, "RecipientUnavailable")
	end

	local nowTimestamp = os.time()
	if get_active_confirmed_gift_intent(profileData, nowTimestamp) then
		return create_gift_response(false, "GiftAlreadyPending")
	end

	local liveOps = ensure_live_ops_tables(profileData)
	local pendingGiftPurchases = prune_pending_gift_intents(profileData, nowTimestamp)
	local intentId = HttpService:GenerateGUID(false)

	pendingGiftPurchases[#pendingGiftPurchases + 1] = {
		IntentId = intentId,
		ProductId = definition.ProductId,
		ProductKey = definition.Key,
		RecipientUserId = recipientPlayer.UserId,
		RecipientName = recipientPlayer.Name,
		RecipientDisplayName = recipientPlayer.DisplayName,
		State = "Draft",
		CreatedAt = nowTimestamp,
		ExpiresAt = nowTimestamp + GIFT_INTENT_EXPIRATION_SECONDS,
	}

	while #pendingGiftPurchases > MAX_PENDING_GIFT_INTENTS do
		table.remove(pendingGiftPurchases, 1)
	end

	liveOps.PendingGiftPurchases = pendingGiftPurchases
	save_live_ops(player, profileData)

	return create_gift_response(true, "GiftIntentCreated", {
		IntentId = intentId,
		ProductId = definition.ProductId,
		ProductKey = definition.Key,
		RecipientUserId = recipientPlayer.UserId,
		RecipientName = recipientPlayer.Name,
		RecipientDisplayName = recipientPlayer.DisplayName,
	})
end

local function confirm_gift_purchase(player: Player, intentId)
	if type(intentId) ~= "string" or intentId == "" then
		return create_gift_response(false, "GiftIntentMissing")
	end

	local profileData = ensure_profile_data(player)
	if not profileData then
		return create_gift_response(false, "ProfileNotReady")
	end

	local nowTimestamp = os.time()
	local pendingGiftPurchases = prune_pending_gift_intents(profileData, nowTimestamp)
	local giftIntent = get_gift_intent_by_id(pendingGiftPurchases, intentId)
	if not giftIntent then
		return create_gift_response(false, "GiftIntentNotFound")
	end

	giftIntent.State = "Confirmed"
	giftIntent.ConfirmedAt = nowTimestamp
	giftIntent.ExpiresAt = nowTimestamp + GIFT_INTENT_EXPIRATION_SECONDS

	save_live_ops(player, profileData)

	return create_gift_response(true, "GiftIntentConfirmed", {
		IntentId = giftIntent.IntentId,
		ProductId = giftIntent.ProductId,
		ProductKey = giftIntent.ProductKey,
		RecipientUserId = giftIntent.RecipientUserId,
		RecipientName = giftIntent.RecipientName,
		RecipientDisplayName = giftIntent.RecipientDisplayName,
	})
end

local function cancel_gift_purchase(player: Player, intentId)
	if type(intentId) ~= "string" or intentId == "" then
		return create_gift_response(false, "GiftIntentMissing")
	end

	local profileData = ensure_profile_data(player)
	if not profileData then
		return create_gift_response(false, "ProfileNotReady")
	end

	local pendingGiftPurchases = prune_pending_gift_intents(profileData, os.time())
	local didRemoveGiftIntent = remove_gift_intent_by_id(pendingGiftPurchases, intentId)

	if didRemoveGiftIntent then
		save_live_ops(player, profileData)
		return create_gift_response(true, "GiftIntentCanceled")
	end

	return create_gift_response(false, "GiftIntentNotFound")
end

local function process_receipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local definition = RobuxShopCatalog.GetDefinitionByProductId(receiptInfo.ProductId, "DeveloperProduct")
	if not definition then
		warn(("[RobuxShop] Produto desconhecido recebido no receipt: %s"):format(tostring(receiptInfo.ProductId)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profileData = ensure_profile_data(player)
	if not profileData then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local liveOps = ensure_live_ops_tables(profileData)
	local purchaseId = tostring(receiptInfo.PurchaseId)

	if liveOps.ProcessedDeveloperReceipts[purchaseId] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local nowTimestamp = os.time()
	local matchedGiftIntent = consume_matching_gift_intent(profileData, definition.ProductId, nowTimestamp)
	local recipientUserId = matchedGiftIntent and normalize_whole_number(matchedGiftIntent.RecipientUserId) or player.UserId

	if recipientUserId == player.UserId then
		if not can_grant_reward(definition.Reward) then
			warn(("[RobuxShop] Unsupported reward for product %s."):format(definition.Key))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	else
		local giftMessageSent = ProfileSessionService.SendMessageToUserId(recipientUserId, {
			Type = GIFT_MESSAGE_TYPE,
			PurchaseId = purchaseId,
			ProductId = definition.ProductId,
			ProductKey = definition.Key,
			Reward = definition.Reward,
			SenderUserId = player.UserId,
			SenderName = player.Name,
			SenderDisplayName = player.DisplayName,
			RecipientUserId = recipientUserId,
			IntentId = matchedGiftIntent and matchedGiftIntent.IntentId or "",
			CreatedAt = nowTimestamp,
		})

		if not giftMessageSent then
			if matchedGiftIntent then
				local pendingGiftPurchases = ensure_live_ops_tables(profileData).PendingGiftPurchases
				pendingGiftPurchases[#pendingGiftPurchases + 1] = matchedGiftIntent
				save_live_ops(player, profileData)
			end

			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	end

	liveOps.ProcessedDeveloperReceipts[purchaseId] = true
	liveOps.ProcessedDeveloperReceiptOrder[#liveOps.ProcessedDeveloperReceiptOrder + 1] = purchaseId
	trim_receipt_history(
		liveOps.ProcessedDeveloperReceipts,
		liveOps.ProcessedDeveloperReceiptOrder,
		PROCESSED_RECEIPT_LIMIT
	)

	if recipientUserId == player.UserId then
		if not commit_reward(player, profileData, definition.Reward) then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
	else
		save_live_ops(player, profileData)
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

ProfileSessionService.AddMessageHandler("RobuxShopGiftGrant", handle_gift_message)

Net.Function[RobuxShopCatalog.RemoteNames.GetCatalog]:Respond(function()
	return build_catalog_response()
end)

Net.Function[RobuxShopCatalog.RemoteNames.BeginGiftPurchase]:Respond(function(player, productKey, recipientUserId)
	return begin_gift_purchase(player, productKey, recipientUserId)
end)

Net.Function[RobuxShopCatalog.RemoteNames.ConfirmGiftPurchase]:Respond(function(player, intentId)
	return confirm_gift_purchase(player, intentId)
end)

Net.Function[RobuxShopCatalog.RemoteNames.CancelGiftPurchase]:Respond(function(player, intentId)
	return cancel_gift_purchase(player, intentId)
end)

MarketplaceService.ProcessReceipt = process_receipt
