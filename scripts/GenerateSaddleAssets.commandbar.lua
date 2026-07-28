-- Paste this entire file into Roblox Studio's Command Bar while NOT playing.
-- It creates editable previews in Workspace.SaddleAssetPreview and installs
-- runtime Tools in ReplicatedStorage.Assets.Items.Tack.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

assert(not RunService:IsRunning(), "Run this command from Studio edit mode, not during Play mode.")

local ToolItemCatalog = require(
	ReplicatedStorage:WaitForChild("Modules")
		:WaitForChild("GameData")
		:WaitForChild("ToolItemCatalog")
)

local GENERATED_ATTRIBUTE = "GeneratedSaddleAsset"
local PREVIEW_FOLDER_NAME = "SaddleAssetPreview"
local SADDLE_ITEM_IDS = {
	"starter_saddle",
	"western_saddle",
	"english_saddle",
}

local STYLES = {
	starter_saddle = {
		Kind = "Starter",
		Leather = Color3.fromRGB(111, 73, 48),
		LeatherDark = Color3.fromRGB(67, 43, 31),
		Accent = Color3.fromRGB(187, 143, 76),
		Cloth = Color3.fromRGB(131, 105, 82),
	},
	western_saddle = {
		Kind = "Western",
		Leather = Color3.fromRGB(151, 81, 42),
		LeatherDark = Color3.fromRGB(79, 42, 29),
		Accent = Color3.fromRGB(214, 158, 66),
		Cloth = Color3.fromRGB(64, 105, 122),
	},
	english_saddle = {
		Kind = "English",
		Leather = Color3.fromRGB(65, 45, 39),
		LeatherDark = Color3.fromRGB(35, 28, 27),
		Accent = Color3.fromRGB(190, 195, 197),
		Cloth = Color3.fromRGB(159, 202, 183),
	},
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

local function add_part(
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
	return add_part(
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
	return add_part(
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

local function add_stirrup(tool, handle, style, sideSign)
	local x = 1.08 * sideSign
	block(
		tool,
		handle,
		"StirrupLeather",
		Vector3.new(0.11, 1.55, 0.13),
		Vector3.new(x, -0.75, 0.05),
		style.LeatherDark,
		nil,
		Enum.Material.Fabric
	)
	block(
		tool,
		handle,
		"StirrupBase",
		Vector3.new(0.52, 0.11, 0.42),
		Vector3.new(x, -1.52, 0.05),
		style.Accent,
		nil,
		Enum.Material.Metal
	)
	for _, z in ipairs({ -0.18, 0.18 }) do
		block(
			tool,
			handle,
			"StirrupSide",
			Vector3.new(0.11, 0.48, 0.11),
			Vector3.new(x, -1.3, z + 0.05),
			style.Accent,
			CFrame.Angles(math.rad(z * 22), 0, 0),
			Enum.Material.Metal
		)
	end
end

local function build_saddle(tool: Tool, handle: BasePart, style)
	block(
		tool,
		handle,
		"SaddlePad",
		Vector3.new(2.45, 0.16, 2.45),
		Vector3.new(0, -0.3, 0.12),
		style.Cloth,
		CFrame.Angles(0, 0, math.rad(2)),
		Enum.Material.Fabric
	)
	block(
		tool,
		handle,
		"Seat",
		Vector3.new(1.8, 0.48, 2.15),
		Vector3.new(0, 0.15, 0),
		style.Leather,
		CFrame.Angles(math.rad(-4), 0, 0),
		Enum.Material.Fabric
	)
	block(
		tool,
		handle,
		"LeftSkirt",
		Vector3.new(0.2, 1.3, 1.65),
		Vector3.new(-1, -0.25, 0.2),
		style.Leather,
		CFrame.Angles(math.rad(4), 0, math.rad(-4)),
		Enum.Material.Fabric
	)
	block(
		tool,
		handle,
		"RightSkirt",
		Vector3.new(0.2, 1.3, 1.65),
		Vector3.new(1, -0.25, 0.2),
		style.Leather,
		CFrame.Angles(math.rad(4), 0, math.rad(4)),
		Enum.Material.Fabric
	)
	block(
		tool,
		handle,
		"Cantle",
		Vector3.new(1.9, 0.72, 0.35),
		Vector3.new(0, 0.5, 0.93),
		style.LeatherDark,
		CFrame.Angles(math.rad(-14), 0, 0),
		Enum.Material.Fabric
	)

	if style.Kind == "Western" then
		cylinder(
			tool,
			handle,
			"Horn",
			Vector3.new(0.72, 0.22, 0.22),
			Vector3.new(0, 0.72, -0.82),
			style.LeatherDark,
			CFrame.Angles(0, 0, math.rad(90)),
			Enum.Material.Fabric
		)
		cylinder(
			tool,
			handle,
			"HornCap",
			Vector3.new(0.18, 0.48, 0.48),
			Vector3.new(0, 1.08, -0.82),
			style.Accent,
			CFrame.Angles(0, 0, math.rad(90)),
			Enum.Material.Metal
		)
		for _, x in ipairs({ -0.68, 0.68 }) do
			block(
				tool,
				handle,
				"Decor",
				Vector3.new(0.18, 0.08, 1.15),
				Vector3.new(x, 0.43, 0.05),
				style.Accent,
				CFrame.Angles(0, 0, math.rad(x * 7)),
				Enum.Material.Metal
			)
		end
	elseif style.Kind == "English" then
		block(
			tool,
			handle,
			"FrontArch",
			Vector3.new(1.75, 0.58, 0.28),
			Vector3.new(0, 0.46, -0.88),
			style.LeatherDark,
			CFrame.Angles(math.rad(12), 0, 0),
			Enum.Material.Fabric
		)
		for _, sideSign in ipairs({ -1, 1 }) do
			block(
				tool,
				handle,
				"KneeRoll",
				Vector3.new(0.28, 0.72, 0.62),
				Vector3.new(0.83 * sideSign, 0.02, -0.62),
				style.LeatherDark,
				CFrame.Angles(math.rad(-8), 0, math.rad(8 * sideSign)),
				Enum.Material.Fabric
			)
		end
	else
		block(
			tool,
			handle,
			"Pommel",
			Vector3.new(1.55, 0.5, 0.32),
			Vector3.new(0, 0.48, -0.88),
			style.LeatherDark,
			CFrame.Angles(math.rad(10), 0, 0),
			Enum.Material.Fabric
		)
	end

	add_stirrup(tool, handle, style, -1)
	add_stirrup(tool, handle, style, 1)
end

local function create_saddle_tool(itemId: string, previewCFrame: CFrame): Tool
	local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
	local style = STYLES[itemId]
	assert(itemDefinition, ("Missing ToolItemCatalog definition for '%s'"):format(itemId))
	assert(style, ("Missing saddle style for '%s'"):format(itemId))

	local tool = Instance.new("Tool")
	tool.Name = itemDefinition.DisplayName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -0.25, 0) * CFrame.Angles(0, math.rad(90), math.rad(-8))

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

	build_saddle(tool, handle, style)
	ToolItemCatalog.ApplyToolMetadata(tool, itemDefinition)
	tool:SetAttribute(GENERATED_ATTRIBUTE, true)
	return tool
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

ChangeHistoryService:SetWaypoint("Before generating saddle assets")

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

local assets = get_or_create_folder(ReplicatedStorage, "Assets")
local items = get_or_create_folder(assets, "Items")
local tackAssets = get_or_create_folder(items, "Tack")

for index, itemId in ipairs(SADDLE_ITEM_IDS) do
	local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
	remove_matching_tools(tackAssets, itemDefinition)

	local previewTool = create_saddle_tool(itemId, CFrame.new((index - 2) * 4.5, 4, 0))
	previewTool.Parent = previewFolder

	local runtimeTool = previewTool:Clone()
	local runtimeHandle = runtimeTool:FindFirstChild("Handle")
	if runtimeHandle and runtimeHandle:IsA("BasePart") then
		runtimeHandle.Anchored = false
	end
	runtimeTool.Parent = tackAssets
end

local previewFloor = Instance.new("Part")
previewFloor.Name = "PreviewFloor"
previewFloor.Size = Vector3.new(16, 0.2, 7)
previewFloor.Position = Vector3.new(0, 0, 0)
previewFloor.Anchored = true
previewFloor.Material = Enum.Material.WoodPlanks
previewFloor.Color = Color3.fromRGB(126, 91, 63)
previewFloor:SetAttribute(GENERATED_ATTRIBUTE, true)
previewFloor.Parent = previewFolder

ChangeHistoryService:SetWaypoint("Generated saddle assets")
print(
	("[SaddleAssets] Created %d saddle Tools in Workspace.%s and ReplicatedStorage.Assets.Items.Tack."):format(
		#SADDLE_ITEM_IDS,
		PREVIEW_FOLDER_NAME
	)
)
