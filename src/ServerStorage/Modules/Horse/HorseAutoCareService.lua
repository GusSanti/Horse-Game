local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local Utility = Modules:WaitForChild("Utility")

local ServerModules = ServerStorage:WaitForChild("Modules")
local HorseModules = ServerModules:WaitForChild("Horse")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local ToolDictionary = require(Dictionary:WaitForChild("ToolDictionary"))
local HayBaleService = require(HorseModules:WaitForChild("HayBaleService"))
local HorseCareService = require(HorseModules:WaitForChild("HorseCareService"))
local HorseRoamingService = require(HorseModules:WaitForChild("HorseRoamingService"))
local WaterTankService = require(HorseModules:WaitForChild("WaterTankService"))

local HorseAutoCareService = {}

local PLOT_VALUE_NAME = ToolDictionary.PlotValueName
local MOUNTED_USER_ID_ATTRIBUTE = ToolDictionary.MountedUserIdAttribute

local HAY_BALE_FOLDER_NAME = "HayBaleFolder"
local HAY_BALE_BUNDLE_NAME = "HaybaleBundle"
local HAY_BALE_MODEL_PREFIX = "Haybale"
local HAY_BALES_PLACED_FIELD = "HayBalesPlaced"
local MAX_HAY_BALES = 3

local HORSE_WATER_FOLDER_NAME = "HorseWater"
local WATER_TANK_MODEL_NAME = "TankHorseWater"
local WATER_PART_NAME = "Water"
local WATER_TANK_FILLED_FIELD = "WaterTankFilled"

local NEED_TRIGGER_RATIO = 0.9
local SCAN_INTERVAL_SECONDS = 8
local ACTION_REPEAT_COUNT = 3
local ACTION_SECONDS_PER_REPEAT = 1.55
local ACTION_MOVE_TIMEOUT_SECONDS = 26
local HAY_APPROACH_DISTANCE = 5
local WATER_APPROACH_DISTANCE = 4.25

local initialized = false
local activeActionByPlayer = {}

local function get_player_plot(player: Player): Instance?
	local plotValue = player:FindFirstChild(PLOT_VALUE_NAME)
	if plotValue and plotValue:IsA("ObjectValue") then
		return plotValue.Value
	end

	return nil
end

local function get_hay_bale_bundle(plot: Instance?): Instance?
	local hayBaleFolder = plot and plot:FindFirstChild(HAY_BALE_FOLDER_NAME)
	return hayBaleFolder and hayBaleFolder:FindFirstChild(HAY_BALE_BUNDLE_NAME) or nil
end

local function find_hay_bale_model(plot: Instance?, slotIndex: number): Instance?
	local bundle = get_hay_bale_bundle(plot)
	if not bundle then
		return nil
	end

	local modelName = ("%s%d"):format(HAY_BALE_MODEL_PREFIX, slotIndex)
	return bundle:FindFirstChild(modelName) or bundle:FindFirstChild(modelName, true)
end

local function find_water_tank_model(plot: Instance?): Instance?
	local horseWaterFolder = plot and plot:FindFirstChild(HORSE_WATER_FOLDER_NAME)
	if not horseWaterFolder then
		return nil
	end

	return horseWaterFolder:FindFirstChild(WATER_TANK_MODEL_NAME)
		or horseWaterFolder:FindFirstChild(WATER_TANK_MODEL_NAME, true)
end

local function find_water_target(waterTankModel: Instance?): Instance?
	if not waterTankModel then
		return nil
	end

	local waterPart = waterTankModel:FindFirstChild(WATER_PART_NAME, true)
	if waterPart and waterPart:IsA("BasePart") then
		return waterPart
	end

	return waterTankModel
end

local function get_normalized_hay_count(stable): number
	local placedCount = type(stable) == "table" and tonumber(stable[HAY_BALES_PLACED_FIELD]) or 0
	return math.clamp(math.floor(placedCount or 0), 0, MAX_HAY_BALES)
end

local function is_water_tank_filled(stable): boolean
	return type(stable) == "table" and stable[WATER_TANK_FILLED_FIELD] == true
end

local function get_instance_cframe(instance: Instance?): CFrame?
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	if instance:IsA("Model") then
		local success, pivot = pcall(function()
			return instance:GetPivot()
		end)
		if success then
			return pivot
		end
	end

	local part = instance:FindFirstChildWhichIsA("BasePart", true)
	return part and part.CFrame or nil
end

local function get_action_positions(visual: Instance, target: Instance, approachDistance: number): (Vector3?, Vector3?)
	local visualCFrame = get_instance_cframe(visual)
	local targetCFrame = get_instance_cframe(target)
	if not visualCFrame or not targetCFrame then
		return nil, nil
	end

	local visualPosition = visualCFrame.Position
	local targetPosition = targetCFrame.Position
	local awayFromTarget = Vector3.new(
		visualPosition.X - targetPosition.X,
		0,
		visualPosition.Z - targetPosition.Z
	)
	if awayFromTarget.Magnitude <= 0.1 then
		local lookVector = targetCFrame.LookVector
		awayFromTarget = Vector3.new(-lookVector.X, 0, -lookVector.Z)
	end
	if awayFromTarget.Magnitude <= 0.1 then
		awayFromTarget = Vector3.new(0, 0, -1)
	end

	local standPosition = targetPosition + (awayFromTarget.Unit * approachDistance)
	return Vector3.new(standPosition.X, targetPosition.Y, standPosition.Z), targetPosition
end

local function is_visual_mounted(visual: Instance?): boolean
	if not visual then
		return false
	end

	return (tonumber(visual:GetAttribute(MOUNTED_USER_ID_ATTRIBUTE)) or 0) > 0
end

local function get_need_ratio(horse, needKey: string): number?
	local needs = horse and horse.Needs
	local values = needs and needs.Values
	local maxValues = needs and needs.Max
	local maxValue = tonumber(maxValues and maxValues[needKey]) or 100
	if maxValue <= 0 then
		return nil
	end

	local value = tonumber(values and values[needKey]) or maxValue
	return math.clamp(value / maxValue, 0, 1)
end

local function get_assigned_horse_ids(stable, horses): {string}
	local assignedById = {}
	local ids = {}
	local horseSlots = type(stable) == "table" and stable.HorseSlots or nil
	if type(horseSlots) == "table" then
		for _, assignedHorseId in horseSlots do
			if type(assignedHorseId) == "string"
				and assignedHorseId ~= ""
				and not assignedById[assignedHorseId]
			then
				assignedById[assignedHorseId] = true
				ids[#ids + 1] = assignedHorseId
			end
		end
	end

	local equippedHorseId = type(horses) == "table" and horses.EquippedHorseId or nil
	if #ids == 0 and type(equippedHorseId) == "string" and equippedHorseId ~= "" then
		ids[1] = equippedHorseId
	end

	return ids
end

local function build_action_candidate(player: Player)
	local plot = get_player_plot(player)
	local stable = DataUtility.server.get(player, "Stable")
	local horses = DataUtility.server.get(player, "Horses")
	local owned = type(horses) == "table" and horses.Owned or nil
	if not plot or type(stable) ~= "table" or type(owned) ~= "table" then
		return nil
	end

	local hayCount = get_normalized_hay_count(stable)
	local waterFilled = is_water_tank_filled(stable)
	if hayCount <= 0 and not waterFilled then
		return nil
	end

	local bestCandidate = nil
	for _, horseId in get_assigned_horse_ids(stable, horses) do
		local horse = owned[horseId]
		local visual = horse and HorseRoamingService.GetLiveVisual(player, horseId) or nil
		if visual and visual.Parent and not is_visual_mounted(visual) then
			if hayCount > 0 then
				local hungerRatio = get_need_ratio(horse, "Hunger")
				if hungerRatio and hungerRatio <= NEED_TRIGGER_RATIO then
					local hayTarget = find_hay_bale_model(plot, hayCount)
					if hayTarget then
						bestCandidate = bestCandidate or {
							HorseId = horseId,
							Visual = visual,
							Target = hayTarget,
							Resource = "Hay",
							NeedKey = "Hunger",
							Behavior = "Eating",
							ApproachDistance = HAY_APPROACH_DISTANCE,
							Score = hungerRatio,
						}
						if hungerRatio < bestCandidate.Score then
							bestCandidate = {
								HorseId = horseId,
								Visual = visual,
								Target = hayTarget,
								Resource = "Hay",
								NeedKey = "Hunger",
								Behavior = "Eating",
								ApproachDistance = HAY_APPROACH_DISTANCE,
								Score = hungerRatio,
							}
						end
					end
				end
			end

			if waterFilled then
				local thirstRatio = get_need_ratio(horse, "Thirst")
				if thirstRatio and thirstRatio <= NEED_TRIGGER_RATIO then
					local waterTarget = find_water_target(find_water_tank_model(plot))
					if waterTarget then
						local candidate = {
							HorseId = horseId,
							Visual = visual,
							Target = waterTarget,
							Resource = "Water",
							NeedKey = "Thirst",
							Behavior = "Drinking",
							ApproachDistance = WATER_APPROACH_DISTANCE,
							Score = thirstRatio,
						}
						if not bestCandidate or candidate.Score < bestCandidate.Score then
							bestCandidate = candidate
						end
					end
				end
			end
		end
	end

	return bestCandidate
end

local function restore_need_to_full(horse, needKey: string, now: number): boolean
	local needs = horse.Needs
	local values = needs and needs.Values
	local maxValues = needs and needs.Max
	if not values or not maxValues then
		return false
	end

	local maxValue = tonumber(maxValues[needKey]) or 100
	local currentValue = tonumber(values[needKey]) or 0
	values[needKey] = math.clamp(maxValue, 0, maxValue)

	horse.State = horse.State or {}
	horse.State.LastCareAt = now
	if needKey == "Hunger" then
		horse.State.LastFedAt = now
	elseif needKey == "Thirst" then
		horse.State.LastWateredAt = now
	end

	return currentValue ~= values[needKey]
end

local function is_need_full(horse, needKey: string): boolean
	local needs = horse.Needs
	local values = needs and needs.Values
	local maxValues = needs and needs.Max
	local maxValue = tonumber(maxValues and maxValues[needKey]) or 100
	local currentValue = tonumber(values and values[needKey]) or maxValue
	return currentValue >= maxValue
end

local function consume_resource_and_restore(player: Player, action): boolean
	local stable = DataUtility.server.get(player, "Stable")
	local horses = DataUtility.server.get(player, "Horses")
	local owned = type(horses) == "table" and horses.Owned or nil
	local horse = type(owned) == "table" and owned[action.HorseId] or nil
	if type(stable) ~= "table" or not horse then
		return false
	end

	local now = os.time()
	HorseCareService.RefreshHorse(horse, now)
	if is_need_full(horse, action.NeedKey) then
		return false
	end

	if action.Resource == "Hay" then
		local hayCount = get_normalized_hay_count(stable)
		if hayCount <= 0 then
			return false
		end
		stable[HAY_BALES_PLACED_FIELD] = hayCount - 1
	elseif action.Resource == "Water" then
		if not is_water_tank_filled(stable) then
			return false
		end
		stable[WATER_TANK_FILLED_FIELD] = false
	else
		return false
	end

	restore_need_to_full(horse, action.NeedKey, now)

	DataUtility.server.begin_batch(player)
	DataUtility.server.set(player, "Stable", stable)
	DataUtility.server.set(player, "Horses.Owned", owned)
	DataUtility.server.end_batch(player)

	if action.Resource == "Hay" then
		HayBaleService.SyncPlayerVisuals(player)
	elseif action.Resource == "Water" then
		WaterTankService.SyncPlayerVisuals(player)
	end

	return true
end

local function perform_action(player: Player, action)
	local visual = action.Visual
	if not visual or not visual.Parent or is_visual_mounted(visual) then
		return
	end

	local targetPosition, facePosition = get_action_positions(visual, action.Target, action.ApproachDistance)
	if not targetPosition or not facePosition then
		return
	end

	local completed = HorseRoamingService.PerformStableAction(player, action.HorseId, visual, {
		TargetPosition = targetPosition,
		FacePosition = facePosition,
		Behavior = action.Behavior,
		RepeatCount = ACTION_REPEAT_COUNT,
		RepeatDuration = ACTION_SECONDS_PER_REPEAT,
		MoveTimeout = ACTION_MOVE_TIMEOUT_SECONDS,
	})
	if completed then
		consume_resource_and_restore(player, action)
	end
end

local function try_start_player_action(player: Player)
	if activeActionByPlayer[player] then
		return
	end

	local action = build_action_candidate(player)
	if not action then
		return
	end

	activeActionByPlayer[player] = true
	task.spawn(function()
		local success, err = pcall(function()
			perform_action(player, action)
		end)
		if not success then
			warn(("[HorseAutoCareService] failed to perform auto care for %s: %s"):format(
				player.Name,
				tostring(err)
			))
		end

		activeActionByPlayer[player] = nil
	end)
end

function HorseAutoCareService.Init()
	if initialized then
		return
	end

	initialized = true

	Players.PlayerRemoving:Connect(function(player)
		activeActionByPlayer[player] = nil
	end)

	task.spawn(function()
		while initialized do
			for _, player in ipairs(Players:GetPlayers()) do
				try_start_player_action(player)
			end

			task.wait(SCAN_INTERVAL_SECONDS)
		end
	end)
end

function HorseAutoCareService.Destroy()
	initialized = false
	table.clear(activeActionByPlayer)
end

return HorseAutoCareService
