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

local WATER_INDICATOR_FOLDER_NAME = "WaterFarm"
local WATER_INDICATOR_TEMPLATE_NAME = "WaterFarm"
local WATER_INDICATOR_UPDATE_INTERVAL = 1
local WATER_INDICATOR_OFFSET_Y = 0.8

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
		local pivot = instance:GetPivot()
		local rotation = CFrame.fromMatrix(Vector3.zero, pivot.XVector, pivot.YVector, pivot.ZVector)
		instance:PivotTo(CFrame.new(worldPosition) * rotation)
		return
	end

	local basePart = FarmingUtility.GetFirstBasePart(instance)
	if basePart then
		local rotation = CFrame.fromMatrix(Vector3.zero, basePart.CFrame.XVector, basePart.CFrame.YVector, basePart.CFrame.ZVector)
		basePart.CFrame = CFrame.new(worldPosition) * rotation
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

local function get_crop_max_stage(cropDefinition): number
	return math.max(1, math.floor(tonumber(cropDefinition and cropDefinition.MaxStage) or FarmingUtility.MAX_STAGE))
end

local function get_initial_water_delay(cropDefinition): number
	return math.max(
		1,
		math.floor(tonumber(cropDefinition and cropDefinition.InitialWaterDelaySeconds)
			or tonumber(cropDefinition and cropDefinition.WaterIntervalSeconds)
			or 300)
	)
end

local function get_water_interval(cropDefinition): number
	return math.max(1, math.floor(tonumber(cropDefinition and cropDefinition.WaterIntervalSeconds) or 300))
end

local function get_stage_advance_delay(cropDefinition, intervalSeconds: number): number
	local stageAdvanceRatio = math.max(0.1, math.min(0.95, tonumber(cropDefinition and cropDefinition.StageAdvanceRatio) or 0.6))
	return math.max(1, math.floor(intervalSeconds * stageAdvanceRatio))
end

local function format_countdown(remainingSeconds: number): string
	local totalSeconds = math.max(0, math.ceil(remainingSeconds))
	local seconds = totalSeconds % 60
	local minutes = math.floor(totalSeconds / 60) % 60
	local hours = math.floor(totalSeconds / 3600)

	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds)
	end

	return string.format("%02d:%02d", minutes, seconds)
end

local function get_water_indicator_template(): Instance?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	local waterIndicatorFolder = assetsFolder and assetsFolder:FindFirstChild(WATER_INDICATOR_FOLDER_NAME)
	local template = waterIndicatorFolder and waterIndicatorFolder:FindFirstChild(WATER_INDICATOR_TEMPLATE_NAME)
	if template then
		return template
	end

	return nil
end

local function configure_water_indicator(indicator: Instance)
	if indicator:IsA("BasePart") then
		indicator.Anchored = true
		indicator.CanCollide = false
		indicator.CanTouch = false
		indicator.CanQuery = true
		indicator.Transparency = 1
	end

	for _, descendant in ipairs(indicator:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = true
			descendant.Transparency = 1
		elseif descendant:IsA("BillboardGui") then
			descendant.Enabled = true
		end
	end
end

local function get_instance_top_position(instance: Instance): (Vector3, Vector3)
	if instance:IsA("Model") then
		local boundingBoxCFrame, boundingBoxSize = instance:GetBoundingBox()
		return boundingBoxCFrame.Position + Vector3.new(0, boundingBoxSize.Y * 0.5, 0), boundingBoxSize
	end

	local basePart = FarmingUtility.GetFirstBasePart(instance)
	if basePart then
		return basePart.Position + Vector3.new(0, basePart.Size.Y * 0.5, 0), basePart.Size
	end

	return Vector3.zero, Vector3.zero
end

local function move_indicator_to_position(indicator: Instance, position: Vector3)
	if indicator:IsA("Model") then
		indicator:PivotTo(CFrame.new(position))
		return
	end

	local basePart = FarmingUtility.GetFirstBasePart(indicator)
	if basePart then
		basePart.CFrame = CFrame.new(position)
	end
end

local function position_water_indicator(state)
	if not state.WaterIndicator or not state.Model then
		return
	end

	local topPosition, size = get_instance_top_position(state.Model)
	local offsetY = math.max(WATER_INDICATOR_OFFSET_Y, size.Y * 0.25 + WATER_INDICATOR_OFFSET_Y)
	move_indicator_to_position(state.WaterIndicator, topPosition + Vector3.new(0, offsetY, 0))
end

local function destroy_water_indicator(state)
	if state.WaterIndicator then
		state.WaterIndicator:Destroy()
		state.WaterIndicator = nil
	end
end

local function ensure_water_indicator(state): Instance?
	if state.WaterIndicator and state.WaterIndicator.Parent then
		position_water_indicator(state)
		return state.WaterIndicator
	end

	local template = get_water_indicator_template()
	if not template then
		return nil
	end

	local indicator = template:Clone()
	indicator.Name = ("%s_%d_WaterIndicator"):format(state.Crop.CropId, state.Id)
	indicator:SetAttribute("FarmPlantId", state.Id)
	indicator:SetAttribute("FarmPlantOwnerUserId", state.OwnerUserId)
	indicator:SetAttribute("FarmCropId", state.Crop.CropId)
	configure_water_indicator(indicator)
	indicator.Parent = FarmingUtility.GetFarmFolder(true)

	state.WaterIndicator = indicator
	position_water_indicator(state)
	return indicator
end

local function set_water_indicator_mode(state, mode: string, remainingSeconds: number?)
	local indicator = ensure_water_indicator(state)
	if not indicator then
		return
	end

	local imageLabel = indicator:FindFirstChildWhichIsA("ImageLabel", true)
	local textLabel = indicator:FindFirstChildWhichIsA("TextLabel", true)

	if textLabel then
		textLabel.Visible = mode == "Countdown"
		if mode == "Countdown" then
			textLabel.Text = format_countdown(remainingSeconds or 0)
		end
	end

	if imageLabel then
		imageLabel.Visible = mode == "Ready"
	end
end

local function update_water_indicator(state)
	if state.Harvestable then
		destroy_water_indicator(state)
		return
	end

	if state.WaterReady then
		set_water_indicator_mode(state, "Ready")
		return
	end

	if state.NextWaterAt then
		set_water_indicator_mode(state, "Countdown", math.max(0, state.NextWaterAt - os.clock()))
	end
end

local function reset_stage_trove(state)
	if state.StageTrove then
		state.StageTrove:Destroy()
	end

	state.StageTrove = Trove.new()
end

local function clear_plant(state)
	state.TimerToken = (state.TimerToken or 0) + 1

	if state.StageTrove then
		state.StageTrove:Destroy()
		state.StageTrove = nil
	end

	destroy_water_indicator(state)
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
	position_water_indicator(state)

	return true
end

local function make_plant_harvestable(state)
	if activePlants[state.Id] ~= state or state.Harvestable then
		return
	end

	state.Harvestable = true
	state.WaterReady = false
	state.NextWaterAt = nil
	state.StageAdvanceAt = nil
	destroy_water_indicator(state)
	attach_harvest_prompt(state)
end

local function start_growth_timer(state, durationSeconds: number, shouldAdvanceStage: boolean)
	state.TimerToken = (state.TimerToken or 0) + 1
	state.WaterReady = false
	state.Harvestable = false
	state.GrowthError = nil
	state.StageAdvanced = false

	local token = state.TimerToken
	local now = os.clock()
	local maxStage = get_crop_max_stage(state.Crop)
	local duration = math.max(1, math.floor(durationSeconds))

	state.NextWaterAt = now + duration
	state.StageAdvanceAt = nil

	if shouldAdvanceStage and state.Stage < maxStage then
		state.StageAdvanceAt = now + get_stage_advance_delay(state.Crop, duration)
	end

	update_water_indicator(state)

	task.spawn(function()
		while activePlants[state.Id] == state and state.TimerToken == token do
			local currentTime = os.clock()

			if state.StageAdvanceAt and not state.StageAdvanced and currentTime >= state.StageAdvanceAt then
				state.StageAdvanced = true

				if state.Stage < maxStage and not create_stage_visual(state, state.Stage + 1) then
					state.GrowthError = "StageTemplateMissing"
					state.TimerToken += 1
					destroy_water_indicator(state)
					return
				end
			end

			local remainingSeconds = (state.NextWaterAt or currentTime) - currentTime
			if remainingSeconds <= 0 then
				if state.Stage >= maxStage then
					make_plant_harvestable(state)
				else
					state.WaterReady = true
					state.NextWaterAt = nil
					state.StageAdvanceAt = nil
					update_water_indicator(state)
				end

				return
			end

			update_water_indicator(state)
			task.wait(math.min(WATER_INDICATOR_UPDATE_INTERVAL, remainingSeconds))
		end
	end)
end

local function validate_stage_templates(cropDefinition): (boolean, number?)
	for stage = 1, get_crop_max_stage(cropDefinition) do
		if not FarmingUtility.GetStageTemplate(cropDefinition, stage) then
			return false, stage
		end
	end

	return true, nil
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

	local hasStageTemplates, missingStage = validate_stage_templates(cropDefinition)
	if not hasStageTemplates then
		return {
			Success = false,
			Code = "StageTemplateMissing",
			MissingStage = missingStage,
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
		WaterIndicator = nil,
		TimerToken = 0,
		WaterReady = false,
		Harvestable = false,
		NextWaterAt = nil,
		StageAdvanceAt = nil,
		StageAdvanced = false,
	}

	activePlants[state.Id] = state

	if not create_stage_visual(state, 1) then
		activePlants[state.Id] = nil
		return {
			Success = false,
			Code = "StageTemplateMissing",
		}
	end

	start_growth_timer(state, get_initial_water_delay(cropDefinition), false)

	return {
		Success = true,
		Code = "Planted",
		PlantId = state.Id,
		CropId = cropDefinition.CropId,
		NextWaterInSeconds = get_initial_water_delay(cropDefinition),
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

	if state.Harvestable then
		return {
			Success = false,
			Code = "PlantAlreadyMature",
		}
	end

	if state.GrowthError then
		return {
			Success = false,
			Code = state.GrowthError,
		}
	end

	if not state.WaterReady then
		return {
			Success = false,
			Code = "WaterNotReady",
			PlantId = state.Id,
			RemainingSeconds = state.NextWaterAt and math.max(0, math.ceil(state.NextWaterAt - os.clock())) or 0,
		}
	end

	local waterInterval = get_water_interval(state.Crop)
	start_growth_timer(state, waterInterval, true)

	return {
		Success = true,
		Code = "PlantWatered",
		PlantId = state.Id,
		Stage = state.Stage,
		CropId = state.Crop.CropId,
		NextWaterInSeconds = waterInterval,
		StageAdvancesInSeconds = get_stage_advance_delay(state.Crop, waterInterval),
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
