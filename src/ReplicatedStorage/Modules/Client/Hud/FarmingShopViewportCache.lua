local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))

local FarmingShopViewportCache = {}

local VIEWPORT_FIELD_OF_VIEW = 35
local VIEWPORT_RADIUS_SCALE = 0.55
local VIEWPORT_CAMERA_Y_SCALE = 0.2
local VIEWPORT_CAMERA_X_SCALE = 0.45

local cacheByItemId = {}
local preloadInstances = nil
local itemDefinitionsById = {}
local allItemDefinitions = nil

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

local function get_all_item_definitions()
	if allItemDefinitions then
		return allItemDefinitions
	end

	allItemDefinitions = {}

	for _, itemDefinition in ipairs(get_seed_items()) do
		itemDefinitionsById[normalize_key(itemDefinition.ItemId)] = itemDefinition
		allItemDefinitions[#allItemDefinitions + 1] = itemDefinition
	end

	for _, itemDefinition in ipairs(get_fruit_items()) do
		itemDefinitionsById[normalize_key(itemDefinition.ItemId)] = itemDefinition
		allItemDefinitions[#allItemDefinitions + 1] = itemDefinition
	end

	return allItemDefinitions
end

local function resolve_item_definition(itemDefinitionOrId)
	if type(itemDefinitionOrId) == "table" then
		return itemDefinitionOrId
	end

	get_all_item_definitions()
	return itemDefinitionsById[normalize_key(itemDefinitionOrId)]
end

local function strip_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function prepare_viewport_model(root: Instance)
	strip_scripts(root)

	if root:IsA("BasePart") then
		root.Anchored = true
		root.CanCollide = false
		root.CanTouch = false
		root.CanQuery = false
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.CastShadow = false
		end
	end
end

local function get_bounds(root: Instance): (Vector3?, Vector3?)
	local minVector = Vector3.new(math.huge, math.huge, math.huge)
	local maxVector = Vector3.new(-math.huge, -math.huge, -math.huge)
	local foundPart = false

	local function include_part(part: BasePart)
		local halfSize = part.Size * 0.5

		for xSign = -1, 1, 2 do
			for ySign = -1, 1, 2 do
				for zSign = -1, 1, 2 do
					local corner = part.CFrame:PointToWorldSpace(Vector3.new(
						halfSize.X * xSign,
						halfSize.Y * ySign,
						halfSize.Z * zSign
					))

					minVector = Vector3.new(
						math.min(minVector.X, corner.X),
						math.min(minVector.Y, corner.Y),
						math.min(minVector.Z, corner.Z)
					)

					maxVector = Vector3.new(
						math.max(maxVector.X, corner.X),
						math.max(maxVector.Y, corner.Y),
						math.max(maxVector.Z, corner.Z)
					)

					foundPart = true
				end
			end
		end
	end

	if root:IsA("BasePart") then
		include_part(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			include_part(descendant)
		end
	end

	if not foundPart then
		return nil, nil
	end

	return (minVector + maxVector) * 0.5, maxVector - minVector
end

local function build_cache_entry(itemDefinition)
	local asset = FarmingUtility.GetViewportAsset(itemDefinition) or FarmingUtility.GetItemAsset(itemDefinition)
	if not asset then
		return nil
	end

	local preparedTemplate = asset:Clone()
	prepare_viewport_model(preparedTemplate)

	local center, size = get_bounds(preparedTemplate)
	if not center or not size then
		preparedTemplate:Destroy()
		return nil
	end

	local radius = math.max(size.X, size.Y, size.Z) * VIEWPORT_RADIUS_SCALE
	local distance = radius / math.tan(math.rad(VIEWPORT_FIELD_OF_VIEW * 0.5)) + radius

	local cacheEntry = {
		ItemId = itemDefinition.ItemId,
		Template = preparedTemplate,
		FieldOfView = VIEWPORT_FIELD_OF_VIEW,
		CameraCFrame = CFrame.lookAt(
			center + Vector3.new(distance * VIEWPORT_CAMERA_X_SCALE, distance * VIEWPORT_CAMERA_Y_SCALE, distance),
			center
		),
	}

	cacheByItemId[itemDefinition.ItemId] = cacheEntry
	return cacheEntry
end

function FarmingShopViewportCache.Get(itemDefinitionOrId)
	local itemDefinition = resolve_item_definition(itemDefinitionOrId)
	if not itemDefinition then
		return nil
	end

	local cacheEntry = cacheByItemId[itemDefinition.ItemId]
	if cacheEntry then
		return cacheEntry
	end

	return build_cache_entry(itemDefinition)
end

function FarmingShopViewportCache.BuildAll(yieldInterval: number?)
	local normalizedYieldInterval = math.max(0, math.floor(tonumber(yieldInterval) or 0))

	for index, itemDefinition in ipairs(get_all_item_definitions()) do
		FarmingShopViewportCache.Get(itemDefinition)

		if normalizedYieldInterval > 0 and index % normalizedYieldInterval == 0 then
			task.wait()
		end
	end
end

function FarmingShopViewportCache.GetPreloadInstances()
	if preloadInstances then
		return preloadInstances
	end

	preloadInstances = {}

	for _, itemDefinition in ipairs(get_all_item_definitions()) do
		local asset = FarmingUtility.GetViewportAsset(itemDefinition) or FarmingUtility.GetItemAsset(itemDefinition)
		if asset then
			preloadInstances[#preloadInstances + 1] = asset
		end
	end

	return preloadInstances
end

return FarmingShopViewportCache