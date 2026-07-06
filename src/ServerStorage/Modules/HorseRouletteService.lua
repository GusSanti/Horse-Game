local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseService"))

local HorseRouletteService = {}

local function contains_catalog_id(collectionIds, catalogId)
	for _, ownedCatalogId in ipairs(collectionIds or {}) do
		if ownedCatalogId == catalogId then
			return true
		end
	end

	return false
end

local function get_balance(player)
	return math.max(0, tonumber(DataUtility.server.get(player, "Currencies.Horseshoes")) or 0)
end

local function build_horse_payload(catalogId)
	local definition = HorseCatalog.GetDefinition(catalogId) or HorseCatalog.GetDefinition("Default")
	local rouletteEntry = HorseCatalog.GetRouletteEntry(catalogId)

	return {
		CatalogId = definition.CatalogId,
		DisplayName = definition.DisplayName,
		Rarity = definition.Rarity,
		Weight = rouletteEntry and rouletteEntry.Weight or 0,
		ModelKey = definition.PlaceholderModelKey,
	}
end

local function build_state_payload(player)
	local price = HorseCatalog.RoulettePrice or 500
	local balance = get_balance(player)

	return {
		Success = true,
		Price = price,
		Balance = balance,
		FreeWhenZero = true,
		Horses = HorseCatalog.GetRouletteHorseOptions(),
		CanRoll = balance == 0 or balance >= price,
	}
end

function HorseRouletteService.GetState(player)
	return build_state_payload(player)
end

function HorseRouletteService.Roll(player)
	local price = HorseCatalog.RoulettePrice or 500
	local balance = get_balance(player)

	if balance > 0 and balance < price then
		return {
			Success = false,
			Code = "InsufficientFunds",
			MessageCode = "InsufficientFunds",
			PaidPrice = 0,
			RemainingHorseshoes = balance,
			RolledHorse = nil,
			GrantedHorseId = nil,
			LostBecauseNoSlot = false,
			AlreadyOwnedCatalog = false,
		}
	end

	local paidPrice = 0
	if balance >= price then
		paidPrice = price
		balance -= price
		DataUtility.server.set(player, "Currencies.Horseshoes", balance)
	end

	local catalogId = HorseCatalog.RollRouletteHorseId()
	local rolledHorse = build_horse_payload(catalogId)
	local collection = DataUtility.server.get(player, "Collection")
	local alreadyOwnedCatalog = contains_catalog_id(
		collection and collection.OwnedHorseCatalogIds or nil,
		catalogId
	)

	local grantedHorse, grantCode = HorseService.CreateHorseForPlayer(player, catalogId, {
		Source = "AdminHorseRoulette",
		EquipOnGrant = false,
	})

	if grantedHorse then
		return {
			Success = true,
			Code = "Granted",
			MessageCode = alreadyOwnedCatalog and "DuplicateGranted" or "Granted",
			PaidPrice = paidPrice,
			RemainingHorseshoes = balance,
			RolledHorse = rolledHorse,
			GrantedHorseId = grantedHorse.Id,
			LostBecauseNoSlot = false,
			AlreadyOwnedCatalog = alreadyOwnedCatalog,
		}
	end

	if grantCode == "NoStableSlotAvailable" then
		return {
			Success = true,
			Code = grantCode,
			MessageCode = "LostBecauseNoStableSlot",
			PaidPrice = paidPrice,
			RemainingHorseshoes = balance,
			RolledHorse = rolledHorse,
			GrantedHorseId = nil,
			LostBecauseNoSlot = true,
			AlreadyOwnedCatalog = alreadyOwnedCatalog,
		}
	end

	if paidPrice > 0 then
		DataUtility.server.set(player, "Currencies.Horseshoes", balance + paidPrice)
		balance += paidPrice
	end

	return {
		Success = false,
		Code = grantCode or "GrantFailed",
		MessageCode = grantCode or "GrantFailed",
		PaidPrice = 0,
		RemainingHorseshoes = balance,
		RolledHorse = rolledHorse,
		GrantedHorseId = nil,
		LostBecauseNoSlot = false,
		AlreadyOwnedCatalog = alreadyOwnedCatalog,
	}
end

return HorseRouletteService
