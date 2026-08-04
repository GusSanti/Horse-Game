--!strict

local HeldItemVisual = {}

local DEFAULT_COLOR_BY_CATEGORY: { [string]: Color3 } = {
	Food = Color3.fromRGB(231, 175, 87),
	Fruits = Color3.fromRGB(209, 106, 62),
	Water = Color3.fromRGB(98, 175, 255),
	Grooming = Color3.fromRGB(225, 157, 188),
	Misc = Color3.fromRGB(201, 201, 201),
	Medicine = Color3.fromRGB(121, 205, 140),
	Seeds = Color3.fromRGB(126, 97, 64),
	Tack = Color3.fromRGB(150, 117, 86),
	Cosmetics = Color3.fromRGB(212, 136, 174),
	StableDecor = Color3.fromRGB(159, 134, 98),
}

local function ConfigurePart(Part: BasePart): ()
	Part.Anchored = false
	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
	Part.CastShadow = true
	Part.Massless = true
	Part.TopSurface = Enum.SurfaceType.Smooth
	Part.BottomSurface = Enum.SurfaceType.Smooth
end

local function CreatePart(
	ClassName: "Part" | "WedgePart",
	Name: string,
	Size: Vector3,
	Color: Color3,
	Material: Enum.Material
): BasePart
	local Part: BasePart = Instance.new(ClassName) :: BasePart
	Part.Name = Name
	Part.Size = Size
	Part.Color = Color
	Part.Material = Material
	ConfigurePart(Part)
	return Part
end

local function Attach(Tool: Tool, Handle: BasePart, Part: BasePart, Offset: CFrame): ()
	Part.CFrame = Handle.CFrame * Offset
	Part.Parent = Tool

	local Weld: WeldConstraint = Instance.new("WeldConstraint")
	Weld.Part0 = Handle
	Weld.Part1 = Part
	Weld.Parent = Part
end

local function CreateTool(Name: string, Handle: BasePart): Tool
	local Tool: Tool = Instance.new("Tool")
	Tool.Name = Name
	Tool.CanBeDropped = false
	Tool.RequiresHandle = false
	Handle.Name = "Handle"
	Handle.Parent = Tool
	return Tool
end

local function CreateBerrySplash(Name: string): Tool
	local Handle: Part = CreatePart(
		"Part",
		"Handle",
		Vector3.new(0.5, 0.5, 0.5),
		Color3.fromRGB(112, 43, 139),
		Enum.Material.SmoothPlastic
	) :: Part
	Handle.Shape = Enum.PartType.Ball

	local Tool: Tool = CreateTool(Name, Handle)
	for Index: number, Offset: Vector3 in {
		Vector3.new(0.28, 0.05, 0.08),
		Vector3.new(-0.23, 0.11, -0.12),
		Vector3.new(0.04, 0.27, -0.16),
	} do
		local Berry: Part = CreatePart(
			"Part",
			`Berry{Index}`,
			Vector3.new(0.42, 0.42, 0.42),
			if Index == 2 then Color3.fromRGB(74, 33, 118) else Color3.fromRGB(151, 54, 154),
			Enum.Material.SmoothPlastic
		) :: Part
		Berry.Shape = Enum.PartType.Ball
		Attach(Tool, Handle, Berry, CFrame.new(Offset))
	end

	local Leaf: BasePart = CreatePart(
		"Part",
		"Leaf",
		Vector3.new(0.5, 0.08, 0.26),
		Color3.fromRGB(91, 151, 68),
		Enum.Material.SmoothPlastic
	)
	Attach(Tool, Handle, Leaf, CFrame.new(0, 0.35, 0) * CFrame.Angles(0, 0, math.rad(18)))
	return Tool
end

local function CreatePineapplePie(Name: string): Tool
	local Handle: BasePart = CreatePart(
		"WedgePart",
		"Handle",
		Vector3.new(0.84, 0.3, 0.98),
		Color3.fromRGB(188, 116, 50),
		Enum.Material.SmoothPlastic
	)
	local Tool: Tool = CreateTool(Name, Handle)

	local Filling: BasePart = CreatePart(
		"WedgePart",
		"Filling",
		Vector3.new(0.68, 0.18, 0.78),
		Color3.fromRGB(250, 200, 78),
		Enum.Material.SmoothPlastic
	)
	Attach(Tool, Handle, Filling, CFrame.new(0, 0.2, -0.02))

	for Index: number, Offset: Vector3 in {
		Vector3.new(-0.19, 0.33, -0.1),
		Vector3.new(0.16, 0.33, 0.08),
		Vector3.new(0, 0.33, 0.3),
	} do
		local Fruit: BasePart = CreatePart(
			"Part",
			`Pineapple{Index}`,
			Vector3.new(0.18, 0.1, 0.18),
			Color3.fromRGB(255, 220, 85),
			Enum.Material.SmoothPlastic
		)
		Attach(Tool, Handle, Fruit, CFrame.new(Offset))
	end
	return Tool
end

local function CreateHorseBrush(Name: string): Tool
	local Handle: BasePart = CreatePart(
		"Part",
		"Handle",
		Vector3.new(0.76, 0.24, 0.34),
		Color3.fromRGB(118, 76, 51),
		Enum.Material.Wood
	)
	local Tool: Tool = CreateTool(Name, Handle)

	local Grip: BasePart = CreatePart(
		"Part",
		"Grip",
		Vector3.new(0.92, 0.18, 0.24),
		Color3.fromRGB(118, 76, 51),
		Enum.Material.Wood
	)
	Attach(Tool, Handle, Grip, CFrame.new(0.8, 0.04, 0) * CFrame.Angles(0, 0, math.rad(7)))

	for Index: number = 1, 4 do
		local Bristles: BasePart = CreatePart(
			"Part",
			`Bristles{Index}`,
			Vector3.new(0.1, 0.3, 0.24),
			Color3.fromRGB(226, 188, 130),
			Enum.Material.Fabric
		)
		Attach(Tool, Handle, Bristles, CFrame.new(-0.27 + (Index - 1) * 0.18, -0.25, 0))
	end
	return Tool
end

local function CreateGeneric(ItemDefinition: any): Tool
	local Color: Color3 = DEFAULT_COLOR_BY_CATEGORY[ItemDefinition.ToolCategory] or Color3.fromRGB(214, 214, 214)
	local Handle: BasePart = CreatePart("Part", "Handle", Vector3.new(0.72, 0.72, 0.72), Color, Enum.Material.SmoothPlastic)
	return CreateTool(ItemDefinition.ToolName or ItemDefinition.DisplayName or ItemDefinition.ItemId, Handle)
end

local BUILDERS: { [string]: (string) -> Tool } = {
	berry_splash = CreateBerrySplash,
	horse_brush = CreateHorseBrush,
	pineapple_pie = CreatePineapplePie,
}

function HeldItemVisual.CreateFallback(ItemDefinition: any): Tool
	local Name: string = ItemDefinition.ToolName or ItemDefinition.DisplayName or ItemDefinition.ItemId
	local Builder: ((string) -> Tool)? = BUILDERS[ItemDefinition.ItemId]
	return if Builder then Builder(Name) else CreateGeneric(ItemDefinition)
end

function HeldItemVisual.Prepare(Tool: Tool, ItemDefinition: any): ()
	local ToolGrip: any = ItemDefinition.ToolGrip
	if typeof(ToolGrip) == "CFrame" then
		Tool.Grip = ToolGrip
	end

	if typeof(ToolGrip) ~= "CFrame" and BUILDERS[ItemDefinition.ItemId] == nil then
		return
	end

	for _Index: number, Descendant: Instance in Tool:GetDescendants() do
		if Descendant:IsA("BasePart") then
			ConfigurePart(Descendant)
		end
	end
end

return table.freeze(HeldItemVisual)
