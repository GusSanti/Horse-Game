local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local CropRarityUtility = require(Utility:WaitForChild("CropRarityUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))

local FarmingShopViewportCache = {}

local VIEWPORT_FIELD_OF_VIEW = 35
local VIEWPORT_RADIUS_SCALE = 0.5
local VIEWPORT_CAMERA_Y_SCALE = 0.2
local VIEWPORT_CAMERA_X_SCALE = 0.45
local CLOSE_VIEWPORT_DISTANCE_SCALE = 0.82
local SEED_TOP_DOWN_DISTANCE = 2.25

local CLOSE_VIEWPORT_CROP_IDS = {
	beetroot = true,
	carrot = true,
	corn = true,
	eggplant = true,
	grape = true,
	pineapple = true,
	pumpkin = true,
	radish = true,
	wheat = true,
}

local MODEL_ROTATION_BY_CROP_ID = {
	carrot = CFrame.Angles(0, 0, math.rad(-90)),
}

local TOP_DOWN_VIEWPORT_CROP_IDS = {
	lettuce = true,
}

local cacheByItemId = {}
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

local function get_all_item_definitions()
	if allItemDefinitions then
		return allItemDefinitions
	end

	allItemDefinitions = {}

	for _, toolCategory in ipairs({ "Seeds", "Fruits" }) do
		for _, itemDefinition in ipairs(ToolItemCatalog.GetItemsByToolCategory(toolCategory) or {}) do
			if itemDefinition.Kind == "Seed" or itemDefinition.Kind == "Fruit" then
				itemDefinitionsById[normalize_key(itemDefinition.ItemId)] = itemDefinition
				allItemDefinitions[#allItemDefinitions + 1] = itemDefinition
			end
		end
	end

	return allItemDefinitions
end

local function resolve_item_definition(itemDefinitionOrId)
	if type(itemDefinitionOrId) == "table" then
		return itemDefinitionOrId
	end

	local normalizedItemId = normalize_key(itemDefinitionOrId)
	if not normalizedItemId then
		return nil
	end

	get_all_item_definitions()
	return itemDefinitionsById[normalizedItemId]
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

local function apply_model_rotation(root: Instance, rotation: CFrame)
	local center = get_bounds(root)
	if not center then
		return
	end

	local origin = CFrame.new(center)

	local function rotate_part(part: BasePart)
		part.CFrame = origin * rotation * origin:ToObjectSpace(part.CFrame)
	end

	if root:IsA("BasePart") then
		rotate_part(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			rotate_part(descendant)
		end
	end
end

local function get_top_down_camera_cframe(center: Vector3, distance: number): CFrame
	return CFrame.lookAt(
		center + Vector3.new(0, distance, 0),
		center,
		Vector3.new(0, 0, -1)
	)
end

local function build_cache_entry(itemDefinition)
	local asset = FarmingUtility.GetViewportAsset(itemDefinition) or FarmingUtility.GetItemAsset(itemDefinition)
	if not asset then
		return nil
	end

	local preparedTemplate = asset:Clone()
	prepare_viewport_model(preparedTemplate)

	local isSeed = itemDefinition.Kind == "Seed"
	local cropKey = normalize_key(itemDefinition.CropId)
	local modelRotation = if not isSeed and cropKey then MODEL_ROTATION_BY_CROP_ID[cropKey] else nil
	if modelRotation then
		apply_model_rotation(preparedTemplate, modelRotation)
	end

	local center, size = get_bounds(preparedTemplate)
	if not center or not size then
		preparedTemplate:Destroy()
		return nil
	end

	local radius = math.max(size.X, size.Y, size.Z) * VIEWPORT_RADIUS_SCALE
	local distance = radius / math.tan(math.rad(VIEWPORT_FIELD_OF_VIEW * 0.5)) + radius
	if not isSeed and cropKey and CLOSE_VIEWPORT_CROP_IDS[cropKey] then
		distance *= CLOSE_VIEWPORT_DISTANCE_SCALE
	end

	local cameraCFrame
	if isSeed then
		cameraCFrame = get_top_down_camera_cframe(center, SEED_TOP_DOWN_DISTANCE)
	elseif cropKey and TOP_DOWN_VIEWPORT_CROP_IDS[cropKey] then
		cameraCFrame = get_top_down_camera_cframe(center, distance)
	else
		cameraCFrame = CFrame.lookAt(
			center + Vector3.new(distance * VIEWPORT_CAMERA_X_SCALE, distance * VIEWPORT_CAMERA_Y_SCALE, distance),
			center
		)
	end

	local cacheEntry = {
		ItemId = itemDefinition.ItemId,
		Template = preparedTemplate,
		FieldOfView = VIEWPORT_FIELD_OF_VIEW,
		CameraCFrame = cameraCFrame,
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

function FarmingShopViewportCache.ApplyToViewport(viewportFrame: ViewportFrame, itemDefinitionOrId, worldModelName: string?, cameraName: string?): boolean
	if not viewportFrame then
		return false
	end

	local itemDefinition = resolve_item_definition(itemDefinitionOrId)
	local cachedViewport = FarmingShopViewportCache.Get(itemDefinition)
	if not cachedViewport then
		return false
	end

	for _, child in ipairs(viewportFrame:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end

	local worldModel = Instance.new("WorldModel")
	worldModel.Name = worldModelName or "FarmingViewportWorldModel"
	worldModel.Parent = viewportFrame
	cachedViewport.Template:Clone().Parent = worldModel

	local camera = Instance.new("Camera")
	camera.Name = cameraName or "FarmingViewportCamera"
	camera.FieldOfView = cachedViewport.FieldOfView
	camera.CFrame = cachedViewport.CameraCFrame
	camera.Parent = viewportFrame

	viewportFrame.CurrentCamera = camera
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.Ambient = Color3.fromRGB(220, 220, 220)
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
	CropRarityUtility.ApplyToViewport(viewportFrame, itemDefinition)

	return true
end

return FarmingShopViewportCache
