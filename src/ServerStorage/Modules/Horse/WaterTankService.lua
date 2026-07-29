local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")
local ServerModules = ServerStorage:WaitForChild("Modules")
local InventoryModules = ServerModules:WaitForChild("Inventory")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local InventoryService = require(InventoryModules:WaitForChild("InventoryServer"))
local InventoryLoadoutService = require(InventoryModules:WaitForChild("InventoryLoadoutService"))
local Net = require(Libraries:WaitForChild("Net"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local Trove = require(Libraries:WaitForChild("Trove"))

local WaterTankService = {}

local FRESH_BUCKET_ITEM_ID = "fresh_bucket"
local FILL_WATER_TANK_FUNCTION_NAME = "FillStableWaterTank"
local PLOT_VALUE_NAME = "Plot"
local STABLES_FOLDER_NAME = "Stables"
local HORSE_WATER_FOLDER_NAME = "HorseWater"
local WATER_TANK_MODEL_NAME = "TankHorseWater"
local WATER_PART_NAME = "Water"
local WATER_TANK_FILLED_FIELD = "WaterTankFilled"
local WATER_TANK_FILLED_ATTRIBUTE = "StableWaterTankFilled"
local MAX_FILL_DISTANCE = 12

local initialized = false
local activeRequestByPlayer = {}
local playerTroves = {}
local lastPlotByPlayer = {}

local function get_player_plot(player: Player): Instance?
	local plotValue = player:FindFirstChild(PLOT_VALUE_NAME)
	if not plotValue or not plotValue:IsA("ObjectValue") then
		return nil
	end

	return plotValue.Value
end

local function find_water_tank_model(plot: Instance?): Instance?
	local horseWaterFolder = plot and plot:FindFirstChild(HORSE_WATER_FOLDER_NAME)
	if not horseWaterFolder then
		return nil
	end

	return horseWaterFolder:FindFirstChild(WATER_TANK_MODEL_NAME)
		or horseWaterFolder:FindFirstChild(WATER_TANK_MODEL_NAME, true)
end

local function find_water_part(waterTankModel: Instance?): BasePart?
	if not waterTankModel then
		return nil
	end

	local waterPart = waterTankModel:FindFirstChild(WATER_PART_NAME, true)
	return if waterPart and waterPart:IsA("BasePart") then waterPart else nil
end

local function find_prompt_parent(waterTankModel: Instance?): BasePart?
	if not waterTankModel then
		return nil
	end

	if waterTankModel:IsA("BasePart") and waterTankModel.Name ~= WATER_PART_NAME then
		return waterTankModel
	end

	if waterTankModel:IsA("Model")
		and waterTankModel.PrimaryPart
		and waterTankModel.PrimaryPart.Name ~= WATER_PART_NAME
	then
		return waterTankModel.PrimaryPart
	end

	for _, child in ipairs(waterTankModel:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= WATER_PART_NAME then
			return child
		end
	end

	for _, descendant in ipairs(waterTankModel:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= WATER_PART_NAME then
			return descendant
		end
	end

	return find_water_part(waterTankModel)
end

local function set_water_tank_filled(waterTankModel: Instance?, isFilled: boolean)
	if not waterTankModel then
		return
	end

	waterTankModel:SetAttribute(WATER_TANK_FILLED_ATTRIBUTE, isFilled)

	local waterPart = find_water_part(waterTankModel)
	if waterPart then
		waterPart.Transparency = if isFilled then 0 else 1
	end
end

local function get_normalized_water_tank_filled(stable): boolean
	return type(stable) == "table" and stable[WATER_TANK_FILLED_FIELD] == true
end

local function normalize_stable_water_tank(player: Player): (any?, boolean)
	local stable = DataUtility.server.get(player, "Stable")
	if type(stable) ~= "table" then
		return nil, false
	end

	local isFilled = get_normalized_water_tank_filled(stable)
	if stable[WATER_TANK_FILLED_FIELD] ~= isFilled then
		stable[WATER_TANK_FILLED_FIELD] = isFilled
		DataUtility.server.set(player, "Stable", stable)
	end

	return stable, isFilled
end

local function sync_plot_visuals(plot: Instance?, isFilled: boolean)
	set_water_tank_filled(find_water_tank_model(plot), isFilled)
end

function WaterTankService.SyncPlayerVisuals(player: Player)
	local _stable, isFilled = normalize_stable_water_tank(player)
	local plot = get_player_plot(player)
	if not plot then
		return
	end

	lastPlotByPlayer[player] = plot
	sync_plot_visuals(plot, isFilled)
end

local function clear_plot_visuals(plot: Instance?)
	sync_plot_visuals(plot, false)
end

local function is_tool_equipped_fresh_bucket(player: Player, tool: Instance?): boolean
	local character = player.Character
	if not character or not tool or not tool:IsA("Tool") or tool.Parent ~= character then
		return false
	end

	local itemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
	return itemDefinition ~= nil and itemDefinition.ItemId == FRESH_BUCKET_ITEM_ID
end

local function is_player_close_enough(player: Player, waterTankModel: Instance): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local promptParent = find_prompt_parent(waterTankModel)

	if not rootPart or not rootPart:IsA("BasePart") or not promptParent then
		return false
	end

	return (rootPart.Position - promptParent.Position).Magnitude <= MAX_FILL_DISTANCE
end

local function fill_water_tank(player: Player, tool: Instance?): (boolean, string)
	if activeRequestByPlayer[player] then
		return false, "Busy"
	end

	if not is_tool_equipped_fresh_bucket(player, tool) then
		return false, "FreshBucketToolNotEquipped"
	end

	local plot = get_player_plot(player)
	local waterTankModel = find_water_tank_model(plot)
	if not plot or not waterTankModel or not is_player_close_enough(player, waterTankModel) then
		return false, "TooFar"
	end

	local stable, isFilled = normalize_stable_water_tank(player)
	if type(stable) ~= "table" then
		return false, "StableMissing"
	end

	if isFilled then
		return false, "WaterTankFull"
	end

	local itemDefinition = ToolItemCatalog.GetItemDefinition(FRESH_BUCKET_ITEM_ID)
	if not itemDefinition then
		return false, "FreshBucketItemMissing"
	end

	local itemCount = InventoryService.GetItemCount(player, itemDefinition)
	if itemCount <= 0 then
		return false, "FreshBucketUnavailable"
	end

	activeRequestByPlayer[player] = true
	local success, result, reason = pcall(function()
		DataUtility.server.begin_batch(player)
		InventoryService.SetItemCount(player, itemDefinition, itemCount - 1)
		stable[WATER_TANK_FILLED_FIELD] = true
		DataUtility.server.set(player, "Stable", stable)
		DataUtility.server.end_batch(player)

		sync_plot_visuals(plot, true)
		InventoryLoadoutService.SyncPlayerTools(player)
		return true, "Filled"
	end)
	activeRequestByPlayer[player] = nil

	if not success then
		warn(("[WaterTankService] failed to fill water tank for %s: %s"):format(player.Name, tostring(result)))
		return false, "ServerError"
	end

	return result == true, reason or "Filled"
end

local function hide_all_stable_water()
	local stablesFolder = Workspace:FindFirstChild(STABLES_FOLDER_NAME)
	if not stablesFolder then
		return
	end

	for _, plot in ipairs(stablesFolder:GetChildren()) do
		clear_plot_visuals(plot)
	end
end

local function disconnect_player(player: Player)
	activeRequestByPlayer[player] = nil
	clear_plot_visuals(lastPlotByPlayer[player])
	lastPlotByPlayer[player] = nil

	local trove = playerTroves[player]
	if trove then
		trove:Destroy()
		playerTroves[player] = nil
	end
end

local function bind_plot_value(player: Player, plotValue: ObjectValue, trove)
	trove:Connect(plotValue:GetPropertyChangedSignal("Value"), function()
		WaterTankService.SyncPlayerVisuals(player)
	end)

	task.defer(WaterTankService.SyncPlayerVisuals, player)
end

local function track_player(player: Player)
	disconnect_player(player)

	local trove = Trove.new()
	playerTroves[player] = trove

	local stableConnection = DataUtility.server.bind(player, "Stable", function()
		WaterTankService.SyncPlayerVisuals(player)
	end)

	if stableConnection then
		trove:Add(stableConnection)
	end

	local plotValue = player:FindFirstChild(PLOT_VALUE_NAME)
	if plotValue and plotValue:IsA("ObjectValue") then
		bind_plot_value(player, plotValue, trove)
	end

	trove:Connect(player.ChildAdded, function(child)
		if child.Name == PLOT_VALUE_NAME and child:IsA("ObjectValue") then
			bind_plot_value(player, child, trove)
		end
	end)

	task.defer(WaterTankService.SyncPlayerVisuals, player)
end

function WaterTankService.PlayerReady(player: Player)
	WaterTankService.SyncPlayerVisuals(player)
end

function WaterTankService.Init()
	if initialized then
		return
	end

	initialized = true
	Net.Function[FILL_WATER_TANK_FUNCTION_NAME]:Respond(fill_water_tank)
	hide_all_stable_water()

	for _, player in ipairs(Players:GetPlayers()) do
		track_player(player)
	end

	Players.PlayerAdded:Connect(track_player)
	Players.PlayerRemoving:Connect(disconnect_player)

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == STABLES_FOLDER_NAME then
			task.defer(hide_all_stable_water)
		end
	end)
end

return WaterTankService
