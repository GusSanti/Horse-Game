local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))

local FarmingService = {}

local initialized = false
local nextPlantId = 0
local activePlants: { [number]: any } = {}

local function get_equipped_tool(player: Player, toolName: string): Tool?
	local character = player.Character
	if not character then
		return nil
	end

	local equippedTool = character:FindFirstChildOfClass("Tool")
	if equippedTool and equippedTool.Name == toolName then
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
end

local function get_anchor_part(instance: Instance): BasePart?
	if instance:IsA("Model") and instance.PrimaryPart then
		return instance.PrimaryPart
	end

	return FarmingUtility.GetFirstBasePart(instance)
end

local function destroy_display_tool(state)
	if state.HarvestTool then
		state.HarvestTool:Destroy()
		state.HarvestTool = nil
	end
end

local function reset_stage_trove(state)
	if state.StageTrove then
		state.StageTrove:Destroy()
	end

	state.StageTrove = Trove.new()
end

local function clear_plant(state, keepHarvestTool: boolean?)
	if state.StageTrove then
		state.StageTrove:Destroy()
		state.StageTrove = nil
	end

	if not keepHarvestTool then
		destroy_display_tool(state)
	end

	state.Model = nil
end

local function prepare_tool_for_inventory(tool: Tool)
	for _, descendant in ipairs(tool:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant:Destroy()
		elseif descendant:IsA("WeldConstraint") then
			local part0 = descendant.Part0
			local part1 = descendant.Part1
			local part0InsideTool = part0 and part0:IsDescendantOf(tool)
			local part1InsideTool = part1 and part1:IsDescendantOf(tool)

			if not (part0InsideTool and part1InsideTool) then
				descendant:Destroy()
			end
		end
	end

	local handle = FarmingUtility.GetToolHandle(tool)
	if handle then
		handle.Anchored = false
		handle.CanCollide = false
		handle.CanTouch = true
	end
end

local function award_harvest_tool(player: Player, tool: Tool)
	prepare_tool_for_inventory(tool)

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 2)
	local character = player.Character

	if backpack then
		tool.Parent = backpack
	elseif character then
		tool.Parent = character
	else
		tool.Parent = player
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid:EquipTool(tool)
	end
end

local function attach_harvest_prompt(state)
	local harvestTool = FarmingUtility.GetHarvestToolTemplate():Clone()
	local handle = FarmingUtility.GetToolHandle(harvestTool)
	local anchorPart = state.Model and get_anchor_part(state.Model)

	if not handle or not anchorPart then
		harvestTool:Destroy()
		return
	end

	set_plant_attributes(harvestTool, state)
	set_plant_attributes(handle, state)

	handle.CFrame = anchorPart.CFrame
	handle.Anchored = false
	handle.CanCollide = false

	local weldConstraint = handle:FindFirstChildOfClass("WeldConstraint")
	if not weldConstraint then
		weldConstraint = Instance.new("WeldConstraint")
		weldConstraint.Parent = handle
	end

	weldConstraint.Part0 = handle
	weldConstraint.Part1 = anchorPart

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Colher"
	prompt.ObjectText = harvestTool.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = handle

	harvestTool.Parent = FarmingUtility.GetFarmFolder(true)
	state.HarvestTool = harvestTool

	state.StageTrove:Add(prompt.Triggered:Connect(function(player)
		if player.UserId ~= state.OwnerUserId then
			return
		end

		if not activePlants[state.Id] or state.HarvestTool ~= harvestTool then
			return
		end

		prompt:Destroy()

		state.HarvestTool = nil
		award_harvest_tool(player, harvestTool)

		clear_plant(state, true)
		activePlants[state.Id] = nil
	end))
end

local function create_stage_visual(state, stage: number)
	local placementWorldPosition = FarmingUtility.GetWorldTopPosition(state.Soil, state.LocalPoint)
	local stageTemplate = FarmingUtility.GetStageTemplate(stage)
	local stageClone = stageTemplate:Clone()
	local bottomOffset = get_instance_bottom_offset(stageTemplate)
	local worldPosition = placementWorldPosition + state.Soil.CFrame.UpVector * bottomOffset

	reset_stage_trove(state)
	destroy_display_tool(state)

	state.Stage = stage
	state.Model = stageClone

	stageClone.Name = ("FarmPlant_%d_Stage%d"):format(state.Id, stage)
	set_plant_attributes(stageClone, state)
	move_instance_to_position(stageClone, worldPosition)
	configure_stage_visual(stageClone)
	stageClone.Parent = FarmingUtility.GetFarmFolder(true)

	state.StageTrove:Add(stageClone)

	if stage >= FarmingUtility.MAX_STAGE then
		attach_harvest_prompt(state)
	end
end

function FarmingService.PlaceSeed(player: Player, worldPosition: Vector3)
	if typeof(worldPosition) ~= "Vector3" then
		return {
			Success = false,
			Code = "InvalidPosition",
		}
	end

	if not get_equipped_tool(player, FarmingUtility.SEED_TOOL_NAME) then
		return {
			Success = false,
			Code = "SeedNotEquipped",
		}
	end

	local placement = FarmingUtility.GetSoilPlacementData(worldPosition)
	if not placement then
		return {
			Success = false,
			Code = "InvalidSoil",
		}
	end

	nextPlantId += 1

	local state = {
		Id = nextPlantId,
		OwnerUserId = player.UserId,
		Soil = placement.Soil,
		LocalPoint = placement.LocalPoint,
		Stage = 0,
		Model = nil,
		HarvestTool = nil,
		StageTrove = nil,
	}

	activePlants[state.Id] = state
	create_stage_visual(state, 1)

	return {
		Success = true,
		Code = "Planted",
		PlantId = state.Id,
	}
end

function FarmingService.WaterPlant(player: Player, targetInstance: Instance)
	if typeof(targetInstance) ~= "Instance" then
		return {
			Success = false,
			Code = "InvalidTarget",
		}
	end

	if not get_equipped_tool(player, FarmingUtility.WATERING_TOOL_NAME) then
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

	if state.Stage >= FarmingUtility.MAX_STAGE then
		return {
			Success = false,
			Code = "PlantAlreadyMature",
		}
	end

	create_stage_visual(state, state.Stage + 1)

	return {
		Success = true,
		Code = "PlantWatered",
		PlantId = state.Id,
		Stage = state.Stage,
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
