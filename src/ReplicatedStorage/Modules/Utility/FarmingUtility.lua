local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))

local FarmingUtility = {}

FarmingUtility.WATERING_TOOL_NAME = "Regadera"
FarmingUtility.FARMING_ZONE_NAME = "FarmingZone"
FarmingUtility.SOIL_NAME = "Soil"
FarmingUtility.FARM_FOLDER_NAME = "FarmPlants"
FarmingUtility.STAGE_FOLDER_NAME = "StagePlants"
FarmingUtility.FARMING_ITEM_ATTRIBUTE = "FarmingItemId"
FarmingUtility.FARMING_CROP_ATTRIBUTE = "FarmingCropId"
FarmingUtility.FARMING_KIND_ATTRIBUTE = "FarmingToolKind"
FarmingUtility.MAX_STAGE = 5

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

local function get_seed_items()
	if type(FarmingCatalog.GetSeedItems) == "function" then
		return FarmingCatalog.GetSeedItems() or {}
	end

	return type(FarmingCatalog.Seeds) == "table" and FarmingCatalog.Seeds or {}
end

local function get_fruit_items()
	if type(FarmingCatalog.GetFruitItems) == "function" then
		return FarmingCatalog.GetFruitItems() or {}
	end

	return type(FarmingCatalog.Fruits) == "table" and FarmingCatalog.Fruits or {}
end

local function get_item_definition(itemId)
	if type(FarmingCatalog.GetItem) == "function" then
		return FarmingCatalog.GetItem(itemId)
	end

	local normalizedItemId = normalize_key(itemId)
	if not normalizedItemId then
		return nil
	end

	for _, seedDefinition in ipairs(get_seed_items()) do
		if normalize_key(seedDefinition.ItemId) == normalizedItemId then
			return seedDefinition
		end
	end

	for _, fruitDefinition in ipairs(get_fruit_items()) do
		if normalize_key(fruitDefinition.ItemId) == normalizedItemId then
			return fruitDefinition
		end
	end

	return nil
end

local function get_crop_definition(cropId)
	if type(FarmingCatalog.GetCrop) == "function" then
		return FarmingCatalog.GetCrop(cropId)
	end

	local normalizedCropId = normalize_key(cropId)
	if not normalizedCropId then
		return nil
	end

	for _, cropDefinition in ipairs(type(FarmingCatalog.Crops) == "table" and FarmingCatalog.Crops or {}) do
		if normalize_key(cropDefinition.CropId) == normalizedCropId then
			return cropDefinition
		end
	end

	return nil
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

function FarmingUtility.GetCropStageFolder(cropDefinition): Folder?
	local stagePlantsFolder = FarmingUtility.GetStagePlantsFolder()
	local folderName = cropDefinition and cropDefinition.StageFolderName

	if type(folderName) ~= "string" or folderName == "" then
		return nil
	end

	local folder = stagePlantsFolder:FindFirstChild(folderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

function FarmingUtility.GetStageTemplate(cropDefinition, stage: number): Instance?
	local cropStageFolder = FarmingUtility.GetCropStageFolder(cropDefinition)
	if not cropStageFolder then
		return nil
	end

	return cropStageFolder:FindFirstChild(("Plant%d"):format(stage))
end

function FarmingUtility.GetFarmingZone(): Instance
	return workspace:WaitForChild(FarmingUtility.FARMING_ZONE_NAME)
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

function FarmingUtility.GetSoilParts(): { BasePart }
	local soils = {}

	for _, descendant in ipairs(FarmingUtility.GetFarmingZone():GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == FarmingUtility.SOIL_NAME then
			table.insert(soils, descendant)
		end
	end

	return soils
end

function FarmingUtility.GetSoilPlacementData(worldPosition: Vector3): { Soil: BasePart, LocalPoint: Vector3, WorldTopPosition: Vector3 }?
	for _, soil in ipairs(FarmingUtility.GetSoilParts()) do
		local localPoint = soil.CFrame:PointToObjectSpace(worldPosition)

		if math.abs(localPoint.X) <= soil.Size.X * 0.5 and math.abs(localPoint.Z) <= soil.Size.Z * 0.5 then
			return {
				Soil = soil,
				LocalPoint = localPoint,
				WorldTopPosition = FarmingUtility.GetWorldTopPosition(soil, localPoint),
			}
		end
	end

	return nil
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
