local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))

local FarmingUtility = {}

FarmingUtility.WATERING_TOOL_NAME = "Regadera"
FarmingUtility.FARMING_ZONE_NAME = "FarmingZone"
FarmingUtility.SOIL_NAME = "Soil"
FarmingUtility.PLOT_VALUE_NAME = "Plot"
FarmingUtility.FENCE_MODEL_NAME = "Fence"
FarmingUtility.GARDEN_MODEL_NAME = "Garden"
FarmingUtility.GARDEN_SOIL_NAME = "Union"
FarmingUtility.FARM_FOLDER_NAME = "FarmPlants"
FarmingUtility.STAGE_FOLDER_NAME = "StagePlants"
FarmingUtility.FARMING_ITEM_ATTRIBUTE = "FarmingItemId"
FarmingUtility.FARMING_CROP_ATTRIBUTE = "FarmingCropId"
FarmingUtility.FARMING_KIND_ATTRIBUTE = "FarmingToolKind"
FarmingUtility.FARMING_RARITY_ATTRIBUTE = "FarmingRarity"
FarmingUtility.PLANT_FOOTPRINT_SIZE = Vector3.new(2.4, 0.2, 2.4)
FarmingUtility.PLANT_FOOTPRINT_PADDING = 0.1
FarmingUtility.MAX_STAGE = 4

local function normalize_key(value): string?
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function normalize_asset_name(value): string?
	local normalizedValue = normalize_key(value)
	if not normalizedValue then
		return nil
	end

	return string.gsub(normalizedValue, "[_%-%s]+", "")
end

local function get_seed_items()
	return FarmingCatalog.GetSeedItems() or {}
end

local function get_item_definition(itemId)
	return FarmingCatalog.GetSeedItem(itemId)
end

local function get_crop_definition(cropId)
	return FarmingCatalog.GetCrop(cropId)
end

local function get_nested_child(root: Instance?, pathParts): Instance?
	local current = root

	for _, part in ipairs(pathParts or {}) do
		if not current then
			return nil
		end

		current = current:FindFirstChild(part)
	end

	return current
end

local function find_ancestor_named(instance: Instance, stopAt: Instance?, ancestorName: string): Instance?
	local current = instance.Parent

	while current and current ~= stopAt do
		if current.Name == ancestorName then
			return current
		end

		current = current.Parent
	end

	return nil
end

local function get_number_attribute(instance: Instance, attributeName: string): number?
	local value = instance:GetAttribute(attributeName)
	return if type(value) == "number" then value else nil
end

local function insert_unique_instance(instances, instance: Instance?)
	if not instance then
		return
	end

	for _, existing in ipairs(instances) do
		if existing == instance then
			return
		end
	end

	instances[#instances + 1] = instance
end

local function push_unique_name(names, seenLookup, value)
	if type(value) ~= "string" or value == "" then
		return
	end

	if seenLookup[value] then
		return
	end

	seenLookup[value] = true
	names[#names + 1] = value
end

local function get_crop_stage_folder_candidates(cropDefinition): { string }
	local names = {}
	local seen = {}

	push_unique_name(names, seen, cropDefinition and cropDefinition.StageFolderName)
	push_unique_name(names, seen, cropDefinition and cropDefinition.CropId)
	push_unique_name(names, seen, cropDefinition and cropDefinition.DisplayName)

	for _, alias in ipairs(cropDefinition and cropDefinition.StageFolderAliases or {}) do
		push_unique_name(names, seen, alias)
	end

	return names
end

local function get_stage_template_name_candidates(cropDefinition, stage: number): { string }
	local names = {}
	local seen = {}
	local cropId = cropDefinition and cropDefinition.CropId or ""
	local displayName = cropDefinition and cropDefinition.DisplayName or ""
	local stageAssetPrefix = cropDefinition and cropDefinition.StageAssetPrefix or nil

	push_unique_name(names, seen, ("Plant%d"):format(stage))
	push_unique_name(names, seen, ("Stage%d"):format(stage))

	if type(stageAssetPrefix) == "string" and stageAssetPrefix ~= "" then
		push_unique_name(names, seen, ("%s_Stage%d"):format(stageAssetPrefix, stage))
		push_unique_name(names, seen, ("%sStage%d"):format(stageAssetPrefix, stage))
	end

	if cropId ~= "" then
		push_unique_name(names, seen, ("%s_Stage%d"):format(cropId, stage))
		push_unique_name(names, seen, ("%sStage%d"):format(cropId, stage))
	end

	if displayName ~= "" then
		push_unique_name(names, seen, ("%s_Stage%d"):format(displayName, stage))
		push_unique_name(names, seen, ("%sStage%d"):format(displayName, stage))
	end

	return names
end

local function find_child_by_name_candidates(root: Instance?, candidateNames): Instance?
	if not root then
		return nil
	end

	for _, candidateName in ipairs(candidateNames or {}) do
		local directChild = root:FindFirstChild(candidateName)
		if directChild then
			return directChild
		end
	end

	local normalizedCandidateLookup = {}
	for _, candidateName in ipairs(candidateNames or {}) do
		local normalizedCandidateName = normalize_asset_name(candidateName)
		if normalizedCandidateName then
			normalizedCandidateLookup[normalizedCandidateName] = true
		end
	end

	for _, child in ipairs(root:GetChildren()) do
		local normalizedChildName = normalize_asset_name(child.Name)
		if normalizedChildName and normalizedCandidateLookup[normalizedChildName] then
			return child
		end
	end

	return nil
end

local function get_item_search_names(itemDefinition): { string }
	local names = {}

	local function push(value)
		if type(value) ~= "string" or value == "" then
			return
		end

		for _, existing in ipairs(names) do
			if existing == value then
				return
			end
		end

		names[#names + 1] = value
	end

	push(itemDefinition and itemDefinition.ToolName)
	push(itemDefinition and itemDefinition.DisplayName)
	push(itemDefinition and itemDefinition.ItemId)

	for _, legacyName in ipairs(itemDefinition and itemDefinition.LegacyToolNames or {}) do
		push(legacyName)
	end

	return names
end

local function find_first_named_asset(root: Instance?, itemDefinition): Instance?
	if not root then
		return nil
	end

	for _, name in ipairs(get_item_search_names(itemDefinition)) do
		local found = root:FindFirstChild(name, true)
		if found then
			return found
		end
	end

	return nil
end

local function get_asset_folder_candidates(itemDefinition): { Instance }
	local assetsFolder = FarmingUtility.GetAssetsFolder()
	local folders = {}

	insert_unique_instance(folders, assetsFolder)

	if itemDefinition and itemDefinition.Kind == "Seed" then
		insert_unique_instance(folders, get_nested_child(assetsFolder, { "Seeds" }))
		insert_unique_instance(folders, get_nested_child(assetsFolder, { "Items", "Seeds" }))
	else
		insert_unique_instance(folders, get_nested_child(assetsFolder, { "Fruits" }))
		insert_unique_instance(folders, get_nested_child(assetsFolder, { "Items", "Fruits" }))
		insert_unique_instance(folders, get_nested_child(assetsFolder, { "Items", "Food" }))
	end

	return folders
end

local function resolve_item_asset(itemDefinition, explicitPath): Instance?
	local assetsFolder = FarmingUtility.GetAssetsFolder()
	local directAsset = get_nested_child(assetsFolder, explicitPath)
	if directAsset then
		return directAsset
	end

	for _, folder in ipairs(get_asset_folder_candidates(itemDefinition)) do
		local found = find_first_named_asset(folder, itemDefinition)
		if found then
			return found
		end
	end

	return nil
end

function FarmingUtility.GetAssetsFolder(): Folder
	return ReplicatedStorage:WaitForChild("Assets") :: Folder
end

function FarmingUtility.GetStagePlantsFolder(): Folder
	return FarmingUtility.GetAssetsFolder():WaitForChild(FarmingUtility.STAGE_FOLDER_NAME) :: Folder
end

function FarmingUtility.GetItemAsset(itemDefinition): Instance?
	return resolve_item_asset(itemDefinition, itemDefinition and itemDefinition.AssetPath)
end

function FarmingUtility.GetViewportAsset(itemDefinition): Instance?
	return resolve_item_asset(itemDefinition, itemDefinition and itemDefinition.ViewportAssetPath)
end

function FarmingUtility.GetCropStageFolder(cropDefinition): Instance?
	local stagePlantsFolder = FarmingUtility.GetStagePlantsFolder()
	local folder = find_child_by_name_candidates(stagePlantsFolder, get_crop_stage_folder_candidates(cropDefinition))
	if folder and (folder:IsA("Folder") or folder:IsA("Model")) then
		return folder
	end

	return nil
end

function FarmingUtility.GetStageTemplate(cropDefinition, stage: number): Instance?
	local cropStageFolder = FarmingUtility.GetCropStageFolder(cropDefinition)
	if not cropStageFolder then
		return nil
	end

	local template = find_child_by_name_candidates(cropStageFolder, get_stage_template_name_candidates(cropDefinition, stage))
	if template then
		return template
	end

	local normalizedCropToken = normalize_asset_name(cropDefinition and cropDefinition.CropId)
		or normalize_asset_name(cropDefinition and cropDefinition.DisplayName)
	local normalizedStageToken = normalize_asset_name(("stage%d"):format(stage))

	for _, child in ipairs(cropStageFolder:GetChildren()) do
		local normalizedChildName = normalize_asset_name(child.Name)
		if normalizedChildName
			and normalizedStageToken
			and string.find(normalizedChildName, normalizedStageToken, 1, true)
			and (
				not normalizedCropToken
				or normalizedCropToken == ""
				or string.find(normalizedChildName, normalizedCropToken, 1, true)
			)
		then
			return child
		end
	end

	return nil
end

function FarmingUtility.GetFarmingZone(): Instance?
	return workspace:FindFirstChild(FarmingUtility.FARMING_ZONE_NAME)
end

function FarmingUtility.GetFarmFolder(createIfMissing: boolean?): Folder?
	local folder = workspace:FindFirstChild(FarmingUtility.FARM_FOLDER_NAME)
	if folder then
		return folder :: Folder
	end

	if not createIfMissing then
		return nil
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = FarmingUtility.FARM_FOLDER_NAME
	newFolder.Parent = workspace

	return newFolder
end

function FarmingUtility.GetPlayerPlot(player: Player?): Instance?
	if not player then
		return nil
	end

	local plotValue = player:FindFirstChild(FarmingUtility.PLOT_VALUE_NAME)
	if not plotValue or not plotValue:IsA("ObjectValue") then
		return nil
	end

	local plot = plotValue.Value
	return if plot and plot.Parent then plot else nil
end

function FarmingUtility.GetRelativePath(instance: Instance, ancestor: Instance?): string?
	if not instance or not ancestor then
		return nil
	end

	local parts = {}
	local current = instance

	while current and current ~= ancestor do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end

	if current ~= ancestor then
		return nil
	end

	return table.concat(parts, "/")
end

function FarmingUtility.GetSoilId(soil: BasePart?, plot: Instance?): string?
	if not soil then
		return nil
	end

	return FarmingUtility.GetRelativePath(soil, plot) or soil.Name
end

function FarmingUtility.GetGardenSoilParts(plot: Instance?): { BasePart }
	local soils = {}
	if not plot then
		return soils
	end

	for _, descendant in ipairs(plot:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == FarmingUtility.GARDEN_SOIL_NAME then
			local garden = find_ancestor_named(descendant, plot, FarmingUtility.GARDEN_MODEL_NAME)
			local fence = garden and find_ancestor_named(garden, plot, FarmingUtility.FENCE_MODEL_NAME)
			if garden and fence then
				table.insert(soils, descendant)
			end
		end
	end

	return soils
end

function FarmingUtility.GetPlayerSoilParts(player: Player?): { BasePart }
	return FarmingUtility.GetGardenSoilParts(FarmingUtility.GetPlayerPlot(player))
end

function FarmingUtility.GetPlayerSoilPartById(player: Player?, soilId: string?): BasePart?
	local plot = FarmingUtility.GetPlayerPlot(player)
	local soils = FarmingUtility.GetGardenSoilParts(plot)

	if type(soilId) == "string" and soilId ~= "" then
		for _, soil in ipairs(soils) do
			if FarmingUtility.GetSoilId(soil, plot) == soilId then
				return soil
			end
		end
	end

	return if #soils == 1 then soils[1] else nil
end

function FarmingUtility.GetSoilParts(player: Player?): { BasePart }
	if player then
		return FarmingUtility.GetPlayerSoilParts(player)
	end

	local soils = {}
	local farmingZone = FarmingUtility.GetFarmingZone()
	if not farmingZone then
		return soils
	end

	for _, descendant in ipairs(farmingZone:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == FarmingUtility.SOIL_NAME then
			table.insert(soils, descendant)
		end
	end

	return soils
end

function FarmingUtility.IsFootprintInsideSoil(soil: BasePart, localPoint: Vector3, footprintSize: Vector3?): boolean
	local footprint = footprintSize or FarmingUtility.PLANT_FOOTPRINT_SIZE
	local halfFootprintX = math.max(0, footprint.X) * 0.5
	local halfFootprintZ = math.max(0, footprint.Z) * 0.5

	return math.abs(localPoint.X) + halfFootprintX <= soil.Size.X * 0.5
		and math.abs(localPoint.Z) + halfFootprintZ <= soil.Size.Z * 0.5
end

function FarmingUtility.FootprintsOverlap(
	localPointA: Vector3,
	footprintA: Vector3?,
	localPointB: Vector3,
	footprintB: Vector3?,
	padding: number?
): boolean
	local sizeA = footprintA or FarmingUtility.PLANT_FOOTPRINT_SIZE
	local sizeB = footprintB or FarmingUtility.PLANT_FOOTPRINT_SIZE
	local extraPadding = math.max(0, tonumber(padding) or FarmingUtility.PLANT_FOOTPRINT_PADDING)
	local overlapX = math.abs(localPointA.X - localPointB.X) < ((sizeA.X + sizeB.X) * 0.5 + extraPadding)
	local overlapZ = math.abs(localPointA.Z - localPointB.Z) < ((sizeA.Z + sizeB.Z) * 0.5 + extraPadding)

	return overlapX and overlapZ
end

function FarmingUtility.GetSoilPlacementData(
	worldPosition: Vector3,
	player: Player?,
	footprintSize: Vector3?
): { Soil: BasePart, SoilId: string?, LocalPoint: Vector3, WorldTopPosition: Vector3, FootprintSize: Vector3 }?
	local plot = player and FarmingUtility.GetPlayerPlot(player) or nil
	local footprint = footprintSize or FarmingUtility.PLANT_FOOTPRINT_SIZE

	for _, soil in ipairs(FarmingUtility.GetSoilParts(player)) do
		local localPoint = soil.CFrame:PointToObjectSpace(worldPosition)

		if FarmingUtility.IsFootprintInsideSoil(soil, localPoint, footprint) then
			local snappedLocalPoint = Vector3.new(localPoint.X, 0, localPoint.Z)
			return {
				Soil = soil,
				SoilId = FarmingUtility.GetSoilId(soil, plot),
				LocalPoint = snappedLocalPoint,
				WorldTopPosition = FarmingUtility.GetWorldTopPosition(soil, snappedLocalPoint),
				FootprintSize = footprint,
			}
		end
	end

	return nil
end

function FarmingUtility.IsPlacementOccupied(placement, ownerUserId: number?, ignoredPlantId: number?): (boolean, Instance?)
	if not placement or not placement.LocalPoint then
		return false, nil
	end

	local farmFolder = FarmingUtility.GetFarmFolder(false)
	if not farmFolder then
		return false, nil
	end

	local footprint = placement.FootprintSize or FarmingUtility.PLANT_FOOTPRINT_SIZE
	local soilId = placement.SoilId

	for _, child in ipairs(farmFolder:GetChildren()) do
		local plantId = get_number_attribute(child, "FarmPlantId")
		if plantId and plantId ~= ignoredPlantId then
			local candidateOwnerUserId = get_number_attribute(child, "FarmPlantOwnerUserId")
			if ownerUserId == nil or candidateOwnerUserId == ownerUserId then
				local candidateSoilId = child:GetAttribute("FarmPlantSoilId")
				local sameSoil = soilId == nil
					or type(candidateSoilId) ~= "string"
					or candidateSoilId == soilId

				if sameSoil then
					local localX = get_number_attribute(child, "FarmPlantLocalX")
					local localZ = get_number_attribute(child, "FarmPlantLocalZ")
					local footprintX = get_number_attribute(child, "FarmPlantFootprintX")
					local footprintZ = get_number_attribute(child, "FarmPlantFootprintZ")

					if localX and localZ then
						local candidatePoint = Vector3.new(localX, 0, localZ)
						local candidateFootprint = Vector3.new(
							footprintX or FarmingUtility.PLANT_FOOTPRINT_SIZE.X,
							footprint.Y,
							footprintZ or FarmingUtility.PLANT_FOOTPRINT_SIZE.Z
						)

						if FarmingUtility.FootprintsOverlap(placement.LocalPoint, footprint, candidatePoint, candidateFootprint) then
							return true, child
						end
					end
				end
			end
		end
	end

	return false, nil
end

function FarmingUtility.GetWorldTopPosition(soil: BasePart, localPoint: Vector3): Vector3
	return soil.CFrame:PointToWorldSpace(Vector3.new(localPoint.X, soil.Size.Y * 0.5, localPoint.Z))
end

function FarmingUtility.GetFirstBasePart(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

function FarmingUtility.GetToolHandle(tool: Tool): BasePart?
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return FarmingUtility.GetFirstBasePart(tool)
end

function FarmingUtility.FindHarvestHandle(root: Instance?): BasePart?
	if not root then
		return nil
	end

	local directHandle = root:FindFirstChild("Handle")
	if directHandle and directHandle:IsA("BasePart") then
		return directHandle
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "Handle" then
			return descendant
		end
	end

	return FarmingUtility.GetFirstBasePart(root)
end

function FarmingUtility.GetSeedItemFromTool(tool: Tool?): any?
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	local itemDefinition = get_item_definition(tool:GetAttribute(FarmingUtility.FARMING_ITEM_ATTRIBUTE))
	if itemDefinition and itemDefinition.Kind == "Seed" then
		return itemDefinition
	end

	local normalizedName = normalize_key(tool.Name)
	if not normalizedName then
		return nil
	end

	for _, seedDefinition in ipairs(get_seed_items()) do
		if normalize_key(seedDefinition.ToolName) == normalizedName then
			return seedDefinition
		end

		for _, legacyName in ipairs(seedDefinition.LegacyToolNames or {}) do
			if normalize_key(legacyName) == normalizedName then
				return seedDefinition
			end
		end
	end

	return nil
end

function FarmingUtility.IsSeedTool(tool: Tool?): boolean
	return FarmingUtility.GetSeedItemFromTool(tool) ~= nil
end

function FarmingUtility.GetCropFromSeedTool(tool: Tool?): any?
	local seedItem = FarmingUtility.GetSeedItemFromTool(tool)
	if not seedItem then
		return nil
	end

	return get_crop_definition(seedItem.CropId)
end

function FarmingUtility.FindPlantIdFromInstance(instance: Instance?): number?
	local current = instance

	while current and current ~= workspace do
		local plantId = current:GetAttribute("FarmPlantId")
		if type(plantId) == "number" then
			return plantId
		end

		current = current.Parent
	end

	return nil
end

return FarmingUtility
