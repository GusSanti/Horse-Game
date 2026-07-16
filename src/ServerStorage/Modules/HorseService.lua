------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------//CONSTANTS
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")
local Services = Modules:WaitForChild("Services")
local Utility = Modules:WaitForChild("Utility")

local HORSE_FOLDER_NAME = "HorseFolder"
local HORSE_POSITION_NAME = "HorsePosition"
local PRIMARY_HORSE_SLOT_NAME = "Slot1"
local VISUAL_HORSE_ATTRIBUTE = "IsStableVisualHorse"
local HORSE_ID_ATTRIBUTE = "HorseId"
local HORSE_CATALOG_ID_ATTRIBUTE = "HorseCatalogId"
local HORSE_VISUAL_MODEL_NAME_ATTRIBUTE = "HorseVisualModelName"
local STATUS_UPDATE_INTERVAL_SECONDS = 60

------------------//VARIABLES
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local HorseFactory = require(GameData:WaitForChild("HorseFactory"))
local HorseBondService = require(Services:WaitForChild("HorseBondService"))
local HorseStatusService = require(Services:WaitForChild("HorseStatusService"))
local StableDictionary = require(Dictionary:WaitForChild("StableDictionary"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))
local HorseCareService = require(script.Parent:WaitForChild("HorseCareService"))

local HorseService = {}
local statusDecayLoopStarted = false
local RACE_MIN_STATUS_PERCENT = 50
local STATUS_DISPLAY_NAMES = {
	Happiness = "Felicidade",
	Hunger = "Fome",
	Thirst = "Sede",
	Cleanliness = "Limpeza",
	Health = "Saude",
}

------------------//FUNCTIONS
local function get_display_name(horse)
	local nickname = horse.Nickname or ""
	if nickname ~= "" then
		return nickname
	end

	return horse.DisplayName or horse.CatalogId or horse.Id
end

local function get_status_display_name(statusName: string?): string
	if type(statusName) ~= "string" or statusName == "" then
		return "Status"
	end

	return STATUS_DISPLAY_NAMES[statusName] or statusName
end

local function evaluate_race_readiness(horse, now: number?)
	local statuses = HorseStatusService.GetComputedStatuses(horse, now)
	local needs = horse and horse.Needs or {}
	local maxValues = needs and needs.Max or {}
	local lowestStatus = nil
	local lowestPercent = 100
	local blockedStatus = nil
	local blockedPercent = 100
	local totalPercent = 0
	local statusCount = 0

	for _, statusName: string in ipairs(HorseStatusService.StatusOrder) do
		local maxValue = math.max(1, tonumber(maxValues[statusName]) or 100)
		local currentValue = math.clamp(tonumber(statuses and statuses[statusName]) or 0, 0, maxValue)
		local percent = math.floor(((currentValue / maxValue) * 100) + 0.5)
		totalPercent += percent
		statusCount += 1

		if not lowestStatus or percent < lowestPercent then
			lowestStatus = statusName
			lowestPercent = percent
		end

		if percent < RACE_MIN_STATUS_PERCENT and (not blockedStatus or percent < blockedPercent) then
			blockedStatus = statusName
			blockedPercent = percent
		end
	end

	return {
		CanRace = blockedStatus == nil,
		MinimumPercent = RACE_MIN_STATUS_PERCENT,
		LowestStatus = lowestStatus,
		LowestStatusDisplay = get_status_display_name(lowestStatus),
		LowestPercent = lowestPercent,
		BlockedStatus = blockedStatus,
		BlockedStatusDisplay = get_status_display_name(blockedStatus),
		BlockedPercent = blockedPercent,
		AveragePercent = statusCount > 0 and math.floor((totalPercent / statusCount) + 0.5) or 100,
	}
end

local function get_first_owned_horse_id(horses): string?
	local orderedIds = horses.OrderedIds or {}
	local ownedHorses = horses.Owned or {}

	for _, horseId: string in orderedIds do
		if ownedHorses[horseId] then
			return horseId
		end
	end

	for horseId in ownedHorses do
		return horseId
	end

	return nil
end

local function get_owned_horse_ids_in_order(horses): {string}
	local orderedHorseIds: {string} = {}
	local addedHorseIds: {[string]: boolean} = {}
	local orderedIds = horses.OrderedIds or {}
	local ownedHorses = horses.Owned or {}

	for _, horseId: string in orderedIds do
		if ownedHorses[horseId] and not addedHorseIds[horseId] then
			addedHorseIds[horseId] = true
			orderedHorseIds[#orderedHorseIds + 1] = horseId
		end
	end

	for horseId in ownedHorses do
		if not addedHorseIds[horseId] then
			addedHorseIds[horseId] = true
			orderedHorseIds[#orderedHorseIds + 1] = horseId
		end
	end

	return orderedHorseIds
end

local function get_owned_horses_state(player: Player)
	local horses = DataUtility.server.get(player, "Horses")
	if not horses then
		return nil, nil
	end

	return horses, horses.Owned or {}
end

local function get_owned_stalls(stable): number
	local maxOwnedStalls = StableDictionary.MaxOwnedStalls or #StableDictionary.HorseSlotOrder
	local ownedStalls = stable.OwnedStalls

	if type(ownedStalls) ~= "number" then
		return StableDictionary.DefaultOwnedStalls
	end

	return math.clamp(math.floor(ownedStalls), 0, maxOwnedStalls)
end

local function get_slot_purchase_price(slotName: string): number?
	if StableDictionary.get_slot_purchase_price then
		return StableDictionary.get_slot_purchase_price(slotName)
	end

	return StableDictionary.SlotPurchasePrices and StableDictionary.SlotPurchasePrices[slotName] or nil
end

local function get_next_purchasable_slot_name(ownedStalls: number): string?
	local nextIndex = ownedStalls + 1
	return StableDictionary.HorseSlotOrder[nextIndex]
end

local function is_valid_slot_name(slotName: string): boolean
	for _, currentSlotName: string in StableDictionary.HorseSlotOrder do
		if currentSlotName == slotName then
			return true
		end
	end

	return false
end

local function get_slot_index(slotName: string): number?
	for slotIndex, currentSlotName: string in StableDictionary.HorseSlotOrder do
		if currentSlotName == slotName then
			return slotIndex
		end
	end

	return nil
end

local function get_first_empty_slot_name(horseSlots: {[string]: string}, ownedStalls: number): string?
	for slotIndex, slotName: string in StableDictionary.HorseSlotOrder do
		if slotIndex > ownedStalls then
			break
		end

		if horseSlots[slotName] == "" then
			return slotName
		end
	end

	return nil
end

local function clear_duplicate_horse_slots(horseSlots: {[string]: string}, horseId: string, ignoreSlotName: string?): ()
	for _, slotName: string in StableDictionary.HorseSlotOrder do
		if slotName ~= ignoreSlotName and horseSlots[slotName] == horseId then
			horseSlots[slotName] = ""
		end
	end
end

local function ensure_stable_state(stable, horses): boolean
	local changed = false

	if type(stable.HorseSlots) ~= "table" then
		stable.HorseSlots = StableDictionary.get_default_horse_slots()
		changed = true
	end

	local ownedStalls = get_owned_stalls(stable)
	if stable.OwnedStalls ~= ownedStalls then
		stable.OwnedStalls = ownedStalls
		changed = true
	end

	local horseSlots = stable.HorseSlots
	local ownedHorses = horses.Owned or {}
	local assignedHorseIds: {[string]: boolean} = {}

	for _, slotName: string in StableDictionary.HorseSlotOrder do
		if type(horseSlots[slotName]) ~= "string" then
			horseSlots[slotName] = ""
			changed = true
		end
	end

	for slotIndex, slotName: string in StableDictionary.HorseSlotOrder do
		local horseId = horseSlots[slotName]

		if slotIndex > ownedStalls then
			if horseId ~= "" then
				horseSlots[slotName] = ""
				changed = true
			end
		elseif horseId ~= "" then
			if not ownedHorses[horseId] or assignedHorseIds[horseId] then
				horseSlots[slotName] = ""
				changed = true
			else
				assignedHorseIds[horseId] = true
			end
		end
	end

	local orderedHorseIds = get_owned_horse_ids_in_order(horses)
	local equippedHorseId = horses.EquippedHorseId or ""

	if equippedHorseId ~= "" and ownedHorses[equippedHorseId] then
		local prioritizedHorseIds = { equippedHorseId }

		for _, horseId: string in orderedHorseIds do
			if horseId ~= equippedHorseId then
				prioritizedHorseIds[#prioritizedHorseIds + 1] = horseId
			end
		end

		orderedHorseIds = prioritizedHorseIds
	end

	for _, horseId: string in orderedHorseIds do
		if not assignedHorseIds[horseId] then
			local emptySlotName = get_first_empty_slot_name(horseSlots, ownedStalls)
			if not emptySlotName then
				break
			end

			horseSlots[emptySlotName] = horseId
			assignedHorseIds[horseId] = true
			changed = true
		end
	end

	return changed
end

local function save_stable(player: Player, stable): ()
	DataUtility.server.set(player, "Stable", stable)
end

local function save_owned_horses(player: Player, horses): ()
	DataUtility.server.set(player, "Horses.Owned", horses.Owned)
end

local function refresh_owned_horse_statuses(player: Player, horses, horseId: string?): (boolean, string)
	if not horses or type(horses.Owned) ~= "table" then
		return false, "DataUnavailable"
	end

	local now = os.time()
	local changed = false
	local totalBondXP = 0

	local function refresh_horse(horse): ()
		local horseChanged = HorseCareService.RefreshHorse(horse, now)
		local bondChanged, xpGained = HorseBondService.ApplyPassiveProgress(horse, now)

		changed = changed or horseChanged or bondChanged
		totalBondXP += xpGained or 0
	end

	if horseId and horseId ~= "" then
		local horse = horses.Owned[horseId]
		if not horse then
			return false, "HorseNotOwned"
		end

		refresh_horse(horse)
	else
		for _, horse in horses.Owned do
			refresh_horse(horse)
		end
	end

	if changed then
		save_owned_horses(player, horses)

		if totalBondXP > 0 then
			local currentBondPoints = DataUtility.server.get(player, "Stats.TotalBondPointsEarned") or 0
			DataUtility.server.set(player, "Stats.TotalBondPointsEarned", currentBondPoints + totalBondXP)
		end

		return true, "Updated"
	end

	return true, "Unchanged"
end

local function get_horse_assets_folder(): Instance?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		return nil
	end

	return assetsFolder:FindFirstChild("Horses")
end

local function get_horse_visual_model_name(horse): string
	if type(horse.VisualModelName) == "string" and horse.VisualModelName ~= "" then
		return horse.VisualModelName
	end

	if type(horse.PlaceholderModelKey) == "string" and horse.PlaceholderModelKey ~= "" then
		return horse.PlaceholderModelKey
	end

	if type(horse.CatalogId) == "string" and horse.CatalogId ~= "" then
		return horse.CatalogId
	end

	if type(horse.DisplayName) == "string" and horse.DisplayName ~= "" then
		return horse.DisplayName
	end

	return ""
end

local function find_horse_visual_source(horse): Instance?
	local horsesFolder = get_horse_assets_folder()
	if not horsesFolder then
		return nil
	end

	local modelName = get_horse_visual_model_name(horse)
	if modelName ~= "" then
		local model = horsesFolder:FindFirstChild(modelName)
		if model then
			return model
		end
	end

	local catalogId = horse.CatalogId
	if type(catalogId) == "string" and catalogId ~= "" then
		local catalogModel = horsesFolder:FindFirstChild(catalogId)
		if catalogModel then
			return catalogModel
		end

		local definition = HorseCatalog.GetDefinition(catalogId)
		if definition then
			local placeholderModel = horsesFolder:FindFirstChild(definition.PlaceholderModelKey)
			if placeholderModel then
				return placeholderModel
			end
		end
	end

	return nil
end

local function get_base_part_lowest_y(basePart: BasePart): number
	local cframe = basePart.CFrame
	local halfSizeX = cframe.RightVector * (basePart.Size.X * 0.5)
	local halfSizeY = cframe.UpVector * (basePart.Size.Y * 0.5)
	local halfSizeZ = cframe.LookVector * (basePart.Size.Z * 0.5)
	local lowestY = math.huge

	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local cornerPosition = cframe.Position + (halfSizeX * xSign) + (halfSizeY * ySign) + (halfSizeZ * zSign)
				lowestY = math.min(lowestY, cornerPosition.Y)
			end
		end
	end

	return lowestY
end

local function get_instance_lowest_y(instance: Instance): number?
	if instance:IsA("BasePart") then
		return get_base_part_lowest_y(instance)
	end

	local lowestY = math.huge
	local foundBasePart = false

	for _, descendant: Instance in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			foundBasePart = true
			lowestY = math.min(lowestY, get_base_part_lowest_y(descendant))
		end
	end

	if not foundBasePart then
		return nil
	end

	return lowestY
end

local function clear_visual_horse_from_slot(slotFolder: Instance): ()
	for _, child: Instance in slotFolder:GetChildren() do
		if child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function get_visual_horses_in_slot(slotFolder: Instance): {Instance}
	local visualHorses = {}

	for _, child: Instance in slotFolder:GetChildren() do
		if child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true then
			visualHorses[#visualHorses + 1] = child
		end
	end

	return visualHorses
end

local function apply_visual_horse_metadata(visualHorse: Instance, horse): ()
	visualHorse.Name = horse.Id
	visualHorse:SetAttribute(VISUAL_HORSE_ATTRIBUTE, true)
	visualHorse:SetAttribute(HORSE_ID_ATTRIBUTE, horse.Id)
	visualHorse:SetAttribute(HORSE_CATALOG_ID_ATTRIBUTE, horse.CatalogId)
	visualHorse:SetAttribute(HORSE_VISUAL_MODEL_NAME_ATTRIBUTE, get_horse_visual_model_name(horse))
end

local function has_matching_visual_horse_identity(visualHorse: Instance, horse): boolean
	if visualHorse:GetAttribute(VISUAL_HORSE_ATTRIBUTE) ~= true then
		return false
	end

	if visualHorse:GetAttribute(HORSE_ID_ATTRIBUTE) ~= horse.Id then
		return false
	end

	if visualHorse:GetAttribute(HORSE_CATALOG_ID_ATTRIBUTE) ~= horse.CatalogId then
		return false
	end

	return true
end

local function is_visual_horse_current(visualHorse: Instance, horse): boolean
	if not has_matching_visual_horse_identity(visualHorse, horse) then
		return false
	end

	local currentModelName = visualHorse:GetAttribute(HORSE_VISUAL_MODEL_NAME_ATTRIBUTE)
	if type(currentModelName) ~= "string" or currentModelName == "" then
		return true
	end

	return visualHorse:GetAttribute(HORSE_VISUAL_MODEL_NAME_ATTRIBUTE) == get_horse_visual_model_name(horse)
end

local function create_visual_horse_in_slot(slotFolder: Instance, horse): (Instance?, string)
	clear_visual_horse_from_slot(slotFolder)

	local horsePosition = slotFolder:FindFirstChild(HORSE_POSITION_NAME)
	if not horsePosition or not horsePosition:IsA("BasePart") then
		return nil, "HorsePositionMissing"
	end

	local horseModel = find_horse_visual_source(horse)
	if not horseModel then
		return nil, "HorseModelMissing"
	end

	local visualHorse = horseModel:Clone()
	apply_visual_horse_metadata(visualHorse, horse)
	visualHorse.Parent = slotFolder

	if visualHorse:IsA("Model") or visualHorse:IsA("BasePart") then
		visualHorse:PivotTo(horsePosition.CFrame)

		local horseLowestY = get_instance_lowest_y(visualHorse)
		local positionLowestY = get_instance_lowest_y(horsePosition)

		if horseLowestY and positionLowestY then
			local currentPivot = visualHorse:GetPivot()
			local heightOffset = positionLowestY - horseLowestY
			visualHorse:PivotTo(currentPivot + Vector3.new(0, heightOffset, 0))
		end

		return visualHorse, "Created"
	end

	visualHorse:Destroy()
	return nil, "InvalidHorseModelType"
end

local function sync_visual_horse_in_slot(slotFolder: Instance, horse): ()
	if not horse then
		clear_visual_horse_from_slot(slotFolder)
		return
	end

	local visualHorses = get_visual_horses_in_slot(slotFolder)
	if #visualHorses == 1 and is_visual_horse_current(visualHorses[1], horse) then
		apply_visual_horse_metadata(visualHorses[1], horse)
		return
	end

	create_visual_horse_in_slot(slotFolder, horse)
end

local function build_horse_summary(horse, equippedHorseId, now: number?)
	local movement = horse.Movement or {}
	local stats = horse.Stats or {}
	local readiness = evaluate_race_readiness(horse, now)

	return {
		Id = horse.Id,
		CatalogId = horse.CatalogId,
		Name = get_display_name(horse),
		DisplayName = horse.DisplayName or horse.CatalogId or horse.Id,
		Nickname = horse.Nickname or "",
		PlaceholderModelKey = horse.PlaceholderModelKey or "",
		RaceAffinity = movement.RaceAffinity or 0.5,
		SprintSpeed = movement.SprintSpeed or 24,
		Acceleration = movement.Acceleration or 0.8,
		Stamina = movement.Stamina or 100,
		RacesEntered = stats.RacesEntered or 0,
		RacesWon = stats.RacesWon or 0,
		BestRaceTimeMs = stats.BestRaceTimeMs or 0,
		IsEquipped = horse.Id == equippedHorseId,
		CanRace = readiness.CanRace,
		RaceMinPercent = readiness.MinimumPercent,
		RaceConditionPercent = readiness.AveragePercent,
		RaceLowestStatus = readiness.LowestStatus,
		RaceLowestStatusDisplay = readiness.LowestStatusDisplay,
		RaceLowestPercent = readiness.LowestPercent,
		RaceBlockedStatus = readiness.BlockedStatus,
		RaceBlockedStatusDisplay = readiness.BlockedStatusDisplay,
		RaceBlockedPercent = readiness.BlockedPercent,
	}
end

local function build_horse_reveal_payload(horse)
	if type(horse) ~= "table" then
		return nil
	end

	local definition = HorseCatalog.GetDefinition(horse.CatalogId) or HorseCatalog.GetDefinition("Default")
	if not definition then
		return nil
	end

	return {
		HorseId = horse.Id,
		CatalogId = definition.CatalogId,
		DisplayName = definition.DisplayName,
		Rarity = definition.Rarity,
		ModelKey = definition.PlaceholderModelKey,
		Source = horse.Acquisition and horse.Acquisition.Source or "",
	}
end

local function find_starter_granted_horse(horses)
	if type(horses) ~= "table" or type(horses.Owned) ~= "table" then
		return nil
	end

	for _, horseId: string in ipairs(horses.OrderedIds or {}) do
		local horse = horses.Owned[horseId]
		if horse and horse.Acquisition and horse.Acquisition.Source == "StarterGrant" then
			return horse
		end
	end

	for _, horse in pairs(horses.Owned) do
		if horse and horse.Acquisition and horse.Acquisition.Source == "StarterGrant" then
			return horse
		end
	end

	return nil
end

local function compute_race_happiness_gain(placement: number, participantCount: number): number
	local clampedParticipantCount = math.max(1, math.floor(participantCount or 1))
	local clampedPlacement = math.clamp(math.floor(placement or clampedParticipantCount), 1, clampedParticipantCount)

	if clampedParticipantCount == 1 then
		return 2
	end

	local placementAlpha = 1 - ((clampedPlacement - 1) / (clampedParticipantCount - 1))
	return math.max(1, math.floor((1 + (placementAlpha * 3)) + 0.5))
end

local function add_happiness_to_horse(horse, happinessGain: number, moodText: string?): ()
	local safeGain = math.max(0, happinessGain or 0)
	if safeGain <= 0 then
		return
	end

	horse.Needs = horse.Needs or {}
	horse.Needs.Values = horse.Needs.Values or {}
	horse.Needs.Max = horse.Needs.Max or {}
	horse.State = horse.State or {}

	horse.Needs.Values.Happiness = math.clamp(
		(horse.Needs.Values.Happiness or 0) + safeGain,
		0,
		horse.Needs.Max.Happiness or 100
	)

	if type(moodText) == "string" and moodText ~= "" then
		horse.State.Mood = moodText
	end
end

------------------//MAIN FUNCTIONS
function HorseService.get_player_horse(player: Player, horseId: string?): (any?, string)
	local horses = DataUtility.server.get(player, "Horses")
	if not horses or not horses.Owned then
		return nil, "DataUnavailable"
	end

	if horseId and horseId ~= "" then
		if not horses.Owned[horseId] then
			return nil, "HorseNotOwned"
		end

		local requestedHorse = horses.Owned[horseId]
		if requestedHorse and HorseCareService.RefreshHorse(requestedHorse, os.time()) then
			DataUtility.server.set(player, "Horses", horses)
		end

		return requestedHorse, horseId
	end

	local resolvedHorseId = horses.EquippedHorseId or ""
	if resolvedHorseId == "" or not horses.Owned[resolvedHorseId] then
		local firstHorseId = get_first_owned_horse_id(horses)
		if not firstHorseId then
			return nil, "HorseNotFound"
		end

		resolvedHorseId = firstHorseId
	end

	local horse = horses.Owned[resolvedHorseId]
	if horse and HorseCareService.RefreshHorse(horse, os.time()) then
		DataUtility.server.set(player, "Horses", horses)
	end

	return horse, resolvedHorseId
end

function HorseService.equip_horse(player: Player, horseId: string): (boolean, string)
	local horse = HorseService.get_player_horse(player, horseId)
	if not horse then
		return false, "HorseNotOwned"
	end

	local horses = DataUtility.server.get(player, "Horses")
	if not horses then
		return false, "DataUnavailable"
	end

	horses.EquippedHorseId = horseId
	DataUtility.server.set(player, "Horses", horses)
	HorseService.set_stable_slot_horse(player, PRIMARY_HORSE_SLOT_NAME, horseId)

	return true, horseId
end

function HorseService.GetOwnedHorse(player, horseId)
	local _, owned = get_owned_horses_state(player)
	if not owned then
		return nil
	end

	return owned[horseId]
end

function HorseService.GetOwnedHorses(player)
	local horses, owned = get_owned_horses_state(player)
	if not horses or not owned then
		return {}
	end

	local ordered = {}
	local inserted = {}

	for _, horseId in ipairs(horses.OrderedIds or {}) do
		local horse = owned[horseId]
		if horse then
			ordered[#ordered + 1] = horse
			inserted[horseId] = true
		end
	end

	for horseId, horse in pairs(owned) do
		if not inserted[horseId] then
			ordered[#ordered + 1] = horse
		end
	end

	return ordered
end

function HorseService.GetOwnedHorseSummaries(player)
	local horses = DataUtility.server.get(player, "Horses")
	if not horses then
		return {}
	end

	local summaries = {}
	local now = os.time()
	for _, horse in ipairs(HorseService.GetOwnedHorses(player)) do
		summaries[#summaries + 1] = build_horse_summary(horse, horses.EquippedHorseId, now)
	end

	return summaries
end

function HorseService.GetRaceReadiness(player: Player, horseId: string)
	local horse, errorCode = HorseService.get_player_horse(player, horseId)
	if not horse then
		return nil, errorCode or "HorseNotOwned"
	end

	return evaluate_race_readiness(horse, os.time()), nil
end

function HorseService.GetEquippedHorse(player)
	local horses, owned = get_owned_horses_state(player)
	if not horses or not owned then
		return nil
	end

	local equippedHorseId = horses.EquippedHorseId or ""
	if equippedHorseId ~= "" and owned[equippedHorseId] then
		return owned[equippedHorseId]
	end

	local fallbackHorseId = get_first_owned_horse_id(horses)
	if fallbackHorseId then
		return owned[fallbackHorseId]
	end

	return nil
end

function HorseService.create_horse_for_player(player: Player, catalogId: string, options): (any, string)
	options = options or {}

	local horses = DataUtility.server.get(player, "Horses")
	local collection = DataUtility.server.get(player, "Collection")
	local stats = DataUtility.server.get(player, "Stats")
	local stable = DataUtility.server.get(player, "Stable")

	if not horses or not collection or not stats or not stable then
		return nil, "DataUnavailable"
	end

	if not HorseCatalog.GetDefinition(catalogId) then
		return nil, "UnknownHorseCatalogId"
	end

	local stableChanged = ensure_stable_state(stable, horses)
	local ownedStalls = get_owned_stalls(stable)
	local emptySlotName = get_first_empty_slot_name(stable.HorseSlots, ownedStalls)

	if not emptySlotName then
		if stableChanged then
			save_stable(player, stable)
		end

		return nil, "NoStableSlotAvailable"
	end

	horses.NextHorseInstanceId = (horses.NextHorseInstanceId or 0) + 1

	local horse = HorseFactory.Create(catalogId, horses.NextHorseInstanceId, {
		OwnerUserId = player.UserId,
		Nickname = options.Nickname,
		Source = options.Source,
		IsStarterGrant = options.IsStarterGrant,
		ObtainedAt = options.ObtainedAt,
	})
	HorseBondService.NormalizeBond(horse, os.time())
	HorseStatusService.NormalizeHorse(horse, os.time())

	horses.Owned[horse.Id] = horse
	TableUtility.InsertUnique(horses.OrderedIds, horse.Id)
	stable.HorseSlots[emptySlotName] = horse.Id

	if options.EquipOnGrant or horses.EquippedHorseId == "" then
		horses.EquippedHorseId = horse.Id
	end

	stableChanged = ensure_stable_state(stable, horses) or stableChanged

	TableUtility.InsertUnique(collection.DiscoveredHorseIds, catalogId)
	TableUtility.InsertUnique(collection.OwnedHorseCatalogIds, catalogId)

	stats.TotalHorsesOwned = #horses.OrderedIds

	DataUtility.server.set(player, "Horses", horses)

	if stableChanged then
		save_stable(player, stable)
	end

	DataUtility.server.set(player, "Collection", collection)
	DataUtility.server.set(player, "Stats.TotalHorsesOwned", stats.TotalHorsesOwned)

	return horse, "Created"
end

function HorseService.ensure_starter_horse(player: Player): (any, string)
	local horses = DataUtility.server.get(player, "Horses")
	local progression = DataUtility.server.get(player, "Progression")
	local stable = DataUtility.server.get(player, "Stable")

	if not horses or not progression or not stable then
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
		if progression.StarterRevealAcknowledged ~= true and type(progression.PendingHorseReveal) ~= "table" then
			local starterHorse = find_starter_granted_horse(horses)
			local revealPayload = build_horse_reveal_payload(starterHorse)
			if revealPayload then
				DataUtility.server.set(player, "Progression.PendingHorseReveal", revealPayload)
			end
		end

		local stableChanged = ensure_stable_state(stable, horses)
		if stableChanged then
			save_stable(player, stable)
		end

		if horses.EquippedHorseId == "" then
			horses = DataUtility.server.get(player, "Horses")
		end

		local currentHorse = HorseService.get_player_horse(player)
		return currentHorse, "AlreadyGranted"
	end

	if not hasAnyHorse then
		local starterHorseId = HorseCatalog.GetStarterHorseIdForPlayer(player.UserId)
		local starterHorse, starterError = HorseService.create_horse_for_player(player, starterHorseId, {
			Source = "StarterGrant",
			IsStarterGrant = true,
			EquipOnGrant = true,
		})

		if not starterHorse then
			return nil, starterError or "StarterGrantFailed"
		end

		local revealPayload = build_horse_reveal_payload(starterHorse)
		if revealPayload then
			DataUtility.server.set(player, "Progression.PendingHorseReveal", revealPayload)
		end
	end

	progression.FirstHorseGranted = true
	DataUtility.server.set(player, "Progression", progression)

	local updatedHorses = DataUtility.server.get(player, "Horses")
	local updatedStable = DataUtility.server.get(player, "Stable")
	if updatedHorses and updatedStable and ensure_stable_state(updatedStable, updatedHorses) then
		save_stable(player, updatedStable)
	end

	local currentHorse = HorseService.get_player_horse(player)
	if not currentHorse then
		return nil, "Granted"
	end

	return currentHorse, "Granted"
end

function HorseService.set_stable_slot_horse(player: Player, slotName: string, horseId: string): (boolean, string)
	if not is_valid_slot_name(slotName) then
		return false, "InvalidSlot"
	end

	local horses = DataUtility.server.get(player, "Horses")
	local stable = DataUtility.server.get(player, "Stable")

	if not horses or not stable then
		return false, "DataUnavailable"
	end

	if not horses.Owned or not horses.Owned[horseId] then
		return false, "HorseNotOwned"
	end

	ensure_stable_state(stable, horses)

	local slotIndex = get_slot_index(slotName)
	local ownedStalls = get_owned_stalls(stable)
	if not slotIndex or slotIndex > ownedStalls then
		return false, "SlotLocked"
	end

	local horseSlots = stable.HorseSlots
	local previousHorseId = horseSlots[slotName]

	clear_duplicate_horse_slots(horseSlots, horseId, slotName)
	horseSlots[slotName] = horseId

	if previousHorseId ~= "" and previousHorseId ~= horseId then
		local emptySlotName = get_first_empty_slot_name(horseSlots, ownedStalls)
		if emptySlotName then
			horseSlots[emptySlotName] = previousHorseId
		end
	end

	save_stable(player, stable)

	return true, horseId
end

function HorseService.clear_stable_slot(player: Player, slotName: string): (boolean, string)
	if not is_valid_slot_name(slotName) then
		return false, "InvalidSlot"
	end

	local horses = DataUtility.server.get(player, "Horses")
	local stable = DataUtility.server.get(player, "Stable")

	if not horses or not stable then
		return false, "DataUnavailable"
	end

	ensure_stable_state(stable, horses)
	stable.HorseSlots[slotName] = ""
	save_stable(player, stable)

	return true, slotName
end

function HorseService.get_owned_stalls(player: Player): (number?, string?)
	local stable = DataUtility.server.get(player, "Stable")
	if not stable then
		return nil, "DataUnavailable"
	end

	return get_owned_stalls(stable), nil
end

function HorseService.buy_stable_slot(player: Player, slotName: string): (boolean, string, number?)
	if not is_valid_slot_name(slotName) then
		return false, "InvalidSlot", nil
	end

	if slotName == PRIMARY_HORSE_SLOT_NAME then
		return false, "StarterSlotAlwaysOwned", nil
	end

	local slotPrice = get_slot_purchase_price(slotName)
	if type(slotPrice) ~= "number" or slotPrice <= 0 then
		return false, "SlotNotPurchasable", nil
	end

	local horses = DataUtility.server.get(player, "Horses")
	local stable = DataUtility.server.get(player, "Stable")
	if not horses or not stable then
		return false, "DataUnavailable", nil
	end

	local stableChanged = ensure_stable_state(stable, horses)
	local ownedStalls = get_owned_stalls(stable)
	local slotIndex = get_slot_index(slotName)
	local nextSlotName = get_next_purchasable_slot_name(ownedStalls)

	if stableChanged then
		save_stable(player, stable)
	end

	if not slotIndex then
		return false, "InvalidSlot", nil
	end

	if slotIndex <= ownedStalls then
		return false, "SlotAlreadyOwned", ownedStalls
	end

	if slotName ~= nextSlotName then
		return false, "PreviousSlotRequired", ownedStalls
	end

	local currentHorseshoes = DataUtility.server.get(player, "Currencies.Horseshoes") or 0
	if currentHorseshoes < slotPrice then
		return false, "NotEnoughHorseshoes", ownedStalls
	end

	stable.OwnedStalls = math.min(
		ownedStalls + 1,
		StableDictionary.MaxOwnedStalls or #StableDictionary.HorseSlotOrder
	)

	if ensure_stable_state(stable, horses) then
		-- ensure_stable_state may auto-fill newly unlocked slots with already owned horses.
	end

	DataUtility.server.set(player, "Currencies.Horseshoes", currentHorseshoes - slotPrice)
	save_stable(player, stable)

	return true, slotName, stable.OwnedStalls
end

function HorseService.clear_plot_horses(plot: Instance): (boolean, string)
	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return false, "HorseFolderMissing"
	end

	for _, slotFolder: Instance in horseFolder:GetChildren() do
		clear_visual_horse_from_slot(slotFolder)
	end

	return true, "Cleared"
end

function HorseService.sync_plot_horses(player: Player, plot: Instance): (boolean, string)
	local horses = DataUtility.server.get(player, "Horses")
	local stable = DataUtility.server.get(player, "Stable")

	if not horses or not stable then
		return false, "DataUnavailable"
	end

	local stableChanged = ensure_stable_state(stable, horses)
	if stableChanged then
		save_stable(player, stable)
	end

	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return false, "HorseFolderMissing"
	end

	local ownedStalls = get_owned_stalls(stable)
	local horseSlots = stable.HorseSlots or {}
	local ownedHorses = horses.Owned or {}

	for slotIndex, slotName: string in StableDictionary.HorseSlotOrder do
		local slotFolder = horseFolder:FindFirstChild(slotName)
		if slotFolder then
			local horseId = slotIndex <= ownedStalls and horseSlots[slotName] or ""
			local horse = horseId ~= "" and ownedHorses[horseId] or nil
			sync_visual_horse_in_slot(slotFolder, horse)
		end
	end

	return true, "Synced"
end

function HorseService.refresh_horse_statuses(player: Player, horseId: string?): (boolean, string)
	local horses = DataUtility.server.get(player, "Horses")
	return refresh_owned_horse_statuses(player, horses, horseId)
end

function HorseService.refresh_all_player_horses(player: Player): boolean
	local success = HorseService.refresh_horse_statuses(player)
	return success == true
end

function HorseService.start_status_decay_loop(): ()
	if statusDecayLoopStarted then
		return
	end

	statusDecayLoopStarted = true

	task.spawn(function()
		while statusDecayLoopStarted do
			task.wait(STATUS_UPDATE_INTERVAL_SECONDS)

			for _, player: Player in Players:GetPlayers() do
				HorseService.refresh_horse_statuses(player)
			end
		end
	end)
end

function HorseService.RecordRaceEntry(player, horseId)
	local horses, owned = get_owned_horses_state(player)
	if not horses or not owned or not owned[horseId] then
		return false, "HorseNotOwned"
	end

	local horse = owned[horseId]
	horse.Stats = horse.Stats or {}
	horse.Stats.RacesEntered = (horse.Stats.RacesEntered or 0) + 1
	owned[horseId] = horse
	horses.Owned = owned

	DataUtility.server.set(player, "Horses", horses)

	local totalRacesEntered = (DataUtility.server.get(player, "Stats.TotalRacesEntered") or 0) + 1
	DataUtility.server.set(player, "Stats.TotalRacesEntered", totalRacesEntered)

	local raceStats = DataUtility.server.get(player, "Race")
	if raceStats then
		raceStats.RacesEntered = (raceStats.RacesEntered or 0) + 1
		raceStats.LastRaceAt = os.time()
		DataUtility.server.set(player, "Race", raceStats)
	end

	return true, build_horse_summary(horse, horses.EquippedHorseId)
end

function HorseService.RecordRaceWin(player, horseId, finishTimeMs, rewardAmount)
	local horses, owned = get_owned_horses_state(player)
	if not horses or not owned or not owned[horseId] then
		return false, "HorseNotOwned"
	end

	local horse = owned[horseId]
	horse.Stats = horse.Stats or {}
	horse.Stats.RacesWon = (horse.Stats.RacesWon or 0) + 1

	local currentBestTime = horse.Stats.BestRaceTimeMs or 0
	if finishTimeMs and finishTimeMs > 0 and (currentBestTime <= 0 or finishTimeMs < currentBestTime) then
		horse.Stats.BestRaceTimeMs = finishTimeMs
	end

	owned[horseId] = horse
	horses.Owned = owned
	DataUtility.server.set(player, "Horses", horses)

	local totalRaceWins = (DataUtility.server.get(player, "Stats.TotalRaceWins") or 0) + 1
	DataUtility.server.set(player, "Stats.TotalRaceWins", totalRaceWins)

	local raceStats = DataUtility.server.get(player, "Race")
	if raceStats then
		raceStats.RacesWon = (raceStats.RacesWon or 0) + 1
		raceStats.LastRaceAt = os.time()

		local currentBestRaceTime = raceStats.BestRaceTimeMs or 0
		if finishTimeMs and finishTimeMs > 0 and (currentBestRaceTime <= 0 or finishTimeMs < currentBestRaceTime) then
			raceStats.BestRaceTimeMs = finishTimeMs
		end

		raceStats.TotalRewardsEarned = (raceStats.TotalRewardsEarned or 0) + math.max(0, rewardAmount or 0)
		DataUtility.server.set(player, "Race", raceStats)
	end

	return true, build_horse_summary(horse, horses.EquippedHorseId)
end

function HorseService.RecordRacePlacement(player, horseId, placement, participantCount)
	local horses, owned = get_owned_horses_state(player)
	if not horses or not owned or not owned[horseId] then
		return false, "HorseNotOwned"
	end

	local horse = owned[horseId]
	local now = os.time()
	HorseCareService.RefreshHorse(horse, now)

	add_happiness_to_horse(
		horse,
		compute_race_happiness_gain(placement, participantCount),
		placement == 1 and "Thrilled" or "Proud"
	)

	owned[horseId] = horse
	horses.Owned = owned
	DataUtility.server.set(player, "Horses", horses)

	return true, build_horse_summary(horse, horses.EquippedHorseId, now)
end

HorseService.EquipHorse = HorseService.equip_horse
HorseService.CreateHorseForPlayer = HorseService.create_horse_for_player
HorseService.EnsureStarterHorse = HorseService.ensure_starter_horse
HorseService.SetStableSlotHorse = HorseService.set_stable_slot_horse
HorseService.ClearStableSlot = HorseService.clear_stable_slot
HorseService.GetOwnedStalls = HorseService.get_owned_stalls
HorseService.BuyStableSlot = HorseService.buy_stable_slot
HorseService.ClearPlotHorses = HorseService.clear_plot_horses
HorseService.SyncPlotHorses = HorseService.sync_plot_horses
HorseService.GetPlayerHorse = HorseService.get_player_horse
HorseService.RefreshAllPlayerHorses = HorseService.refresh_all_player_horses
HorseService.RefreshHorseStatuses = HorseService.refresh_horse_statuses
HorseService.StartStatusDecayLoop = HorseService.start_status_decay_loop

------------------//INIT
return HorseService
