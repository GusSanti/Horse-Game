-- SERVICES
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

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
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))
local InventoryLoadout = require(Utility:WaitForChild("InventoryLoadout"))

local UPDATE_LOADOUT_REMOTE_NAME = "UpdateInventoryLoadout"
local DEFAULT_GENERIC_TOOL_DEFINITIONS = InventoryLoadout.GetDefaultGenericToolDefinitions()
local MAX_HOTBAR_SLOTS = InventoryLoadout.MAX_HOTBAR_SLOTS or 9

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local FoodHoverTooltip = {}
do
    local tooltipGui = nil
    local tooltipFrame = nil
    local titleLabel = nil
    local bodyLabel = nil
    local activeTarget = nil
    local positionConnection = nil

    local function format_number(value)
        local numberValue = tonumber(value) or 0
        if math.abs(numberValue - math.floor(numberValue + 0.5)) < 0.001 then
            return tostring(math.floor(numberValue + 0.5))
        end

        return string.format("%.1f", numberValue)
    end

    local function format_signed(value)
        local numberValue = tonumber(value) or 0
        return numberValue >= 0 and ("+" .. format_number(numberValue)) or format_number(numberValue)
    end

    local function ensure_tooltip()
        if tooltipGui and tooltipGui.Parent and tooltipFrame and tooltipFrame.Parent then
            return tooltipFrame
        end

        tooltipGui = playerGui:FindFirstChild("FoodHoverTooltipGui")
        if not tooltipGui then
            tooltipGui = Instance.new("ScreenGui")
            tooltipGui.Name = "FoodHoverTooltipGui"
            tooltipGui.IgnoreGuiInset = true
            tooltipGui.ResetOnSpawn = false
            tooltipGui.DisplayOrder = 10000
            tooltipGui.Parent = playerGui
        end

        tooltipFrame = tooltipGui:FindFirstChild("Tooltip")
        if not tooltipFrame then
            tooltipFrame = Instance.new("Frame")
            tooltipFrame.Name = "Tooltip"
            tooltipFrame.BackgroundColor3 = Color3.fromRGB(24, 22, 20)
            tooltipFrame.BackgroundTransparency = 0.08
            tooltipFrame.BorderSizePixel = 0
            tooltipFrame.AutomaticSize = Enum.AutomaticSize.Y
            tooltipFrame.Size = UDim2.fromOffset(238, 0)
            tooltipFrame.Visible = false
            tooltipFrame.ZIndex = 10000
            tooltipFrame.Parent = tooltipGui

            local corner = Instance.new("UICorner")
            corner.CornerRadius = UDim.new(0, 6)
            corner.Parent = tooltipFrame

            local stroke = Instance.new("UIStroke")
            stroke.Color = Color3.fromRGB(255, 225, 170)
            stroke.Transparency = 0.28
            stroke.Thickness = 1
            stroke.Parent = tooltipFrame

            local padding = Instance.new("UIPadding")
            padding.PaddingLeft = UDim.new(0, 10)
            padding.PaddingRight = UDim.new(0, 10)
            padding.PaddingTop = UDim.new(0, 10)
            padding.PaddingBottom = UDim.new(0, 10)
            padding.Parent = tooltipFrame

            local layout = Instance.new("UIListLayout")
            layout.FillDirection = Enum.FillDirection.Vertical
            layout.SortOrder = Enum.SortOrder.LayoutOrder
            layout.Padding = UDim.new(0, 5)
            layout.Parent = tooltipFrame

            titleLabel = Instance.new("TextLabel")
            titleLabel.Name = "Title"
            titleLabel.BackgroundTransparency = 1
            titleLabel.Font = Enum.Font.GothamBold
            titleLabel.TextColor3 = Color3.fromRGB(255, 236, 192)
            titleLabel.TextSize = 15
            titleLabel.TextXAlignment = Enum.TextXAlignment.Left
            titleLabel.TextWrapped = true
            titleLabel.AutomaticSize = Enum.AutomaticSize.Y
            titleLabel.Size = UDim2.fromScale(1, 0)
            titleLabel.LayoutOrder = 1
            titleLabel.ZIndex = 10001
            titleLabel.Parent = tooltipFrame

            bodyLabel = Instance.new("TextLabel")
            bodyLabel.Name = "Body"
            bodyLabel.BackgroundTransparency = 1
            bodyLabel.Font = Enum.Font.Gotham
            bodyLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
            bodyLabel.TextSize = 13
            bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
            bodyLabel.TextWrapped = true
            bodyLabel.AutomaticSize = Enum.AutomaticSize.Y
            bodyLabel.Size = UDim2.fromScale(1, 0)
            bodyLabel.LayoutOrder = 2
            bodyLabel.ZIndex = 10001
            bodyLabel.Parent = tooltipFrame
        else
            titleLabel = tooltipFrame:FindFirstChild("Title")
            bodyLabel = tooltipFrame:FindFirstChild("Body")
        end

        return tooltipFrame
    end

    local function is_target_visible(target)
        local current = target

        while current do
            if current:IsA("GuiObject") and not current.Visible then
                return false
            end

            if current:IsA("LayerCollector") and not current.Enabled then
                return false
            end

            current = current.Parent
        end

        return target ~= nil and target.Parent ~= nil
    end

    local function update_position()
        if not tooltipFrame or not tooltipFrame.Visible then
            return
        end

        if activeTarget and not is_target_visible(activeTarget) then
            FoodHoverTooltip.Hide(activeTarget)
            return
        end

        local mousePosition = UserInputService:GetMouseLocation()
        local viewportSize = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
        local frameSize = tooltipFrame.AbsoluteSize
        local x = mousePosition.X + 16
        local y = mousePosition.Y + 18

        if x + frameSize.X + 10 > viewportSize.X then
            x = mousePosition.X - frameSize.X - 16
        end

        if y + frameSize.Y + 10 > viewportSize.Y then
            y = mousePosition.Y - frameSize.Y - 18
        end

        tooltipFrame.Position = UDim2.fromOffset(math.max(10, x), math.max(10, y))
    end

    local function build_effect_lines(itemDefinition)
        local effects = itemDefinition and itemDefinition.Effects or {}
        local lines = {}

        if itemDefinition and itemDefinition.NeedKey == "Hunger" and effects.NeedGain ~= nil then
            lines[#lines + 1] = "Fome: +" .. format_number(effects.NeedGain)
        elseif itemDefinition and itemDefinition.NeedKey and effects.NeedGain ~= nil then
            lines[#lines + 1] = tostring(itemDefinition.NeedKey) .. ": +" .. format_number(effects.NeedGain)
        end

        if effects.HealthGain ~= nil then
            lines[#lines + 1] = "Saude: " .. format_signed(effects.HealthGain)
        end

        if effects.HappinessGain ~= nil then
            lines[#lines + 1] = "Felicidade: " .. format_signed(effects.HappinessGain)
        end

        if effects.FriendshipGain ~= nil then
            lines[#lines + 1] = "Amizade: " .. format_signed(effects.FriendshipGain)
        end

        local decayBuff = effects.DecayBuff
        if type(decayBuff) == "table" and tonumber(decayBuff.Multiplier) then
            local multiplier = tonumber(decayBuff.Multiplier)
            if multiplier and multiplier < 1 then
                local percent = math.max(0, math.floor((1 - multiplier) * 100 + 0.5))
                local duration = tonumber(decayBuff.DurationMinutes)
                local suffix = duration and duration > 0 and (" por " .. format_number(duration) .. " min") or ""
                lines[#lines + 1] = "Queda de fome: -" .. percent .. "%" .. suffix
            end
        end

        if effects.MoodText ~= nil and tostring(effects.MoodText) ~= "" then
            lines[#lines + 1] = "Humor: " .. tostring(effects.MoodText)
        end

        if #lines == 0 and type(itemDefinition.Description) == "string" and itemDefinition.Description ~= "" then
            lines[#lines + 1] = itemDefinition.Description
        end

        return lines
    end

    function FoodHoverTooltip.HasTooltip(itemDefinition)
        return type(itemDefinition) == "table" and #build_effect_lines(itemDefinition) > 0
    end

    function FoodHoverTooltip.Show(source, target)
        local itemDefinition = type(source) == "function" and source() or source
        if not FoodHoverTooltip.HasTooltip(itemDefinition) then
            return
        end

        local frame = ensure_tooltip()
        if not frame or not titleLabel or not bodyLabel then
            return
        end

        activeTarget = target
        titleLabel.Text = itemDefinition.DisplayName or itemDefinition.ToolName or itemDefinition.ItemId or "Food"
        bodyLabel.Text = table.concat(build_effect_lines(itemDefinition), "\n")
        frame.Visible = true
        update_position()

        if not positionConnection then
            positionConnection = RunService.RenderStepped:Connect(update_position)
        end
    end

    function FoodHoverTooltip.Hide(target)
        if target and activeTarget ~= target then
            return
        end

        activeTarget = nil
        if tooltipFrame then
            tooltipFrame.Visible = false
        end

        if positionConnection then
            positionConnection:Disconnect()
            positionConnection = nil
        end
    end

    function FoodHoverTooltip.Bind(target, source, trove)
        if not target or not target:IsA("GuiObject") then
            return
        end

        trove:Connect(target.MouseEnter, function()
            FoodHoverTooltip.Show(source, target)
        end)
        trove:Connect(target.MouseLeave, function()
            FoodHoverTooltip.Hide(target)
        end)
        trove:Connect(target.AncestryChanged, function(_, parent)
            if not parent then
                FoodHoverTooltip.Hide(target)
            end
        end)
    end
end

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
local renderDirty = true
local renderGeneration = 0
local viewportPopulationInProgress = false
local liveGroupsQueued = false
local previewCache = {}
local activeEntriesByItemId = {}
local activeCardsByItemId = {}
local currentLiveGroups = {}
local lastRenderedCategoryId = nil
local currentGridTemplateMetrics = nil

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

local function normalize_generic_tool_name(toolName)
    return InventoryLoadout.NormalizeGenericToolName(toolName)
end

local function build_generic_entry_key(toolName)
    local normalizedToolName = normalize_generic_tool_name(toolName)
    if not normalizedToolName then
        return nil
    end

    return ("generic:%s"):format(string.lower(normalizedToolName))
end

local function get_entry_key_from_item_id(itemId)
    return normalize_key(itemId)
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

local function resolve_udim_axis(udim, absoluteAxisSize)
    return math.max(0, udim.Offset + absoluteAxisSize * udim.Scale)
end

local function find_grid_layout(container)
    if not container then return nil end
    return container:FindFirstChildOfClass("UIGridLayout")
        or container:FindFirstChildWhichIsA("UIGridLayout", true)
end

local function find_ui_padding(container)
    if not container then return nil end
    return container:FindFirstChildOfClass("UIPadding")
        or container:FindFirstChildWhichIsA("UIPadding", true)
end

local function get_padding_offsets(padding, absoluteSize)
    if not padding then
        return 0, 0, 0, 0
    end

    return resolve_udim_axis(padding.PaddingLeft, absoluteSize.X),
        resolve_udim_axis(padding.PaddingRight, absoluteSize.X),
        resolve_udim_axis(padding.PaddingTop, absoluteSize.Y),
        resolve_udim_axis(padding.PaddingBottom, absoluteSize.Y)
end

local function capture_template_metrics(template, container, layout)
    if not template or not container then return nil end

    local referenceWidth = resolve_udim_axis(template.Size.X, container.AbsoluteSize.X)
    local referenceHeight = resolve_udim_axis(template.Size.Y, container.AbsoluteSize.Y)

    if referenceWidth <= 0 or referenceHeight <= 0 then
        local fallbackCellSize = layout and layout.CellSize or UDim2.fromOffset(96, 96)
        referenceWidth = math.max(referenceWidth, resolve_udim_axis(fallbackCellSize.X, container.AbsoluteSize.X))
        referenceHeight = math.max(referenceHeight, resolve_udim_axis(fallbackCellSize.Y, container.AbsoluteSize.Y))
    end

    local aspectConstraint = template:FindFirstChildWhichIsA("UIAspectRatioConstraint", true)
    local aspectRatio = aspectConstraint and aspectConstraint.AspectRatio or 0
    if aspectRatio <= 0 then
        aspectRatio = referenceWidth / math.max(referenceHeight, 1)
    end

    return {
        ReferenceWidth = math.max(1, math.floor(referenceWidth + 0.5)),
        ReferenceHeight = math.max(1, math.floor(referenceHeight + 0.5)),
        AspectRatio = math.max(0.1, aspectRatio),
    }
end

local function update_canvas_size()
    if not currentUi or not currentUi.GridContainer or not currentUi.GridContainer:IsA("ScrollingFrame") then
        return
    end

    local scrollingFrame = currentUi.GridContainer
    local layout = find_grid_layout(scrollingFrame)
    if not layout then return end

    local padding = find_ui_padding(scrollingFrame)
    local _, _, topPadding, bottomPadding = get_padding_offsets(padding, scrollingFrame.AbsoluteSize)

    scrollingFrame.CanvasSize = UDim2.fromOffset(
        0,
        math.max(0, math.ceil(layout.AbsoluteContentSize.Y + topPadding + bottomPadding))
    )
end

local function update_grid_layout()
    if not currentUi or not currentUi.GridContainer or not currentUi.GridContainer:IsA("ScrollingFrame") then
        return
    end

    local scrollingFrame = currentUi.GridContainer
    local layout = find_grid_layout(scrollingFrame)
    if not layout then
        update_canvas_size()
        return
    end

    local capturedMetrics = capture_template_metrics(currentTemplateSource, scrollingFrame, layout)
    if capturedMetrics then
        currentGridTemplateMetrics = capturedMetrics
    end

    local templateMetrics = currentGridTemplateMetrics
    if not templateMetrics then
        update_canvas_size()
        return
    end

    local padding = find_ui_padding(scrollingFrame)
    local leftPadding, rightPadding = get_padding_offsets(padding, scrollingFrame.AbsoluteSize)
    local availableWidth = scrollingFrame.AbsoluteSize.X - leftPadding - rightPadding

    if scrollingFrame.ScrollBarThickness > 0 then
        availableWidth = availableWidth - scrollingFrame.ScrollBarThickness
    end

    availableWidth = math.max(1, availableWidth)

    local horizontalSpacing = resolve_udim_axis(layout.CellPadding.X, availableWidth)
    local columns = math.max(
        1,
        math.floor((availableWidth + horizontalSpacing) / (templateMetrics.ReferenceWidth + horizontalSpacing))
    )

    if layout.FillDirectionMaxCells > 0 then
        columns = math.min(columns, layout.FillDirectionMaxCells)
    end

    local cellWidth = math.max(
        1,
        math.floor((availableWidth - horizontalSpacing * math.max(0, columns - 1)) / columns)
    )
    local cellHeight = math.max(1, math.floor(cellWidth / templateMetrics.AspectRatio))
    local desiredCellSize = UDim2.fromOffset(cellWidth, cellHeight)

    if layout.CellSize ~= desiredCellSize then
        layout.CellSize = desiredCellSize
    end

    update_canvas_size()
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

local function find_named_asset(root, searchNames)
    if not root then return nil end

    for _, name in ipairs(searchNames or {}) do
        if type(name) == "string" and name ~= "" then
            local found = root:FindFirstChild(name, true)
            if found then
                return found
            end
        end
    end

    return nil
end

local function get_generic_render_source(toolName)
    local itemsFolder = get_assets_items_root()
    if itemsFolder then
        local asset = find_named_asset(itemsFolder, { toolName })
        if asset then
            return asset
        end
    end

    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local character = localPlayer.Character

    for _, container in ipairs({ backpack, character }) do
        if container then
            local tool = container:FindFirstChild(toolName)
            if tool then
                return tool
            end
        end
    end

    return nil
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

    local previewKey = entry.EntryKey or entry.ItemId or entry.DisplayName
    local snapshot = get_preview_snapshot(previewKey, entry.RenderSource, entry.DisplayName, cameraConfig, cameraKey)
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

local function create_item_entry(itemDefinition, farmingDefinition, count)
    local itemId = itemDefinition and itemDefinition.ItemId or farmingDefinition and farmingDefinition.ItemId or nil
    local entryKey = get_entry_key_from_item_id(itemId)
    local isDefaultItem = InventoryLoadout.IsDefaultItemId(itemId)
    local displayCount = isDefaultItem and math.max(count, 1) or count

    return {
        EntryKey = entryKey,
        ItemId = itemId,
        Definition = itemDefinition or farmingDefinition,
        DisplayName = itemDefinition and itemDefinition.DisplayName or farmingDefinition and farmingDefinition.DisplayName or "",
        Description = get_item_description(itemDefinition, farmingDefinition),
        Count = displayCount,
        SortOrder = (itemDefinition and itemDefinition.SortOrder)
            or (farmingDefinition and farmingDefinition.SortOrder)
            or math.huge,
        RenderSource = get_farming_render_source(farmingDefinition) or get_catalog_render_source(itemDefinition),
        LoadoutKind = "item",
        LoadoutValue = itemId,
        CanHotbarEquip = displayCount > 0 or isDefaultItem,
        IsDefaultItem = isDefaultItem,
    }
end

local function create_generic_entry(definition)
    local entryKey = build_generic_entry_key(definition and definition.ToolName)
    if not entryKey then
        return nil
    end

    return {
        EntryKey = entryKey,
        ItemId = definition.ToolName,
        DisplayName = definition.DisplayName or definition.ToolName or "",
        Description = definition.Description or "",
        Count = 1,
        SortOrder = definition.SortOrder or math.huge,
        RenderSource = get_generic_render_source(definition.ToolName),
        LoadoutKind = "generic",
        LoadoutValue = definition.ToolName,
        CanHotbarEquip = true,
        IsDefaultItem = true,
    }
end

local function push_tool_category_entries(entries, seenEntryKeys, toolCategory)
    for _, itemDefinition in ipairs(ToolItemCatalog.GetItemsByToolCategory(toolCategory) or {}) do
        local itemId = itemDefinition.ItemId
        local entryKey = get_entry_key_from_item_id(itemId)
        if not entryKey or seenEntryKeys[entryKey] then continue end

        local count = get_item_count(itemDefinition)
        local isDefaultItem = InventoryLoadout.IsDefaultItemId(itemId)
        if count <= 0 and not isDefaultItem then continue end

        seenEntryKeys[entryKey] = true
        entries[#entries + 1] = create_item_entry(itemDefinition, FarmingCatalog.GetItem(itemId), count)
    end
end

local function push_missing_farming_entries(entries, seenEntryKeys, farmingItems, inventoryPath)
    local bucket = DataUtility.client.get(inventoryPath)
    for _, farmingDefinition in ipairs(farmingItems or {}) do
        local entryKey = get_entry_key_from_item_id(farmingDefinition.ItemId)
        if not entryKey or seenEntryKeys[entryKey] then continue end

        local count = get_bucket_item_count(bucket, farmingDefinition.ItemId)
        if count <= 0 then continue end

        seenEntryKeys[entryKey] = true
        entries[#entries + 1] = create_item_entry(
            ToolItemCatalog.GetItemDefinition(farmingDefinition.ItemId),
            farmingDefinition,
            count
        )
    end
end

local function push_default_generic_entries(entries, seenEntryKeys)
    for _, definition in ipairs(DEFAULT_GENERIC_TOOL_DEFINITIONS) do
        local entry = create_generic_entry(definition)
        if not entry or not entry.EntryKey or seenEntryKeys[entry.EntryKey] then continue end

        seenEntryKeys[entry.EntryKey] = true
        entries[#entries + 1] = entry
    end
end

local function build_category_entries(categoryId)
    local entries = {}
    local seenEntryKeys = {}

    for _, toolCategory in ipairs(CATEGORY_TOOL_CATEGORIES[categoryId] or {}) do
        push_tool_category_entries(entries, seenEntryKeys, toolCategory)
    end

    if categoryId == "Utility" then
        push_default_generic_entries(entries, seenEntryKeys)
    elseif categoryId == "Seeds" then
        push_missing_farming_entries(entries, seenEntryKeys, FarmingCatalog.GetSeedItems(), "Inventory.Seeds")
    elseif categoryId == "Foods" then
        push_missing_farming_entries(entries, seenEntryKeys, FarmingCatalog.GetFruitItems(), "Inventory.Fruits")
    end

    table.sort(entries, function(left, right)
        if left.SortOrder ~= right.SortOrder then
            return left.SortOrder < right.SortOrder
        end
        return string.lower(left.DisplayName) < string.lower(right.DisplayName)
    end)
    return entries
end

local function resolve_tool_loadout_entry(tool)
    local farmingItemId = normalize_key(tool:GetAttribute(FarmingUtility.FARMING_ITEM_ATTRIBUTE))
    if farmingItemId then
        local farmingDefinition = FarmingCatalog.GetItem(farmingItemId)
        if farmingDefinition then
            return {
                EntryKey = get_entry_key_from_item_id(farmingDefinition.ItemId),
                Kind = "item",
                Value = farmingDefinition.ItemId,
            }
        end
    end

    local toolDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
    if toolDefinition then
        return {
            EntryKey = get_entry_key_from_item_id(toolDefinition.ItemId),
            Kind = "item",
            Value = toolDefinition.ItemId,
        }
    end

    local explicitItemId = normalize_key(tool:GetAttribute("ToolItemId"))
        or normalize_key(tool:GetAttribute("ItemId"))
    local explicitDefinition = explicitItemId and (ToolItemCatalog.GetItemDefinition(explicitItemId) or FarmingCatalog.GetItem(explicitItemId))
    if explicitDefinition then
        return {
            EntryKey = get_entry_key_from_item_id(explicitDefinition.ItemId),
            Kind = "item",
            Value = explicitDefinition.ItemId,
        }
    end

    local genericToolName = normalize_generic_tool_name(tool.Name)
    if genericToolName then
        return {
            EntryKey = build_generic_entry_key(genericToolName),
            Kind = "generic",
            Value = genericToolName,
        }
    end

    return nil
end

local function rebuild_live_groups()
    clear_dictionary(currentLiveGroups)
    local backpack = localPlayer:FindFirstChildOfClass("Backpack")
    local character = localPlayer.Character
    local order = 0

    local function register_tool(tool, isCharacterTool)
        local loadoutEntry = resolve_tool_loadout_entry(tool)
        local entryKey = loadoutEntry and loadoutEntry.EntryKey or nil
        if not entryKey then return end

        order += 1
        local group = currentLiveGroups[entryKey]
        if not group then
            group = {
                EntryKey = entryKey,
                Kind = loadoutEntry.Kind,
                Value = loadoutEntry.Value,
                Order = order,
                Tools = {},
                BackpackTools = {},
                CharacterTools = {},
            }
            currentLiveGroups[entryKey] = group
        end

        group.Tools[#group.Tools + 1] = tool
        if isCharacterTool then
            group.CharacterTools[#group.CharacterTools + 1] = tool
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

local function get_saved_loadout_values()
	return DataUtility.client.get(InventoryLoadout.HOTBAR_ITEM_IDS_PATH) or {},
		DataUtility.client.get(InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH) or {}
end

local function get_visible_hotbar_entries()
	rebuild_live_groups()

	local itemIds, genericToolNames = get_saved_loadout_values()
	local entries = {}
	local seenKeys = {}

	local function push(kind, value, entryKey)
		if not entryKey or seenKeys[entryKey] or not currentLiveGroups[entryKey] then
			return
		end

		seenKeys[entryKey] = true
		entries[#entries + 1] = {
			Kind = kind,
			Value = value,
			EntryKey = entryKey,
		}
	end

	for _, itemId in ipairs(itemIds) do
		push("item", itemId, get_entry_key_from_item_id(itemId))
	end

	for _, toolName in ipairs(genericToolNames) do
		push("generic", toolName, build_generic_entry_key(toolName))
	end

	local unorderedEntries = {}
	for entryKey, group in pairs(currentLiveGroups) do
		if not seenKeys[entryKey] and group.Kind and group.Value then
			unorderedEntries[#unorderedEntries + 1] = group
		end
	end

	table.sort(unorderedEntries, function(left, right)
		return (left.Order or math.huge) < (right.Order or math.huge)
	end)

	for _, group in ipairs(unorderedEntries) do
		push(group.Kind, group.Value, group.EntryKey)
	end

	return entries
end

local function get_hotbar_entries_payload()
	local entries = {}

	for index, hotbarEntry in ipairs(get_visible_hotbar_entries()) do
		if index > MAX_HOTBAR_SLOTS then
			break
		end

		entries[#entries + 1] = {
			Kind = hotbarEntry.Kind,
			Value = hotbarEntry.Value,
		}
	end

	return entries
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

    local liveGroup = entry and currentLiveGroups[entry.EntryKey] or nil
    local isInHotbar = liveGroup and #liveGroup.Tools > 0 or false
    local canEquip = entry ~= nil and entry.CanHotbarEquip == true

    if currentUi.EquipButton then
        currentUi.EquipButton.Visible = entry ~= nil and not isInHotbar
        set_button_enabled(currentUi.EquipButton, canEquip and not isInHotbar)
    end

    if currentUi.UnequipButton then
        currentUi.UnequipButton.Visible = entry ~= nil and isInHotbar
        set_button_enabled(currentUi.UnequipButton, entry ~= nil and isInHotbar)
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
    card.Name = entry.EntryKey or entry.ItemId
    card.LayoutOrder = layoutOrder
    card.Visible = true

    local nameLabel = find_text_label(card, ITEM_NAME_NAMES, true)
    local amountLabel = find_text_label(card, ITEM_AMOUNT_NAMES, true)
    local imageRoot = find_gui_object(card, ITEM_IMAGE_NAMES, true)
    local viewportFrame = find_viewport_frame(imageRoot or card)

    if nameLabel then nameLabel.Text = entry.DisplayName end
    if amountLabel then amountLabel.Text = ("x%d"):format(entry.Count) end

    return viewportFrame
end

local function render_inventory()
    if not currentUi or not currentTemplateSource then return end
    if not is_gui_visible(currentUi.Root) then
        renderDirty = true
        return
    end

    renderDirty = false
    renderGeneration += 1
    local generation = renderGeneration

    cardTrove:Clean()
    clear_dictionary(activeEntriesByItemId)
    clear_dictionary(activeCardsByItemId)

    if currentUi.GridContainer:IsA("ScrollingFrame") and lastRenderedCategoryId ~= activeCategoryId then
        currentUi.GridContainer.CanvasPosition = Vector2.zero
    end

    local entries = build_category_entries(activeCategoryId)
    local pendingViewports = {}
    for layoutOrder, entry in ipairs(entries) do
        local card = currentTemplateSource:Clone()
        local clickTarget = create_click_target(card)

        local viewportFrame = configure_card(card, entry, layoutOrder)
        card.Parent = currentUi.GridContainer
        cardTrove:Add(card)

        activeEntriesByItemId[entry.EntryKey] = entry
        activeCardsByItemId[entry.EntryKey] = card

        if activeCategoryId == "Foods" and FoodHoverTooltip.HasTooltip(entry.Definition) then
            FoodHoverTooltip.Bind(clickTarget or card, entry.Definition, cardTrove)
        end

        if clickTarget then
            cardTrove:Connect(clickTarget.Activated, function()
                selectedItemId = entry.EntryKey
                apply_selection()
            end)
        end

        if viewportFrame then
            pendingViewports[#pendingViewports + 1] = {
                Card = card,
                Entry = entry,
                ViewportFrame = viewportFrame,
            }
        end
    end

    lastRenderedCategoryId = activeCategoryId
    apply_selection()
    update_grid_layout()

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

            render_viewport(pending.ViewportFrame, pending.Entry, GRID_VIEWPORT_CONFIG, "grid")
            RunService.Heartbeat:Wait()
        end

        if generation == renderGeneration then
            viewportPopulationInProgress = false
        end
    end)
end

queue_render = function()
    renderDirty = true
    if not currentUi or not is_gui_visible(currentUi.Root) then return end
    if renderQueued then return end
    renderQueued = true
    task.defer(function()
        renderQueued = false
        if renderDirty then
            render_inventory()
        end
    end)
end

local function equip_selected_item()
    if not selectedItemId then return end
    local entry = activeEntriesByItemId[selectedItemId]
    if not entry or entry.CanHotbarEquip ~= true then
        apply_selection()
        return
    end

    local payload = {
        Kind = entry.LoadoutKind,
        Value = entry.LoadoutValue,
        Equipped = true,
        HotbarEntries = get_hotbar_entries_payload(),
    }

    local success, updated = pcall(function()
        return Net.Function[UPDATE_LOADOUT_REMOTE_NAME]:Call(payload)
    end)
    if success and updated ~= false then
        task.defer(queue_live_groups_refresh)
        task.defer(queue_render)
    else
        apply_selection()
    end
end

local function unequip_selected_item()
    if not selectedItemId then return end
    local entry = activeEntriesByItemId[selectedItemId]
    if not entry then
        apply_selection()
        return
    end

    local success, updated = pcall(function()
        return Net.Function[UPDATE_LOADOUT_REMOTE_NAME]:Call({
            Kind = entry.LoadoutKind,
            Value = entry.LoadoutValue,
            Equipped = false,
        })
    end)
    if success and updated ~= false then
        task.defer(queue_live_groups_refresh)
        task.defer(queue_render)
    else
        apply_selection()
    end
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
        DetailsDisplayRoot = detailsDisplayRoot,
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
    renderGeneration += 1
    renderDirty = true
    viewportPopulationInProgress = false
    cardTrove:Clean()
    uiTrove:Destroy()
    uiTrove = Trove.new()

    clear_dictionary(activeEntriesByItemId)
    clear_dictionary(activeCardsByItemId)
    currentUi = nil
    currentTemplateSource = nil
    lastRenderedCategoryId = nil
    currentGridTemplateMetrics = nil
end

local function bind_ui(ui)
    if currentUi and currentUi.Root == ui.Root and currentTemplateSource and currentUi.Root.Parent then
        return
    end

    destroy_ui_binding()

    currentUi = ui
    local gridLayout = ui.GridContainer:IsA("ScrollingFrame") and find_grid_layout(ui.GridContainer) or nil
    currentGridTemplateMetrics = capture_template_metrics(ui.Template, ui.GridContainer, gridLayout)
    currentTemplateSource = make_template_source(ui.Template)
    uiTrove:Add(currentTemplateSource)

    if ui.GridContainer:IsA("ScrollingFrame") then
        ui.GridContainer.Active = true
        ui.GridContainer.ScrollingEnabled = true
        
        ui.GridContainer.AutomaticCanvasSize = Enum.AutomaticSize.None
        ui.GridContainer.CanvasSize = UDim2.new(0, 0, 0, 0)
        
        ui.GridContainer.ScrollingDirection = Enum.ScrollingDirection.Y
    end

    if ui.EquipButton then
        set_button_text(ui.EquipButton, EQUIP_TEXT_NAMES, EQUIP_SHADOW_TEXT_NAMES, "Equip")
    end

    if ui.UnequipButton then
        set_button_text(ui.UnequipButton, UNEQUIP_TEXT_NAMES, UNEQUIP_SHADOW_TEXT_NAMES, "Unequip")
    end

    if ui.DetailsDisplayRoot then
        FoodHoverTooltip.Bind(ui.DetailsDisplayRoot, function()
            if activeCategoryId ~= "Foods" or not selectedItemId then
                return nil
            end

            local entry = activeEntriesByItemId[selectedItemId]
            return entry and entry.Definition or nil
        end, uiTrove)
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

    for _, loadoutPath in ipairs({
        InventoryLoadout.HOTBAR_ITEM_IDS_PATH,
        InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH,
        InventoryLoadout.HOTBAR_INITIALIZED_PATH,
    }) do
        uiTrove:Add(DataUtility.client.bind(loadoutPath, function()
            queue_live_groups_refresh()
            queue_render()
        end))
    end

    if ui.GridContainer:IsA("ScrollingFrame") then
        local scrollingFrame = ui.GridContainer
        local layout = find_grid_layout(scrollingFrame)

        if layout then
            uiTrove:Connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), update_canvas_size)
            uiTrove:Connect(layout:GetPropertyChangedSignal("CellPadding"), update_grid_layout)
            uiTrove:Connect(layout:GetPropertyChangedSignal("FillDirectionMaxCells"), update_grid_layout)
        end

        uiTrove:Connect(scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"), update_grid_layout)
        uiTrove:Connect(scrollingFrame:GetPropertyChangedSignal("ScrollBarThickness"), update_grid_layout)
        update_grid_layout()
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