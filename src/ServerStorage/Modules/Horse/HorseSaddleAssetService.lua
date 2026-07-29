local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local GENERATED_ATTRIBUTE = "GeneratedSaddleAsset"

local STYLES = {
	starter_saddle = {
		Kind = "Starter",
		Leather = Color3.fromRGB(111, 73, 48),
		Dark = Color3.fromRGB(67, 43, 31),
		Accent = Color3.fromRGB(187, 143, 76),
		Cloth = Color3.fromRGB(131, 105, 82),
	},
	trail_saddle = {
		Kind = "Trail",
		Leather = Color3.fromRGB(121, 82, 52),
		Dark = Color3.fromRGB(70, 47, 34),
		Accent = Color3.fromRGB(166, 151, 116),
		Cloth = Color3.fromRGB(84, 126, 91),
	},
	western_saddle = {
		Kind = "Western",
		Leather = Color3.fromRGB(151, 81, 42),
		Dark = Color3.fromRGB(79, 42, 29),
		Accent = Color3.fromRGB(214, 158, 66),
		Cloth = Color3.fromRGB(64, 105, 122),
	},
	endurance_saddle = {
		Kind = "Endurance",
		Leather = Color3.fromRGB(62, 76, 69),
		Dark = Color3.fromRGB(35, 43, 40),
		Accent = Color3.fromRGB(191, 151, 64),
		Cloth = Color3.fromRGB(58, 139, 137),
	},
	english_saddle = {
		Kind = "English",
		Leather = Color3.fromRGB(65, 45, 39),
		Dark = Color3.fromRGB(35, 28, 27),
		Accent = Color3.fromRGB(190, 195, 197),
		Cloth = Color3.fromRGB(159, 202, 183),
	},
	racing_saddle = {
		Kind = "Racing",
		Leather = Color3.fromRGB(36, 38, 44),
		Dark = Color3.fromRGB(18, 19, 23),
		Accent = Color3.fromRGB(220, 53, 69),
		Cloth = Color3.fromRGB(235, 235, 238),
	},
	royal_saddle = {
		Kind = "Royal",
		Leather = Color3.fromRGB(74, 36, 101),
		Dark = Color3.fromRGB(39, 19, 56),
		Accent = Color3.fromRGB(236, 190, 62),
		Cloth = Color3.fromRGB(113, 54, 150),
	},
}

local HorseSaddleAssetService = {}

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
	container: Instance,
	root: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = root.CFrame * offset
	part.Color = color
	part.Material = material
	part.Shape = shape or Enum.PartType.Block
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.Parent = container

	local weld = Instance.new("WeldConstraint")
	weld.Name = "VisualWeld"
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
	return part
end

local function block(container, root, name, size, position, color, rotation, material)
	return add_part(
		container,
		root,
		name,
		size,
		CFrame.new(position) * (rotation or CFrame.identity),
		color,
		material or Enum.Material.Fabric
	)
end

local function cylinder(container, root, name, size, position, color, rotation, material)
	return add_part(
		container,
		root,
		name,
		size,
		CFrame.new(position) * (rotation or CFrame.identity),
		color,
		material or Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
end

local function add_stirrup(container, root, style, sideSign)
	local x = 1.08 * sideSign
	block(container, root, "StirrupLeather", Vector3.new(0.11, 1.55, 0.13), Vector3.new(x, -0.75, 0.05), style.Dark)
	block(
		container,
		root,
		"StirrupBase",
		Vector3.new(0.52, 0.11, 0.42),
		Vector3.new(x, -1.52, 0.05),
		style.Accent,
		nil,
		Enum.Material.Metal
	)
	for _, z in ipairs({ -0.18, 0.18 }) do
		block(
			container,
			root,
			"StirrupSide",
			Vector3.new(0.11, 0.48, 0.11),
			Vector3.new(x, -1.3, z + 0.05),
			style.Accent,
			nil,
			Enum.Material.Metal
		)
	end
end

local function build_saddle(container: Instance, root: BasePart, style)
	block(container, root, "SaddlePad", Vector3.new(2.45, 0.16, 2.45), Vector3.new(0, -0.3, 0.12), style.Cloth)
	block(
		container,
		root,
		"Seat",
		Vector3.new(1.8, 0.48, 2.15),
		Vector3.new(0, 0.15, 0),
		style.Leather,
		CFrame.Angles(math.rad(-4), 0, 0)
	)
	block(container, root, "LeftSkirt", Vector3.new(0.2, 1.3, 1.65), Vector3.new(-1, -0.25, 0.2), style.Leather)
	block(container, root, "RightSkirt", Vector3.new(0.2, 1.3, 1.65), Vector3.new(1, -0.25, 0.2), style.Leather)
	block(
		container,
		root,
		"Cantle",
		Vector3.new(1.9, 0.72, 0.35),
		Vector3.new(0, 0.5, 0.93),
		style.Dark,
		CFrame.Angles(math.rad(-14), 0, 0)
	)

	if style.Kind == "Western" then
		cylinder(
			container,
			root,
			"Horn",
			Vector3.new(0.72, 0.22, 0.22),
			Vector3.new(0, 0.72, -0.82),
			style.Dark,
			CFrame.Angles(0, 0, math.rad(90)),
			Enum.Material.Fabric
		)
		cylinder(
			container,
			root,
			"HornCap",
			Vector3.new(0.18, 0.48, 0.48),
			Vector3.new(0, 1.08, -0.82),
			style.Accent,
			CFrame.Angles(0, 0, math.rad(90))
		)
	elseif style.Kind == "Trail" or style.Kind == "Endurance" then
		for _, sideSign in ipairs({ -1, 1 }) do
			block(
				container,
				root,
				"SaddleBag",
				Vector3.new(0.55, 0.65, 0.7),
				Vector3.new(0.94 * sideSign, -0.42, 0.82),
				style.Dark
			)
		end
	elseif style.Kind == "Racing" then
		block(
			container,
			root,
			"RacingStripe",
			Vector3.new(0.42, 0.05, 2.05),
			Vector3.new(0, 0.41, -0.02),
			style.Accent,
			CFrame.Angles(math.rad(-4), 0, 0),
			Enum.Material.SmoothPlastic
		)
	elseif style.Kind == "Royal" then
		for _, sideSign in ipairs({ -1, 1 }) do
			block(
				container,
				root,
				"GoldTrim",
				Vector3.new(0.12, 0.1, 1.7),
				Vector3.new(0.78 * sideSign, 0.43, 0.08),
				style.Accent,
				nil,
				Enum.Material.Metal
			)
		end
	else
		block(
			container,
			root,
			"Pommel",
			Vector3.new(1.65, 0.5, 0.3),
			Vector3.new(0, 0.48, -0.88),
			style.Dark,
			CFrame.Angles(math.rad(10), 0, 0)
		)
	end

	add_stirrup(container, root, style, -1)
	add_stirrup(container, root, style, 1)
end

local function create_root(parent: Instance, name: string, anchored: boolean): Part
	local root = Instance.new("Part")
	root.Name = name
	root.Size = Vector3.new(0.25, 0.25, 0.25)
	root.Transparency = 1
	root.Anchored = anchored
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Massless = true
	root.Parent = parent
	return root
end

local function create_tool(itemDefinition, style): Tool
	local tool = Instance.new("Tool")
	tool.Name = itemDefinition.DisplayName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, -0.25, 0) * CFrame.Angles(0, math.rad(90), math.rad(-8))

	local root = create_root(tool, "Handle", false)
	build_saddle(tool, root, style)
	ToolItemCatalog.ApplyToolMetadata(tool, itemDefinition)
	tool:SetAttribute(GENERATED_ATTRIBUTE, true)
	return tool
end

local function create_model(itemDefinition, style): Model
	local model = Instance.new("Model")
	model.Name = itemDefinition.ItemId
	model:SetAttribute("ToolItemId", itemDefinition.ItemId)
	model:SetAttribute("DisplayName", itemDefinition.DisplayName)
	model:SetAttribute(GENERATED_ATTRIBUTE, true)

	local root = create_root(model, "SaddleRoot", true)
	model.PrimaryPart = root
	build_saddle(model, root, style)
	return model
end

local function is_plain_placeholder_tool(tool: Tool): boolean
	local visibleParts = 0
	local handle = tool:FindFirstChild("Handle")
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			visibleParts += 1
		end
	end

	return visibleParts <= 1
		and handle ~= nil
		and handle:IsA("Part")
		and handle:FindFirstChildWhichIsA("DataModelMesh") == nil
end

local function find_tool(folder: Instance, itemDefinition): Tool?
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Tool")
			and (
				child:GetAttribute("ToolItemId") == itemDefinition.ItemId
				or child.Name == itemDefinition.DisplayName
				or child.Name == itemDefinition.ItemId
			)
		then
			return child
		end
	end
	return nil
end

function HorseSaddleAssetService.EnsureAssets()
	local assets = get_or_create_folder(ReplicatedStorage, "Assets")
	local items = get_or_create_folder(assets, "Items")
	local tackAssets = get_or_create_folder(items, "Tack")
	local horseEquipment = get_or_create_folder(assets, "HorseEquipment")
	local saddleModels = get_or_create_folder(horseEquipment, "Saddles")

	for _, itemDefinition in ipairs(ToolItemCatalog.GetItemsByToolCategory("Tack")) do
		if itemDefinition.EquipmentType ~= "Saddle" then
			continue
		end

		local style = STYLES[itemDefinition.ItemId] or STYLES.starter_saddle
		local existingTool = find_tool(tackAssets, itemDefinition)
		if existingTool and is_plain_placeholder_tool(existingTool) then
			existingTool:Destroy()
			existingTool = nil
		end

		if not existingTool then
			create_tool(itemDefinition, style).Parent = tackAssets
		end

		local existingModel = saddleModels:FindFirstChild(itemDefinition.ItemId)
		if not existingModel then
			create_model(itemDefinition, style).Parent = saddleModels
		end
	end
end

HorseSaddleAssetService.Init = HorseSaddleAssetService.EnsureAssets

return HorseSaddleAssetService
