local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local FarmingShopService = require(script.Parent:WaitForChild("FarmingShopService"))
local QuestService = require(script.Parent:WaitForChild("QuestService"))

local FarmingService = {}

local initialized = false
local nextPlantId = 0
local activePlants: { [number]: any } = {}

local function get_equipped_seed_tool(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool and FarmingUtility.IsSeedTool(equippedTool) then
		return equippedTool
	end

	return nil
end

local function get_equipped_watering_tool(player: Player): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool and equippedTool.Name == FarmingUtility.WATERING_TOOL_NAME then
		return equippedTool
	end

	return nil
end

local function get_instance_bottom_offset(instance: Instance): number
	if instance:IsA("Model") then
		local pivot = instance:GetPivot()
		local boundingBoxCFrame, boundingBoxSize = instance:GetBoundingBox()
		return pivot.Position.Y - (boundingBoxCFrame.Position.Y - boundingBoxSize.Y * 0.5)
	end

	local basePart = FarmingUtility.GetFirstBasePart(instance)
	if basePart then
		return basePart.Size.Y * 0.5
	end

	return 0
end

local function move_instance_to_position(instance: Instance, worldPosition: Vector3)
	if instance:IsA("Model") then
		instance:PivotTo(CFrame.new(worldPosition))
		return
	end

	local basePart = FarmingUtility.GetFirstBasePart(instance)
	if basePart then
		basePart.CFrame = CFrame.new(worldPosition)
	end
end

local function configure_stage_visual(instance: Instance)
	if instance:IsA("BasePart") then
		instance.Anchored = true
		instance.CanCollide = false
		return
	end

	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
		end
	end
end

local function set_plant_attributes(instance: Instance, state)
	instance:SetAttribute("FarmPlantId", state.Id)
	instance:SetAttribute("FarmPlantStage", state.Stage)
	instance:SetAttribute("FarmPlantOwnerUserId", state.OwnerUserId)
	instance:SetAttribute("FarmCropId", state.Crop.CropId)
	instance:SetAttribute("FarmSeedItemId", state.Crop.Seed.ItemId)
	instance:SetAttribute("FarmFruitItemId", state.Crop.Fruit.ItemId)
end

local function reset_stage_trove(state)
	if state.StageTrove then
		state.StageTrove:Destroy()
	end

	state.StageTrove = Trove.new()
end

local function clear_plant(state)
	if state.StageTrove then
		state.StageTrove:Destroy()
		state.StageTrove = nil
	end

	state.Model = nil
end

local function attach_harvest_prompt(state)
	local harvestHandle = FarmingUtility.FindHarvestHandle(state.Model)
	if not harvestHandle then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HarvestPrompt"
	prompt.ActionText = "Colher"
	prompt.ObjectText = state.Crop.Fruit.DisplayName
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = harvestHandle

	state.StageTrove:Add(prompt)
	state.StageTrove:Add(prompt.Triggered:Connect(function(player)
		if player.UserId ~= state.OwnerUserId then
			return
		end

		if activePlants[state.Id] ~= state then
			return
		end

		if harvestHandle.Parent then
			harvestHandle:Destroy()
		end

		FarmingShopService.AwardHarvest(player, state.Crop.Fruit)
		QuestService.IncrementStat(player, "Stats.TotalCropsHarvested", 1)

		clear_plant(state)
		activePlants[state.Id] = nil
	end))
end

local function create_stage_visual(state, stage: number)
	local stageTemplate = FarmingUtility.GetStageTemplate(state.Crop, stage)
	if not stageTemplate then
		return false
	end

	local placementWorldPosition = FarmingUtility.GetWorldTopPosition(state.Soil, state.LocalPoint)
	local stageClone = stageTemplate:Clone()
	local bottomOffset = get_instance_bottom_offset(stageTemplate)
	local worldPosition = placementWorldPosition + state.Soil.CFrame.UpVector * bottomOffset

	reset_stage_trove(state)

	state.Stage = stage
	state.Model = stageClone

	stageClone.Name = ("%s_%d_Stage%d"):format(state.Crop.CropId, state.Id, stage)
	set_plant_attributes(stageClone, state)
	move_instance_to_position(stageClone, worldPosition)
	configure_stage_visual(stageClone)
	stageClone.Parent = FarmingUtility.GetFarmFolder(true)

	state.StageTrove:Add(stageClone)

	if stage >= (state.Crop.MaxStage or FarmingUtility.MAX_STAGE) then
		attach_harvest_prompt(state)
	end

	return true
end

function FarmingService.PlaceSeed(player: Player, worldPosition: Vector3)
	if typeof(worldPosition) ~= "Vector3" then
		return {
			Success = false,
			Code = "InvalidPosition",
		}
	end

	local seedTool = get_equipped_seed_tool(player)
	if not seedTool then
		return {
			Success = false,
			Code = "SeedNotEquipped",
		}
	end

	local cropDefinition = FarmingUtility.GetCropFromSeedTool(seedTool)
	if not cropDefinition then
		return {
			Success = false,
			Code = "InvalidSeedTool",
		}
	end

	local placement = FarmingUtility.GetSoilPlacementData(worldPosition)
	if not placement then
		return {
			Success = false,
			Code = "InvalidSoil",
		}
	end

	local consumedSeed, consumeResponse = FarmingShopService.ConsumeSeed(player, cropDefinition.Seed)
	if not consumedSeed then
		return consumeResponse
	end

	nextPlantId += 1

	local state = {
		Id = nextPlantId,
		OwnerUserId = player.UserId,
		Crop = cropDefinition,
		Soil = placement.Soil,
		LocalPoint = placement.LocalPoint,
		Stage = 0,
		Model = nil,
		StageTrove = nil,
	}

	activePlants[state.Id] = state

	if not create_stage_visual(state, 1) then
		activePlants[state.Id] = nil
		return {
			Success = false,
			Code = "StageTemplateMissing",
		}
	end

	return {
		Success = true,
		Code = "Planted",
		PlantId = state.Id,
		CropId = cropDefinition.CropId,
	}
end

function FarmingService.WaterPlant(player: Player, targetInstance: Instance)
	if typeof(targetInstance) ~= "Instance" then
		return {
			Success = false,
			Code = "InvalidTarget",
		}
	end

	if not get_equipped_watering_tool(player) then
		return {
			Success = false,
			Code = "RegaderaNotEquipped",
		}
	end

	local plantId = FarmingUtility.FindPlantIdFromInstance(targetInstance)
	local state = plantId and activePlants[plantId]

	if not state then
		return {
			Success = false,
			Code = "PlantNotFound",
		}
	end

	if state.OwnerUserId ~= player.UserId then
		return {
			Success = false,
			Code = "PlantOwnerMismatch",
		}
	end

	if state.Stage >= (state.Crop.MaxStage or FarmingUtility.MAX_STAGE) then
		return {
			Success = false,
			Code = "PlantAlreadyMature",
		}
	end

	if not create_stage_visual(state, state.Stage + 1) then
		return {
			Success = false,
			Code = "StageTemplateMissing",
		}
	end

	return {
		Success = true,
		Code = "PlantWatered",
		PlantId = state.Id,
		Stage = state.Stage,
		CropId = state.Crop.CropId,
	}
end

function FarmingService.Init()
	if initialized then
		return
	end

	Net.Function.PlantSeed:Respond(function(player, worldPosition)
		return FarmingService.PlaceSeed(player, worldPosition)
	end)

	Net.Function.WaterPlant:Respond(function(player, targetInstance)
		return FarmingService.WaterPlant(player, targetInstance)
	end)

	initialized = true
end

return FarmingService
