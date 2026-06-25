------------------//SERVICES
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------//CONSTANTS
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local HORSE_FOLDER_NAME = "HorseFolder"
local HORSE_POSITION_NAME = "HorsePosition"
local PRIMARY_HORSE_SLOT_NAME = "Slot1"
local VISUAL_HORSE_ATTRIBUTE = "IsStableVisualHorse"
local HORSE_ID_ATTRIBUTE = "HorseId"
local HORSE_CATALOG_ID_ATTRIBUTE = "HorseCatalogId"

------------------//VARIABLES
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local HorseFactory = require(GameData:WaitForChild("HorseFactory"))
local StableDictionary = require(Dictionary:WaitForChild("StableDictionary"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))

local HorseService = {}

------------------//FUNCTIONS
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

local function get_owned_stalls(stable): number
	local maxOwnedStalls = StableDictionary.DefaultOwnedStalls
	local ownedStalls = stable.OwnedStalls

	if type(ownedStalls) ~= "number" then
		return maxOwnedStalls
	end

	return math.clamp(math.floor(ownedStalls), 0, maxOwnedStalls)
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
	visualHorse.Name = horse.Id
	visualHorse:SetAttribute(VISUAL_HORSE_ATTRIBUTE, true)
	visualHorse:SetAttribute(HORSE_ID_ATTRIBUTE, horse.Id)
	visualHorse:SetAttribute(HORSE_CATALOG_ID_ATTRIBUTE, horse.CatalogId)
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

		return horses.Owned[horseId], horseId
	end

	local resolvedHorseId = horses.EquippedHorseId or ""
	if resolvedHorseId == "" or not horses.Owned[resolvedHorseId] then
		local firstHorseId = get_first_owned_horse_id(horses)
		if not firstHorseId then
			return nil, "HorseNotFound"
		end

		resolvedHorseId = firstHorseId
	end

	return horses.Owned[resolvedHorseId], resolvedHorseId
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

	local stableChanged = ensure_stable_state(stable, horses)

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
		local starterHorse = HorseService.create_horse_for_player(player, starterHorseId, {
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

	HorseService.clear_plot_horses(plot)

	local ownedStalls = get_owned_stalls(stable)
	local horseSlots = stable.HorseSlots or {}
	local ownedHorses = horses.Owned or {}

	for slotIndex, slotName: string in StableDictionary.HorseSlotOrder do
		if slotIndex > ownedStalls then
			break
		end

		local slotFolder = horseFolder:FindFirstChild(slotName)
		local horseId = horseSlots[slotName]

		if slotFolder and horseId ~= "" then
			local horse = ownedHorses[horseId]
			if horse then
				create_visual_horse_in_slot(slotFolder, horse)
			end
		end
	end

	return true, "Synced"
end

HorseService.EquipHorse = HorseService.equip_horse
HorseService.CreateHorseForPlayer = HorseService.create_horse_for_player
HorseService.EnsureStarterHorse = HorseService.ensure_starter_horse
HorseService.SetStableSlotHorse = HorseService.set_stable_slot_horse
HorseService.ClearStableSlot = HorseService.clear_stable_slot
HorseService.ClearPlotHorses = HorseService.clear_plot_horses
HorseService.SyncPlotHorses = HorseService.sync_plot_horses
HorseService.GetPlayerHorse = HorseService.get_player_horse

------------------//INIT
return HorseService
