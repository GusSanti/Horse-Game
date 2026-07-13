-- Paste this entire file into Roblox Studio's Command Bar while NOT playing.
-- It creates editable previews in Workspace.HorseToolModels and runtime templates
-- in ReplicatedStorage.Assets.Items, using the metadata already defined by the game.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local ChangeHistoryService = game:GetService("ChangeHistoryService")

assert(not game:GetService("RunService"):IsRunning(), "Run this from Studio edit mode, not during Play mode.")

local ToolItemCatalog = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameData"):WaitForChild("ToolItemCatalog")
)

ChangeHistoryService:SetWaypoint("Before generating horse Tool models")

local PREVIEW_FOLDER_NAME = "HorseToolModels"
local GENERATED_ATTRIBUTE = "GeneratedHorseToolAsset"
local INCLUDED_CATEGORIES = {
	Food = true,
	Water = true,
	Grooming = true,
	Misc = true,
	Medicine = true,
	Tack = true,
}

local WHITE = Color3.fromRGB(242, 239, 229)
local DARK = Color3.fromRGB(62, 57, 52)
local METAL = Color3.fromRGB(125, 137, 144)
local WATER = Color3.fromRGB(80, 176, 229)
local WOOD = Color3.fromRGB(115, 75, 47)

local styles = {
	-- Food
	hay_bale = { kind = "bale", main = Color3.fromRGB(210, 174, 76), accent = Color3.fromRGB(106, 76, 43) },
	apple_treat = { kind = "apple", main = Color3.fromRGB(204, 61, 55), accent = Color3.fromRGB(75, 126, 67) },
	carrot_bunch = { kind = "carrots", main = Color3.fromRGB(232, 126, 43), accent = Color3.fromRGB(77, 139, 73) },
	apple_fruit = { kind = "apple", main = Color3.fromRGB(220, 68, 56), accent = Color3.fromRGB(77, 139, 73) },
	carrot_fruit = { kind = "carrots", main = Color3.fromRGB(239, 137, 45), accent = Color3.fromRGB(79, 145, 73), single = true },
	mint_treat = { kind = "pouch", main = Color3.fromRGB(111, 170, 108), accent = Color3.fromRGB(213, 235, 169) },
	oat_crunch = { kind = "pouch", main = Color3.fromRGB(202, 167, 104), accent = Color3.fromRGB(246, 220, 151) },
	clover_mix = { kind = "pouch", main = Color3.fromRGB(83, 145, 77), accent = Color3.fromRGB(185, 215, 116) },
	beet_pellets = { kind = "bowl", main = Color3.fromRGB(126, 73, 61), accent = Color3.fromRGB(107, 45, 66) },
	berry_mash = { kind = "bowl", main = Color3.fromRGB(105, 68, 127), accent = Color3.fromRGB(174, 76, 128) },
	grain_scoop = { kind = "scoop", main = Color3.fromRGB(185, 145, 76), accent = Color3.fromRGB(238, 194, 91) },
	meadow_supper = { kind = "bowl", main = Color3.fromRGB(90, 119, 70), accent = Color3.fromRGB(196, 174, 76) },

	-- Water
	fresh_bucket = { kind = "bucket", main = METAL, accent = WATER },
	cool_stream = { kind = "bucket", main = Color3.fromRGB(102, 151, 164), accent = Color3.fromRGB(102, 211, 226) },
	mint_infusion = { kind = "bottle", main = Color3.fromRGB(106, 183, 155), accent = Color3.fromRGB(202, 239, 196) },
	apple_splash = { kind = "bottle", main = Color3.fromRGB(197, 92, 75), accent = Color3.fromRGB(242, 184, 111) },
	spring_water = { kind = "bottle", main = Color3.fromRGB(72, 150, 202), accent = Color3.fromRGB(180, 229, 242) },
	rain_barrel = { kind = "bucket", main = WOOD, accent = Color3.fromRGB(89, 156, 190) },
	electrolyte_mix = { kind = "bottle", main = Color3.fromRGB(222, 139, 65), accent = Color3.fromRGB(249, 219, 125) },
	herbal_cooler = { kind = "bottle", main = Color3.fromRGB(92, 139, 104), accent = Color3.fromRGB(181, 211, 151) },
	glacier_sip = { kind = "bottle", main = Color3.fromRGB(113, 190, 219), accent = Color3.fromRGB(225, 248, 250) },
	golden_trough = { kind = "trough", main = Color3.fromRGB(191, 145, 53), accent = Color3.fromRGB(79, 177, 218) },

	-- Grooming, medicine, misc and tack
	soft_brush = { kind = "brush", main = Color3.fromRGB(188, 121, 139), accent = Color3.fromRGB(238, 205, 190) },
	grooming_kit = { kind = "kit", main = Color3.fromRGB(112, 78, 61), accent = Color3.fromRGB(213, 151, 155) },
	shine_kit = { kind = "kit", main = Color3.fromRGB(190, 148, 61), accent = Color3.fromRGB(245, 221, 144) },
	basic_bandage = { kind = "bandage", main = WHITE, accent = Color3.fromRGB(194, 66, 60) },
	herbal_poultice = { kind = "jar", main = Color3.fromRGB(108, 139, 83), accent = Color3.fromRGB(204, 218, 157) },
	bitter_syrup = { kind = "bottle", main = Color3.fromRGB(111, 68, 48), accent = Color3.fromRGB(224, 184, 98) },
	digestive_relief = { kind = "kit", main = Color3.fromRGB(83, 137, 145), accent = Color3.fromRGB(209, 230, 195) },
	recovery_tonic = { kind = "bottle", main = Color3.fromRGB(114, 77, 151), accent = Color3.fromRGB(218, 174, 228) },
	soap = { kind = "soap", main = Color3.fromRGB(236, 193, 204), accent = Color3.fromRGB(250, 235, 211) },
	horse_brush = { kind = "brush", main = Color3.fromRGB(118, 76, 51), accent = Color3.fromRGB(226, 188, 130) },
	starter_bridle = { kind = "bridle", main = Color3.fromRGB(84, 56, 43), accent = Color3.fromRGB(184, 145, 74) },
	starter_saddle = { kind = "saddle", main = Color3.fromRGB(103, 65, 44), accent = Color3.fromRGB(191, 146, 76) },
}

local function part(tool, handle, name, size, relativeCFrame, color, shape, material)
	local object = Instance.new("Part")
	object.Name = name
	object.Size = size
	object.CFrame = handle.CFrame * relativeCFrame
	object.Color = color
	object.Shape = shape or Enum.PartType.Block
	object.Material = material or Enum.Material.SmoothPlastic
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.Anchored = false
	object.CanCollide = false
	object.CanTouch = false
	object.CanQuery = false
	object.Massless = true
	object.CastShadow = true
	object.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Name = "VisualWeld"
	weld.Part0 = handle
	weld.Part1 = object
	weld.Parent = object
	return object
end

local function block(tool, handle, name, size, position, color, rotation, material)
	return part(tool, handle, name, size, CFrame.new(position) * (rotation or CFrame.identity), color, nil, material)
end

local function ball(tool, handle, name, size, position, color, material)
	return part(tool, handle, name, size, CFrame.new(position), color, Enum.PartType.Ball, material)
end

local function cylinder(tool, handle, name, size, position, color, rotation, material)
	return part(
		tool,
		handle,
		name,
		size,
		CFrame.new(position) * (rotation or CFrame.identity),
		color,
		Enum.PartType.Cylinder,
		material
	)
end

local verticalCylinder = CFrame.Angles(0, 0, math.rad(90))

local builders = {}

function builders.bale(tool, handle, style)
	block(tool, handle, "Hay", Vector3.new(2.2, 1.25, 1.35), Vector3.zero, style.main, nil, Enum.Material.Fabric)
	for _, x in ipairs({ -0.62, 0.62 }) do
		block(tool, handle, "Twine", Vector3.new(0.14, 1.34, 1.42), Vector3.new(x, 0, 0), style.accent)
	end
	block(tool, handle, "StrawTop", Vector3.new(1.7, 0.12, 0.8), Vector3.new(0, 0.68, 0), Color3.fromRGB(231, 199, 102))
end

function builders.apple(tool, handle, style)
	ball(tool, handle, "Fruit", Vector3.new(1.45, 1.35, 1.45), Vector3.new(0, 0, 0), style.main)
	cylinder(tool, handle, "Stem", Vector3.new(0.16, 0.52, 0.16), Vector3.new(0, 0.78, 0), WOOD, verticalCylinder)
	block(tool, handle, "Leaf", Vector3.new(0.58, 0.1, 0.3), Vector3.new(0.28, 0.9, 0), style.accent, CFrame.Angles(0, math.rad(25), math.rad(-18)))
end

function builders.carrots(tool, handle, style)
	local offsets = style.single and { 0 } or { -0.42, 0, 0.42 }
	for index, x in ipairs(offsets) do
		local angle = math.rad((index - 2) * 12)
		cylinder(tool, handle, "Carrot", Vector3.new(1.35, 0.38, 0.38), Vector3.new(x, -0.1, 0), style.main, CFrame.Angles(0, 0, math.rad(90) + angle))
		for leafIndex = -1, 1 do
			block(tool, handle, "Leaf", Vector3.new(0.12, 0.72, 0.2), Vector3.new(x + leafIndex * 0.1, 0.72, 0), style.accent, CFrame.Angles(0, 0, math.rad(leafIndex * 16)))
		end
	end
end

function builders.pouch(tool, handle, style)
	block(tool, handle, "Bag", Vector3.new(1.45, 1.65, 0.72), Vector3.new(0, -0.05, 0), style.main, nil, Enum.Material.Fabric)
	block(tool, handle, "Fold", Vector3.new(1.2, 0.25, 0.76), Vector3.new(0, 0.87, 0), DARK)
	ball(tool, handle, "Label", Vector3.new(0.58, 0.58, 0.12), Vector3.new(0, 0, -0.4), style.accent)
	block(tool, handle, "LeafMark", Vector3.new(0.28, 0.08, 0.15), Vector3.new(0.08, 0.08, -0.48), Color3.fromRGB(67, 105, 58), CFrame.Angles(0, 0, math.rad(25)))
end

function builders.bowl(tool, handle, style)
	cylinder(tool, handle, "Bowl", Vector3.new(0.65, 1.85, 1.85), Vector3.new(0, -0.28, 0), style.main, verticalCylinder)
	cylinder(tool, handle, "Food", Vector3.new(0.15, 1.55, 1.55), Vector3.new(0, 0.08, 0), style.accent, verticalCylinder, Enum.Material.Fabric)
	for _, offset in ipairs({ Vector3.new(-0.35, 0.2, -0.2), Vector3.new(0.32, 0.19, 0.18), Vector3.new(0, 0.22, 0.35) }) do
		ball(tool, handle, "FoodPiece", Vector3.new(0.28, 0.2, 0.28), offset, style.accent)
	end
end

function builders.scoop(tool, handle, style)
	cylinder(tool, handle, "Grip", Vector3.new(1.8, 0.28, 0.28), Vector3.new(0.55, -0.05, 0), WOOD)
	cylinder(tool, handle, "Scoop", Vector3.new(0.7, 1.15, 1.15), Vector3.new(-0.65, -0.05, 0), style.main, verticalCylinder)
	cylinder(tool, handle, "Grain", Vector3.new(0.12, 0.9, 0.9), Vector3.new(-0.65, 0.34, 0), style.accent, verticalCylinder)
end

function builders.bucket(tool, handle, style)
	cylinder(tool, handle, "Bucket", Vector3.new(1.35, 1.55, 1.55), Vector3.new(0, -0.12, 0), style.main, verticalCylinder, style.main == WOOD and Enum.Material.Wood or Enum.Material.Metal)
	cylinder(tool, handle, "Water", Vector3.new(0.12, 1.32, 1.32), Vector3.new(0, 0.59, 0), style.accent, verticalCylinder, Enum.Material.Glass)
	block(tool, handle, "HandleLeft", Vector3.new(0.12, 1.1, 0.12), Vector3.new(-0.86, 0.65, 0), DARK)
	block(tool, handle, "HandleRight", Vector3.new(0.12, 1.1, 0.12), Vector3.new(0.86, 0.65, 0), DARK)
	block(tool, handle, "HandleTop", Vector3.new(1.84, 0.12, 0.12), Vector3.new(0, 1.18, 0), DARK)
end

function builders.bottle(tool, handle, style)
	cylinder(tool, handle, "Bottle", Vector3.new(1.35, 0.9, 0.9), Vector3.new(0, -0.18, 0), style.main, verticalCylinder, Enum.Material.Glass)
	cylinder(tool, handle, "Neck", Vector3.new(0.42, 0.45, 0.45), Vector3.new(0, 0.68, 0), style.main, verticalCylinder, Enum.Material.Glass)
	cylinder(tool, handle, "Cap", Vector3.new(0.2, 0.5, 0.5), Vector3.new(0, 1, 0), style.accent, verticalCylinder, Enum.Material.Metal)
	block(tool, handle, "Label", Vector3.new(0.55, 0.62, 0.08), Vector3.new(0, -0.08, -0.48), style.accent)
	block(tool, handle, "LabelMark", Vector3.new(0.3, 0.09, 0.09), Vector3.new(0, -0.08, -0.54), WHITE)
end

function builders.trough(tool, handle, style)
	block(tool, handle, "Base", Vector3.new(2.3, 0.65, 1.25), Vector3.new(0, -0.25, 0), style.main, nil, Enum.Material.Metal)
	block(tool, handle, "Water", Vector3.new(1.85, 0.12, 0.85), Vector3.new(0, 0.12, 0), style.accent, nil, Enum.Material.Glass)
	for _, x in ipairs({ -0.85, 0.85 }) do
		block(tool, handle, "Leg", Vector3.new(0.22, 0.65, 0.8), Vector3.new(x, -0.75, 0), DARK)
	end
end

function builders.brush(tool, handle, style)
	block(tool, handle, "BrushBack", Vector3.new(1.6, 0.42, 0.78), Vector3.new(0, 0.1, 0), style.main, nil, Enum.Material.Wood)
	block(tool, handle, "Grip", Vector3.new(1.05, 0.25, 0.35), Vector3.new(1.08, 0.15, 0), style.main, CFrame.Angles(0, 0, math.rad(8)), Enum.Material.Wood)
	for _, x in ipairs({ -0.55, -0.18, 0.18, 0.55 }) do
		block(tool, handle, "Bristles", Vector3.new(0.16, 0.4, 0.55), Vector3.new(x, -0.28, 0), style.accent, nil, Enum.Material.Fabric)
	end
end

function builders.kit(tool, handle, style)
	block(tool, handle, "Case", Vector3.new(1.65, 1.18, 0.62), Vector3.new(0, -0.1, 0), style.main)
	block(tool, handle, "CaseBand", Vector3.new(1.72, 0.12, 0.68), Vector3.new(0, 0.15, 0), style.accent)
	block(tool, handle, "Latch", Vector3.new(0.32, 0.28, 0.12), Vector3.new(0, -0.05, -0.38), style.accent, nil, Enum.Material.Metal)
	block(tool, handle, "HandleTop", Vector3.new(0.72, 0.16, 0.16), Vector3.new(0, 0.76, 0), DARK)
	for _, x in ipairs({ -0.36, 0.36 }) do
		block(tool, handle, "HandleSide", Vector3.new(0.14, 0.42, 0.14), Vector3.new(x, 0.58, 0), DARK)
	end
end

function builders.bandage(tool, handle, style)
	cylinder(tool, handle, "BandageRoll", Vector3.new(1.05, 1.15, 1.15), Vector3.zero, style.main, nil, Enum.Material.Fabric)
	cylinder(tool, handle, "Core", Vector3.new(1.12, 0.4, 0.4), Vector3.zero, DARK)
	block(tool, handle, "CrossVertical", Vector3.new(0.1, 0.62, 0.2), Vector3.new(-0.58, 0, 0), style.accent)
	block(tool, handle, "CrossHorizontal", Vector3.new(0.1, 0.2, 0.62), Vector3.new(-0.58, 0, 0), style.accent)
end

function builders.jar(tool, handle, style)
	cylinder(tool, handle, "Jar", Vector3.new(1.05, 1.05, 1.05), Vector3.new(0, -0.15, 0), style.main, verticalCylinder, Enum.Material.Glass)
	cylinder(tool, handle, "Lid", Vector3.new(0.22, 1.12, 1.12), Vector3.new(0, 0.5, 0), style.accent, verticalCylinder, Enum.Material.Metal)
	block(tool, handle, "Label", Vector3.new(0.55, 0.48, 0.08), Vector3.new(0, -0.12, -0.57), style.accent)
	for _, x in ipairs({ -0.2, 0.05, 0.22 }) do
		block(tool, handle, "Herb", Vector3.new(0.1, 0.42, 0.12), Vector3.new(x, 0.08, -0.63), Color3.fromRGB(55, 104, 61), CFrame.Angles(0, 0, math.rad(x * 80)))
	end
end

function builders.soap(tool, handle, style)
	block(tool, handle, "SoapBar", Vector3.new(1.5, 0.7, 0.95), Vector3.zero, style.main)
	block(tool, handle, "Inset", Vector3.new(0.72, 0.08, 0.38), Vector3.new(0, 0.39, 0), style.accent)
	for index, offset in ipairs({ Vector3.new(-0.55, 0.58, 0), Vector3.new(0.55, 0.72, 0.12), Vector3.new(0.2, 0.62, -0.35) }) do
		ball(tool, handle, "Bubble" .. index, Vector3.new(0.28, 0.28, 0.28), offset, WHITE, Enum.Material.Glass)
	end
end

function builders.bridle(tool, handle, style)
	for _, x in ipairs({ -0.48, 0.48 }) do
		block(tool, handle, "LeatherStrap", Vector3.new(0.16, 1.65, 0.18), Vector3.new(x, 0, 0), style.main, CFrame.Angles(0, 0, math.rad(x * 20)), Enum.Material.Fabric)
	end
	block(tool, handle, "BrowBand", Vector3.new(1.15, 0.16, 0.18), Vector3.new(0, 0.58, 0), style.main, nil, Enum.Material.Fabric)
	block(tool, handle, "Bit", Vector3.new(1.2, 0.12, 0.12), Vector3.new(0, -0.62, 0), style.accent, nil, Enum.Material.Metal)
	for _, x in ipairs({ -0.68, 0.68 }) do
		cylinder(tool, handle, "Ring", Vector3.new(0.12, 0.4, 0.4), Vector3.new(x, -0.62, 0), style.accent, nil, Enum.Material.Metal)
	end
end

function builders.saddle(tool, handle, style)
	block(tool, handle, "Seat", Vector3.new(1.8, 0.48, 1.15), Vector3.new(0, 0.15, 0), style.main, nil, Enum.Material.Fabric)
	block(tool, handle, "Pommel", Vector3.new(0.35, 0.72, 0.7), Vector3.new(-0.7, 0.55, 0), style.main, CFrame.Angles(0, 0, math.rad(-10)), Enum.Material.Fabric)
	block(tool, handle, "Blanket", Vector3.new(1.95, 0.16, 1.35), Vector3.new(0.08, -0.18, 0), style.accent, nil, Enum.Material.Fabric)
	for _, x in ipairs({ -0.58, 0.58 }) do
		block(tool, handle, "StirrupStrap", Vector3.new(0.12, 0.95, 0.12), Vector3.new(x, -0.62, 0), style.main, nil, Enum.Material.Fabric)
		block(tool, handle, "Stirrup", Vector3.new(0.45, 0.12, 0.32), Vector3.new(x, -1.08, 0), style.accent, nil, Enum.Material.Metal)
	end
end

local function createTool(itemDefinition, previewCFrame)
	local style = styles[itemDefinition.ItemId]
	assert(style, ("Missing visual style for %s"):format(itemDefinition.ItemId))

	local tool = Instance.new("Tool")
	tool.Name = itemDefinition.DisplayName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = itemDefinition.ToolTip or itemDefinition.Description or ""
	tool.Grip = CFrame.new(0, -0.25, 0) * CFrame.Angles(0, math.rad(90), 0)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 0.3)
	handle.CFrame = previewCFrame
	handle.Transparency = 1
	handle.Anchored = true
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool

	builders[style.kind](tool, handle, style)
	ToolItemCatalog.ApplyToolMetadata(tool, itemDefinition)
	tool:SetAttribute(GENERATED_ATTRIBUTE, true)
	tool:SetAttribute("VisualStyle", style.kind)
	return tool
end

local oldPreviewFolder = Workspace:FindFirstChild(PREVIEW_FOLDER_NAME)
if oldPreviewFolder then
	oldPreviewFolder:Destroy()
end

local previewFolder = Instance.new("Folder")
previewFolder.Name = PREVIEW_FOLDER_NAME
previewFolder:SetAttribute(GENERATED_ATTRIBUTE, true)
previewFolder.Parent = Workspace

local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
if not assetsFolder then
	assetsFolder = Instance.new("Folder")
	assetsFolder.Name = "Assets"
	assetsFolder.Parent = ReplicatedStorage
end

local itemsFolder = assetsFolder:FindFirstChild("Items")
if not itemsFolder then
	itemsFolder = Instance.new("Folder")
	itemsFolder.Name = "Items"
	itemsFolder.Parent = assetsFolder
end

local categoryRows = { Food = 0, Water = 1, Grooming = 2, Misc = 3, Medicine = 4, Tack = 5 }
local itemIndexByCategory = {}
local generatedCount = 0

for _, itemDefinition in ipairs(ToolItemCatalog.GetAllItems()) do
	local category = itemDefinition.ToolCategory
	if INCLUDED_CATEGORIES[category] and styles[itemDefinition.ItemId] then
		local previewCategory = previewFolder:FindFirstChild(category)
		if not previewCategory then
			previewCategory = Instance.new("Folder")
			previewCategory.Name = category
			previewCategory.Parent = previewFolder
		end

		local assetCategory = itemsFolder:FindFirstChild(category)
		if not assetCategory then
			assetCategory = Instance.new("Folder")
			assetCategory.Name = category
			assetCategory.Parent = itemsFolder
		end

		itemIndexByCategory[category] = (itemIndexByCategory[category] or 0) + 1
		local column = itemIndexByCategory[category]
		local row = categoryRows[category] or 0
		local previewCFrame = CFrame.new((column - 1) * 4, 5, row * 4)
		local tool = createTool(itemDefinition, previewCFrame)
		tool.Parent = previewCategory

		local replacementNames = {}
		for _, searchName in ipairs({ itemDefinition.ToolName, itemDefinition.DisplayName, itemDefinition.ItemId }) do
			if type(searchName) == "string" and searchName ~= "" then
				replacementNames[searchName] = true
			end
		end
		for _, existing in ipairs(assetCategory:GetDescendants()) do
			if existing:IsA("Tool") and replacementNames[existing.Name] then
				existing:Destroy()
			end
		end

		local runtimeTool = tool:Clone()
		local runtimeHandle = runtimeTool:FindFirstChild("Handle")
		if runtimeHandle and runtimeHandle:IsA("BasePart") then
			runtimeHandle.Anchored = false
		end
		runtimeTool.Parent = assetCategory
		generatedCount += 1
	end
end

ChangeHistoryService:SetWaypoint("Generated horse Tool models")
print(("[HorseToolModels] Created %d configured Tools in Workspace.%s and ReplicatedStorage.Assets.Items"):format(
	generatedCount,
	PREVIEW_FOLDER_NAME
))
