-- SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- CONSTANTS
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainFrameFR", "MainframeFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local INVENTORY_ROOT_NAMES = { "Inventory" }
local INVENTORY_BACKGROUND_NAMES = { "InventoryBG" }
local INVENTORY_TAB_NAMES = { "InventoryTabFR" }
local CATEGORIES_ROOT_NAMES = { "CategoriesFR" }
local GRID_CONTAINER_NAMES = { "GridScrollingFrame", "ListScrollingFrame", "ScrollingFrame", "ScrollFrame", "Scroll" }
local ITEM_TEMPLATE_NAMES = { "ItemBT" }
local ITEM_IMAGE_NAMES = { "HorseImage", "ItemImage", "ImageItem", "ImageLabel", "Icon" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }
local ITEM_NAME_NAMES = { "ItemNameTX", "ItemName" }
local ITEM_AMOUNT_NAMES = { "ItemAmountTX", "AmountTX", "Quant" }
local DETAILS_FRAME_NAMES = { "ItemDetailsFR" }
local DETAILS_ROOT_NAMES = { "ItemBG" }
local DETAILS_DISPLAY_NAMES = { "ItemDisplayBG" }
local DETAILS_IMAGE_NAMES = { "HorseImage", "ItemImage", "ImageItem", "ImageLabel", "Icon" }
local DETAILS_TEXT_NAMES = { "DetailsTX", "DetailTX", "DescriptionTX" }
local DETAILS_NAME_NAMES = { "ItemNameTX", "ItemTX", "ItemName" }
local DETAILS_NAME_SHADOW_NAMES = { "ItemNameShadowTX" }
local BUTTONS_ROOT_NAMES = { "ButtonsFR" }
local EQUIP_BUTTON_NAMES = { "EquipBT" }
local UNEQUIP_BUTTON_NAMES = { "UnequipBT" }
local EQUIP_TEXT_NAMES = { "EquipTX" }
local EQUIP_SHADOW_TEXT_NAMES = { "EquipShadowTX" }
local UNEQUIP_TEXT_NAMES = { "UnequipTX", "DeleteTX" }
local UNEQUIP_SHADOW_TEXT_NAMES = { "UnequipShadowTX", "DeleteShadowTX" }
local CLOSE_BUTTON_NAMES = { "ExitBT", "CloseBT" }

local CATEGORY_BUTTON_NAMES = {
    Utility = { "Utility" },
    Seeds = { "Seeds", "Seed" },
    Foods = { "Foods", "Food" },
}

local CATEGORY_TOOL_CATEGORIES = {
    Utility = { "Water", "Grooming", "Misc", "Medicine" },
    Seeds = { "Seeds" },
    Foods = { "Food" },
}

local RELEVANT_INVENTORY_PATHS = {
    "Inventory.Seeds",
    "Inventory.Fruits",
    "Inventory.Consumables.Food",
    "Inventory.Consumables.Water",
    "Inventory.Consumables.Grooming",
    "Inventory.Consumables.Misc",
    "Inventory.Consumables.Medical",
}

local GRID_VIEWPORT_CONFIG = {
    FieldOfView = 32,
    RadiusScale = 0.42,
    DistanceMultiplier = 1.42,
    FocusYOffsetScale = 0.04,
    CameraOffsetScale = Vector3.new(0.18, 0.12, 1.1),
}

local DETAILS_VIEWPORT_CONFIG = {
    FieldOfView = 29,
    RadiusScale = 0.46,
    DistanceMultiplier = 1.28,
    FocusYOffsetScale = 0.05,
    CameraOffsetScale = Vector3.new(0.18, 0.15, 1.02),
}

-- VARIABLES
local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()
local backpackTrove = Trove.new()
local characterTrove = Trove.new()

local currentUi = nil
local currentTemplateSource = nil
local activeCategoryId = "Utility"
local selectedItemId = nil
local renderQueued = false
local liveGroupsQueued = false
local previewCache = {}
local activeEntriesByItemId = {}
local activeCardsByItemId = {}
local currentLiveGroups = {}
local lastRenderedCategoryId = nil

local queue_render
local try_bind_ui
local apply_selection

-- FUNCTIONS
local function normalize_key(value)
    if type(value) ~= "string" then
        return nil
    end
    local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
    local normalizedValue = string.lower(trimmedValue)
    if normalizedValue == "" then return nil end
    return normalizedValue
end

local function normalize_inventory_path(path)
    if type(path) ~= "string" then return nil end
    local trimmedPath = string.gsub(path, "^%s*(.-)%s*$", "%1")
    if trimmedPath == "" then return nil end
    if string.sub(trimmedPath, 1, #"Inventory.") == "Inventory." then
        return trimmedPath
    end
    return ("Inventory.%s"):format(trimmedPath)
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

local function find_gui_button(root, aliases, recursive)
    return find_named_instance(root, aliases, "GuiButton", recursive)
end

local function find_text_label(root, aliases, recursive)
    return find_named_instance(root, aliases, "TextLabel", recursive)
end

local function find_viewport_frame(root)
    if not root then return nil end
    if root:IsA("ViewportFrame") then return root end
    return find_named_instance(root, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
end

local function clear_dictionary(dictionary)
    for key in pairs(dictionary) do
        dictionary[key] = nil
    end
end

local function set_gui_visible(instance, isVisible)
    if not instance then return end
    if instance:IsA("GuiObject") then
        instance.Visible = isVisible
    elseif instance:IsA("LayerCollector") then
        instance.Enabled = isVisible
    end
end

local function set_button_enabled(button, isEnabled)
    if not button then return end
    button.Active = isEnabled
    button.Selectable = isEnabled
    button.AutoButtonColor = isEnabled
end

local function set_button_text(button, labelAliases, shadowAliases, text)
    local label = find_text_label(button, labelAliases, true)
    local shadowLabel = find_text_label(button, shadowAliases, true)
    if label then label.Text = text end
    if shadowLabel then shadowLabel.Text = text end
end

local function create_click_target(card)
    if card:IsA("GuiButton") then return card end
    local existingButton = card:FindFirstChild("InventoryClickTarget")
    if existingButton and existingButton:IsA("GuiButton") then return existingButton end

    local button = Instance.new("TextButton")
    button.Name = "InventoryClickTarget"
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

local function set_selected_visual(card, isSelected)
    local stroke = card:FindFirstChildWhichIsA("UIStroke", true)
    if not stroke and card:IsA("GuiObject") then
        stroke = Instance.new("UIStroke")
        stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        stroke.Parent = card
    end
    if stroke then
        stroke.Thickness = isSelected and 2.5 or 1
        stroke.Transparency = isSelected and 0 or 0.22
        stroke.Color = isSelected and Color3.fromRGB(255, 219, 134) or Color3.fromRGB(255, 255, 255)
    end
end

local function clear_viewport(viewportFrame)
    for _, child in ipairs(viewportFrame:GetChildren()) do
        child:Destroy()
    end
    viewportFrame.CurrentCamera = nil
end

local function get_assets_items_root()
    local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
    if not assetsFolder then return nil end
    return assetsFolder:FindFirstChild("Items")
end

local function get_item_search_names(itemDefinition)
    local names = {}
    local seen = {}

    local function push(value)
        if type(value) ~= "string" or value == "" or seen[value] then return end
        seen[value] = true
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

local function find_first_named_asset(root, itemDefinition)
    if not root then return nil end
    for _, name in ipairs(get_item_search_names(itemDefinition)) do
        local found = root:FindFirstChild(name, true)
        if found then return found end
    end
    return nil
end

local function get_catalog_render_source(itemDefinition)
    local itemsFolder = get_assets_items_root()
    if not itemsFolder or not itemDefinition then return nil end

    local categoryFolderName = ToolItemCatalog.GetCategoryFolderName(itemDefinition)
    local categoryFolder = itemsFolder:FindFirstChild(categoryFolderName)
    if categoryFolder and categoryFolder:IsA("Folder") then
        local categoryMatch = find_first_named_asset(categoryFolder, itemDefinition)
        if categoryMatch then return categoryMatch end
    end
    return find_first_named_asset(itemsFolder, itemDefinition)
end

local function get_farming_render_source(itemDefinition)
    if not itemDefinition then return nil end
    return FarmingUtility.GetViewportAsset(itemDefinition) or FarmingUtility.GetItemAsset(itemDefinition)
end

local function collect_render_parts(root)
    local baseParts = {}
    if root:IsA("BasePart") then
        baseParts[#baseParts + 1] = root
    end
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("BasePart") then
            baseParts[#baseParts + 1] = descendant
        end
    end
    return baseParts
end

local function create_placeholder_preview_model(displayName)
    local model = Instance.new("Model")
    model.Name = ("%sPreview"):format(displayName or "Item")
    local part = Instance.new("Part")
    part.Name = "Preview"
    part.Size = Vector3.new(1.25, 1.25, 1.25)
    part.Material = Enum.Material.SmoothPlastic
    part.Color = Color3.fromRGB(214, 214, 214)
    part.Parent = model
    return model
end

local function create_preview_model(source, displayName)
    if not source then return create_placeholder_preview_model(displayName) end

    local sourceClone = source:Clone()
    strip_scripts(sourceClone)
    local previewModel = nil

    if sourceClone:IsA("Model") then
        previewModel = sourceClone
    else
        previewModel = Instance.new("Model")
        previewModel.Name = sourceClone.Name
        if sourceClone:IsA("BasePart") then
            sourceClone.Parent = previewModel
        else
            for _, child in ipairs(sourceClone:GetChildren()) do
                child.Parent = previewModel
            end
            sourceClone:Destroy()
        end
    end

    local baseParts = collect_render_parts(previewModel)
    if #baseParts == 0 then
        previewModel:Destroy()
        return create_placeholder_preview_model(displayName)
    end

    for _, basePart in ipairs(baseParts) do
        basePart.Anchored = true
        basePart.CanCollide = false
        basePart.CanTouch = false
        basePart.CanQuery = false
        basePart.CastShadow = false
    end

    previewModel:PivotTo(CFrame.new())
    return previewModel
end

local function get_preview_snapshot(itemId, source, displayName, cameraConfig, cameraKey)
    local cacheKey = ("%s|%s"):format(cameraKey, itemId)
    local cachedPreview = previewCache[cacheKey]
    if cachedPreview then return cachedPreview end

    local previewModel = create_preview_model(source, displayName)
    local boxCFrame, boxSize = previewModel:GetBoundingBox()
    local maxDimension = math.max(boxSize.X, boxSize.Y, boxSize.Z, 1)
    local focusPosition = boxCFrame.Position + Vector3.new(0, boxSize.Y * cameraConfig.FocusYOffsetScale, 0)
    local radius = maxDimension * cameraConfig.RadiusScale
    local distance = math.max(
        1.75,
        (radius / math.tan(math.rad(cameraConfig.FieldOfView * 0.5))) * cameraConfig.DistanceMultiplier
    )

    local cameraOffsetScale = cameraConfig.CameraOffsetScale
    local cameraOffset = Vector3.new(
        distance * cameraOffsetScale.X,
        distance * cameraOffsetScale.Y,
        distance * cameraOffsetScale.Z
    )

    cachedPreview = {
        ModelTemplate = previewModel,
        FieldOfView = cameraConfig.FieldOfView,
        CameraCFrame = CFrame.lookAt(focusPosition + cameraOffset, focusPosition),
    }
    previewCache[cacheKey] = cachedPreview
    return cachedPreview
end

local function render_viewport(viewportFrame, entry, cameraConfig, cameraKey)
    clear_viewport(viewportFrame)

    local snapshot = get_preview_snapshot(entry.ItemId, entry.RenderSource, entry.DisplayName, cameraConfig, cameraKey)
    local worldModel = Instance.new("WorldModel")
    worldModel.Parent = viewportFrame
    snapshot.ModelTemplate:Clone().Parent = worldModel

    local camera = Instance.new("Camera")
    camera.FieldOfView = snapshot.FieldOfView
    camera.CFrame = snapshot.CameraCFrame
    camera.Parent = viewportFrame

    viewportFrame.CurrentCamera = camera
    viewportFrame.BackgroundTransparency = 1
    viewportFrame.Ambient = Color3.fromRGB(220, 220, 220)
    viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)
end

local function get_bucket_item_count(bucket, itemId)
    if type(bucket) ~= "table" then return 0 end
    return math.max(0, math.floor(tonumber(bucket[itemId]) or 0))
end

local function get_item_count(itemDefinition)
    local inventoryPath = normalize_inventory_path(itemDefinition and itemDefinition.InventoryPath)
    if not inventoryPath then return 0 end
    return get_bucket_item_count(DataUtility.client.get(inventoryPath), itemDefinition.ItemId)
end

local function get_default_farming_description(farmingDefinition)
    if not farmingDefinition then
        return "No description configured for this item yet."
    end
    if farmingDefinition.Kind == "Seed" then
        local cropName = farmingDefinition.CropDisplayName or farmingDefinition.DisplayName or "a crop"
        return ("Plant this seed to grow %s."):format(cropName)
    end
    local itemName = farmingDefinition.DisplayName or "produce"
    return ("Freshly harvested %s from the farm."):format(string.lower(itemName))
end

local function get_item_description(toolDefinition, farmingDefinition)
    if toolDefinition and type(toolDefinition.Description) == "string" and toolDefinition.Description ~= "" then
        return toolDefinition.Description
    end
    if farmingDefinition and type(farmingDefinition.Description) == "string" and farmingDefinition.Description ~= "" then
        return farmingDefinition.Description
    end
    return get_default_farming_description(farmingDefinition)
end

local function create_entry(itemDefinition, farmingDefinition, count)
    return {
        ItemId = itemDefinition and itemDefinition.ItemId or farmingDefinition.ItemId,
        DisplayName = itemDefinition and itemDefinition.DisplayName or farmingDefinition.DisplayName or "",
        Description = get_item_description(itemDefinition, farmingDefinition),
        Count = count,
        SortOrder = (itemDefinition and itemDefinition.SortOrder)
            or (farmingDefinition and farmingDefinition.SortOrder)
            or math.huge,
        RenderSource = get_farming_render_source(farmingDefinition) or get_catalog_render_source(itemDefinition),
    }
end

local function push_tool_category_entries(entries, seenItemIds, toolCategory)
    for _, itemDefinition in ipairs(ToolItemCatalog.GetItemsByToolCategory(toolCategory) or {}) do
        local itemId = itemDefinition.ItemId
        if seenItemIds[itemId] then continue end

        local count = get_item_count(itemDefinition)
        if count <= 0 then continue end

        seenItemIds[itemId] = true
        entries[#entries + 1] = create_entry(itemDefinition, FarmingCatalog.GetItem(itemId), count)
    end
end

local function push_missing_farming_entries(entries, seenItemIds, farmingItems, inventoryPath)
    local bucket = DataUtility.client.get(inventoryPath)
    for _, farmingDefinition in ipairs(farmingItems or {}) do
        if seenItemIds[farmingDefinition.ItemId] then continue end

        local count = get_bucket_item_count(bucket, farmingDefinition.ItemId)
        if count <= 0 then continue end

        seenItemIds[farmingDefinition.ItemId] = true
        entries[#entries + 1] = create_entry(ToolItemCatalog.GetItemDefinition(farmingDefinition.ItemId), farmingDefinition, count)
    end
end

local function build_category_entries(categoryId)
    local entries = {}
    local seenItemIds = {}

    for _, toolCategory in ipairs(CATEGORY_TOOL_CATEGORIES[categoryId] or {}) do
        push_tool_category_entries(entries, seenItemIds, toolCategory)
    end

    if categoryId == "Seeds" then
        push_missing_farming_entries(entries, seenItemIds, FarmingCatalog.GetSeedItems(), "Inventory.Seeds")
    elseif categoryId == "Foods" then
        push_missing_farming_entries(entries, seenItemIds, FarmingCatalog.GetFruitItems(), "Inventory.Fruits")
    end

    table.sort(entries, function(left, right)
        if left.SortOrder ~= right.SortOrder then
            return left.SortOrder < right.SortOrder
        end
        return string.lower(left.DisplayName) < string.lower(right.DisplayName)
    end)
    return entries
end

local function resolve_tool_item_id(tool)
    local farmingItemId = normalize_key(tool:GetAttribute(FarmingUtility.FARMING_ITEM_ATTRIBUTE))
    if farmingItemId and FarmingCatalog.GetItem(farmingItemId) then
        return farmingItemId
    end

    local toolDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
    if toolDefinition then return toolDefinition.ItemId end

    local explicitItemId = normalize_key(tool:GetAttribute("ToolItemId"))
        or normalize_key(tool:GetAttribute("ItemId"))
    if explicitItemId and (ToolItemCatalog.GetItemDefinition(explicitItemId) or FarmingCatalog.GetItem(explicitItemId)) then
        return explicitItemId
    end
    return nil
end

local function rebuild_live_groups()
    clear_dictionary(currentLiveGroups)
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local character = localPlayer.Character

    local function register_tool(tool, isEquipped)
        local itemId = resolve_tool_item_id(tool)
        if not itemId then return end

        local group = currentLiveGroups[itemId]
        if not group then
            group = {
                Tools = {}, BackpackTools = {}, CharacterTools = {}, Equipped = false,
            }
            currentLiveGroups[itemId] = group
        end

        group.Tools[#group.Tools + 1] = tool
        if isEquipped then
            group.CharacterTools[#group.CharacterTools + 1] = tool
            group.Equipped = true
        else
            group.BackpackTools[#group.BackpackTools + 1] = tool
        end
    end

    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then register_tool(child, false) end
        end
    end
    if character then
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then register_tool(child, true) end
        end
    end
end

local function queue_live_groups_refresh()
    if liveGroupsQueued then return end
    liveGroupsQueued = true
    task.defer(function()
        liveGroupsQueued = false
        rebuild_live_groups()
        apply_selection()
    end)
end

local function render_details(entry)
    if not currentUi then return end

    set_gui_visible(currentUi.DetailsRoot, true)

    local nameText = entry and entry.DisplayName or ""
    local detailsText = entry and entry.Description or ""

    if currentUi.DetailsNameLabel then currentUi.DetailsNameLabel.Text = nameText end
    if currentUi.DetailsNameShadowLabel then currentUi.DetailsNameShadowLabel.Text = nameText end
    if currentUi.DetailsTextLabel then currentUi.DetailsTextLabel.Text = detailsText end

    if currentUi.DetailsViewport then
        if entry then
            render_viewport(currentUi.DetailsViewport, entry, DETAILS_VIEWPORT_CONFIG, "details")
        else
            clear_viewport(currentUi.DetailsViewport)
        end
    end

    local liveGroup = entry and currentLiveGroups[entry.ItemId] or nil
    local isEquipped = liveGroup and liveGroup.Equipped == true or false
    local hasToolInstance = liveGroup and #liveGroup.Tools > 0 or false

    if currentUi.EquipButton then
        currentUi.EquipButton.Visible = entry ~= nil and not isEquipped
        set_button_enabled(currentUi.EquipButton, entry ~= nil and hasToolInstance and not isEquipped)
    end

    if currentUi.UnequipButton then
        currentUi.UnequipButton.Visible = entry ~= nil and isEquipped
        set_button_enabled(currentUi.UnequipButton, entry ~= nil and isEquipped)
    end
end

apply_selection = function()
    if not currentUi then return end

    local selectedEntry = nil
    if selectedItemId then
        selectedEntry = activeEntriesByItemId[selectedItemId]
    end

    if selectedItemId and not selectedEntry then selectedItemId = nil end

    for itemId, card in pairs(activeCardsByItemId) do
        set_selected_visual(card, selectedItemId == itemId)
    end
    render_details(selectedEntry)
end

local function configure_card(card, entry, layoutOrder)
    card.Name = entry.ItemId
    card.LayoutOrder = layoutOrder
    card.Visible = true

    local nameLabel = find_text_label(card, ITEM_NAME_NAMES, true)
    local amountLabel = find_text_label(card, ITEM_AMOUNT_NAMES, true)
    local imageRoot = find_gui_object(card, ITEM_IMAGE_NAMES, true)
    local viewportFrame = find_viewport_frame(imageRoot or card)

    if nameLabel then nameLabel.Text = entry.DisplayName end
    if amountLabel then amountLabel.Text = ("x%d"):format(entry.Count) end

    if viewportFrame then
        render_viewport(viewportFrame, entry, GRID_VIEWPORT_CONFIG, "grid")
    end
end

local function render_inventory()
    if not currentUi or not currentTemplateSource then return end

    cardTrove:Clean()
    clear_dictionary(activeEntriesByItemId)
    clear_dictionary(activeCardsByItemId)

    if currentUi.GridContainer:IsA("ScrollingFrame") and lastRenderedCategoryId ~= activeCategoryId then
        currentUi.GridContainer.CanvasPosition = Vector2.zero
    end

    local entries = build_category_entries(activeCategoryId)
    for layoutOrder, entry in ipairs(entries) do
        local card = currentTemplateSource:Clone()
        local clickTarget = create_click_target(card)

        configure_card(card, entry, layoutOrder)
        card.Parent = currentUi.GridContainer
        cardTrove:Add(card)

        activeEntriesByItemId[entry.ItemId] = entry
        activeCardsByItemId[entry.ItemId] = card

        if clickTarget then
            cardTrove:Connect(clickTarget.Activated, function()
                selectedItemId = entry.ItemId
                apply_selection()
            end)
        end
    end

    lastRenderedCategoryId = activeCategoryId
    apply_selection()
end

queue_render = function()
    if renderQueued then return end
    renderQueued = true
    task.defer(function()
        renderQueued = false
        render_inventory()
    end)
end

local function equip_selected_item()
    if not selectedItemId then return end
    rebuild_live_groups()

    local liveGroup = currentLiveGroups[selectedItemId]
    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not liveGroup or liveGroup.Equipped or not humanoid then
        apply_selection()
        return
    end

    for _, tool in ipairs(liveGroup.BackpackTools) do
        if tool.Parent and tool.Parent:IsA("Backpack") then
            humanoid:EquipTool(tool)
            break
        end
    end
    task.defer(queue_live_groups_refresh)
end

local function unequip_selected_item()
    if not selectedItemId then return end
    rebuild_live_groups()

    local liveGroup = currentLiveGroups[selectedItemId]
    local character = localPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not liveGroup or not liveGroup.Equipped or not humanoid then
        apply_selection()
        return
    end

    humanoid:UnequipTools()
    task.defer(queue_live_groups_refresh)
end

local function set_active_category(categoryId)
    if activeCategoryId == categoryId then return end
    activeCategoryId = categoryId
    selectedItemId = nil
    queue_render()
end

local function get_inventory_ui(inventoryRoot)
    local contentRoot = find_gui_object(inventoryRoot, INVENTORY_BACKGROUND_NAMES, true) or inventoryRoot
    local tabRoot = find_gui_object(contentRoot, INVENTORY_TAB_NAMES, true) or contentRoot
    local categoriesRoot = find_gui_object(tabRoot, CATEGORIES_ROOT_NAMES, true) or tabRoot
    local gridContainer = find_named_instance(tabRoot, GRID_CONTAINER_NAMES, "ScrollingFrame", true)
    local template = gridContainer and find_gui_object(gridContainer, ITEM_TEMPLATE_NAMES, false)

    if not template and gridContainer then
        template = find_gui_object(gridContainer, ITEM_TEMPLATE_NAMES, true)
    end

    local detailsFrame = find_gui_object(tabRoot, DETAILS_FRAME_NAMES, true) or contentRoot
    local detailsRoot = find_gui_object(detailsFrame, DETAILS_ROOT_NAMES, true) or detailsFrame
    local detailsDisplayRoot = find_gui_object(detailsRoot, DETAILS_DISPLAY_NAMES, true) or detailsRoot
    local detailsImageRoot = find_gui_object(detailsDisplayRoot, DETAILS_IMAGE_NAMES, true) or detailsDisplayRoot
    local detailsViewport = find_viewport_frame(detailsImageRoot)
    local buttonsRoot = find_gui_object(detailsRoot, BUTTONS_ROOT_NAMES, true) or detailsRoot

    local utilityButton = find_gui_button(categoriesRoot, CATEGORY_BUTTON_NAMES.Utility, true)
    local seedsButton = find_gui_button(categoriesRoot, CATEGORY_BUTTON_NAMES.Seeds, true)
    local foodsButton = find_gui_button(categoriesRoot, CATEGORY_BUTTON_NAMES.Foods, true)
    local closeButton = find_gui_button(inventoryRoot, CLOSE_BUTTON_NAMES, true)

    local detailsNameLabel = find_text_label(detailsRoot, DETAILS_NAME_NAMES, true)
    local detailsNameShadowLabel = find_text_label(detailsRoot, DETAILS_NAME_SHADOW_NAMES, true)
    local detailsTextLabel = find_text_label(detailsRoot, DETAILS_TEXT_NAMES, true)
    local equipButton = find_gui_button(buttonsRoot, EQUIP_BUTTON_NAMES, true)
    local unequipButton = find_gui_button(buttonsRoot, UNEQUIP_BUTTON_NAMES, true)

    if not gridContainer or not template or not utilityButton or not seedsButton or not foodsButton then
        return nil
    end

    if not detailsRoot or not detailsViewport or not detailsTextLabel then return nil end
    if not detailsNameLabel and not detailsNameShadowLabel then return nil end

    return {
        Root = inventoryRoot,
        GridContainer = gridContainer,
        Template = template,
        UtilityButton = utilityButton,
        SeedsButton = seedsButton,
        FoodsButton = foodsButton,
        CloseButton = closeButton,
        DetailsRoot = detailsRoot,
        DetailsViewport = detailsViewport,
        DetailsNameLabel = detailsNameLabel,
        DetailsNameShadowLabel = detailsNameShadowLabel,
        DetailsTextLabel = detailsTextLabel,
        EquipButton = equipButton,
        UnequipButton = unequipButton,
    }
end

local function find_inventory_ui()
    local mainUi = find_named_instance(playerGui, MAIN_UI_NAMES, nil, true)
    if not mainUi then return nil end
    local mainframe = find_named_instance(mainUi, MAINFRAME_NAMES, nil, true)
    if not mainframe then return nil end
    local framesContainer = find_named_instance(mainframe, FRAMES_CONTAINER_NAMES, nil, true)
    if not framesContainer then return nil end
    local inventoryRoot = find_named_instance(framesContainer, INVENTORY_ROOT_NAMES, nil, true)
    if not inventoryRoot then return nil end
    return get_inventory_ui(inventoryRoot)
end

local function destroy_ui_binding()
    cardTrove:Clean()
    uiTrove:Destroy()
    uiTrove = Trove.new()

    clear_dictionary(activeEntriesByItemId)
    clear_dictionary(activeCardsByItemId)
    currentUi = nil
    currentTemplateSource = nil
    lastRenderedCategoryId = nil
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
        
        -- Modificação crucial aqui! Passando o controle do canvas para o Roblox nativamente:
        ui.GridContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
        ui.GridContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
        
        ui.GridContainer.ScrollingDirection = Enum.ScrollingDirection.Y
    end

    if ui.EquipButton then
        set_button_text(ui.EquipButton, EQUIP_TEXT_NAMES, EQUIP_SHADOW_TEXT_NAMES, "Equip")
    end

    if ui.UnequipButton then
        set_button_text(ui.UnequipButton, UNEQUIP_TEXT_NAMES, UNEQUIP_SHADOW_TEXT_NAMES, "Unequip")
    end

    render_details(nil)

    uiTrove:Connect(ui.UtilityButton.Activated, function() set_active_category("Utility") end)
    uiTrove:Connect(ui.SeedsButton.Activated, function() set_active_category("Seeds") end)
    uiTrove:Connect(ui.FoodsButton.Activated, function() set_active_category("Foods") end)

    if ui.CloseButton then
        uiTrove:Connect(ui.CloseButton.Activated, function() set_gui_visible(ui.Root, false) end)
    end

    if ui.EquipButton then uiTrove:Connect(ui.EquipButton.Activated, equip_selected_item) end
    if ui.UnequipButton then uiTrove:Connect(ui.UnequipButton.Activated, unequip_selected_item) end

    for _, inventoryPath in ipairs(RELEVANT_INVENTORY_PATHS) do
        uiTrove:Add(DataUtility.client.bind(inventoryPath, queue_render))
    end

    uiTrove:Connect(ui.Root.AncestryChanged, function(_, parent)
        if parent then return end
        if currentUi and currentUi.Root == ui.Root then
            destroy_ui_binding()
            task.defer(try_bind_ui)
        end
    end)

    queue_render()
end

local function is_inventory_ui_related(instance)
    return matches_alias(instance, MAIN_UI_NAMES)
        or matches_alias(instance, MAINFRAME_NAMES)
        or matches_alias(instance, FRAMES_CONTAINER_NAMES)
        or matches_alias(instance, INVENTORY_ROOT_NAMES)
        or matches_alias(instance, INVENTORY_BACKGROUND_NAMES)
        or matches_alias(instance, INVENTORY_TAB_NAMES)
        or matches_alias(instance, CATEGORIES_ROOT_NAMES)
        or matches_alias(instance, GRID_CONTAINER_NAMES)
        or matches_alias(instance, ITEM_TEMPLATE_NAMES)
        or matches_alias(instance, DETAILS_FRAME_NAMES)
        or matches_alias(instance, DETAILS_ROOT_NAMES)
        or matches_alias(instance, DETAILS_DISPLAY_NAMES)
        or matches_alias(instance, ITEM_IMAGE_NAMES)
        or matches_alias(instance, VIEWPORT_FRAME_NAMES)
end

try_bind_ui = function()
    if currentUi and currentUi.Root and currentUi.Root.Parent and currentTemplateSource then return end
    local ui = find_inventory_ui()
    if not ui then
        destroy_ui_binding()
        return
    end
    bind_ui(ui)
end

local function watch_tool_container(container, trove)
    if not container then return end
    trove:Connect(container.ChildAdded, function(child)
        if child:IsA("Tool") then queue_live_groups_refresh() end
    end)
    trove:Connect(container.ChildRemoved, function(child)
        if child:IsA("Tool") then queue_live_groups_refresh() end
    end)
end

local function bind_backpack(backpack)
    backpackTrove:Clean()
    watch_tool_container(backpack, backpackTrove)
    queue_live_groups_refresh()
end

local function bind_character(character)
    characterTrove:Clean()
    watch_tool_container(character, characterTrove)
    queue_live_groups_refresh()
end

-- INIT
DataUtility.client.ensure_remotes()
rebuild_live_groups()

rootTrove:Add(cardTrove)
rootTrove:Add(backpackTrove)
rootTrove:Add(characterTrove)

local backpack = localPlayer:FindFirstChildOfClass("Backpack")
if backpack then bind_backpack(backpack) end
if localPlayer.Character then bind_character(localPlayer.Character) end

rootTrove:Connect(localPlayer.ChildAdded, function(child)
    if child:IsA("Backpack") then bind_backpack(child) end
end)

rootTrove:Connect(localPlayer.CharacterAdded, bind_character)

rootTrove:Connect(playerGui.DescendantAdded, function(instance)
    if instance:IsA("LayerCollector") or is_inventory_ui_related(instance) then
        try_bind_ui()
    end
end)

rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
    if currentUi and (instance == currentUi.Root or instance:IsDescendantOf(currentUi.Root)) then
        task.defer(try_bind_ui)
    elseif is_inventory_ui_related(instance) then
        task.defer(try_bind_ui)
    end
end)

try_bind_ui()