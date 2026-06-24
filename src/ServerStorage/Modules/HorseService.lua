local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local HorseFactory = require(GameData:WaitForChild("HorseFactory"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))

local HorseService = {}

local function get_first_owned_horse_id(horses)
	for _, horseId in ipairs(horses.OrderedIds or {}) do
		if horses.Owned[horseId] then
			return horseId
		end
	end

	for horseId in pairs(horses.Owned or {}) do
		return horseId
	end

	return nil
end

function HorseService.EquipHorse(player, horseId)
	local horses = DataUtility.server.get(player, "Horses")
	if not horses or not horses.Owned or not horses.Owned[horseId] then
		return false, "HorseNotOwned"
	end

	horses.EquippedHorseId = horseId
	DataUtility.server.set(player, "Horses", horses)

	return true, horseId
end

function HorseService.CreateHorseForPlayer(player, catalogId, options)
	options = options or {}

	local horses = DataUtility.server.get(player, "Horses")
	local collection = DataUtility.server.get(player, "Collection")
	local stats = DataUtility.server.get(player, "Stats")

	if not horses or not collection or not stats then
		return nil, "DataUnavailable"
	end

	if not HorseCatalog.GetDefinition(catalogId) then
		return nil, "UnknownHorseCatalogId"
	end

	horses.NextHorseInstanceId = (horses.NextHorseInstanceId or 0) + 1

	local horse = HorseFactory.Create(catalogId, horses.NextHorseInstanceId, {
		OwnerUserId = player.UserId,
		Nickname = options.Nickname,
		Source = options.Source,
		IsStarterGrant = options.IsStarterGrant,
		ObtainedAt = options.ObtainedAt,
	})

	horses.Owned[horse.Id] = horse
	TableUtility.InsertUnique(horses.OrderedIds, horse.Id)

	if options.EquipOnGrant or horses.EquippedHorseId == "" then
		horses.EquippedHorseId = horse.Id
	end

	TableUtility.InsertUnique(collection.DiscoveredHorseIds, catalogId)
	TableUtility.InsertUnique(collection.OwnedHorseCatalogIds, catalogId)

	stats.TotalHorsesOwned = #horses.OrderedIds

	DataUtility.server.set(player, "Horses", horses)
	DataUtility.server.set(player, "Collection", collection)
	DataUtility.server.set(player, "Stats.TotalHorsesOwned", stats.TotalHorsesOwned)

	return horse, "Created"
end

function HorseService.EnsureStarterHorse(player)
	local horses = DataUtility.server.get(player, "Horses")
	local progression = DataUtility.server.get(player, "Progression")

	if not horses or not progression then
		return nil, "DataUnavailable"
	end

	local hasAnyHorse = next(horses.Owned or {}) ~= nil
	if hasAnyHorse and (horses.EquippedHorseId == "" or horses.Owned[horses.EquippedHorseId] == nil) then
		local firstHorseId = get_first_owned_horse_id(horses)
		if firstHorseId then
			horses.EquippedHorseId = firstHorseId
			DataUtility.server.set(player, "Horses", horses)
		end
	end

	if progression.FirstHorseGranted and hasAnyHorse then
		if horses.EquippedHorseId == "" then
			horses = DataUtility.server.get(player, "Horses")
		end

		return horses.Owned[horses.EquippedHorseId], "AlreadyGranted"
	end

	if not hasAnyHorse then
		local starterHorseId = HorseCatalog.GetStarterHorseIdForPlayer(player.UserId)
		local starterHorse = HorseService.CreateHorseForPlayer(player, starterHorseId, {
			Source = "StarterGrant",
			IsStarterGrant = true,
			EquipOnGrant = true,
		})

		if not starterHorse then
			return nil, "StarterGrantFailed"
		end
	end

	progression.FirstHorseGranted = true
	DataUtility.server.set(player, "Progression", progression)

	local updatedHorses = DataUtility.server.get(player, "Horses")
	local equippedHorseId = updatedHorses and updatedHorses.EquippedHorseId or ""

	return updatedHorses and updatedHorses.Owned[equippedHorseId] or nil, "Granted"
end

return HorseService
