local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")
local ServerModules = script.Parent.Parent

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))
local CropRarityUtility = require(Utility:WaitForChild("CropRarityUtility"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local FarmingShopService = require(script.Parent:WaitForChild("FarmingShopService"))
local QuestService = require(ServerModules:WaitForChild("Quest"):WaitForChild("QuestService"))
local GrowthSchedule = require(script.Parent:WaitForChild("GrowthSchedule"))

local FarmingService = {}

local initialized = false
local nextPlantId = 0
local activePlants: { [number]: any } = {}
local activePlantIdsByPlayer: { [Player]: { [number]: boolean } } = {}
local playerTroves: { [Player]: any } = {}
local restoreTokensByPlayer: { [Player]: number } = {}
local lastStableLevelByPlayer: { [Player]: any } = {}

local WATER_INDICATOR_FOLDER_NAME = "WaterFarm"
local WATER_INDICATOR_TEMPLATE_NAME = "WaterFarm"
local WATER_INDICATOR_UPDATE_INTERVAL = 1
local WATER_INDICATOR_OFFSET_Y = 0.8
local PLANT_HITBOX_NAME_SUFFIX = "Hitbox"
local PLANT_HITBOX_HEIGHT = 0.45
local PLAYER_PLOT_WAIT_TIMEOUT_SECONDS = 10

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

local function get_state_status(state): string
	if state.Harvestable then
		return "Harvestable"
	elseif state.WaterReady then
		return "WaterReady"
	elseif state.GrowthError then
		return "Error"
	end

	return "Growing"
end

local function get_state_footprint_size(state): Vector3
	return state.FootprintSize or FarmingUtility.PLANT_FOOTPRINT_SIZE
end

local function set_plant_attributes(instance: Instance, state)
	instance:SetAttribute("FarmPlantId", state.Id)
	instance:SetAttribute("FarmPlantPersistentId", state.PersistentId)
	instance:SetAttribute("FarmPlantStage", state.Stage)
	instance:SetAttribute("FarmPlantOwnerUserId", state.OwnerUserId)
	instance:SetAttribute("FarmCropId", state.Crop.CropId)
	instance:SetAttribute("FarmSeedItemId", state.Crop.Seed.ItemId)
	instance:SetAttribute("FarmFruitItemId", state.HarvestItem.ItemId)
	instance:SetAttribute("FarmCropRarity", state.Rarity or "")
	instance:SetAttribute("FarmPlantState", get_state_status(state))
	instance:SetAttribute("FarmPlantSoilId", state.SoilId)
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

local function get_now(): number
	return os.time()
end

local function round_number(value: number): number
	return math.floor((value * 1000) + 0.5) / 1000
end

local function get_player_from_state(state): Player?
	if state.Player and state.Player.Parent == Players then
		return state.Player
	end

	return Players:GetPlayerByUserId(state.OwnerUserId)
end

local function get_farming_data(player: Player): any?
	local profileData = DataUtility.server.get(player)
	if type(profileData) ~= "table" then
		return nil
	end

	local changed = false
	local farmingData = profileData.Farming

	if type(farmingData) ~= "table" then
		farmingData = {
			UnlockedPlots = 1,
		}
		changed = true
	end

	if type(farmingData.NextPlantId) ~= "number" then
		farmingData.NextPlantId = 0
		changed = true
	end

	if type(farmingData.Plants) ~= "table" then
		farmingData.Plants = {}
		changed = true
	end

	if changed then
		DataUtility.server.set(player, "Farming", farmingData)
	end

	return farmingData
end

local function find_saved_plant_index(farmingData, persistentId: number): number?
	for index, savedPlant in ipairs(farmingData.Plants or {}) do
		if type(savedPlant) == "table" and tonumber(savedPlant.PlantId) == persistentId then
			return index
		end
	end

	return nil
end

local function serialize_plant_state(state)
	local footprintSize = get_state_footprint_size(state)

	return {
		PlantId = state.PersistentId,
		CropId = state.Crop.CropId,
		SeedItemId = state.Crop.Seed.ItemId,
		HarvestItemId = state.HarvestItem.ItemId,
		Rarity = state.Rarity or "",
		SoilId = state.SoilId or "",
		LocalX = round_number(state.LocalPoint.X),
		LocalZ = round_number(state.LocalPoint.Z),
		FootprintX = round_number(footprintSize.X),
		FootprintZ = round_number(footprintSize.Z),
		Stage = state.Stage,
		PlantedAt = state.PlantedAt or get_now(),
		LastWateredAt = state.LastWateredAt or 0,
		NextWaterAt = state.NextWaterAt or 0,
		StageAdvanceAt = state.StageAdvanceAt or 0,
		StageAdvanced = state.StageAdvanced == true,
		WaterReady = state.WaterReady == true,
		Harvestable = state.Harvestable == true,
		GrowthError = state.GrowthError or "",
	}
end

local function persist_plant_state(state)
	local player = get_player_from_state(state)
	if not player or not state.PersistentId then
		return
	end

	local farmingData = get_farming_data(player)
	if not farmingData then
		return
	end

	local savedPlant = serialize_plant_state(state)
	local existingIndex = find_saved_plant_index(farmingData, state.PersistentId)
	if existingIndex then
		farmingData.Plants[existingIndex] = savedPlant
	else
		table.insert(farmingData.Plants, savedPlant)
	end

	DataUtility.server.set(player, "Farming", farmingData)
end

local function remove_saved_plant(player: Player, persistentId: number?)
	if not persistentId then
		return
	end

	local farmingData = get_farming_data(player)
	if not farmingData then
		return
	end

	local existingIndex = find_saved_plant_index(farmingData, persistentId)
	if not existingIndex then
		return
	end

	table.remove(farmingData.Plants, existingIndex)
	DataUtility.server.set(player, "Farming", farmingData)
end

local function allocate_saved_plant_id(farmingData): number
	local nextSavedPlantId = math.max(0, math.floor(tonumber(farmingData.NextPlantId) or 0)) + 1
	farmingData.NextPlantId = nextSavedPlantId
	return nextSavedPlantId
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

local function set_plant_spatial_attributes(instance: Instance, state)
	local footprintSize = get_state_footprint_size(state)

	set_plant_attributes(instance, state)
	instance:SetAttribute("FarmPlantLocalX", state.LocalPoint.X)
	instance:SetAttribute("FarmPlantLocalZ", state.LocalPoint.Z)
	instance:SetAttribute("FarmPlantFootprintX", footprintSize.X)
	instance:SetAttribute("FarmPlantFootprintZ", footprintSize.Z)
end

local function refresh_plant_attributes(state)
	if state.Model then
		set_plant_attributes(state.Model, state)
	end

	if state.Hitbox then
		set_plant_spatial_attributes(state.Hitbox, state)
	end
end

local function position_plant_hitbox(state)
	if not state.Hitbox or not state.Soil then
		return
	end

	local footprintSize = get_state_footprint_size(state)
	state.Hitbox.Size = Vector3.new(footprintSize.X, PLANT_HITBOX_HEIGHT, footprintSize.Z)
	state.Hitbox.CFrame = state.Soil.CFrame
		* CFrame.new(
			state.LocalPoint.X,
			state.Soil.Size.Y * 0.5 + PLANT_HITBOX_HEIGHT * 0.5 + 0.04,
			state.LocalPoint.Z
		)
end

local function ensure_plant_hitbox(state): BasePart?
	if state.Hitbox and state.Hitbox.Parent then
		position_plant_hitbox(state)
		set_plant_spatial_attributes(state.Hitbox, state)
		return state.Hitbox
	end

	if not state.Soil then
		return nil
	end

	local hitbox = Instance.new("Part")
	hitbox.Name = ("%s_%d_%s"):format(state.Crop.CropId, state.Id, PLANT_HITBOX_NAME_SUFFIX)
	hitbox.Anchored = true
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.CanQuery = true
	hitbox.Transparency = 1
	hitbox.CastShadow = false
	set_plant_spatial_attributes(hitbox, state)
	hitbox.Parent = FarmingUtility.GetFarmFolder(true)

	state.Hitbox = hitbox
	position_plant_hitbox(state)

	return hitbox
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
		set_water_indicator_mode(state, "Countdown", math.max(0, state.NextWaterAt - get_now()))
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
	if state.GrowthSchedule then
		state.GrowthSchedule:Destroy()
		state.GrowthSchedule = nil
	end

	if state.StageTrove then
		state.StageTrove:Destroy()
		state.StageTrove = nil
	end

	destroy_water_indicator(state)
	if state.Hitbox then
		state.Hitbox:Destroy()
		state.Hitbox = nil
	end

	state.Model = nil
end

local function unregister_active_plant(state)
	activePlants[state.Id] = nil

	local player = state.Player
	local playerPlants = player and activePlantIdsByPlayer[player] or nil
	if playerPlants then
		playerPlants[state.Id] = nil
	end
end

local function register_active_plant(player: Player, state)
	state.Player = player
	activePlants[state.Id] = state

	local playerPlants = activePlantIdsByPlayer[player]
	if not playerPlants then
		playerPlants = {}
		activePlantIdsByPlayer[player] = playerPlants
	end

	playerPlants[state.Id] = true
end

local function destroy_active_plant(state)
	clear_plant(state)
	unregister_active_plant(state)
end

local function clear_player_plants(player: Player)
	local playerPlants = activePlantIdsByPlayer[player]
	if not playerPlants then
		return
	end

	local plantIds = {}
	for plantId in pairs(playerPlants) do
		table.insert(plantIds, plantId)
	end

	for _, plantId in ipairs(plantIds) do
		local state = activePlants[plantId]
		if state then
			destroy_active_plant(state)
		end
	end

	activePlantIdsByPlayer[player] = nil
end

local function attach_harvest_prompt(state)
	local harvestHandle = FarmingUtility.FindHarvestHandle(state.Model)
	if not harvestHandle then
		return
	end

	local existingPrompt = harvestHandle:FindFirstChild("HarvestPrompt")
	if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
		existingPrompt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "HarvestPrompt"
	prompt.ActionText = "Colher"
	prompt.ObjectText = state.HarvestItem.DisplayName
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

		FarmingShopService.AwardHarvest(player, state.HarvestItem)
		QuestService.IncrementStat(player, "Stats.TotalCropsHarvested", 1)

		remove_saved_plant(player, state.PersistentId)
		destroy_active_plant(state)
	end))
end

local function create_stage_visual(state, stage: number)
	if not state.Soil or not state.Soil.Parent then
		return false
	end

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
	ensure_plant_hitbox(state)
	refresh_plant_attributes(state)
	position_water_indicator(state)

	return true
end

local function make_plant_harvestable(state)
	if activePlants[state.Id] ~= state then
		return
	end

	state.Harvestable = true
	state.WaterReady = false
	state.NextWaterAt = nil
	state.StageAdvanceAt = nil
	if state.GrowthSchedule then
		state.GrowthSchedule:Destroy()
		state.GrowthSchedule = nil
	end
	destroy_water_indicator(state)
	refresh_plant_attributes(state)
	persist_plant_state(state)

	if state.Model then
		CropRarityUtility.ApplyToInstance(state.Model, state.HarvestItem)
		attach_harvest_prompt(state)
	end
end

local function fail_growth(state, code: string)
	state.GrowthError = code
	state.TimerToken = (state.TimerToken or 0) + 1
	if state.GrowthSchedule then
		state.GrowthSchedule:Destroy()
		state.GrowthSchedule = nil
	end
	destroy_water_indicator(state)
	refresh_plant_attributes(state)
	persist_plant_state(state)
end

local function advance_stage_if_due(state, currentTime: number): boolean
	if not state.StageAdvanceAt or state.StageAdvanced or currentTime < state.StageAdvanceAt then
		return false
	end

	state.StageAdvanced = true

	if state.Stage < get_crop_max_stage(state.Crop) and not create_stage_visual(state, state.Stage + 1) then
		fail_growth(state, "StageTemplateMissing")
		return true
	end

	refresh_plant_attributes(state)
	persist_plant_state(state)
	return true
end

local function finish_growth_interval_if_due(state, currentTime: number): boolean
	if not state.NextWaterAt or currentTime < state.NextWaterAt then
		return false
	end

	if state.Stage >= get_crop_max_stage(state.Crop) then
		make_plant_harvestable(state)
	else
		state.WaterReady = true
		state.NextWaterAt = nil
		state.StageAdvanceAt = nil
		refresh_plant_attributes(state)
		update_water_indicator(state)
		persist_plant_state(state)
	end

	return true
end

local function apply_elapsed_growth(state, currentTime: number): boolean
	if state.Harvestable or state.WaterReady or state.GrowthError then
		return false
	end

	local advanced = advance_stage_if_due(state, currentTime)
	if state.GrowthError then
		return true
	end

	local finished = finish_growth_interval_if_due(state, currentTime)
	return advanced or finished
end

local function start_growth_schedule(state)
	state.TimerToken = (state.TimerToken or 0) + 1
	if state.GrowthSchedule then
		state.GrowthSchedule:Destroy()
	end

	update_water_indicator(state)
	state.GrowthSchedule = GrowthSchedule.new({
		Now = get_now,
		GetDeadline = function(): number?
			if activePlants[state.Id] ~= state
				or state.WaterReady
				or state.Harvestable
				or state.GrowthError
				or not state.NextWaterAt
			then
				return nil
			end

			local now = get_now()
			local deadline = state.NextWaterAt
			if state.StageAdvanceAt and not state.StageAdvanced then
				deadline = math.min(deadline, state.StageAdvanceAt)
			end
			return math.min(deadline, now + WATER_INDICATOR_UPDATE_INTERVAL)
		end,
		Advance = function(currentTime: number): ()
			if activePlants[state.Id] ~= state then
				return
			end
			apply_elapsed_growth(state, currentTime)
			update_water_indicator(state)
		end,
	})
	state.GrowthSchedule:Refresh()
end

local function resume_growth_timer(state)
	apply_elapsed_growth(state, get_now())

	if not state.WaterReady and not state.Harvestable and not state.GrowthError and state.NextWaterAt then
		start_growth_schedule(state)
	else
		update_water_indicator(state)
	end
end

local function start_growth_timer(state, durationSeconds: number, shouldAdvanceStage: boolean)
	state.WaterReady = false
	state.Harvestable = false
	state.GrowthError = nil
	state.StageAdvanced = false

	local now = get_now()
	local maxStage = get_crop_max_stage(state.Crop)
	local duration = math.max(1, math.floor(durationSeconds))

	state.NextWaterAt = now + duration
	state.StageAdvanceAt = nil

	if shouldAdvanceStage and state.Stage < maxStage then
		state.StageAdvanceAt = now + get_stage_advance_delay(state.Crop, duration)
	end

	refresh_plant_attributes(state)
	persist_plant_state(state)
	start_growth_schedule(state)
end

local function is_active_placement_occupied(player: Player, placement): boolean
	for _, state in pairs(activePlants) do
		if state.OwnerUserId == player.UserId and state.Soil == placement.Soil then
			if FarmingUtility.FootprintsOverlap(
				placement.LocalPoint,
				placement.FootprintSize,
				state.LocalPoint,
				get_state_footprint_size(state)
			) then
				return true
			end
		end
	end

	local occupied = FarmingUtility.IsPlacementOccupied(placement, player.UserId)
	return occupied == true
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

	local placement = FarmingUtility.GetSoilPlacementData(worldPosition, player)
	if not placement then
		return {
			Success = false,
			Code = "InvalidSoil",
		}
	end

	if is_active_placement_occupied(player, placement) then
		return {
			Success = false,
			Code = "PlantSpaceOccupied",
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

	local farmingData = get_farming_data(player)
	if not farmingData then
		return {
			Success = false,
			Code = "FarmingDataMissing",
		}
	end

	local consumedSeed, consumeResponse = FarmingShopService.ConsumeSeed(player, cropDefinition.Seed)
	if not consumedSeed then
		return consumeResponse
	end

	nextPlantId += 1

	local rarity = FarmingCatalog.RollHarvestRarity()
	local harvestItem = FarmingCatalog.GetHarvestItem(cropDefinition, rarity) or cropDefinition.Fruit
	local now = get_now()
	local persistentId = allocate_saved_plant_id(farmingData)
	local state = {
		Id = nextPlantId,
		PersistentId = persistentId,
		Player = player,
		OwnerUserId = player.UserId,
		Crop = cropDefinition,
		HarvestItem = harvestItem,
		Rarity = rarity,
		Soil = placement.Soil,
		SoilId = placement.SoilId,
		LocalPoint = placement.LocalPoint,
		FootprintSize = placement.FootprintSize or FarmingUtility.PLANT_FOOTPRINT_SIZE,
		PlantedAt = now,
		LastWateredAt = 0,
		Stage = 0,
		Model = nil,
		Hitbox = nil,
		StageTrove = nil,
		GrowthSchedule = nil,
		WaterIndicator = nil,
		TimerToken = 0,
		WaterReady = false,
		Harvestable = false,
		NextWaterAt = nil,
		StageAdvanceAt = nil,
		StageAdvanced = false,
	}

	register_active_plant(player, state)

	if not create_stage_visual(state, 1) then
		destroy_active_plant(state)
		return {
			Success = false,
			Code = "StageTemplateMissing",
		}
	end

	table.insert(farmingData.Plants, serialize_plant_state(state))
	DataUtility.server.set(player, "Farming", farmingData)
	start_growth_timer(state, get_initial_water_delay(cropDefinition), false)

	return {
		Success = true,
		Code = "Planted",
		PlantId = state.PersistentId,
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

	apply_elapsed_growth(state, get_now())

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
			PlantId = state.PersistentId,
			RemainingSeconds = state.NextWaterAt and math.max(0, math.ceil(state.NextWaterAt - get_now())) or 0,
		}
	end

	local waterInterval = get_water_interval(state.Crop)
	state.LastWateredAt = get_now()
	start_growth_timer(state, waterInterval, true)

	return {
		Success = true,
		Code = "PlantWatered",
		PlantId = state.PersistentId,
		Stage = state.Stage,
		CropId = state.Crop.CropId,
		NextWaterInSeconds = waterInterval,
		StageAdvancesInSeconds = get_stage_advance_delay(state.Crop, waterInterval),
	}
end

local function wait_for_player_plot(player: Player): Instance?
	local startedAt = os.clock()
	local plot = FarmingUtility.GetPlayerPlot(player)

	while not plot and player.Parent == Players and os.clock() - startedAt < PLAYER_PLOT_WAIT_TIMEOUT_SECONDS do
		task.wait(0.2)
		plot = FarmingUtility.GetPlayerPlot(player)
	end

	return plot
end

local function get_saved_number(savedPlant, key: string, fallback: number): number
	local value = type(savedPlant) == "table" and tonumber(savedPlant[key]) or nil
	return if value then value else fallback
end

local function get_saved_timestamp(savedPlant, key: string): number?
	local value = get_saved_number(savedPlant, key, 0)
	return if value > 0 then math.floor(value) else nil
end

local function get_saved_harvest_item(cropDefinition, savedPlant)
	local rarity = type(savedPlant) == "table" and savedPlant.Rarity or nil
	if type(rarity) ~= "string" or rarity == "" then
		rarity = nil
	end

	return FarmingCatalog.GetHarvestItem(cropDefinition, rarity) or cropDefinition.Fruit, rarity
end

local function create_state_from_saved_plant(player: Player, savedPlant): any?
	if type(savedPlant) ~= "table" then
		return nil
	end

	local persistentId = math.floor(tonumber(savedPlant.PlantId) or 0)
	if persistentId <= 0 then
		return nil
	end

	local cropDefinition = FarmingCatalog.GetCrop(savedPlant.CropId)
	if not cropDefinition then
		return nil
	end

	local soilId = type(savedPlant.SoilId) == "string" and savedPlant.SoilId or nil
	local soil = FarmingUtility.GetPlayerSoilPartById(player, soilId)
	if not soil then
		return nil
	end

	local defaultFootprint = FarmingUtility.PLANT_FOOTPRINT_SIZE
	local footprintSize = Vector3.new(
		math.max(0.1, get_saved_number(savedPlant, "FootprintX", defaultFootprint.X)),
		defaultFootprint.Y,
		math.max(0.1, get_saved_number(savedPlant, "FootprintZ", defaultFootprint.Z))
	)
	local localPoint = Vector3.new(
		get_saved_number(savedPlant, "LocalX", 0),
		0,
		get_saved_number(savedPlant, "LocalZ", 0)
	)

	if not FarmingUtility.IsFootprintInsideSoil(soil, localPoint, footprintSize) then
		return nil
	end

	local maxStage = get_crop_max_stage(cropDefinition)
	local savedStage = math.clamp(math.floor(get_saved_number(savedPlant, "Stage", 1)), 1, maxStage)
	local harvestItem, rarity = get_saved_harvest_item(cropDefinition, savedPlant)
	local growthError = type(savedPlant.GrowthError) == "string" and savedPlant.GrowthError or nil
	if growthError == "" then
		growthError = nil
	end

	nextPlantId += 1

	return {
		Id = nextPlantId,
		PersistentId = persistentId,
		Player = player,
		OwnerUserId = player.UserId,
		Crop = cropDefinition,
		HarvestItem = harvestItem,
		Rarity = rarity,
		Soil = soil,
		SoilId = FarmingUtility.GetSoilId(soil, FarmingUtility.GetPlayerPlot(player)) or soilId,
		LocalPoint = localPoint,
		FootprintSize = footprintSize,
		PlantedAt = get_saved_timestamp(savedPlant, "PlantedAt") or get_now(),
		LastWateredAt = get_saved_timestamp(savedPlant, "LastWateredAt") or 0,
		Stage = savedStage,
		Model = nil,
		Hitbox = nil,
		StageTrove = nil,
		GrowthSchedule = nil,
		WaterIndicator = nil,
		TimerToken = 0,
		WaterReady = savedPlant.WaterReady == true,
		Harvestable = savedPlant.Harvestable == true,
		NextWaterAt = get_saved_timestamp(savedPlant, "NextWaterAt"),
		StageAdvanceAt = get_saved_timestamp(savedPlant, "StageAdvanceAt"),
		StageAdvanced = savedPlant.StageAdvanced == true,
		GrowthError = growthError,
	}
end

local function sync_restored_state(state): boolean
	register_active_plant(state.Player, state)

	if not create_stage_visual(state, state.Stage) then
		fail_growth(state, "StageTemplateMissing")
		destroy_active_plant(state)
		return false
	end

	if state.Harvestable then
		make_plant_harvestable(state)
	elseif state.WaterReady then
		refresh_plant_attributes(state)
		update_water_indicator(state)
		persist_plant_state(state)
	elseif state.GrowthError then
		destroy_water_indicator(state)
		refresh_plant_attributes(state)
	else
		resume_growth_timer(state)
	end

	return true
end

local function restore_player_plants(player: Player, token: number)
	local plot = wait_for_player_plot(player)
	if player.Parent ~= Players or restoreTokensByPlayer[player] ~= token then
		return
	end

	clear_player_plants(player)

	if not plot then
		return
	end

	local farmingData = get_farming_data(player)
	if not farmingData then
		return
	end
	if restoreTokensByPlayer[player] ~= token then
		return
	end

	local maxSavedPlantId = math.max(0, math.floor(tonumber(farmingData.NextPlantId) or 0))

	for _, savedPlant in ipairs(farmingData.Plants or {}) do
		if restoreTokensByPlayer[player] ~= token then
			return
		end

		if type(savedPlant) == "table" then
			local savedPlantId = math.floor(tonumber(savedPlant.PlantId) or 0)
			maxSavedPlantId = math.max(maxSavedPlantId, savedPlantId)

			local state = create_state_from_saved_plant(player, savedPlant)
			if state then
				sync_restored_state(state)
			end
		end
	end

	if farmingData.NextPlantId ~= maxSavedPlantId then
		farmingData.NextPlantId = maxSavedPlantId
		DataUtility.server.set(player, "Farming", farmingData)
	end
end

local function schedule_restore_player_plants(player: Player)
	restoreTokensByPlayer[player] = (restoreTokensByPlayer[player] or 0) + 1
	local token = restoreTokensByPlayer[player]

	task.spawn(function()
		restore_player_plants(player, token)
	end)
end

local function bind_plot_value(player: Player, plotValue: ObjectValue, trove)
	trove:Connect(plotValue:GetPropertyChangedSignal("Value"), function()
		schedule_restore_player_plants(player)
	end)
end

local function disconnect_player(player: Player)
	restoreTokensByPlayer[player] = (restoreTokensByPlayer[player] or 0) + 1
	lastStableLevelByPlayer[player] = nil
	DataUtility.server.flush(player)
	clear_player_plants(player)
	activePlantIdsByPlayer[player] = nil

	local trove = playerTroves[player]
	if trove then
		trove:Destroy()
		playerTroves[player] = nil
	end

	restoreTokensByPlayer[player] = nil
end

local function track_player(player: Player)
	if playerTroves[player] then
		return
	end

	local trove = Trove.new()
	playerTroves[player] = trove

	local stableConnection = DataUtility.server.bind(player, "Stable", function(stable)
		local stableLevel = if type(stable) == "table" then stable.Level else nil
		if lastStableLevelByPlayer[player] == stableLevel then
			return
		end

		lastStableLevelByPlayer[player] = stableLevel
		task.defer(schedule_restore_player_plants, player)
	end)
	if stableConnection then
		trove:Add(stableConnection)
	end

	local plotValue = player:FindFirstChild(FarmingUtility.PLOT_VALUE_NAME)
	if plotValue and plotValue:IsA("ObjectValue") then
		bind_plot_value(player, plotValue, trove)
	end

	trove:Connect(player.ChildAdded, function(child)
		if child.Name == FarmingUtility.PLOT_VALUE_NAME and child:IsA("ObjectValue") then
			bind_plot_value(player, child, trove)
			schedule_restore_player_plants(player)
		end
	end)

	task.defer(schedule_restore_player_plants, player)
end

function FarmingService.PlayerReady(player: Player)
	track_player(player)
	schedule_restore_player_plants(player)
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

	for _, player in ipairs(Players:GetPlayers()) do
		track_player(player)
	end

	Players.PlayerAdded:Connect(track_player)
	Players.PlayerRemoving:Connect(disconnect_player)

	initialized = true
end

return FarmingService
