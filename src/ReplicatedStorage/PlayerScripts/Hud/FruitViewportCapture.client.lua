local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local ClientModules = Modules:WaitForChild("Client")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local FarmingShopViewportCache = require(ClientModules:WaitForChild("Hud"):WaitForChild("FarmingShopViewportCache"))
local CropRarityUtility = require(Utility:WaitForChild("CropRarityUtility"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local SCREEN_GUI_NAME = "FruitViewportCaptureGui"
local IGNORE_HUD_ANIM_ATTRIBUTE = "IgnoreHudAnim"
local BACKGROUND_IMAGE = "rbxassetid://106699018663477"
local CAPTURE_CENTER = UDim2.fromScale(0.5, 0.5)
local BACKGROUND_SIZE = UDim2.fromScale(0.46, 0.46)
local VIEWPORT_SIZE = UDim2.fromScale(0.48, 0.48)

local ROTATE_STEP = math.rad(15)
local ZOOM_IN_MULTIPLIER = 0.88
local ZOOM_OUT_MULTIPLIER = 1.14
local MIN_DISTANCE_SCALE = 0.3
local MAX_DISTANCE_SCALE = 3

local captureGui = nil
local viewportFrame = nil
local itemNameLabel = nil
local itemCountLabel = nil
local statusLabel = nil
local zoomLabel = nil

local fruitItems = {}
local currentIndex = 1
local itemSettings = {}

local function create(className, properties)
	local instance = Instance.new(className)

	for property, value in pairs(properties or {}) do
		if property ~= "Parent" then
			instance[property] = value
		end
	end

	if properties and properties.Parent then
		instance.Parent = properties.Parent
	end

	return instance
end

local function normalize_key(value)
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function get_crop_sort_key(itemDefinition)
	return normalize_key(itemDefinition and itemDefinition.CropId)
		or normalize_key(itemDefinition and itemDefinition.DisplayName)
		or normalize_key(itemDefinition and itemDefinition.ItemId)
		or ""
end

local function get_rarity_sort(itemDefinition)
	local rarityKey = normalize_key(itemDefinition and itemDefinition.Rarity)
	if rarityKey == "gold" then
		return 1
	elseif rarityKey == "diamond" then
		return 2
	end

	return 0
end

local function collect_fruit_items()
	local items = {}

	for _, itemDefinition in ipairs(ToolItemCatalog.GetItemsByToolCategory("Fruits") or {}) do
		if itemDefinition.Kind == "Fruit" then
			items[#items + 1] = itemDefinition
		end
	end

	table.sort(items, function(left, right)
		local leftCrop = get_crop_sort_key(left)
		local rightCrop = get_crop_sort_key(right)
		if leftCrop ~= rightCrop then
			return leftCrop < rightCrop
		end

		local leftRarity = get_rarity_sort(left)
		local rightRarity = get_rarity_sort(right)
		if leftRarity ~= rightRarity then
			return leftRarity < rightRarity
		end

		return (left.DisplayName or left.ItemId) < (right.DisplayName or right.ItemId)
	end)

	return items
end

local function get_parts(root)
	local parts = {}

	if root:IsA("BasePart") then
		parts[#parts + 1] = root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts[#parts + 1] = descendant
		end
	end

	return parts
end

local function get_bounds(root)
	local minVector = Vector3.new(math.huge, math.huge, math.huge)
	local maxVector = Vector3.new(-math.huge, -math.huge, -math.huge)
	local foundPart = false

	for _, part in ipairs(get_parts(root)) do
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

	if not foundPart then
		return nil, nil
	end

	return (minVector + maxVector) * 0.5, maxVector - minVector
end

local function clear_viewport()
	if not viewportFrame then
		return
	end

	for _, child in ipairs(viewportFrame:GetChildren()) do
		child:Destroy()
	end

	viewportFrame.CurrentCamera = nil
end

local function rotate_parts_around(root, center, rotation)
	local origin = CFrame.new(center)

	for _, part in ipairs(get_parts(root)) do
		part.CFrame = origin * rotation * origin:ToObjectSpace(part.CFrame)
	end
end

local function get_current_item()
	return fruitItems[currentIndex]
end

local function get_current_settings()
	local itemDefinition = get_current_item()
	if not itemDefinition then
		return nil
	end

	local settings = itemSettings[itemDefinition.ItemId]
	if not settings then
		settings = {
			RotationY = 0,
			DistanceScale = 1,
		}
		itemSettings[itemDefinition.ItemId] = settings
	end

	return settings
end

local function set_status(text)
	if statusLabel then
		statusLabel.Text = text or ""
	end
end

local function update_labels()
	local itemDefinition = get_current_item()
	if not itemDefinition then
		if itemNameLabel then
			itemNameLabel.Text = "No fruits found"
		end

		if itemCountLabel then
			itemCountLabel.Text = "0 / 0"
		end

		if zoomLabel then
			zoomLabel.Text = "Zoom 100%"
		end

		return
	end

	local settings = get_current_settings()
	if itemNameLabel then
		itemNameLabel.Text = itemDefinition.DisplayName or itemDefinition.ItemId
	end

	if itemCountLabel then
		itemCountLabel.Text = ("%02d / %02d"):format(currentIndex, #fruitItems)
	end

	if zoomLabel and settings then
		zoomLabel.Text = ("Zoom %d%%"):format(math.floor((1 / settings.DistanceScale) * 100 + 0.5))
	end
end

local function get_camera_up_vector(cameraCFrame, direction)
	local upVector = cameraCFrame.UpVector

	if math.abs(direction:Dot(upVector)) > 0.96 then
		return Vector3.new(0, 0, -1)
	end

	return upVector
end

local function render_current_item()
	if not viewportFrame then
		return
	end

	local itemDefinition = get_current_item()
	clear_viewport()
	update_labels()

	if not itemDefinition then
		set_status("Nenhum vegetal/fruta encontrado em ToolItems/Fruits.")
		return
	end

	local cachedViewport = FarmingShopViewportCache.Get(itemDefinition)
	if not cachedViewport then
		set_status("Modelo nao encontrado: " .. tostring(itemDefinition.ItemId))
		return
	end

	local settings = get_current_settings()
	if not settings then
		return
	end

	local worldModel = create("WorldModel", {
		Name = "CaptureWorldModel",
		Parent = viewportFrame,
	})

	local modelClone = cachedViewport.Template:Clone()
	modelClone.Parent = worldModel

	local center = get_bounds(modelClone)
	if not center then
		set_status("Modelo sem BasePart: " .. tostring(itemDefinition.ItemId))
		clear_viewport()
		return
	end

	if math.abs(settings.RotationY) > 0.0001 then
		rotate_parts_around(modelClone, center, CFrame.Angles(0, settings.RotationY, 0))
		center = get_bounds(modelClone) or center
	end

	local camera = create("Camera", {
		Name = "CaptureCamera",
		FieldOfView = cachedViewport.FieldOfView or 35,
		Parent = viewportFrame,
	})

	local cameraCFrame = cachedViewport.CameraCFrame
	local direction = cameraCFrame.Position - center
	if direction.Magnitude < 0.001 then
		direction = Vector3.new(0.45, 0.2, 1)
	end

	local unitDirection = direction.Unit
	local distance = math.max(0.1, direction.Magnitude * settings.DistanceScale)
	local cameraPosition = center + unitDirection * distance
	camera.CFrame = CFrame.lookAt(cameraPosition, center, get_camera_up_vector(cameraCFrame, unitDirection))

	viewportFrame.CurrentCamera = camera
	viewportFrame.BackgroundTransparency = 1
	viewportFrame.Ambient = Color3.fromRGB(220, 220, 220)
	viewportFrame.LightColor = Color3.fromRGB(255, 255, 255)

	CropRarityUtility.ApplyToViewport(viewportFrame, itemDefinition)
	set_status("")
	update_labels()
end

local function show_index(index)
	if #fruitItems == 0 then
		currentIndex = 1
	else
		currentIndex = ((index - 1) % #fruitItems) + 1
	end

	render_current_item()
end

local function next_item()
	show_index(currentIndex + 1)
end

local function previous_item()
	show_index(currentIndex - 1)
end

local function rotate_current(direction)
	local settings = get_current_settings()
	if not settings then
		return
	end

	settings.RotationY += ROTATE_STEP * direction
	render_current_item()
end

local function zoom_current(multiplier)
	local settings = get_current_settings()
	if not settings then
		return
	end

	settings.DistanceScale = math.clamp(settings.DistanceScale * multiplier, MIN_DISTANCE_SCALE, MAX_DISTANCE_SCALE)
	render_current_item()
end

local function reset_current()
	local itemDefinition = get_current_item()
	if itemDefinition then
		itemSettings[itemDefinition.ItemId] = nil
	end

	render_current_item()
end

local function create_button(parent, text, position, size, callback)
	local button = create("TextButton", {
		Name = string.gsub(text, "%s+", "") .. "BT",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(24, 28, 34),
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = position,
		Size = size,
		Text = text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		ZIndex = 20,
		Parent = parent,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = button,
	})

	create("UITextSizeConstraint", {
		MaxTextSize = 22,
		MinTextSize = 10,
		Parent = button,
	})

	button.Activated:Connect(callback)
	return button
end

local function build_gui()
	if captureGui then
		return
	end

	captureGui = create("ScreenGui", {
		Name = SCREEN_GUI_NAME,
		Enabled = false,
		IgnoreGuiInset = true,
		DisplayOrder = 100000,
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = playerGui,
	})
	captureGui:SetAttribute(IGNORE_HUD_ANIM_ATTRIBUTE, true)

	local root = create("Frame", {
		Name = "Root",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
		Parent = captureGui,
	})
	root:SetAttribute(IGNORE_HUD_ANIM_ATTRIBUTE, true)

	create("ImageLabel", {
		Name = "CaptureBackground",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = BACKGROUND_IMAGE,
		Position = CAPTURE_CENTER,
		ScaleType = Enum.ScaleType.Fit,
		Size = BACKGROUND_SIZE,
		ZIndex = 2,
		Parent = root,
	})

	viewportFrame = create("ViewportFrame", {
		Name = "FruitViewport",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = CAPTURE_CENTER,
		Size = VIEWPORT_SIZE,
		ZIndex = 5,
		Parent = root,
	})
	create("UIAspectRatioConstraint", {
		AspectRatio = 1,
		Parent = viewportFrame,
	})

	itemNameLabel = create("TextLabel", {
		Name = "ItemName",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(12, 14, 18),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.5, 0.055),
		Size = UDim2.fromScale(0.34, 0.045),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextScaled = true,
		ZIndex = 20,
		Parent = root,
	})
	create("UICorner", {
		CornerRadius = UDim.new(0, 8),
		Parent = itemNameLabel,
	})
	create("UITextSizeConstraint", {
		MaxTextSize = 26,
		MinTextSize = 10,
		Parent = itemNameLabel,
	})

	itemCountLabel = create("TextLabel", {
		Name = "ItemCount",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.5, 0.101),
		Size = UDim2.fromScale(0.2, 0.032),
		Text = "",
		TextColor3 = Color3.fromRGB(225, 230, 238),
		TextScaled = true,
		ZIndex = 20,
		Parent = root,
	})
	create("UITextSizeConstraint", {
		MaxTextSize = 18,
		MinTextSize = 9,
		Parent = itemCountLabel,
	})

	statusLabel = create("TextLabel", {
		Name = "Status",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(0.5, 0.04),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 214, 105),
		TextScaled = true,
		ZIndex = 20,
		Parent = root,
	})
	create("UITextSizeConstraint", {
		MaxTextSize = 18,
		MinTextSize = 8,
		Parent = statusLabel,
	})

	local controls = create("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.94),
		Size = UDim2.fromScale(0.72, 0.06),
		ZIndex = 15,
		Parent = root,
	})

	create_button(controls, "Prev", UDim2.fromScale(0.06, 0.5), UDim2.fromScale(0.1, 0.9), previous_item)
	create_button(controls, "Next", UDim2.fromScale(0.17, 0.5), UDim2.fromScale(0.1, 0.9), next_item)
	create_button(controls, "Zoom +", UDim2.fromScale(0.31, 0.5), UDim2.fromScale(0.12, 0.9), function()
		zoom_current(ZOOM_IN_MULTIPLIER)
	end)
	create_button(controls, "Zoom -", UDim2.fromScale(0.44, 0.5), UDim2.fromScale(0.12, 0.9), function()
		zoom_current(ZOOM_OUT_MULTIPLIER)
	end)
	create_button(controls, "Rotate L", UDim2.fromScale(0.59, 0.5), UDim2.fromScale(0.13, 0.9), function()
		rotate_current(-1)
	end)
	create_button(controls, "Rotate R", UDim2.fromScale(0.73, 0.5), UDim2.fromScale(0.13, 0.9), function()
		rotate_current(1)
	end)
	create_button(controls, "Reset", UDim2.fromScale(0.87, 0.5), UDim2.fromScale(0.11, 0.9), reset_current)
	create_button(controls, "Close", UDim2.fromScale(0.98, 0.5), UDim2.fromScale(0.1, 0.9), function()
		captureGui.Enabled = false
	end)

	zoomLabel = create("TextLabel", {
		Name = "ZoomLabel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Position = UDim2.fromScale(0.5, 0.895),
		Size = UDim2.fromScale(0.2, 0.03),
		Text = "Zoom 100%",
		TextColor3 = Color3.fromRGB(225, 230, 238),
		TextScaled = true,
		ZIndex = 20,
		Parent = root,
	})
	create("UITextSizeConstraint", {
		MaxTextSize = 16,
		MinTextSize = 8,
		Parent = zoomLabel,
	})
end

local function open_capture_gui()
	build_gui()
	fruitItems = collect_fruit_items()

	if currentIndex > #fruitItems then
		currentIndex = 1
	end

	captureGui.Enabled = true
	render_current_item()
end

local function toggle_capture_gui()
	build_gui()

	if captureGui.Enabled then
		captureGui.Enabled = false
	else
		open_capture_gui()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.K then
		toggle_capture_gui()
	elseif captureGui and captureGui.Enabled then
		if input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.D then
			next_item()
		elseif input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.A then
			previous_item()
		elseif input.KeyCode == Enum.KeyCode.Q then
			rotate_current(-1)
		elseif input.KeyCode == Enum.KeyCode.E then
			rotate_current(1)
		elseif input.KeyCode == Enum.KeyCode.Z then
			zoom_current(ZOOM_IN_MULTIPLIER)
		elseif input.KeyCode == Enum.KeyCode.X then
			zoom_current(ZOOM_OUT_MULTIPLIER)
		elseif input.KeyCode == Enum.KeyCode.R then
			reset_current()
		end
	end
end)
