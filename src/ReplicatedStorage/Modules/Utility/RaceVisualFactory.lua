local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ServerStorage = nil
if RunService:IsServer() then
	ServerStorage = game:GetService("ServerStorage")
end

local RaceVisualFactory = {}

local HORSE_COLORS = {
	american_paint_horse = {
		Body = Color3.fromRGB(172, 131, 102),
		Mane = Color3.fromRGB(84, 58, 43),
	},
	andalusian = {
		Body = Color3.fromRGB(180, 184, 191),
		Mane = Color3.fromRGB(104, 108, 116),
	},
	friesian = {
		Body = Color3.fromRGB(42, 44, 50),
		Mane = Color3.fromRGB(15, 16, 20),
	},
	lipizzaner = {
		Body = Color3.fromRGB(225, 227, 232),
		Mane = Color3.fromRGB(169, 172, 180),
	},
	quarter_horse = {
		Body = Color3.fromRGB(154, 107, 76),
		Mane = Color3.fromRGB(80, 49, 34),
	},
	american_saddlebred = {
		Body = Color3.fromRGB(126, 80, 57),
		Mane = Color3.fromRGB(44, 28, 19),
	},
	starter_meadow_bay = {
		Body = Color3.fromRGB(142, 101, 70),
		Mane = Color3.fromRGB(57, 37, 25),
	},
	starter_dusty_chestnut = {
		Body = Color3.fromRGB(167, 95, 54),
		Mane = Color3.fromRGB(87, 43, 22),
	},
	starter_moon_gray = {
		Body = Color3.fromRGB(170, 176, 184),
		Mane = Color3.fromRGB(98, 103, 109),
	},
	starter_midnight_black = {
		Body = Color3.fromRGB(43, 45, 52),
		Mane = Color3.fromRGB(17, 18, 22),
	},
	default = {
		Body = Color3.fromRGB(124, 93, 72),
		Mane = Color3.fromRGB(56, 39, 29),
	},
}

local function create_part(parent, name, size, color, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = cframe
	part.Parent = parent
	return part
end

function RaceVisualFactory.ExtractRotation(cframe)
	return CFrame.fromMatrix(Vector3.zero, cframe.XVector, cframe.YVector, cframe.ZVector)
end

function RaceVisualFactory.PrepareModel(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

function RaceVisualFactory.FindTemplateModel(modelKey, raceFolder)
	if type(modelKey) ~= "string" or modelKey == "" then
		return nil
	end

	local candidates = {}
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		local assetHorses = assetsFolder:FindFirstChild("Horses")
		if assetHorses then
			candidates[#candidates + 1] = assetHorses
		end
		candidates[#candidates + 1] = assetsFolder
	end

	local replicatedHorses = ReplicatedStorage:FindFirstChild("HorseModels")
	if replicatedHorses then
		candidates[#candidates + 1] = replicatedHorses
	end

	if ServerStorage then
		local serverHorses = ServerStorage:FindFirstChild("HorseModels")
		if serverHorses then
			candidates[#candidates + 1] = serverHorses
		end
	end

	local templatesFolder = raceFolder and raceFolder:FindFirstChild("Templates")
	if templatesFolder then
		candidates[#candidates + 1] = templatesFolder
	end

	for _, folder in ipairs(candidates) do
		local candidate = folder:FindFirstChild(modelKey)
		if candidate and candidate:IsA("Model") then
			return candidate
		end
	end

	return nil
end

function RaceVisualFactory.BuildFallbackHorseModel(horseSummary)
	local catalogId = horseSummary and horseSummary.CatalogId or nil
	local horseId = horseSummary and (horseSummary.HorseId or horseSummary.Id) or "horse"
	local palette = HORSE_COLORS[catalogId] or HORSE_COLORS.default
	local model = Instance.new("Model")
	model.Name = ("%s_RaceModel"):format(horseId)

	local root = create_part(model, "Root", Vector3.new(2.6, 3.4, 7.2), palette.Body, CFrame.new(0, 3.4, 0))
	root.Transparency = 1

	create_part(model, "Body", Vector3.new(2.4, 2.5, 6.8), palette.Body, CFrame.new(0, 3.6, 0))
	create_part(model, "Chest", Vector3.new(2.2, 2.2, 2.1), palette.Body, CFrame.new(0, 3.45, -2.15))
	create_part(model, "Neck", Vector3.new(1.3, 2.3, 1.2), palette.Body, CFrame.new(0, 4.35, -3.35) * CFrame.Angles(math.rad(-24), 0, 0))
	create_part(model, "Head", Vector3.new(1.25, 1.25, 2.1), palette.Body, CFrame.new(0, 5.05, -4.35) * CFrame.Angles(math.rad(-12), 0, 0))
	create_part(model, "Mane", Vector3.new(0.6, 2.7, 0.8), palette.Mane, CFrame.new(0, 4.55, -3.2) * CFrame.Angles(math.rad(-18), 0, 0))
	create_part(model, "Tail", Vector3.new(0.65, 2.5, 0.85), palette.Mane, CFrame.new(0, 4.05, 3.35) * CFrame.Angles(math.rad(32), 0, 0))

	local legOffsets = {
		Vector3.new(-0.7, 1.6, -2.2),
		Vector3.new(0.7, 1.6, -2.2),
		Vector3.new(-0.7, 1.6, 2.1),
		Vector3.new(0.7, 1.6, 2.1),
	}

	for index, offset in ipairs(legOffsets) do
		create_part(model, ("Leg_%d"):format(index), Vector3.new(0.55, 3.1, 0.55), palette.Mane, CFrame.new(offset))
	end

	model.PrimaryPart = root
	return model
end

function RaceVisualFactory.CreateRaceModel(horseSummary, raceFolder, parent)
	local template = RaceVisualFactory.FindTemplateModel(horseSummary and horseSummary.PlaceholderModelKey or "", raceFolder)
	local model = nil

	if template then
		model = template:Clone()
		model.Name = ("%s_RaceModel"):format(horseSummary and horseSummary.Id or "horse")
	else
		model = RaceVisualFactory.BuildFallbackHorseModel(horseSummary)
	end

	RaceVisualFactory.PrepareModel(model)

	if parent then
		model.Parent = parent
	end

	return model
end

function RaceVisualFactory.GetAlignedSlotPivot(model, slot)
	local pivot = model:GetPivot()
	local boxCFrame, boxSize = model:GetBoundingBox()
	local boxOffset = pivot:ToObjectSpace(boxCFrame)
	local slotPosition = slot.Position + Vector3.new(0, slot.Size.Y * 0.5 + boxSize.Y * 0.5, 0)
	local desiredBoxCFrame = CFrame.new(slotPosition) * RaceVisualFactory.ExtractRotation(slot.CFrame)
	return desiredBoxCFrame * boxOffset:Inverse()
end

return RaceVisualFactory
