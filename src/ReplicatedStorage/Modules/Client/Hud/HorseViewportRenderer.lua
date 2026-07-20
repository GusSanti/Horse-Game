-- Shared horse ViewportFrame renderer.
-- Expensive model preparation and camera calculations are cached across every HUD.
-- Queued renders are limited to one per frame so opening a screen cannot stall the UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local RaceVisualFactory = require(Utility:WaitForChild("RaceVisualFactory"))

local DYNAMIC_ATTRIBUTE = "HorseViewportDynamic"
local CONTENT_KEY_ATTRIBUTE = "HorseViewportContentKey"
local WORLD_MODEL_NAME = "HorseViewportWorldModel"
local CAMERA_NAME = "HorseViewportCamera"

local FACE_PART_PATTERNS = { "head", "face", "neck", "mane", "nose", "muzzle", "ear", "eye", "jaw" }
local TAIL_PART_PATTERNS = { "tail", "rear", "hind", "rump" }

local DEFAULT_AMBIENT = Color3.fromRGB(220, 220, 220)
local DEFAULT_LIGHT_COLOR = Color3.fromRGB(255, 255, 255)
local DEFAULT_LIGHT_DIRECTION = Vector3.new(-0.8, -1, -0.45)

local HorseViewportRenderer = {}

HorseViewportRenderer.Presets = {
	IndexGrid = {
		FieldOfView = 24,
		FocusMode = "Face",
		FocusYOffsetScale = 0.34,
		FocusZOffsetScale = -0.42,
		FaceFocusYOffsetScale = 0.15,
		RadiusScale = 0.52,
		DistanceMultiplier = 2.4,
		CameraOffsetScale = Vector3.new(0.34, -0.5, -0.76),
	},
	IndexDetails = {
		FieldOfView = 22,
		FocusMode = "Face",
		FocusYOffsetScale = 0.36,
		FocusZOffsetScale = -0.44,
		FaceFocusYOffsetScale = 0.15,
		RadiusScale = 0.54,
		DistanceMultiplier = 2.4,
		CameraOffsetScale = Vector3.new(0.38, -0.5, -0.74),
	},
	Wheel = {
		FieldOfView = 30,
		FocusMode = "Head",
		FocusYOffsetScale = 0.18,
		FocusZOffsetScale = -0.28,
		RadiusScale = 0.5,
		DistanceMultiplier = 0.7,
		CameraOffsetScale = Vector3.new(0.18, 0.08, -0.54),
	},
	Reward = {
		FieldOfView = 27,
		FocusMode = "Head",
		FocusYOffsetScale = 0.2,
		FocusZOffsetScale = -0.32,
		RadiusScale = 0.48,
		DistanceMultiplier = 0.66,
		CameraOffsetScale = Vector3.new(0.14, 0.07, -0.48),
	},
	Stable = {
		FieldOfView = 35,
		FocusMode = "Bounds",
		OrientationMode = "World",
		FocusYOffsetScale = 0.08,
		FocusZOffsetScale = 0,
		RadiusScale = 0.6,
		DistanceMultiplier = 0.82,
		CameraOffsetScale = Vector3.new(0.42, 0.18, -1),
	},
	Race = {
		FieldOfView = 32,
		FocusMode = "Bounds",
		OrientationMode = "World",
		FocusYOffsetScale = 0.1,
		FocusZOffsetScale = 0,
		RadiusScale = 0.62,
		DistanceMultiplier = 1.15,
		CameraOffsetScale = Vector3.new(0.2, 0.06, 1),
	},
	Admin = {
		FieldOfView = 32,
		FocusMode = "Bounds",
		FocusYOffsetScale = 0.08,
		FocusZOffsetScale = 0,
		RadiusScale = 0.65,
		DistanceMultiplier = 1.1,
		CameraOffsetScale = Vector3.new(0.25, 0.12, -1),
	},
}

local catalogTemplateCache = {}
local sourceTemplateCache = {}
local snapshotCache = {}
local queuedByViewport = setmetatable({}, { __mode = "k" })
local renderQueue = {}
local prewarmQueued = {}
local workerRunning = false
local nextJobId = 0

local function normalize_key(value)
	if type(value) ~= "string" then return nil end
	local normalized = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalized == "" then return nil end
	return normalized
end

local function config_signature(config)
	local offset = config.CameraOffsetScale or Vector3.new(0.25, 0.1, -1)
	return table.concat({
		tostring(config.FieldOfView or 35),
		tostring(config.FocusMode or "Bounds"),
		tostring(config.OrientationMode or "Horse"),
		tostring(config.FocusYOffsetScale or 0),
		tostring(config.FocusZOffsetScale or 0),
		tostring(config.FaceFocusYOffsetScale or 0),
		tostring(config.RadiusScale or 0.6),
		tostring(config.DistanceMultiplier or 1),
		("%.4f,%.4f,%.4f"):format(offset.X, offset.Y, offset.Z),
	}, "|")
end

local function remove_runtime_instances(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script")
			or descendant:IsA("LocalScript")
			or descendant:IsA("BillboardGui")
			or descendant:IsA("SurfaceGui")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("Animator")
		then
			descendant:Destroy()
		end
	end
end

local function is_invisible_helper_part(part)
	local name = normalize_key(part.Name)
	return part.Transparency >= 1 or name == "root" or name == "humanoidrootpart"
end

local function prepare_model(model, silhouette)
	remove_runtime_instances(model)

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Decal") or descendant:IsA("Texture") or descendant:IsA("SurfaceAppearance") then
			if silhouette then descendant:Destroy() end
		elseif descendant:IsA("BasePart") then
			local keepInvisible = is_invisible_helper_part(descendant)
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Reflectance = 0

			if keepInvisible then
				descendant.Transparency = 1
			elseif silhouette then
				descendant.Material = Enum.Material.SmoothPlastic
				descendant.Color = Color3.fromRGB(10, 10, 10)
				descendant.Transparency = 0.45
				if descendant:IsA("MeshPart") then descendant.TextureID = "" end
			end
		end
	end

	RaceVisualFactory.PrepareModel(model)

	if silhouette then
		local highlight = Instance.new("Highlight")
		highlight.Name = "SilhouetteHighlight"
		highlight.FillColor = Color3.fromRGB(10, 10, 10)
		highlight.FillTransparency = 0.52
		highlight.OutlineColor = Color3.fromRGB(0, 0, 0)
		highlight.OutlineTransparency = 0.08
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model
	end
end

local function normalize_as_model(root)
	if root:IsA("Model") then return root end

	local model = Instance.new("Model")
	model.Name = root.Name
	if root:IsA("BasePart") then
		root.Parent = model
	else
		for _, child in ipairs(root:GetChildren()) do child.Parent = model end
		root:Destroy()
	end
	return model
end

local function clone_prepared_source(source, silhouette)
	if not source or not source.Parent then return nil end
	local success, clone = pcall(function() return source:Clone() end)
	if not success or not clone then return nil end

	local model = normalize_as_model(clone)
	local hasPart = model:FindFirstChildWhichIsA("BasePart", true) ~= nil
	if not hasPart then
		model:Destroy()
		return nil
	end

	prepare_model(model, silhouette)
	return model
end

local function get_catalog_template(catalogId, options)
	options = options or {}
	local silhouette = options.Silhouette == true
	local modelKey = options.ModelKey
	local templateKey = table.concat({
		"catalog",
		tostring(catalogId),
		tostring(modelKey or ""),
		silhouette and "locked" or "unlocked",
	}, "|")
	local cached = catalogTemplateCache[templateKey]
	if cached then return cached, templateKey end

	local definition = HorseCatalog.GetDefinition(catalogId) or HorseCatalog.GetDefinition("Default")
	if not definition then return nil, templateKey end

	local source = nil
	for _, candidateKey in ipairs({ modelKey, definition.PlaceholderModelKey, definition.DisplayName, definition.CatalogId }) do
		if type(candidateKey) == "string" and candidateKey ~= "" then
			source = RaceVisualFactory.FindTemplateModel(candidateKey)
			if source then break end
		end
	end

	local model
	if source then
		model = clone_prepared_source(source, silhouette)
	else
		model = RaceVisualFactory.BuildFallbackHorseModel({
			HorseId = catalogId,
			Id = catalogId,
			CatalogId = definition.CatalogId,
			PlaceholderModelKey = definition.PlaceholderModelKey or "",
		})
		prepare_model(model, silhouette)
	end

	if model then catalogTemplateCache[templateKey] = model end
	return model, templateKey
end

local function get_source_template(source, sourceKey, options)
	options = options or {}
	local silhouette = options.Silhouette == true
	local templateKey = table.concat({ "source", tostring(sourceKey), silhouette and "locked" or "unlocked" }, "|")
	local cached = sourceTemplateCache[templateKey]
	if cached then return cached, templateKey end

	local model = clone_prepared_source(source, silhouette)
	if model then sourceTemplateCache[templateKey] = model end
	return model, templateKey
end

local function get_matching_parts(model, patterns)
	local parts = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local name = normalize_key(descendant.Name)
			for _, pattern in ipairs(patterns) do
				if name and string.find(name, pattern, 1, true) then
					parts[#parts + 1] = descendant
					break
				end
			end
		end
	end
	return parts
end

local function average_positions(parts)
	if #parts == 0 then return nil end
	local total = Vector3.zero
	for _, part in ipairs(parts) do total += part.Position end
	return total / #parts
end

local function get_part_bounds(parts)
	if #parts == 0 then return nil, nil end
	local minPoint
	local maxPoint
	for _, part in ipairs(parts) do
		local half = part.Size * 0.5
		for x = -1, 1, 2 do
			for y = -1, 1, 2 do
				for z = -1, 1, 2 do
					local point = part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, half.Y * y, half.Z * z))
					if not minPoint then
						minPoint, maxPoint = point, point
					else
						minPoint = Vector3.new(math.min(minPoint.X, point.X), math.min(minPoint.Y, point.Y), math.min(minPoint.Z, point.Z))
						maxPoint = Vector3.new(math.max(maxPoint.X, point.X), math.max(maxPoint.Y, point.Y), math.max(maxPoint.Z, point.Z))
					end
				end
			end
		end
	end
	return CFrame.new((minPoint + maxPoint) * 0.5), maxPoint - minPoint
end

local function build_camera_cframe(model, config)
	local boxCFrame, boxSize = model:GetBoundingBox()
	local faceParts = get_matching_parts(model, FACE_PART_PATTERNS)
	local tailParts = get_matching_parts(model, TAIL_PART_PATTERNS)
	local headPoint = average_positions(faceParts)
	local tailPoint = average_positions(tailParts)
	local focusPoint
	local focusSize = boxSize

	if config.FocusMode == "Face" then
		local faceCFrame, faceSize = get_part_bounds(faceParts)
		if faceCFrame and faceSize then
			focusPoint = faceCFrame.Position + Vector3.new(0, faceSize.Y * (config.FaceFocusYOffsetScale or 0), 0)
			focusSize = Vector3.new(
				math.max(faceSize.X, boxSize.X * 0.16),
				math.max(faceSize.Y, boxSize.Y * 0.34),
				math.max(faceSize.Z, boxSize.Z * 0.14)
			)
		end
	elseif config.FocusMode == "Head" then
		focusPoint = headPoint
	end

	if not focusPoint then
		focusPoint = boxCFrame.Position + Vector3.new(
			0,
			boxSize.Y * (config.FocusYOffsetScale or 0),
			boxSize.Z * (config.FocusZOffsetScale or 0)
		)
	end

	local forward = boxCFrame.LookVector
	if config.OrientationMode ~= "World" and headPoint and tailPoint and (headPoint - tailPoint).Magnitude > 0.001 then
		forward = (headPoint - tailPoint).Unit
	end
	if forward.Magnitude <= 0.001 then forward = Vector3.new(0, 0, -1) end

	local up = Vector3.yAxis
	local right = forward:Cross(up)
	if right.Magnitude <= 0.001 then right = Vector3.xAxis else right = right.Unit end

	local fieldOfView = config.FieldOfView or 35
	local radius = math.max(focusSize.X * 0.68, focusSize.Y * 0.58, focusSize.Z * 0.2)
		* (config.RadiusScale or 0.6)
	local distance = (radius / math.tan(math.rad(fieldOfView * 0.5)) + radius)
		* (config.DistanceMultiplier or 1)
	local scale = config.CameraOffsetScale or Vector3.new(0.25, 0.1, -1)
	local offset
	if config.OrientationMode == "World" then
		offset = Vector3.new(distance * scale.X, distance * scale.Y, distance * scale.Z)
	else
		offset = (forward * distance * math.max(0.2, math.abs(scale.Z)))
			+ (right * distance * scale.X)
			+ (up * distance * scale.Y)
	end

	return CFrame.lookAt(focusPoint + offset, focusPoint), boxCFrame, boxSize
end

local function get_snapshot(template, templateKey, config, options)
	local signature = config_signature(config)
	local snapshotKey = templateKey .. "|camera|" .. signature
	local cached = snapshotCache[snapshotKey]
	if cached then return cached, snapshotKey end

	local cameraCFrame, boxCFrame, boxSize = build_camera_cframe(template, config)
	local silhouette = options and options.Silhouette == true
	local snapshot = {
		ModelTemplate = template,
		FieldOfView = config.FieldOfView or 35,
		CameraCFrame = cameraCFrame,
		BoxCFrame = boxCFrame,
		BoxSize = boxSize,
		Ambient = options and options.Ambient or (silhouette and Color3.fromRGB(150, 150, 150) or DEFAULT_AMBIENT),
		LightColor = options and options.LightColor or (silhouette and Color3.fromRGB(160, 160, 160) or DEFAULT_LIGHT_COLOR),
		LightDirection = options and options.LightDirection or DEFAULT_LIGHT_DIRECTION,
	}
	snapshotCache[snapshotKey] = snapshot
	return snapshot, snapshotKey
end

local function ensure_scene(viewport)
	local worldModel = viewport:FindFirstChild(WORLD_MODEL_NAME)
	if not worldModel or not worldModel:IsA("WorldModel") then
		for _, child in ipairs(viewport:GetChildren()) do
			if child:IsA("WorldModel") then child:Destroy() end
		end
		worldModel = Instance.new("WorldModel")
		worldModel.Name = WORLD_MODEL_NAME
		worldModel:SetAttribute(DYNAMIC_ATTRIBUTE, true)
		worldModel.Parent = viewport
	end

	local camera = viewport:FindFirstChild(CAMERA_NAME)
	if not camera or not camera:IsA("Camera") then
		for _, child in ipairs(viewport:GetChildren()) do
			if child:IsA("Camera") then child:Destroy() end
		end
		camera = Instance.new("Camera")
		camera.Name = CAMERA_NAME
		camera:SetAttribute(DYNAMIC_ATTRIBUTE, true)
		camera.Parent = viewport
	end
	return worldModel, camera
end

local function apply_snapshot(viewport, snapshot, contentKey)
	if not viewport or not viewport:IsA("ViewportFrame") or not viewport.Parent then return false end
	local worldModel, camera = ensure_scene(viewport)
	camera.FieldOfView = snapshot.FieldOfView
	camera.CFrame = snapshot.CameraCFrame
	viewport.CurrentCamera = camera
	viewport.BackgroundTransparency = 1
	viewport.Ambient = snapshot.Ambient
	viewport.LightColor = snapshot.LightColor
	viewport.LightDirection = snapshot.LightDirection

	local model = worldModel:FindFirstChildOfClass("Model")
	if viewport:GetAttribute(CONTENT_KEY_ATTRIBUTE) ~= contentKey or not model then
		worldModel:ClearAllChildren()
		local success, clone = pcall(function() return snapshot.ModelTemplate:Clone() end)
		if not success or not clone then
			warn("[HorseViewportRenderer] failed to clone " .. tostring(contentKey) .. ": " .. tostring(clone))
			HorseViewportRenderer.Clear(viewport)
			return false
		end
		clone.Parent = worldModel
		model = clone
		viewport:SetAttribute(CONTENT_KEY_ATTRIBUTE, contentKey)
	end

	return true, {
		Viewport = viewport,
		WorldModel = worldModel,
		Camera = camera,
		Model = model,
		BoxCFrame = snapshot.BoxCFrame,
		BoxSize = snapshot.BoxSize,
	}
end

function HorseViewportRenderer.GetCatalogSnapshot(catalogId, config, options)
	config = config or HorseViewportRenderer.Presets.Stable
	options = options or {}
	if type(catalogId) ~= "string" or catalogId == "" then
		return nil
	end

	local template, templateKey = get_catalog_template(catalogId, options)
	if not template then
		return nil
	end
	return get_snapshot(template, templateKey, config, options)
end

function HorseViewportRenderer.ApplyCatalog(viewport, catalogId, config, options)
	HorseViewportRenderer.Cancel(viewport)
	local snapshot, snapshotKey = HorseViewportRenderer.GetCatalogSnapshot(catalogId, config, options)
	if not snapshot then
		HorseViewportRenderer.Clear(viewport)
		return false
	end
	return apply_snapshot(viewport, snapshot, snapshotKey)
end

function HorseViewportRenderer.ApplySource(viewport, source, sourceKey, config, options)
	HorseViewportRenderer.Cancel(viewport)
	config = config or HorseViewportRenderer.Presets.Stable
	options = options or {}
	if not source or sourceKey == nil then
		HorseViewportRenderer.Clear(viewport)
		return false
	end

	local template, templateKey = get_source_template(source, sourceKey, options)
	if not template then
		HorseViewportRenderer.Clear(viewport)
		return false
	end
	local snapshot, snapshotKey = get_snapshot(template, templateKey, config, options)
	return apply_snapshot(viewport, snapshot, snapshotKey)
end

function HorseViewportRenderer.Cancel(viewport)
	if viewport then queuedByViewport[viewport] = nil end
end

function HorseViewportRenderer.Clear(viewport)
	if not viewport then return end
	HorseViewportRenderer.Cancel(viewport)
	for _, child in ipairs(viewport:GetChildren()) do
		if child:IsA("WorldModel") or child:IsA("Camera") or child:GetAttribute(DYNAMIC_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
	viewport.CurrentCamera = nil
	viewport:SetAttribute(CONTENT_KEY_ATTRIBUTE, nil)
end

local function pop_next_job()
	local bestIndex
	local bestPriority
	for index, job in ipairs(renderQueue) do
		if not bestPriority or job.Priority < bestPriority then
			bestIndex = index
			bestPriority = job.Priority
		end
	end
	if not bestIndex then return nil end
	return table.remove(renderQueue, bestIndex)
end

local function start_worker()
	if workerRunning then return end
	workerRunning = true
	task.spawn(function()
		while #renderQueue > 0 do
			RunService.Heartbeat:Wait()
			local job = pop_next_job()
			if job then
				if job.Kind == "Prewarm" then
					prewarmQueued[job.Key] = nil
					local template, templateKey = get_catalog_template(job.CatalogId, job.Options)
					if template then get_snapshot(template, templateKey, job.Config, job.Options) end
				elseif job.Viewport
					and job.Viewport.Parent
					and queuedByViewport[job.Viewport] == job
				then
					local success, scene
					if job.Kind == "Source" then
						success, scene = HorseViewportRenderer.ApplySource(
							job.Viewport, job.Source, job.SourceKey, job.Config, job.Options
						)
					else
						success, scene = HorseViewportRenderer.ApplyCatalog(
							job.Viewport, job.CatalogId, job.Config, job.Options
						)
					end
					if queuedByViewport[job.Viewport] == job then queuedByViewport[job.Viewport] = nil end
					if job.Callback then task.defer(job.Callback, success, scene) end
				end
			end
		end
		workerRunning = false
		if #renderQueue > 0 then start_worker() end
	end)
end

local function enqueue(job)
	nextJobId += 1
	job.Id = nextJobId
	job.Priority = tonumber(job.Priority) or 5
	if job.Viewport then
		queuedByViewport[job.Viewport] = job
	end
	renderQueue[#renderQueue + 1] = job
	start_worker()
	return job.Id
end

function HorseViewportRenderer.QueueCatalog(viewport, catalogId, config, options)
	options = options or {}
	return enqueue({
		Kind = "Catalog",
		Viewport = viewport,
		CatalogId = catalogId,
		Config = config or HorseViewportRenderer.Presets.Stable,
		Options = options,
		Priority = options.Priority,
		Callback = options.Callback,
	})
end

function HorseViewportRenderer.QueueSource(viewport, source, sourceKey, config, options)
	options = options or {}
	return enqueue({
		Kind = "Source",
		Viewport = viewport,
		Source = source,
		SourceKey = sourceKey,
		Config = config or HorseViewportRenderer.Presets.Stable,
		Options = options,
		Priority = options.Priority,
		Callback = options.Callback,
	})
end

function HorseViewportRenderer.PrewarmCatalogs(catalogIds, configs, options)
	options = options or {}
	configs = configs or { HorseViewportRenderer.Presets.Stable }
	for _, value in ipairs(catalogIds or {}) do
		local catalogId = type(value) == "table" and value.CatalogId or value
		if type(catalogId) == "string" and catalogId ~= "" then
			for _, config in ipairs(configs) do
				local key = table.concat({ catalogId, config_signature(config), tostring(options.Silhouette == true) }, "|")
				if not prewarmQueued[key] then
					prewarmQueued[key] = true
					enqueue({
						Kind = "Prewarm",
						Key = key,
						CatalogId = catalogId,
						Config = config,
						Options = options,
						Priority = options.Priority or 20,
					})
				end
			end
		end
	end
end

function HorseViewportRenderer.ForgetSource(sourceKey)
	local prefix = "source|" .. tostring(sourceKey) .. "|"
	for key, template in pairs(sourceTemplateCache) do
		if string.sub(key, 1, #prefix) == prefix then
			template:Destroy()
			sourceTemplateCache[key] = nil
			for snapshotKey in pairs(snapshotCache) do
				if string.sub(snapshotKey, 1, #key) == key then snapshotCache[snapshotKey] = nil end
			end
		end
	end
end

return HorseViewportRenderer
