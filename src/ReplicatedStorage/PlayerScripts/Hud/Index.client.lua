-- SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- CONSTANTS
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local HudAnim = require(Libraries:WaitForChild("HudAnim"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local PRELOAD_READY_ATTRIBUTE = "ClientUiPreloadComplete"
local PRELOAD_SKIPPED_ATTRIBUTE = "ClientUiPreloadSkipped"
local MAX_PRELOAD_WAIT_SECONDS = 3
local UI_DISCOVERY_INTERVAL_SECONDS = 0.5
local UI_DISCOVERY_WARNING_INTERVAL = 20

local INDEX_STATE_FUNCTION_NAME = "HorseIndexGetState"
local INDEX_STATE_CHANGED_EVENT_NAME = "HorseIndexStateChanged"

local CARD_BUILD_INTERVAL_SECONDS = 0.025

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainFrameFR", "MainframeFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local INDEX_ROOT_NAMES = { "Index" }
local INDEX_BACKGROUND_NAMES = { "IndexBG" }
local GRID_CONTAINER_NAMES = { "GridScrollingFrame", "ListScrollingFrame", "ScrollingFrame", "ScrollFrame", "Scroll" }
local ITEM_TEMPLATE_NAMES = { "ItemBT" }
local ITEM_NAME_NAMES = { "ItemNameTX", "ItemName" }
local HORSE_IMAGE_NAMES = { "HorseImage" }
local DETAILS_ROOT_NAMES = { "ItemBG" }
local DETAILS_NAME_NAMES = { "ItemTX", "ItemNameTX", "ItemName" }
local DETAILS_TEXT_NAMES = { "DetailsTX", "DetailTX", "DescriptionTX" }
local DETAILS_DISPLAY_NAMES = { "ItemDisplayBG" }
local DETAILS_IMAGE_NAMES = { "HorseImage" }
local IGNORE_HUD_ANIM_ATTRIBUTE = "IgnoreHudAnim"

local UNLOCKED_IMAGE_COLOR = Color3.fromRGB(255, 255, 255)
local LOCKED_IMAGE_COLOR = Color3.fromRGB(0, 0, 0)

-- VARIABLES
local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()

local currentUi = nil
local selectedCatalogId = nil
local orderedCatalogIds = nil
local serverEntries = nil
local currentEntries = {}
local entriesByCatalogId = {}
local activeCards = {}
local activeCardsByCatalogId = {}

local renderDirty = true
local renderQueued = false
local renderGeneration = 0
local stateRequestToken = 0
local serverEventBound = false

local queue_render
local refresh_or_render_index
local try_bind_ui
local select_catalog

-- FUNCTIONS
local function wait_for_preload_ready()
	local startedAt = os.clock()
	while localPlayer:GetAttribute(PRELOAD_READY_ATTRIBUTE) ~= true
		and localPlayer:GetAttribute(PRELOAD_SKIPPED_ATTRIBUTE) ~= true
		and os.clock() - startedAt < MAX_PRELOAD_WAIT_SECONDS
	do
		task.wait()
	end
end

local function normalize_key(value)
	if type(value) ~= "string" then return nil end
	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then return nil end
	return normalizedValue
end

local function matches_alias(instance, aliases)
	local normalizedName = normalize_key(instance.Name)
	if not normalizedName then return false end
	for _, alias in ipairs(aliases or {}) do
		if normalize_key(alias) == normalizedName then
			return true
		end
	end
	return false
end

local function find_named_instance(root, aliases, className, recursive)
	if not root then return nil end
	for _, child in ipairs(root:GetChildren()) do
		if matches_alias(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end
	if recursive == false then return nil end
	for _, descendant in ipairs(root:GetDescendants()) do
		if matches_alias(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end
	return nil
end

local function find_gui_object(root, aliases, recursive)
	return find_named_instance(root, aliases, "GuiObject", recursive)
end

local function find_text_label(root, aliases, recursive)
	return find_named_instance(root, aliases, "TextLabel", recursive)
end

local function set_gui_visible(instance, isVisible)
	if not instance then return end
	if instance:IsA("GuiObject") then
		instance.Visible = isVisible
	elseif instance:IsA("LayerCollector") then
		instance.Enabled = isVisible
	end
end

local function is_gui_visible(instance)
	local current = instance
	while current do
		if current:IsA("GuiObject") and not current.Visible then return false end
		if current:IsA("LayerCollector") and not current.Enabled then return false end
		current = current.Parent
	end
	return true
end

local function strip_scripts(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function disable_hud_anim(instance)
	if not instance then return end
	instance:SetAttribute(IGNORE_HUD_ANIM_ATTRIBUTE, true)
	if instance:IsA("GuiObject") then
		instance:SetAttribute("UIAnim", false)
		instance:SetAttribute("UIOpen", false)
		instance:SetAttribute("hover_scale", 0)
		instance:SetAttribute("click_scale", 0)
		instance:SetAttribute("rotate_hover_deg", 0)
		instance:SetAttribute("pulse", false)
	end
end

local function disable_hud_anim_tree(root)
	if not root then return end
	disable_hud_anim(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		disable_hud_anim(descendant)
	end
	pcall(function()
		if root:IsA("GuiObject") then
			HudAnim.unbind(root)
		end
		HudAnim.unbind_all(root)
	end)
end

local function get_relative_child_path(root, descendant)
	if not root or not descendant or descendant == root then return nil end
	local path = {}
	local current = descendant
	while current and current ~= root do
		table.insert(path, 1, current.Name)
		current = current.Parent
	end
	if current ~= root then return nil end
	return path
end

local function resolve_child_by_path(root, path, className)
	if not root or not path then return nil end
	local current = root
	for _, segment in ipairs(path) do
		current = current:FindFirstChild(segment)
		if not current then return nil end
	end
	if className and not current:IsA(className) then return nil end
	return current
end

local function clear_viewport_descendants(root)
	if not root then return end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ViewportFrame") then
			descendant:Destroy()
		end
	end
end

local function set_horse_image(imageObject, definition, isUnlocked)
	if not imageObject then return end

	clear_viewport_descendants(imageObject)

	local imageId = definition and definition.Image or ""
	if imageObject:IsA("ImageLabel") or imageObject:IsA("ImageButton") then
		imageObject.Image = type(imageId) == "string" and imageId or ""
		imageObject.ImageColor3 = isUnlocked and UNLOCKED_IMAGE_COLOR or LOCKED_IMAGE_COLOR
		imageObject.ImageTransparency = imageObject.Image ~= "" and 0 or 1
	end
end

local function create_template_map(template)
	local nameLabel = find_text_label(template, ITEM_NAME_NAMES, true)
	local imageRoot = find_gui_object(template, HORSE_IMAGE_NAMES, true)
	return {
		NameLabelPath = get_relative_child_path(template, nameLabel),
		ImagePath = get_relative_child_path(template, imageRoot),
	}
end

local function make_template_source(template)
	local source = template:Clone()
	source.Visible = true
	strip_scripts(source)
	disable_hud_anim_tree(source)
	clear_viewport_descendants(source)

	local originalParent = template.Parent
	template.Visible = false
	template.Parent = nil

	uiTrove:Add(function()
		if template.Parent == nil and originalParent and originalParent.Parent then
			template.Parent = originalParent
			template.Visible = false
		elseif template.Parent == nil then
			template:Destroy()
		end
	end)
	return source
end

local function build_ordered_catalog_ids()
	if orderedCatalogIds then return orderedCatalogIds end
	local ordered = {}
	local seen = { Default = true }

	for _, entry in ipairs(HorseCatalog.GetRoulettePool() or {}) do
		local catalogId = entry and entry.CatalogId
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

local function get_details_text(definition)
	if definition and type(definition.Description) == "string" and definition.Description ~= "" then
		return definition.Description
	end
	return "No description configured for this horse yet."
end

local function build_local_entries()
	local entries = {}
	local unlockedLookup = build_unlocked_catalog_lookup()

	for index, catalogId in ipairs(build_ordered_catalog_ids()) do
		local definition = HorseCatalog.GetDefinition(catalogId)
		if not definition then continue end
		entries[#entries + 1] = {
			CatalogId = catalogId,
			Definition = definition,
			IsUnlocked = unlockedLookup[catalogId] == true,
			SortOrder = index,
		}
	end
	return entries
end

local function sanitize_server_entry(rawEntry, index)
	if type(rawEntry) ~= "table" then return nil end
	local catalogId = rawEntry.CatalogId
	if type(catalogId) ~= "string" or catalogId == "" then return nil end

	local catalogDefinition = HorseCatalog.GetDefinition(catalogId)
	if not catalogDefinition and type(rawEntry.DisplayName) ~= "string" then return nil end

	return {
		CatalogId = catalogId,
		Definition = {
			CatalogId = catalogId,
			DisplayName = rawEntry.DisplayName or (catalogDefinition and catalogDefinition.DisplayName) or catalogId,
			Description = rawEntry.Description or (catalogDefinition and catalogDefinition.Description) or "",
			Rarity = rawEntry.Rarity or (catalogDefinition and catalogDefinition.Rarity) or "",
			Tier = rawEntry.Tier or (catalogDefinition and catalogDefinition.Tier) or "",
			PlaceholderModelKey = rawEntry.ModelKey or (catalogDefinition and catalogDefinition.PlaceholderModelKey) or "",
			Image = rawEntry.Image or (catalogDefinition and catalogDefinition.Image) or "",
		},
		IsUnlocked = rawEntry.IsUnlocked == true,
		SortOrder = tonumber(rawEntry.SortOrder) or index,
	}
end

local function set_server_entries_from_payload(payload)
	if type(payload) ~= "table" or payload.Success == false or type(payload.Entries) ~= "table" then
		return false
	end

	local nextEntries = {}
	for index, rawEntry in ipairs(payload.Entries) do
		local entry = sanitize_server_entry(rawEntry, index)
		if entry then
			nextEntries[#nextEntries + 1] = entry
		end
	end

	if #nextEntries == 0 then return false end
	serverEntries = nextEntries
	return true
end

local function get_entry_data()
	if serverEntries and #serverEntries > 0 then return serverEntries end
	return build_local_entries()
end

local function rebuild_entry_lookup(entries)
	table.clear(entriesByCatalogId)
	for _, entry in ipairs(entries) do
		entriesByCatalogId[entry.CatalogId] = entry
	end
end

local function update_canvas_size()
	local ui = currentUi
	if not ui or not ui.GridContainer or not ui.GridContainer:IsA("ScrollingFrame") then return end

	local scrollingFrame = ui.GridContainer
	local layout = scrollingFrame:FindFirstChildOfClass("UIGridLayout")
		or scrollingFrame:FindFirstChildWhichIsA("UIGridLayout", true)
	local padding = scrollingFrame:FindFirstChildOfClass("UIPadding")
		or scrollingFrame:FindFirstChildWhichIsA("UIPadding", true)

	if not layout then return end

	local verticalPadding = 0
	if padding then
		verticalPadding = padding.PaddingTop.Offset + padding.PaddingBottom.Offset
	end

	scrollingFrame.CanvasSize = UDim2.fromOffset(0, math.max(0, layout.AbsoluteContentSize.Y + verticalPadding))
end

local function create_click_target(card)
	if card:IsA("GuiButton") then return card end
	local existingButton = card:FindFirstChild("IndexClickTarget")
	if existingButton and existingButton:IsA("GuiButton") then return existingButton end
	if not card:IsA("GuiObject") then return nil end

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

local function set_selected_visual(card, isSelected)
	if not card then return end
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

local function render_details(entry)
	local ui = currentUi
	if not ui then return end
	set_gui_visible(ui.DetailsRoot, true)

	if not entry then
		if ui.DetailsNameLabel then ui.DetailsNameLabel.Text = "" end
		if ui.DetailsTextLabel then ui.DetailsTextLabel.Text = "" end
		set_horse_image(ui.DetailsImage, nil, true)
		return
	end

	if ui.DetailsNameLabel then
		ui.DetailsNameLabel.Text = entry.Definition.DisplayName or entry.CatalogId
	end
	if ui.DetailsTextLabel then
		ui.DetailsTextLabel.Text = get_details_text(entry.Definition)
	end
	set_horse_image(ui.DetailsImage, entry.Definition, entry.IsUnlocked)
end

local function apply_selection()
	local selectedEntry = selectedCatalogId and entriesByCatalogId[selectedCatalogId] or nil
	if selectedCatalogId and not selectedEntry then
		selectedCatalogId = nil
	end

	for catalogId, card in pairs(activeCardsByCatalogId) do
		set_selected_visual(card, selectedCatalogId == catalogId)
	end

	render_details(selectedEntry)
end

select_catalog = function(catalogId)
	if selectedCatalogId == catalogId then
		apply_selection()
		return
	end
	selectedCatalogId = catalogId
	apply_selection()
end

local function create_card_entry(ui, entry, entryIndex)
	local card = ui.TemplateSource:Clone()
	card.Name = entry.CatalogId
	card.LayoutOrder = entryIndex
	card.Visible = true
	strip_scripts(card)
	disable_hud_anim_tree(card)

	local nameLabel = resolve_child_by_path(card, ui.TemplateMap.NameLabelPath, "TextLabel") or find_text_label(card, ITEM_NAME_NAMES, true)
	local imageObject = resolve_child_by_path(card, ui.TemplateMap.ImagePath, "GuiObject") or find_gui_object(card, HORSE_IMAGE_NAMES, true)
	local clickTarget = create_click_target(card)

	if nameLabel then
		nameLabel.Text = entry.Definition.DisplayName or entry.CatalogId
	end

	set_horse_image(imageObject, entry.Definition, entry.IsUnlocked)

	if clickTarget then
		cardTrove:Connect(clickTarget.Activated, function()
			select_catalog(entry.CatalogId)
		end)
	end

	return {
		CatalogId = entry.CatalogId,
		Definition = entry.Definition,
		IsUnlocked = entry.IsUnlocked,
		Card = card,
		NameLabel = nameLabel,
		ImageObject = imageObject,
	}
end

local function cards_match_entries(entries)
	if #activeCards ~= #entries then return false end
	for index, entry in ipairs(entries) do
		local cardEntry = activeCards[index]
		if not cardEntry or cardEntry.CatalogId ~= entry.CatalogId or cardEntry.IsUnlocked ~= entry.IsUnlocked then
			return false
		end
	end
	return true
end

local function refresh_cards_from_entries(entries)
	currentEntries = entries
	rebuild_entry_lookup(entries)

	for index, entry in ipairs(entries) do
		local cardEntry = activeCards[index]
		if cardEntry then
			cardEntry.Definition = entry.Definition
			cardEntry.IsUnlocked = entry.IsUnlocked
			if cardEntry.NameLabel then
				cardEntry.NameLabel.Text = entry.Definition.DisplayName or entry.CatalogId
			end
			set_horse_image(cardEntry.ImageObject, entry.Definition, entry.IsUnlocked)
		end
	end

	apply_selection()
end

local function render_index()
	local ui = currentUi
	if not ui or not ui.TemplateSource then return end
	if not is_gui_visible(ui.Root) then
		renderDirty = true
		return
	end

	renderDirty = false
	renderGeneration += 1

	local generation = renderGeneration
	local entries = get_entry_data()
	currentEntries = entries
	rebuild_entry_lookup(entries)

	cardTrove:Clean()
	table.clear(activeCards)
	table.clear(activeCardsByCatalogId)

	if ui.GridContainer:IsA("ScrollingFrame") then
		ui.GridContainer.CanvasPosition = Vector2.zero
	end

	local nextEntryIndex = 1

	local function render_next_card()
		if generation ~= renderGeneration or not currentUi or currentUi ~= ui then return end
		if not is_gui_visible(ui.Root) then
			renderDirty = true
			return
		end

		local entry = entries[nextEntryIndex]
		if not entry then
			if selectedCatalogId and not entriesByCatalogId[selectedCatalogId] then
				selectedCatalogId = nil
			end
			apply_selection()
			update_canvas_size()
			return
		end

		local cardEntry = create_card_entry(ui, entry, nextEntryIndex)
		cardEntry.Card.Parent = ui.GridContainer
		cardTrove:Add(cardEntry.Card)
		activeCards[#activeCards + 1] = cardEntry
		activeCardsByCatalogId[entry.CatalogId] = cardEntry.Card

		set_selected_visual(cardEntry.Card, selectedCatalogId == entry.CatalogId)
		nextEntryIndex += 1

		if nextEntryIndex == 2 or nextEntryIndex % 4 == 0 then
			update_canvas_size()
		end

		task.delay(CARD_BUILD_INTERVAL_SECONDS, render_next_card)
	end

	render_next_card()
end

queue_render = function()
	renderDirty = true
	local ui = currentUi
	if not ui or not ui.Root or not is_gui_visible(ui.Root) or renderQueued then return end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if renderDirty then
			render_index()
		end
	end)
end

refresh_or_render_index = function()
	renderDirty = true
	local ui = currentUi
	if not ui or not ui.Root or not is_gui_visible(ui.Root) then return end

	local entries = get_entry_data()
	if cards_match_entries(entries) then
		renderDirty = false
		refresh_cards_from_entries(entries)
		return
	end
	queue_render()
end

local function request_server_state()
	stateRequestToken += 1
	local requestToken = stateRequestToken

	task.spawn(function()
		local success, payload = pcall(function()
			return Net.Function[INDEX_STATE_FUNCTION_NAME]:Call()
		end)
		if requestToken ~= stateRequestToken then return end
		if success and set_server_entries_from_payload(payload) then
			refresh_or_render_index()
		elseif not success then
			warn("[Index] failed to request horse index state: " .. tostring(payload))
		end
	end)
end

local function on_local_data_changed()
	serverEntries = nil
	refresh_or_render_index()
	request_server_state()
end

local function bind_server_events()
	if serverEventBound then return end
	serverEventBound = true
	local connection = Net.Event[INDEX_STATE_CHANGED_EVENT_NAME]:Connect(function(payload)
		if set_server_entries_from_payload(payload) then
			refresh_or_render_index()
		end
	end)
	rootTrove:Add(connection)
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
	local detailsNameLabel = find_text_label(detailsRoot, DETAILS_NAME_NAMES, true)
	local detailsTextLabel = find_text_label(detailsRoot, DETAILS_TEXT_NAMES, true)

	if not gridContainer or not template or not detailsRoot or not detailsImageRoot or not detailsNameLabel or not detailsTextLabel then
		return nil
	end

	return {
		Root = indexRoot,
		GridContainer = gridContainer,
		Template = template,
		DetailsRoot = detailsRoot,
		DetailsImage = detailsImageRoot,
		DetailsNameLabel = detailsNameLabel,
		DetailsTextLabel = detailsTextLabel,
		TemplateSource = nil,
		TemplateMap = nil,
	}
end

local function find_index_ui()
	local mainUi = find_main_ui_root()
	if not mainUi then return nil end
	local mainframe = find_named_instance(mainUi, MAINFRAME_NAMES, nil, true)
	if not mainframe then return nil end
	local framesContainer = find_named_instance(mainframe, FRAMES_CONTAINER_NAMES, nil, true)
	if not framesContainer then return nil end
	local indexRoot = find_named_instance(framesContainer, INDEX_ROOT_NAMES, nil, true)
	if not indexRoot then return nil end

	return get_index_ui(indexRoot)
end

local function destroy_ui_binding()
	renderGeneration += 1
	renderDirty = true
	renderQueued = false
	cardTrove:Clean()
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = nil
	table.clear(currentEntries)
	table.clear(entriesByCatalogId)
	table.clear(activeCards)
	table.clear(activeCardsByCatalogId)
end

local function bind_ui(ui)
	if currentUi and currentUi.Root == ui.Root and currentUi.TemplateSource and currentUi.Root.Parent then return end
	destroy_ui_binding()

	ui.TemplateSource = make_template_source(ui.Template)
	ui.TemplateMap = create_template_map(ui.TemplateSource)
	currentUi = ui
	uiTrove:Add(ui.TemplateSource)
	disable_hud_anim_tree(ui.GridContainer)

	if ui.GridContainer:IsA("ScrollingFrame") then
		ui.GridContainer.Active = true
		ui.GridContainer.ScrollingEnabled = true
		ui.GridContainer.AutomaticCanvasSize = Enum.AutomaticSize.None
		ui.GridContainer.ScrollingDirection = Enum.ScrollingDirection.Y
	end

	render_details(nil)

	uiTrove:Add(DataUtility.client.bind("Collection", on_local_data_changed))
	uiTrove:Add(DataUtility.client.bind("Horses", on_local_data_changed))
	uiTrove:Add(DataUtility.client.bind("Horses.Owned", on_local_data_changed))

	if ui.GridContainer:IsA("ScrollingFrame") then
		local scrollingFrame = ui.GridContainer
		local layout = scrollingFrame:FindFirstChildOfClass("UIGridLayout") or scrollingFrame:FindFirstChildWhichIsA("UIGridLayout", true)
		if layout then
			uiTrove:Connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), update_canvas_size)
		end
		uiTrove:Connect(scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"), function()
			update_canvas_size()
		end)
	end

	uiTrove:Connect(ui.Root.AncestryChanged, function(_, parent)
		if parent then return end
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
				else
					apply_selection()
				end
			end
		end)
	end

	request_server_state()
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
end

try_bind_ui = function()
	if currentUi and currentUi.Root and currentUi.Root.Parent and currentUi.TemplateSource then return end
	local ui = find_index_ui()
	if not ui then return end
	bind_ui(ui)
end

local function initialize_index()
	wait_for_preload_ready()

	local dataSuccess, dataError = pcall(function()
		DataUtility.client.ensure_remotes()
	end)
	if not dataSuccess then
		warn("[Index] failed to initialize DataUtility: " .. tostring(dataError))
	end

	task.spawn(bind_server_events)

	rootTrove:Connect(playerGui.DescendantAdded, function(instance)
		if is_index_ui_related(instance) or instance:IsA("LayerCollector") then
			try_bind_ui()
		end
	end)

	rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
		local ui = currentUi
		if ui and (instance == ui.Root or instance:IsDescendantOf(ui.Root)) then
			task.defer(try_bind_ui)
		elseif is_index_ui_related(instance) then
			task.defer(try_bind_ui)
		end
	end)

	local attempts = 0
	while not currentUi do
		attempts += 1
		try_bind_ui()
		if currentUi then break end
		if attempts % UI_DISCOVERY_WARNING_INTERVAL == 0 then
			warn("[Index] waiting for Index UI in PlayerGui...")
		end
		task.wait(UI_DISCOVERY_INTERVAL_SECONDS)
	end
end

-- INIT
rootTrove:Connect(RunService.Heartbeat, function()
	local ui = currentUi
	if not ui or not ui.Root or not is_gui_visible(ui.Root) then return end

	if renderDirty and not renderQueued then
		refresh_or_render_index()
	end
	
end)

task.defer(function()
	local success, errorMessage = pcall(initialize_index)
	if not success then
		warn("[Index] initialization failed: " .. tostring(errorMessage))
	end
end)
