-- Paste this entire file into Roblox Studio's Command Bar while NOT playing.
-- It creates editable previews in Workspace.StableCleaningAssetPreview and installs
-- runtime assets in ReplicatedStorage.Assets.Items.Misc and Assets.StableCleaning.Dirt.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

assert(not RunService:IsRunning(), "Run this command from Studio edit mode, not during Play mode.")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local StableCleaningConfig = require(GameData:WaitForChild("StableCleaningConfig"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local GENERATED_ATTRIBUTE = "GeneratedStableCleaningAsset"
local PREVIEW_FOLDER_NAME = "StableCleaningAssetPreview"

local COLORS = {
	DarkWood = Color3.fromRGB(85, 55, 36),
	Wood = Color3.fromRGB(173, 119, 62),
	Metal = Color3.fromRGB(111, 128, 137),
	DarkMetal = Color3.fromRGB(65, 76, 82),
	Straw = Color3.fromRGB(222, 181, 75),
	StrawLight = Color3.fromRGB(242, 213, 118),
	Water = Color3.fromRGB(75, 181, 224),
	Bucket = Color3.fromRGB(46, 154, 174),
	Mud = Color3.fromRGB(91, 61, 40),
	MudLight = Color3.fromRGB(126, 86, 53),
	Manure = Color3.fromRGB(74, 52, 34),
	Fly = Color3.fromRGB(31, 34, 31),
}

local function get_or_create_folder(parent: Instance, name: string): Folder
	local folder = parent:FindFirstChild(name)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

local function remove_matching_tools(folder: Instance, itemDefinition)
	for _, descendant in ipairs(folder:GetDescendants()) do
		if descendant:IsA("Tool")
			and (
				descendant:GetAttribute("ToolItemId") == itemDefinition.ItemId
				or descendant.Name == itemDefinition.DisplayName
				or descendant.Name == itemDefinition.ItemId
			)
		then
			descendant:Destroy()
		end
	end
end

local function add_tool_part(
	tool: Tool,
	handle: BasePart,
	name: string,
	size: Vector3,
	relativeCFrame: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local object = Instance.new("Part")
	object.Name = name
	object.Size = size
	object.CFrame = handle.CFrame * relativeCFrame
	object.Color = color
	object.Material = material or Enum.Material.SmoothPlastic
	object.Shape = shape or Enum.PartType.Block
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.Anchored = false
	object.CanCollide = false
	object.CanTouch = false
	object.CanQuery = false
	object.Massless = true
	object.Parent = tool

	local weld = Instance.new("WeldConstraint")
	weld.Name = "VisualWeld"
	weld.Part0 = handle
	weld.Part1 = object
	weld.Parent = object

	return object
end

local function block(tool, handle, name, size, position, color, rotation, material)
	return add_tool_part(
		tool,
		handle,
		name,
		size,
		CFrame.new(position) * (rotation or CFrame.identity),
		color,
		material,
		Enum.PartType.Block
	)
end

local function cylinder(tool, handle, name, size, position, color, rotation, material)
	return add_tool_part(
		tool,
		handle,
		name,
		size,
		CFrame.new(position) * (rotation or CFrame.identity),
		color,
		material,
		Enum.PartType.Cylinder
	)
end

local verticalCylinder = CFrame.Angles(0, 0, math.rad(90))

local function build_broom(tool: Tool, handle: BasePart)
	cylinder(
		tool,
		handle,
		"Shaft",
		Vector3.new(4.4, 0.22, 0.22),
		Vector3.new(0, 0.7, 0),
		COLORS.Wood,
		verticalCylinder,
		Enum.Material.Wood
	)
	block(tool, handle, "BroomHead", Vector3.new(1.7, 0.3, 0.48), Vector3.new(0, -1.5, 0), COLORS.DarkWood, nil, Enum.Material.Wood)

	for index = -4, 4 do
		local x = index * 0.18
		block(
			tool,
			handle,
			"Bristle",
			Vector3.new(0.12, 0.78, 0.28),
			Vector3.new(x, -2.02, 0),
			if index % 2 == 0 then COLORS.Straw else COLORS.StrawLight,
			CFrame.Angles(0, 0, math.rad(index * 1.5)),
			Enum.Material.Fabric
		)
	end
end

local function build_fork(tool: Tool, handle: BasePart)
	cylinder(
		tool,
		handle,
		"Shaft",
		Vector3.new(4.5, 0.2, 0.2),
		Vector3.new(0, 0.65, 0),
		COLORS.Wood,
		verticalCylinder,
		Enum.Material.Wood
	)
	block(tool, handle, "ForkHead", Vector3.new(1.55, 0.2, 0.22), Vector3.new(0, -1.52, 0), COLORS.DarkMetal, nil, Enum.Material.Metal)

	for index = -3, 3 do
		block(
			tool,
			handle,
			"Tine",
			Vector3.new(0.09, 0.95, 0.1),
			Vector3.new(index * 0.23, -2.02, 0),
			COLORS.Metal,
			CFrame.Angles(0, 0, math.rad(index * 1.2)),
			Enum.Material.Metal
		)
	end
end

local function build_bucket(tool: Tool, handle: BasePart)
	cylinder(
		tool,
		handle,
		"BucketBody",
		Vector3.new(1.35, 1.6, 1.6),
		Vector3.new(0, -0.2, 0),
		COLORS.Bucket,
		verticalCylinder,
		Enum.Material.Metal
	)
	cylinder(
		tool,
		handle,
		"Water",
		Vector3.new(0.12, 1.4, 1.4),
		Vector3.new(0, 0.48, 0),
		COLORS.Water,
		verticalCylinder,
		Enum.Material.Glass
	)
	block(tool, handle, "HandleTop", Vector3.new(1.9, 0.12, 0.12), Vector3.new(0, 1.25, 0), COLORS.DarkMetal, nil, Enum.Material.Metal)
	for _, x in ipairs({ -0.9, 0.9 }) do
		block(tool, handle, "HandleSide", Vector3.new(0.12, 1.05, 0.12), Vector3.new(x, 0.75, 0), COLORS.DarkMetal, nil, Enum.Material.Metal)
	end
end

local TOOL_BUILDERS = {
	stable_broom = build_broom,
	muck_fork = build_fork,
	cleaning_bucket = build_bucket,
}

local function create_tool(itemId: string, previewCFrame: CFrame): Tool
	local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
	assert(itemDefinition, ("Missing ToolItemCatalog definition for '%s'"):format(itemId))

	local tool = Instance.new("Tool")
	tool.Name = itemDefinition.DisplayName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -0.45, 0) * CFrame.Angles(0, 0, math.rad(-12))

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.25, 0.25, 0.25)
	handle.CFrame = previewCFrame
	handle.Transparency = 1
	handle.Anchored = true
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.Parent = tool

	TOOL_BUILDERS[itemId](tool, handle)
	ToolItemCatalog.ApplyToolMetadata(tool, itemDefinition)
	tool:SetAttribute(GENERATED_ATTRIBUTE, true)
	return tool
end

local function add_dirt_part(
	model: Model,
	name: string,
	size: Vector3,
	relativeCFrame: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local object = Instance.new("Part")
	object.Name = name
	object.Size = size
	object.CFrame = relativeCFrame
	object.Color = color
	object.Material = material or Enum.Material.SmoothPlastic
	object.Shape = shape or Enum.PartType.Block
	object.TopSurface = Enum.SurfaceType.Smooth
	object.BottomSurface = Enum.SurfaceType.Smooth
	object.Anchored = true
	object.CanCollide = false
	object.CanTouch = false
	object.CanQuery = false
	object.Parent = model
	return object
end

local function create_dirt_root(templateName: string): (Model, Part)
	local model = Instance.new("Model")
	model.Name = templateName
	model:SetAttribute(GENERATED_ATTRIBUTE, true)

	local root = add_dirt_part(
		model,
		"Root",
		Vector3.new(0.2, 0.2, 0.2),
		CFrame.new(),
		Color3.new(),
		Enum.Material.SmoothPlastic
	)
	root.Transparency = 1
	model.PrimaryPart = root

	return model, root
end

local function build_loose_hay(): Model
	local model = create_dirt_root("LooseHay")
	local visualRandom = Random.new(1107)

	for index = 1, 16 do
		local angle = visualRandom:NextNumber(0, math.pi)
		local x = visualRandom:NextNumber(-1.2, 1.2)
		local z = visualRandom:NextNumber(-0.9, 0.9)
		add_dirt_part(
			model,
			"Straw" .. index,
			Vector3.new(visualRandom:NextNumber(0.75, 1.35), 0.07, 0.07),
			CFrame.new(x, 0.08 + (index % 3) * 0.035, z) * CFrame.Angles(0, angle, 0),
			if index % 3 == 0 then COLORS.StrawLight else COLORS.Straw,
			Enum.Material.Grass
		)
	end

	return model
end

local function build_mud_patch(): Model
	local model = create_dirt_root("MudPatch")

	add_dirt_part(
		model,
		"MudMain",
		Vector3.new(2.8, 0.16, 2.1),
		CFrame.new(0, 0.08, 0),
		COLORS.Mud,
		Enum.Material.Mud,
		Enum.PartType.Ball
	)
	add_dirt_part(
		model,
		"MudSide",
		Vector3.new(1.4, 0.12, 1.2),
		CFrame.new(1.05, 0.07, 0.35),
		COLORS.MudLight,
		Enum.Material.Mud,
		Enum.PartType.Ball
	)
	local sheen = add_dirt_part(
		model,
		"WetSheen",
		Vector3.new(1.25, 0.04, 0.8),
		CFrame.new(-0.35, 0.17, -0.15),
		COLORS.Water,
		Enum.Material.Glass,
		Enum.PartType.Ball
	)
	sheen.Transparency = 0.45

	return model
end

local function build_manure(): Model
	local model = create_dirt_root("Manure")
	local clumpData = {
		{ Vector3.new(-0.48, 0.2, 0.1), Vector3.new(0.9, 0.42, 0.72) },
		{ Vector3.new(0.35, 0.22, -0.2), Vector3.new(1.05, 0.48, 0.8) },
		{ Vector3.new(0.02, 0.48, 0.08), Vector3.new(0.8, 0.55, 0.7) },
	}

	for index, data in ipairs(clumpData) do
		add_dirt_part(
			model,
			"Clump" .. index,
			data[2],
			CFrame.new(data[1]),
			if index == 2 then COLORS.Manure else COLORS.Mud,
			Enum.Material.Ground,
			Enum.PartType.Ball
		)
	end

	for index, position in ipairs({
		Vector3.new(-0.65, 0.8, 0),
		Vector3.new(0.65, 0.95, 0.18),
		Vector3.new(0.05, 1.12, -0.35),
	}) do
		add_dirt_part(
			model,
			"Fly" .. index,
			Vector3.new(0.1, 0.1, 0.1),
			CFrame.new(position),
			COLORS.Fly,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
	end

	return model
end

local DIRT_BUILDERS = {
	LooseHay = build_loose_hay,
	MudPatch = build_mud_patch,
	Manure = build_manure,
}

ChangeHistoryService:SetWaypoint("Before generating stable cleaning assets")

local previousPreview = Workspace:FindFirstChild(PREVIEW_FOLDER_NAME)
if previousPreview then
	assert(
		previousPreview:GetAttribute(GENERATED_ATTRIBUTE) == true,
		("Workspace.%s already exists and was not created by this command"):format(PREVIEW_FOLDER_NAME)
	)
	previousPreview:Destroy()
end

local previewFolder = Instance.new("Folder")
previewFolder.Name = PREVIEW_FOLDER_NAME
previewFolder:SetAttribute(GENERATED_ATTRIBUTE, true)
previewFolder.Parent = Workspace

local toolPreviews = get_or_create_folder(previewFolder, "Tools")
local dirtPreviews = get_or_create_folder(previewFolder, "Dirt")
local assets = get_or_create_folder(ReplicatedStorage, "Assets")
local items = get_or_create_folder(assets, "Items")
local miscItems = get_or_create_folder(items, "Misc")
local cleaningAssets = get_or_create_folder(assets, "StableCleaning")
local dirtAssets = get_or_create_folder(cleaningAssets, "Dirt")

local toolIds = { "stable_broom", "muck_fork", "cleaning_bucket" }
for index, itemId in ipairs(toolIds) do
	local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
	remove_matching_tools(miscItems, itemDefinition)

	local previewTool = create_tool(itemId, CFrame.new((index - 2) * 4, 4, 0))
	previewTool.Parent = toolPreviews

	local runtimeTool = previewTool:Clone()
	local runtimeHandle = runtimeTool:FindFirstChild("Handle")
	if runtimeHandle and runtimeHandle:IsA("BasePart") then
		runtimeHandle.Anchored = false
	end
	runtimeTool.Parent = miscItems
end

for index, dirtTypeId in ipairs(StableCleaningConfig.DirtOrder) do
	local definition = StableCleaningConfig.GetDirtDefinition(dirtTypeId)
	local previousTemplate = dirtAssets:FindFirstChild(definition.TemplateName)
	if previousTemplate then
		previousTemplate:Destroy()
	end

	local template = DIRT_BUILDERS[definition.TemplateName]()
	template.Parent = dirtAssets

	local preview = template:Clone()
	preview.Name = definition.DisplayName
	preview:PivotTo(CFrame.new((index - 2) * 4, 0.15, 5))
	preview.Parent = dirtPreviews
end

local previewFloor = Instance.new("Part")
previewFloor.Name = "PreviewFloor"
previewFloor.Size = Vector3.new(16, 0.2, 10)
previewFloor.Position = Vector3.new(0, -0.12, 2.5)
previewFloor.Anchored = true
previewFloor.CanCollide = true
previewFloor.Material = Enum.Material.WoodPlanks
previewFloor.Color = Color3.fromRGB(137, 99, 67)
previewFloor:SetAttribute(GENERATED_ATTRIBUTE, true)
previewFloor.Parent = previewFolder

ChangeHistoryService:SetWaypoint("Generated stable cleaning assets")
print(
	("[StableCleaningAssets] Created %d Tools and %d dirt templates. Runtime assets are ready in ReplicatedStorage.Assets."):format(
		#toolIds,
		#StableCleaningConfig.DirtOrder
	)
)
