-- SERVICES
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- CONSTANTS
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local RaceVisualFactory = require(Utility:WaitForChild("RaceVisualFactory"))

local DYNAMIC_VIEWPORT_ATTRIBUTE = "HorseIndexDynamic"
local CATALOG_ATTRIBUTE = "HorseIndexCatalogId"
local UNLOCKED_ATTRIBUTE = "HorseIndexUnlocked"
local CAMERA_KEY_ATTRIBUTE = "HorseIndexCameraKey"
local WORLD_MODEL_NAME = "HorseIndexWorldModel"
local CAMERA_NAME = "HorseIndexCamera"

local FACE_PART_PATTERNS = { "head", "face", "neck", "mane", "nose", "muzzle", "ear", "eye", "jaw" }
local TAIL_PART_PATTERNS = { "tail", "rear", "hind", "rump" }

-- VARIABLES
local HorseIndexViewportCache = {}
local modelTemplateCache = {}
local snapshotCache = {}

-- FUNCTIONS
local function normalize_key(value)
	if type(value) ~= "string" then return nil end
	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then return nil end
	return normalizedValue
end

local function is_invisible_helper_part(part)
	local normalizedName = normalize_key(part.Name)
	return part.Transparency >= 1 or normalizedName == "root" or normalizedName == "humanoidrootpart"
end

local function strip_runtime_instances(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") or descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		end
	end
end

local function resolve_catalog_model(catalogId)
	local definition = HorseCatalog.GetDefinition(catalogId) or HorseCatalog.GetDefinition("Default")
	if not definition then return nil end

	local candidateKeys = {
		definition.PlaceholderModelKey,
		definition.DisplayName,
		definition.CatalogId,
	}

	for _, candidateKey in ipairs(candidateKeys) do
		if type(candidateKey) == "string" and candidateKey ~= "" then
			local model = RaceVisualFactory.FindTemplateModel(candidateKey)
			if model then return model:Clone() end
		end
	end

	return RaceVisualFactory.BuildFallbackHorseModel({
		HorseId = catalogId,
		Id = catalogId,
		CatalogId = definition.CatalogId,
		PlaceholderModelKey = definition.PlaceholderModelKey or "",
	})
end

local function prepare_preview_model(root, silhouetteMode)
	strip_runtime_instances(root)

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Decal") or descendant:IsA("Texture") or descendant:IsA("SurfaceAppearance") then
			if silhouetteMode then descendant:Destroy() end
		elseif descendant:IsA("BasePart") then
			local keepInvisible = is_invisible_helper_part(descendant)
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Material = Enum.Material.SmoothPlastic

			if keepInvisible then
				descendant.Transparency = 1
			elseif silhouetteMode then
				descendant.Color = Color3.fromRGB(10, 10, 10)
				descendant.Transparency = 0.45
				descendant.Reflectance = 0
			else
				descendant.Reflectance = 0
			end

			if descendant:IsA("MeshPart") and silhouetteMode and not keepInvisible then
				descendant.TextureID = ""
			end
		end
	end

	if root:IsA("Model") then
		RaceVisualFactory.PrepareModel(root)
	elseif root:IsA("BasePart") then
		root.Anchored = true
		root.CanCollide = false
		root.CanQuery = false
		root.CanTouch = false
		root.CastShadow = false
		root.Material = Enum.Material.SmoothPlastic
		if is_invisible_helper_part(root) then
			root.Transparency = 1
		elseif silhouetteMode then
			root.Color = Color3.fromRGB(10, 10, 10)
			root.Transparency = 0.45
		end
	end

	if silhouetteMode then
		local highlight = Instance.new("Highlight")
		highlight.Name = "SilhouetteHighlight"
		highlight.FillColor = Color3.fromRGB(10, 10, 10)
		highlight.FillTransparency = 0.52
		highlight.OutlineColor = Color3.fromRGB(0, 0, 0)
		highlight.OutlineTransparency = 0.08
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = root
	end
end

local function get_bounding_box(root)
	if root:IsA("Model") then return root:GetBoundingBox() end
	if root:IsA("BasePart") then return root.CFrame, root.Size end

	local model = Instance.new("Model")
	for _, child in ipairs(root:GetChildren()) do
		child.Parent = model
	end
	local boxCFrame, boxSize = model:GetBoundingBox()
	for _, child in ipairs(model:GetChildren()) do
		child.Parent = root
	end
	model:Destroy()
	return boxCFrame, boxSize
end

local function get_named_parts(root, patterns)
	local parts = {}
	local function matches_pattern(instanceName)
		local normalizedName = normalize_key(instanceName)
		if not normalizedName then return false end
		for _, pattern in ipairs(patterns) do
			if string.find(normalizedName, pattern, 1, true) then return true end
		end
		return false
	end

	local function push_part(instance)
		if instance:IsA("BasePart") and matches_pattern(instance.Name) then
			parts[#parts + 1] = instance
		end
	end

	if root:IsA("BasePart") then push_part(root) end
	for _, descendant in ipairs(root:GetDescendants()) do push_part(descendant) end
	return parts
end

local function get_part_bounds(parts)
	if #parts == 0 then return nil, nil end
	local minPoint = nil
	local maxPoint = nil

	local function include_point(point)
		if not minPoint then
			minPoint = point
			maxPoint = point
			return
		end
		minPoint = Vector3.new(
			math.min(minPoint.X, point.X),
			math.min(minPoint.Y, point.Y),
			math.min(minPoint.Z, point.Z)
		)
		maxPoint = Vector3.new(
			math.max(maxPoint.X, point.X),
			math.max(maxPoint.Y, point.Y),
			math.max(maxPoint.Z, point.Z)
		)
	end

	for _, part in ipairs(parts) do
		local halfSize = part.Size * 0.5
		for xSign = -1, 1, 2 do
			for ySign = -1, 1, 2 do
				for zSign = -1, 1, 2 do
					include_point(part.CFrame:PointToWorldSpace(Vector3.new(
						halfSize.X * xSign, halfSize.Y * ySign, halfSize.Z * zSign
					)))
				end
			end
		end
	end
	if not minPoint or not maxPoint then return nil, nil end
	return CFrame.new((minPoint + maxPoint) * 0.5), maxPoint - minPoint
end

local function average_part_positions(parts)
	if #parts == 0 then return nil end
	local total = Vector3.zero
	for _, part in ipairs(parts) do total += part.Position end
	return total / #parts
end

local function get_preview_camera(focusPoint, boxSize, cameraConfig, forwardVector)
	local normalizedForward = forwardVector
	if normalizedForward.Magnitude <= 0.001 then
		normalizedForward = Vector3.new(0, 0, -1)
	else
		normalizedForward = normalizedForward.Unit
	end

	local up = Vector3.yAxis
	local right = normalizedForward:Cross(up)
	if right.Magnitude <= 0.001 then
		right = Vector3.xAxis
	else
		right = right.Unit
	end

	local visualRadius = math.max(boxSize.X * 0.68, boxSize.Y * 0.58, boxSize.Z * 0.2) * cameraConfig.RadiusScale
	local distance = (visualRadius / math.tan(math.rad(cameraConfig.FieldOfView * 0.5)) + visualRadius) * cameraConfig.DistanceMultiplier
	local offsetScale = cameraConfig.CameraOffsetScale
	local forwardDistanceScale = math.max(0.2, math.abs(offsetScale.Z))
	local offset = (normalizedForward * distance * forwardDistanceScale) + (right * distance * offsetScale.X) + (up * distance * offsetScale.Y)

	return CFrame.lookAt(focusPoint + offset, focusPoint)
end

local function get_model_template(catalogId, isUnlocked)
	local cacheKey = ("%s|%s"):format(catalogId, isUnlocked and "unlocked" or "locked")
	local cachedTemplate = modelTemplateCache[cacheKey]
	if cachedTemplate then return cachedTemplate end

	local model = resolve_catalog_model(catalogId)
	if not model then return nil end

	prepare_preview_model(model, not isUnlocked)
	modelTemplateCache[cacheKey] = model
	return model
end

function HorseIndexViewportCache.Get(catalogId, isUnlocked, cameraConfig, cameraKey)
	if type(catalogId) ~= "string" or catalogId == "" or not cameraConfig then return nil end

	local normalizedCameraKey = type(cameraKey) == "string" and cameraKey or "default"
	local cacheKey = table.concat({ normalizedCameraKey, catalogId, isUnlocked and "unlocked" or "locked" }, "|")
	local cachedSnapshot = snapshotCache[cacheKey]
	if cachedSnapshot then return cachedSnapshot end

	local modelTemplate = get_model_template(catalogId, isUnlocked)
	if not modelTemplate then return nil end

	local boxCFrame, boxSize = get_bounding_box(modelTemplate)
	if not boxCFrame or not boxSize then return nil end

	local faceParts = get_named_parts(modelTemplate, FACE_PART_PATTERNS)
	local tailParts = get_named_parts(modelTemplate, TAIL_PART_PATTERNS)
	local faceBoxCFrame, faceBoxSize = get_part_bounds(faceParts)
	local headPoint = faceBoxCFrame and faceBoxCFrame.Position or average_part_positions(faceParts)
	local tailPoint = average_part_positions(tailParts)
	local focusPoint = nil
	local focusBoxSize = nil

	if faceBoxCFrame and faceBoxSize then
		focusPoint = faceBoxCFrame.Position + Vector3.new(0, faceBoxSize.Y * (cameraConfig.FaceFocusYOffsetScale or 0), 0)
		focusBoxSize = Vector3.new(
			math.max(faceBoxSize.X, boxSize.X * 0.16),
			math.max(faceBoxSize.Y, boxSize.Y * 0.34),
			math.max(faceBoxSize.Z, boxSize.Z * 0.14)
		)
	else
		focusPoint = boxCFrame.Position + Vector3.new(0, boxSize.Y * cameraConfig.FocusYOffsetScale, boxSize.Z * cameraConfig.FocusZOffsetScale)
		focusBoxSize = Vector3.new(math.max(boxSize.X * 0.42, 1), math.max(boxSize.Y * 0.48, 1), math.max(boxSize.Z * 0.28, 1))
	end

	local forwardVector = if headPoint and tailPoint then (headPoint - tailPoint) else boxCFrame.LookVector
	local snapshot = {
		ModelTemplate = modelTemplate,
		FieldOfView = cameraConfig.FieldOfView,
		CameraCFrame = get_preview_camera(focusPoint, focusBoxSize, cameraConfig, forwardVector),
		Ambient = if isUnlocked then Color3.fromRGB(220, 220, 220) else Color3.fromRGB(150, 150, 150),
		LightColor = if isUnlocked then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(160, 160, 160),
		LightDirection = Vector3.new(-0.8, -1, -0.45),
	}

	snapshotCache[cacheKey] = snapshot
	return snapshot
end

function HorseIndexViewportCache.GetIfCached(catalogId, isUnlocked, cameraKey)
	local normalizedCameraKey = type(cameraKey) == "string" and cameraKey or "default"
	local cacheKey = table.concat({ normalizedCameraKey, catalogId, isUnlocked and "unlocked" or "locked" }, "|")
	return snapshotCache[cacheKey]
end

function HorseIndexViewportCache.ClearViewport(viewportFrame)
	if not viewportFrame then return end
	for _, child in ipairs(viewportFrame:GetChildren()) do
		if child:GetAttribute(DYNAMIC_VIEWPORT_ATTRIBUTE) == true or child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end
	viewportFrame.CurrentCamera = nil
	viewportFrame:SetAttribute(CATALOG_ATTRIBUTE, nil)
	viewportFrame:SetAttribute(UNLOCKED_ATTRIBUTE, nil)
	viewportFrame:SetAttribute(CAMERA_KEY_ATTRIBUTE, nil)
end

local function ensure_viewport_state(viewportFrame)
	local worldModel = viewportFrame:FindFirstChild(WORLD_MODEL_NAME)
	if not worldModel or not worldModel:IsA("WorldModel") then
		for _, child in ipairs(viewportFrame:GetChildren()) do
			if child:IsA("WorldModel") then child:Destroy() end
		end
		worldModel = Instance.new("WorldModel")
		worldModel.Name = WORLD_MODEL_NAME
		worldModel:SetAttribute(DYNAMIC_VIEWPORT_ATTRIBUTE, true)
		worldModel.Parent = viewportFrame
	end

	local camera = viewportFrame:FindFirstChild(CAMERA_NAME)
	if not camera or not camera:IsA("Camera") then
		for _, child in ipairs(viewportFrame:GetChildren()) do
			if child:IsA("Camera") then child:Destroy() end
		end
		camera = Instance.new("Camera")
		camera.Name = CAMERA_NAME
		camera:SetAttribute(DYNAMIC_VIEWPORT_ATTRIBUTE, true)
		camera.Parent = viewportFrame
	end
	return worldModel, camera
end

local function clear_world_model(worldModel)
	for _, child in ipairs(worldModel:GetChildren()) do
		child:Destroy()
	end
end

function HorseIndexViewportCache.ApplyToViewport(viewportFrame, catalogId, isUnlocked, cameraConfig, cameraKey)
	if not viewportFrame then return false end
	local snapshot = HorseIndexViewportCache.Get(catalogId, isUnlocked, cameraConfig, cameraKey)
	if not snapshot then
		HorseIndexViewportCache.ClearViewport(viewportFrame)
		return false
	end

	local worldModel, camera = ensure_viewport_state(viewportFrame)
	camera.FieldOfView = snapshot.FieldOfView
	camera.CFrame = snapshot.CameraCFrame
	viewportFrame.CurrentCamera = camera
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.Ambient = snapshot.Ambient
	viewportFrame.LightColor = snapshot.LightColor
	viewportFrame.LightDirection = snapshot.LightDirection

	if viewportFrame:GetAttribute(CATALOG_ATTRIBUTE) == catalogId
		and viewportFrame:GetAttribute(UNLOCKED_ATTRIBUTE) == isUnlocked
		and viewportFrame:GetAttribute(CAMERA_KEY_ATTRIBUTE) == cameraKey
		and #worldModel:GetChildren() > 0
	then
		return true
	end

	clear_world_model(worldModel)

	local success, clonedModel = pcall(function()
		return snapshot.ModelTemplate:Clone()
	end)
	if not success or not clonedModel then
		warn("[HorseIndexViewportCache] failed to clone model for " .. tostring(catalogId) .. ": " .. tostring(clonedModel))
		HorseIndexViewportCache.ClearViewport(viewportFrame)
		return false
	end

	clonedModel.Parent = worldModel
	viewportFrame:SetAttribute(CATALOG_ATTRIBUTE, catalogId)
	viewportFrame:SetAttribute(UNLOCKED_ATTRIBUTE, isUnlocked)
	viewportFrame:SetAttribute(CAMERA_KEY_ATTRIBUTE, cameraKey)
	return true
end

function HorseIndexViewportCache.Forget()
	for _, template in pairs(modelTemplateCache) do
		if typeof(template) == "Instance" then template:Destroy() end
	end
	table.clear(modelTemplateCache)
	table.clear(snapshotCache)
end

-- INIT
return HorseIndexViewportCache