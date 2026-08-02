local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local HorseCatalog = require(GameData:WaitForChild("Horse"):WaitForChild("HorseCatalog"))
local NatureCatalog = require(GameData:WaitForChild("Horse"):WaitForChild("NatureCatalog"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))
local HorseService = require(script.Parent:WaitForChild("HorseService"))

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
		FreeWhenZero = false,
		Horses = HorseCatalog.GetRouletteHorseOptions(),
		Natures = NatureCatalog.GetRouletteOptions(),
		OwnedHorses = HorseService.GetOwnedHorseSummaries(player),
		NaturePrice = NatureCatalog.RoulettePrice,
		CanRoll = balance >= price,
	}
end

function HorseRouletteService.GetState(player)
	return build_state_payload(player)
end

local function build_nature_payload(horse)
	local nature = horse and horse.Nature
	local definition = NatureCatalog.GetHorseNatureDefinition(horse)
	if not definition then
		return nil
	end

	return {
		NatureId = definition.Id,
		Id = definition.Id,
		DisplayName = definition.DisplayName,
		Rarity = definition.Rarity,
		Description = definition.Description,
		EffectText = definition.EffectText,
		Source = type(nature) == "table" and nature.Source or "",
		RolledAt = type(nature) == "table" and nature.RolledAt or 0,
	}
end

function HorseRouletteService.RollNature(player, horseId)
	if type(horseId) ~= "string" or horseId == "" then
		return {
			Success = false,
			Code = "HorseMissing",
			MessageCode = "HorseMissing",
		}
	end

	if not HorseService.GetOwnedHorse(player, horseId) then
		return {
			Success = false,
			Code = "HorseNotOwned",
			MessageCode = "HorseNotOwned",
		}
	end

	local price = NatureCatalog.RoulettePrice or 250
	local balance = get_balance(player)
	if balance < price then
		return {
			Success = false,
			Code = "InsufficientFunds",
			MessageCode = "InsufficientFunds",
			PaidPrice = 0,
			RemainingHorseshoes = balance,
		}
	end

	balance -= price
	DataUtility.server.set(player, "Currencies.Horseshoes", balance)

	local natureId = NatureCatalog.RollNatureId()
	local horseSummary, updateCode = HorseService.SetHorseNature(player, horseId, natureId, "NatureRoulette")
	if not horseSummary then
		DataUtility.server.set(player, "Currencies.Horseshoes", balance + price)
		return {
			Success = false,
			Code = updateCode or "NatureUpdateFailed",
			MessageCode = updateCode or "NatureUpdateFailed",
			PaidPrice = 0,
			RemainingHorseshoes = balance + price,
		}
	end

	SoundUtility.PlayGameSFXForPlayer(player, "MoneyGet")
	return {
		Success = true,
		Code = "NatureUpdated",
		MessageCode = "NatureUpdated",
		Mode = "Nature",
		PaidPrice = price,
		RemainingHorseshoes = balance,
		Horse = horseSummary,
		RolledNature = horseSummary.Nature,
	}
end

function HorseRouletteService.Roll(player, request)
	if type(request) == "table" and request.Mode == "Nature" then
		return HorseRouletteService.RollNature(player, request.HorseId)
	end

	local price = HorseCatalog.RoulettePrice or 500
	local balance = get_balance(player)

	if balance < price then
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
		Source = "HorseRoulette",
		EquipOnGrant = false,
	})

	if grantedHorse then
		if paidPrice > 0 then
			SoundUtility.PlayGameSFXForPlayer(player, "MoneyGet")
		end

		return {
			Success = true,
			Code = "Granted",
			MessageCode = alreadyOwnedCatalog and "DuplicateGranted" or "Granted",
			PaidPrice = paidPrice,
			RemainingHorseshoes = balance,
			RolledHorse = rolledHorse,
			RolledNature = build_nature_payload(grantedHorse),
			GrantedHorseId = grantedHorse.Id,
			LostBecauseNoSlot = false,
			AlreadyOwnedCatalog = alreadyOwnedCatalog,
		}
	end

	if grantCode == "NoStableSlotAvailable" then
		if paidPrice > 0 then
			SoundUtility.PlayGameSFXForPlayer(player, "MoneyGet")
		end

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
