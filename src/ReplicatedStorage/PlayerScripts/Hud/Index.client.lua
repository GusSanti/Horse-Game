local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local Trove = require(Libraries:WaitForChild("Trove"))
local RaceVisualFactory = require(Utility:WaitForChild("RaceVisualFactory"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainFrameFR", "MainframeFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local INDEX_ROOT_NAMES = { "Index" }
local INDEX_BACKGROUND_NAMES = { "IndexBG" }
local GRID_CONTAINER_NAMES = { "GridScrollingFrame", "ListScrollingFrame", "ScrollingFrame", "ScrollFrame", "Scroll" }
local ITEM_TEMPLATE_NAMES = { "ItemBT" }
local ITEM_NAME_NAMES = { "ItemNameTX", "ItemName" }
local HORSE_IMAGE_NAMES = { "HorseImage" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }
local DETAILS_ROOT_NAMES = { "ItemBG" }
local DETAILS_NAME_NAMES = { "ItemTX", "ItemNameTX", "ItemName" }
local DETAILS_TEXT_NAMES = { "DetailsTX", "DetailTX", "DescriptionTX" }
local DETAILS_DISPLAY_NAMES = { "ItemDisplayBG" }
local DETAILS_IMAGE_NAMES = { "HorseImage" }

local GRID_CAMERA_CONFIG = {
	FieldOfView = 31,
	FocusYOffsetScale = 0.18,
	FocusZOffsetScale = -0.28,
	RadiusScale = 0.5,
	DistanceMultiplier = 1,
	CameraOffsetScale = Vector3.new(0.18, 0.08, -0.54),
}

local DETAILS_CAMERA_CONFIG = {
	FieldOfView = 27,
	FocusYOffsetScale = 0.2,
	FocusZOffsetScale = -0.32,
	RadiusScale = 0.48,
	DistanceMultiplier = 0.91,
	CameraOffsetScale = Vector3.new(0.14, 0.07, -0.48),
}

local currentUi = nil
local currentTemplateSource = nil
local renderQueued = false
local renderDirty = true
local renderGeneration = 0
local viewportPopulationInProgress = false
local selectedCatalogId = nil
local orderedCatalogIds = nil
local activeEntriesByCatalogId = {}
local activeCardsByCatalogId = {}
local previewSnapshotCache = {}
local previewWarmGeneration = 0

local queue_render
local try_bind_ui
local apply_selection

local function normalize_key(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	local normalizedValue = string.lower(trimmedValue)
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function matches_alias(instance, aliases)
	local normalizedName = normalize_key(instance.Name)
	if not normalizedName then
		return false
	end

	for _, alias in ipairs(aliases or {}) do
		if normalize_key(alias) == normalizedName then
			return true
		end
	end

	return false
end

local function find_named_instance(root, aliases, className, recursive)
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if matches_alias(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	if recursive == false then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if matches_alias(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function find_gui_object(root, aliases, recursive)
	local instance = find_named_instance(root, aliases, "GuiObject", recursive)
	if instance then
		return instance
	end

	return nil
end

local function find_gui_button(root, aliases, recursive)
	local instance = find_named_instance(root, aliases, "GuiButton", recursive)
	if instance then
		return instance
	end

	return nil
end

local function find_text_label(root, aliases, recursive)
	local instance = find_named_instance(root, aliases, "TextLabel", recursive)
	if instance then
		return instance
	end

	return nil
end

local function find_viewport_frame(root)
	if not root then
		return nil
	end

	if root:IsA("ViewportFrame") then
		return root
	end

	local instance = find_named_instance(root, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
	if instance then
		return instance
	end

	return nil
end

local function set_gui_visible(instance, isVisible)
	if not instance then
		return
	end

	if instance:IsA("GuiObject") then
		instance.Visible = isVisible
	elseif instance:IsA("LayerCollector") then
		instance.Enabled = isVisible
	end
end

local function is_gui_visible(instance)
	local current = instance
	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end
		current = current.Parent
	end
	return true
end

local function create_click_target(card)
	if card:IsA("GuiButton") then
		return card
	end

	local existingButton = card:FindFirstChild("IndexClickTarget")
	if existingButton and existingButton:IsA("GuiButton") then
		return existingButton
	end

	if not card:IsA("GuiObject") then
		return nil
	end

	local button = Instance.new("TextButton")
	button.Name = "IndexClickTarget"
	button.BackgroundTransparency = 1
	button.BorderSizePixel = 0
	button.Text = ""
	button.AutoButtonColor = false
	button.Size = UDim2.fromScale(1, 1)
	button.Position = UDim2.fromScale(0, 0)
	button.ZIndex = card.ZIndex + 20
	button.Parent = card

	return button
end

local function strip_scripts(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function make_template_source(template)
	local source = template:Clone()
	source.Visible = true
	strip_scripts(source)

	template.Visible = false
	template.Parent = nil

	return source
end

local function build_ordered_catalog_ids()
	if orderedCatalogIds then
		return orderedCatalogIds
	end

	local ordered = {}
	local seen = {
		Default = true,
	}

	for _, entry in ipairs(HorseCatalog.GetRoulettePool() or {}) do
		local catalogId = entry and entry.CatalogId or nil
		if type(catalogId) == "string" and not seen[catalogId] and HorseCatalog.GetDefinition(catalogId) then
			seen[catalogId] = true
			ordered[#ordered + 1] = catalogId
		end
	end

	local remaining = {}

	for catalogId, definition in pairs(HorseCatalog.Definitions or {}) do
		if definition and not seen[catalogId] then
			remaining[#remaining + 1] = catalogId
		end
	end

	table.sort(remaining, function(leftCatalogId, rightCatalogId)
		local leftDefinition = HorseCatalog.GetDefinition(leftCatalogId)
		local rightDefinition = HorseCatalog.GetDefinition(rightCatalogId)
		local leftName = leftDefinition and leftDefinition.DisplayName or leftCatalogId
		local rightName = rightDefinition and rightDefinition.DisplayName or rightCatalogId
		return string.lower(leftName) < string.lower(rightName)
	end)

	for _, catalogId in ipairs(remaining) do
		ordered[#ordered + 1] = catalogId
	end

	orderedCatalogIds = ordered
	return orderedCatalogIds
end

local function build_unlocked_catalog_lookup()
	local unlocked = {}
	local collection = DataUtility.client.get("Collection")
	local horses = DataUtility.client.get("Horses")

	local function push_catalog_id(catalogId)
		if type(catalogId) == "string" and catalogId ~= "" then
			unlocked[catalogId] = true
		end
	end

	if type(collection) == "table" then
		for _, catalogId in ipairs(collection.DiscoveredHorseIds or {}) do
			push_catalog_id(catalogId)
		end

		for _, catalogId in ipairs(collection.OwnedHorseCatalogIds or {}) do
			push_catalog_id(catalogId)
		end
	end

	if type(horses) == "table" and type(horses.Owned) == "table" then
		for _, horse in pairs(horses.Owned) do
			if type(horse) == "table" then
				push_catalog_id(horse.CatalogId)
			end
		end
	end

	return unlocked
end

local function resolve_catalog_model(catalogId)
	local definition = HorseCatalog.GetDefinition(catalogId) or HorseCatalog.GetDefinition("Default")
	if not definition then
		return nil
	end

	local candidateKeys = {
		definition.PlaceholderModelKey,
		definition.DisplayName,
		definition.CatalogId,
	}

	for _, candidateKey in ipairs(candidateKeys) do
		if type(candidateKey) == "string" and candidateKey ~= "" then
			local model = RaceVisualFactory.FindTemplateModel(candidateKey)
			if model then
				return model:Clone()
			end
		end
	end

	return RaceVisualFactory.BuildFallbackHorseModel({
		HorseId = catalogId,
		Id = catalogId,
		CatalogId = definition.CatalogId,
		PlaceholderModelKey = definition.PlaceholderModelKey or "",
	})
end

local function clear_viewport(viewportFrame)
	for _, child in ipairs(viewportFrame:GetChildren()) do
		child:Destroy()
	end

	viewportFrame.CurrentCamera = nil
end

local function clear_dictionary(dictionary)
	for key in pairs(dictionary) do
		dictionary[key] = nil
	end
end

local function prepare_preview_model(root, silhouetteMode)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		elseif descendant:IsA("BillboardGui") or descendant:IsA("SurfaceGui") or descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif silhouetteMode and (descendant:IsA("Decal") or descendant:IsA("Texture") or descendant:IsA("SurfaceAppearance")) then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Material = Enum.Material.SmoothPlastic

			if silhouetteMode then
				descendant.Color = Color3.fromRGB(10, 10, 10)
				descendant.Transparency = 0.45
				descendant.Reflectance = 0
			else
				descendant.Transparency = 0
				descendant.Reflectance = 0
			end

			if descendant:IsA("MeshPart") and silhouetteMode then
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

		if silhouetteMode then
			root.Color = Color3.fromRGB(10, 10, 10)
			root.Transparency = 0.45
		else
			root.Transparency = 0
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
	if root:IsA("Model") then
		return root:GetBoundingBox()
	end

	if root:IsA("BasePart") then
		return root.CFrame, root.Size
	end

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

local function get_named_part_positions(root, patterns)
	local positions = {}

	local function matches_pattern(instanceName)
		local normalizedName = normalize_key(instanceName)
		if not normalizedName then
			return false
		end

		for _, pattern in ipairs(patterns) do
			if string.find(normalizedName, pattern, 1, true) then
				return true
			end
		end

		return false
	end

	local function push_position(instance)
		if instance:IsA("BasePart") and matches_pattern(instance.Name) then
			positions[#positions + 1] = instance.Position
		end
	end

	if root:IsA("BasePart") then
		push_position(root)
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		push_position(descendant)
	end

	return positions
end

local function average_positions(positions)
	if #positions == 0 then
		return nil
	end

	local total = Vector3.zero
	for _, position in ipairs(positions) do
		total += position
	end

	return total / #positions
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

	local visualRadius = math.max(
		boxSize.X * 0.68,
		boxSize.Y * 0.58,
		boxSize.Z * 0.2
	) * cameraConfig.RadiusScale
	local distance = (visualRadius / math.tan(math.rad(cameraConfig.FieldOfView * 0.5)) + visualRadius)
		* cameraConfig.DistanceMultiplier
	local offsetScale = cameraConfig.CameraOffsetScale
	local forwardDistanceScale = math.max(0.2, math.abs(offsetScale.Z))
	local offset = (normalizedForward * distance * forwardDistanceScale)
		+ (right * distance * offsetScale.X)
		+ (up * distance * offsetScale.Y)

	return CFrame.lookAt(focusPoint + offset, focusPoint)
end

local function build_preview_snapshot(catalogId, isUnlocked, cameraConfig, cameraKey)
	local cacheKey = table.concat({
		cameraKey,
		catalogId,
		isUnlocked and "unlocked" or "locked",
	}, "|")
	local cachedSnapshot = previewSnapshotCache[cacheKey]
	if cachedSnapshot then
		return cachedSnapshot
	end

	local model = resolve_catalog_model(catalogId)
	if not model then
		return nil
	end

	prepare_preview_model(model, not isUnlocked)

	local boxCFrame, boxSize = get_bounding_box(model)
	if not boxCFrame or not boxSize then
		model:Destroy()
		return nil
	end

	local headPoint = average_positions(get_named_part_positions(model, { "head", "face", "neck", "mane", "nose" }))
	local tailPoint = average_positions(get_named_part_positions(model, { "tail", "rear", "hind" }))
	local focusPoint = headPoint or (
		boxCFrame.Position + Vector3.new(
			0,
			boxSize.Y * cameraConfig.FocusYOffsetScale,
			boxSize.Z * cameraConfig.FocusZOffsetScale
		)
	)
	local forwardVector = if headPoint and tailPoint then (headPoint - tailPoint) else boxCFrame.LookVector

	cachedSnapshot = {
		ModelTemplate = model,
		FieldOfView = cameraConfig.FieldOfView,
		CameraCFrame = get_preview_camera(focusPoint, boxSize, cameraConfig, forwardVector),
		Ambient = if isUnlocked then Color3.fromRGB(220, 220, 220) else Color3.fromRGB(150, 150, 150),
		LightColor = if isUnlocked then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(160, 160, 160),
	}
	previewSnapshotCache[cacheKey] = cachedSnapshot

	return cachedSnapshot
end

local function populate_horse_viewport(viewportFrame, catalogId, isUnlocked, cameraConfig, cameraKey)
	local snapshot = build_preview_snapshot(catalogId, isUnlocked, cameraConfig, cameraKey)
	if not snapshot then
		clear_viewport(viewportFrame)
		return
	end

	clear_viewport(viewportFrame)

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewportFrame
	snapshot.ModelTemplate:Clone().Parent = worldModel

	local camera = Instance.new("Camera")
	camera.FieldOfView = snapshot.FieldOfView
	camera.CFrame = snapshot.CameraCFrame
	camera.Parent = viewportFrame

	viewportFrame.CurrentCamera = camera
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.Ambient = snapshot.Ambient
	viewportFrame.LightColor = snapshot.LightColor
end

local function prewarm_detail_snapshots(entries)
	previewWarmGeneration += 1
	local generation = previewWarmGeneration

	task.spawn(function()
		for index, entry in ipairs(entries) do
			if generation ~= previewWarmGeneration or currentUi == nil then
				return
			end

			build_preview_snapshot(entry.CatalogId, entry.IsUnlocked, DETAILS_CAMERA_CONFIG, "details")

			if index < #entries then
				RunService.Heartbeat:Wait()
			end
		end
	end)
end

local function set_selected_visual(card, isSelected)
	local stroke = card:FindFirstChildWhichIsA("UIStroke", true)
	if not stroke and card:IsA("GuiObject") then
		stroke = Instance.new("UIStroke")
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = card
	end

	if stroke then
		stroke.Thickness = isSelected and 2.5 or 1
		stroke.Transparency = isSelected and 0 or 0.18
		stroke.Color = isSelected and Color3.fromRGB(255, 214, 132) or Color3.fromRGB(255, 255, 255)
	end
end

local function get_details_text(definition)
	if definition and type(definition.Description) == "string" and definition.Description ~= "" then
		return definition.Description
	end

	return "No description configured for this horse yet."
end

local function get_entry_data()
	local entries = {}
	local unlockedLookup = build_unlocked_catalog_lookup()

	for _, catalogId in ipairs(build_ordered_catalog_ids()) do
		local definition = HorseCatalog.GetDefinition(catalogId)
		if not definition then
			continue
		end

		entries[#entries + 1] = {
			CatalogId = catalogId,
			Definition = definition,
			IsUnlocked = unlockedLookup[catalogId] == true,
		}
	end

	return entries
end

local function update_canvas_size()
	if not currentUi or not currentUi.GridContainer or not currentUi.GridContainer:IsA("ScrollingFrame") then
		return
	end

	local scrollingFrame = currentUi.GridContainer
	local layout = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
	local padding = scrollingFrame:FindFirstChildOfClass("UIPadding")
	if not layout then
		layout = scrollingFrame:FindFirstChildWhichIsA("UIGridLayout", true)
	end

	if not padding then
		padding = scrollingFrame:FindFirstChildWhichIsA("UIPadding", true)
	end

	if layout then
		local horizontalPadding = 0
		local verticalPadding = 0

		if padding then
			horizontalPadding = padding.PaddingLeft.Offset + padding.PaddingRight.Offset
			verticalPadding = padding.PaddingTop.Offset + padding.PaddingBottom.Offset
		end

		scrollingFrame.CanvasSize = UDim2.fromOffset(
			0,
			math.max(0, layout.AbsoluteContentSize.Y + verticalPadding)
		)
	end
end

local function render_details(entry)
	if not currentUi then
		return
	end

	if not entry then
		set_gui_visible(currentUi.DetailsRoot, true)

		if currentUi.DetailsNameLabel then
			currentUi.DetailsNameLabel.Text = ""
		end

		if currentUi.DetailsTextLabel then
			currentUi.DetailsTextLabel.Text = ""
		end

		if currentUi.DetailsViewport then
			clear_viewport(currentUi.DetailsViewport)
		end

		return
	end

	set_gui_visible(currentUi.DetailsRoot, true)

	if currentUi.DetailsNameLabel then
		currentUi.DetailsNameLabel.Text = entry.Definition.DisplayName or entry.CatalogId
	end

	if currentUi.DetailsTextLabel then
		currentUi.DetailsTextLabel.Text = get_details_text(entry.Definition)
	end

	if currentUi.DetailsViewport then
		populate_horse_viewport(currentUi.DetailsViewport, entry.CatalogId, entry.IsUnlocked, DETAILS_CAMERA_CONFIG, "details")
	end
end

apply_selection = function()
	if not currentUi then
		return
	end

	local selectedEntry = nil
	if selectedCatalogId then
		selectedEntry = activeEntriesByCatalogId[selectedCatalogId]
	end

	if selectedCatalogId and not selectedEntry then
		selectedCatalogId = nil
	end

	for catalogId, card in pairs(activeCardsByCatalogId) do
		set_selected_visual(card, selectedCatalogId == catalogId)
	end

	render_details(selectedEntry)
end

local function render_index()
	if not currentUi or not currentTemplateSource then
		return
	end
	if not is_gui_visible(currentUi.Root) then
		renderDirty = true
		return
	end

	renderDirty = false
	renderGeneration += 1
	local generation = renderGeneration

	cardTrove:Clean()
	clear_dictionary(activeEntriesByCatalogId)
	clear_dictionary(activeCardsByCatalogId)

	if currentUi.GridContainer:IsA("ScrollingFrame") then
		currentUi.GridContainer.CanvasPosition = Vector2.zero
	end

	local entries = get_entry_data()
	local pendingViewports = {}

	for layoutOrder, entry in ipairs(entries) do
		local card = currentTemplateSource:Clone()
		local cardButton = create_click_target(card)
		local nameLabel = find_text_label(card, ITEM_NAME_NAMES, true)
		local imageRoot = find_gui_object(card, HORSE_IMAGE_NAMES, true)
		local viewportFrame = find_viewport_frame(imageRoot or card)

		card.Name = entry.CatalogId
		card.LayoutOrder = layoutOrder
		card.Visible = true
		card.Parent = currentUi.GridContainer
		cardTrove:Add(card)

		if nameLabel then
			nameLabel.Text = entry.Definition.DisplayName or entry.CatalogId
		end

		if viewportFrame then
			pendingViewports[#pendingViewports + 1] = {
				Card = card,
				Entry = entry,
				ViewportFrame = viewportFrame,
			}
		end

		activeEntriesByCatalogId[entry.CatalogId] = entry
		activeCardsByCatalogId[entry.CatalogId] = card

		if cardButton then
			cardTrove:Add(cardButton.Activated:Connect(function()
				selectedCatalogId = entry.CatalogId
				apply_selection()
			end))
		end
	end

	prewarm_detail_snapshots(entries)
	apply_selection()
	update_canvas_size()
	task.defer(update_canvas_size)
	viewportPopulationInProgress = #pendingViewports > 0

	task.spawn(function()
		for _, pending in ipairs(pendingViewports) do
			if generation ~= renderGeneration
				or not currentUi
				or not is_gui_visible(currentUi.Root)
				or pending.Card.Parent ~= currentUi.GridContainer
			then
				return
			end

			populate_horse_viewport(
				pending.ViewportFrame,
				pending.Entry.CatalogId,
				pending.Entry.IsUnlocked,
				GRID_CAMERA_CONFIG,
				"grid"
			)
			RunService.Heartbeat:Wait()
		end

		if generation == renderGeneration then
			viewportPopulationInProgress = false
		end
	end)
end

queue_render = function()
	renderDirty = true
	if not currentUi or not is_gui_visible(currentUi.Root) then
		return
	end
	if renderQueued then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if renderDirty then
			render_index()
		end
	end)
end

local function find_main_ui_root()
	return find_named_instance(playerGui, MAIN_UI_NAMES, nil, true)
end

local function get_index_ui(indexRoot)
	local contentRoot = find_gui_object(indexRoot, INDEX_BACKGROUND_NAMES, true) or indexRoot
	local gridContainer = find_gui_object(contentRoot, GRID_CONTAINER_NAMES, true)
	local template = gridContainer and find_gui_object(gridContainer, ITEM_TEMPLATE_NAMES, false)

	if not template and gridContainer then
		template = find_gui_object(gridContainer, ITEM_TEMPLATE_NAMES, true)
	end

	local detailsRoot = find_gui_object(contentRoot, DETAILS_ROOT_NAMES, true)
	local detailsDisplayRoot = detailsRoot and (find_gui_object(detailsRoot, DETAILS_DISPLAY_NAMES, true) or detailsRoot)
	local detailsImageRoot = detailsDisplayRoot and (find_gui_object(detailsDisplayRoot, DETAILS_IMAGE_NAMES, true) or detailsDisplayRoot)
	local detailsViewport = find_viewport_frame(detailsImageRoot)
	local detailsNameLabel = find_text_label(detailsRoot, DETAILS_NAME_NAMES, true)
	local detailsTextLabel = find_text_label(detailsRoot, DETAILS_TEXT_NAMES, true)

	if not gridContainer or not template or not detailsRoot or not detailsViewport or not detailsNameLabel or not detailsTextLabel then
		return nil
	end

	return {
		Root = indexRoot,
		GridContainer = gridContainer,
		Template = template,
		DetailsRoot = detailsRoot,
		DetailsViewport = detailsViewport,
		DetailsNameLabel = detailsNameLabel,
		DetailsTextLabel = detailsTextLabel,
	}
end

local function find_index_ui()
	local mainUi = find_main_ui_root()
	if not mainUi then
		return nil
	end

	local mainframe = find_named_instance(mainUi, MAINFRAME_NAMES, nil, true)
	if not mainframe then
		return nil
	end

	local framesContainer = find_named_instance(mainframe, FRAMES_CONTAINER_NAMES, nil, true)
	if not framesContainer then
		return nil
	end

	local indexRoot = find_named_instance(framesContainer, INDEX_ROOT_NAMES, nil, true)
	if not indexRoot then
		return nil
	end

	return get_index_ui(indexRoot)
end

local function destroy_ui_binding()
	renderGeneration += 1
	renderDirty = true
	viewportPopulationInProgress = false
	cardTrove:Clean()
	uiTrove:Destroy()
	uiTrove = Trove.new()
	previewWarmGeneration += 1
	clear_dictionary(activeEntriesByCatalogId)
	clear_dictionary(activeCardsByCatalogId)
	currentUi = nil
	currentTemplateSource = nil
end

local function bind_ui(ui)
	if currentUi and currentUi.Root == ui.Root and currentTemplateSource and currentUi.Root.Parent then
		return
	end

	destroy_ui_binding()

	currentUi = ui
	currentTemplateSource = make_template_source(ui.Template)
	uiTrove:Add(currentTemplateSource)

	if ui.GridContainer:IsA("ScrollingFrame") then
		ui.GridContainer.Active = true
		ui.GridContainer.ScrollingEnabled = true
		ui.GridContainer.AutomaticCanvasSize = Enum.AutomaticSize.None
		ui.GridContainer.ScrollingDirection = Enum.ScrollingDirection.Y
	end

	render_details(nil)

	uiTrove:Add(DataUtility.client.bind("Collection", queue_render))
	uiTrove:Add(DataUtility.client.bind("Horses", queue_render))
	uiTrove:Add(DataUtility.client.bind("Horses.Owned", queue_render))

	if ui.GridContainer:IsA("ScrollingFrame") then
		local scrollingFrame = ui.GridContainer
		local layout = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
			or scrollingFrame:FindFirstChildWhichIsA("UIGridLayout", true)
		if layout then
			uiTrove:Connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), update_canvas_size)
		end

		uiTrove:Connect(scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"), update_canvas_size)
	end

	uiTrove:Connect(ui.Root.AncestryChanged, function(_, parent)
		if parent then
			return
		end

		if currentUi and currentUi.Root == ui.Root then
			destroy_ui_binding()
			task.defer(try_bind_ui)
		end
	end)

	if ui.Root:IsA("GuiObject") then
		uiTrove:Connect(ui.Root:GetPropertyChangedSignal("Visible"), function()
			if ui.Root.Visible then
				if renderDirty then
					queue_render()
				end
			elseif viewportPopulationInProgress then
				renderGeneration += 1
				viewportPopulationInProgress = false
				renderDirty = true
			end
		end)
	end

	queue_render()
end

local function is_index_ui_related(instance)
	return matches_alias(instance, MAIN_UI_NAMES)
		or matches_alias(instance, MAINFRAME_NAMES)
		or matches_alias(instance, FRAMES_CONTAINER_NAMES)
		or matches_alias(instance, INDEX_ROOT_NAMES)
		or matches_alias(instance, INDEX_BACKGROUND_NAMES)
		or matches_alias(instance, GRID_CONTAINER_NAMES)
		or matches_alias(instance, ITEM_TEMPLATE_NAMES)
		or matches_alias(instance, DETAILS_ROOT_NAMES)
		or matches_alias(instance, HORSE_IMAGE_NAMES)
		or matches_alias(instance, VIEWPORT_FRAME_NAMES)
end

try_bind_ui = function()
	if currentUi and currentUi.Root and currentUi.Root.Parent and currentTemplateSource then
		return
	end

	local ui = find_index_ui()
	if not ui then
		destroy_ui_binding()
		return
	end

	bind_ui(ui)
end

DataUtility.client.ensure_remotes()

rootTrove:Connect(playerGui.DescendantAdded, function(instance)
	if is_index_ui_related(instance) or instance:IsA("LayerCollector") then
		try_bind_ui()
	end
end)

rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
	if currentUi and (instance == currentUi.Root or instance:IsDescendantOf(currentUi.Root)) then
		task.defer(try_bind_ui)
	elseif is_index_ui_related(instance) then
		task.defer(try_bind_ui)
	end
end)

try_bind_ui()
