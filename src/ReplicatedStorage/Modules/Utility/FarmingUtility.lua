local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FarmingUtility = {}

FarmingUtility.SEED_TOOL_NAME = "Seed"
FarmingUtility.WATERING_TOOL_NAME = "Regadera"
FarmingUtility.HARVEST_TOOL_NAME = "Plant"
FarmingUtility.FARMING_ZONE_NAME = "FarmingZone"
FarmingUtility.SOIL_NAME = "Soil"
FarmingUtility.FARM_FOLDER_NAME = "FarmPlants"
FarmingUtility.STAGE_FOLDER_NAME = "StagePlants"
FarmingUtility.MAX_STAGE = 5

function FarmingUtility.GetStagePlantsFolder(): Folder
	local assets = ReplicatedStorage:WaitForChild("Assets")
	return assets:WaitForChild(FarmingUtility.STAGE_FOLDER_NAME) :: Folder
end

function FarmingUtility.GetStageTemplate(stage: number): Instance
	return FarmingUtility.GetStagePlantsFolder():WaitForChild(("Plant%d"):format(stage))
end

function FarmingUtility.GetHarvestToolTemplate(): Tool
	return FarmingUtility.GetStagePlantsFolder():WaitForChild(FarmingUtility.HARVEST_TOOL_NAME) :: Tool
end

function FarmingUtility.GetSeedToolTemplate(): Tool
	local assets = ReplicatedStorage:WaitForChild("Assets")
	local directTemplate = assets:FindFirstChild(FarmingUtility.SEED_TOOL_NAME, true)

	if directTemplate and directTemplate:IsA("Tool") then
		return directTemplate
	end

	return FarmingUtility.GetStagePlantsFolder():WaitForChild(FarmingUtility.SEED_TOOL_NAME) :: Tool
end

function FarmingUtility.FindHarvestToolTemplate(): Tool?
	local template = FarmingUtility.GetStagePlantsFolder():FindFirstChild(FarmingUtility.HARVEST_TOOL_NAME)
	if template and template:IsA("Tool") then
		return template
	end

	return nil
end

function FarmingUtility.GetFarmingZone(): Instance
	return workspace:WaitForChild(FarmingUtility.FARMING_ZONE_NAME)
end

function FarmingUtility.GetFarmFolder(createIfMissing: boolean?): Folder?
	local folder = workspace:FindFirstChild(FarmingUtility.FARM_FOLDER_NAME)
	if folder then
		return folder :: Folder
	end

	if not createIfMissing then
		return nil
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = FarmingUtility.FARM_FOLDER_NAME
	newFolder.Parent = workspace

	return newFolder
end

function FarmingUtility.GetSoilParts(): { BasePart }
	local soils = {}

	for _, descendant in ipairs(FarmingUtility.GetFarmingZone():GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == FarmingUtility.SOIL_NAME then
			table.insert(soils, descendant)
		end
	end

	return soils
end

function FarmingUtility.GetSoilPlacementData(worldPosition: Vector3): { Soil: BasePart, LocalPoint: Vector3, WorldTopPosition: Vector3 }?
	for _, soil in ipairs(FarmingUtility.GetSoilParts()) do
		local localPoint = soil.CFrame:PointToObjectSpace(worldPosition)

		if math.abs(localPoint.X) <= soil.Size.X * 0.5 and math.abs(localPoint.Z) <= soil.Size.Z * 0.5 then
			return {
				Soil = soil,
				LocalPoint = localPoint,
				WorldTopPosition = FarmingUtility.GetWorldTopPosition(soil, localPoint),
			}
		end
	end

	return nil
end

function FarmingUtility.GetWorldTopPosition(soil: BasePart, localPoint: Vector3): Vector3
	return soil.CFrame:PointToWorldSpace(Vector3.new(localPoint.X, soil.Size.Y * 0.5, localPoint.Z))
end

function FarmingUtility.GetFirstBasePart(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

function FarmingUtility.GetToolHandle(tool: Tool): BasePart?
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return FarmingUtility.GetFirstBasePart(tool)
end

function FarmingUtility.FindPlantIdFromInstance(instance: Instance?): number?
	local current = instance

	while current and current ~= workspace do
		local plantId = current:GetAttribute("FarmPlantId")
		if type(plantId) == "number" then
			return plantId
		end

		current = current.Parent
	end

	return nil
end

return FarmingUtility
