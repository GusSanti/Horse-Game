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

local HayBaleService = {}

local HAY_BALE_ITEM_ID = "hay_bale"
local PLACE_HAY_BALE_FUNCTION_NAME = "PlaceStableHayBale"
local PLOT_VALUE_NAME = "Plot"
local STABLES_FOLDER_NAME = "Stables"
local HAY_BALE_FOLDER_NAME = "HayBaleFolder"
local HAY_BALE_BUNDLE_NAME = "HaybaleBundle"
local HAY_BALE_MODEL_PREFIX = "Haybale"
local HAY_BALES_PLACED_FIELD = "HayBalesPlaced"
local STABLE_HAY_BALE_ORIGINAL_CAN_COLLIDE_ATTRIBUTE = "StableHayBaleOriginalCanCollide"
local STABLE_HAY_BALE_ORIGINAL_CAN_TOUCH_ATTRIBUTE = "StableHayBaleOriginalCanTouch"
local STABLE_HAY_BALE_ORIGINAL_CAN_QUERY_ATTRIBUTE = "StableHayBaleOriginalCanQuery"
local MAX_HAY_BALES = 3
local MAX_PLACE_DISTANCE = 12

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

local function find_prompt_parent(model: Instance?): BasePart?
	if not model then
		return nil
	end

	if model:IsA("BasePart") then
		return model
	end

	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function set_model_visible(model: Instance?, isVisible: boolean)
	if not model then
		return
	end

	local function apply_part(part: BasePart)
		if part:GetAttribute(STABLE_HAY_BALE_ORIGINAL_CAN_COLLIDE_ATTRIBUTE) == nil then
			part:SetAttribute(STABLE_HAY_BALE_ORIGINAL_CAN_COLLIDE_ATTRIBUTE, part.CanCollide)
			part:SetAttribute(STABLE_HAY_BALE_ORIGINAL_CAN_TOUCH_ATTRIBUTE, part.CanTouch)
			part:SetAttribute(STABLE_HAY_BALE_ORIGINAL_CAN_QUERY_ATTRIBUTE, part.CanQuery)
		end

		part.Transparency = if isVisible then 0 else 1
		part.CanCollide = isVisible
		part.CanTouch = isVisible and part:GetAttribute(STABLE_HAY_BALE_ORIGINAL_CAN_TOUCH_ATTRIBUTE) == true
		part.CanQuery = isVisible and part:GetAttribute(STABLE_HAY_BALE_ORIGINAL_CAN_QUERY_ATTRIBUTE) == true
	end

	if model:IsA("BasePart") then
		apply_part(model)
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			apply_part(descendant)
		end
	end
end

local function get_normalized_hay_bales_placed(stable): number
	local placedCount = type(stable) == "table" and tonumber(stable[HAY_BALES_PLACED_FIELD]) or 0
	return math.clamp(math.floor(placedCount or 0), 0, MAX_HAY_BALES)
end

local function normalize_stable_hay_bales(player: Player): (any?, number)
	local stable = DataUtility.server.get(player, "Stable")
	if type(stable) ~= "table" then
		return nil, 0
	end

	local placedCount = get_normalized_hay_bales_placed(stable)
	if stable[HAY_BALES_PLACED_FIELD] ~= placedCount then
		stable[HAY_BALES_PLACED_FIELD] = placedCount
		DataUtility.server.set(player, "Stable", stable)
	end

	return stable, placedCount
end

local function sync_plot_visuals(plot: Instance?, placedCount: number)
	if not plot then
		return
	end

	for slotIndex = 1, MAX_HAY_BALES do
		set_model_visible(find_hay_bale_model(plot, slotIndex), slotIndex <= placedCount)
	end
end

function HayBaleService.SyncPlayerVisuals(player: Player)
	local _stable, placedCount = normalize_stable_hay_bales(player)
	local plot = get_player_plot(player)
	if not plot then
		return
	end

	lastPlotByPlayer[player] = plot
	sync_plot_visuals(plot, placedCount)
end

local function clear_plot_visuals(plot: Instance?)
	sync_plot_visuals(plot, 0)
end

local function is_tool_equipped_hay_bale(player: Player, tool: Instance?): boolean
	local character = player.Character
	if not character or not tool or not tool:IsA("Tool") or tool.Parent ~= character then
		return false
	end

	local itemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
	return itemDefinition ~= nil and itemDefinition.ItemId == HAY_BALE_ITEM_ID
end

local function is_player_close_enough(player: Player, hayBaleModel: Instance): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local promptParent = find_prompt_parent(hayBaleModel)

	if not rootPart or not rootPart:IsA("BasePart") or not promptParent then
		return false
	end

	return (rootPart.Position - promptParent.Position).Magnitude <= MAX_PLACE_DISTANCE
end

local function place_hay_bale(player: Player, tool: Instance?, requestedSlotIndex): (boolean, string)
	if activeRequestByPlayer[player] then
		return false, "Busy"
	end

	if not is_tool_equipped_hay_bale(player, tool) then
		return false, "HayBaleToolNotEquipped"
	end

	local slotIndex = math.floor(tonumber(requestedSlotIndex) or 0)
	if slotIndex < 1 or slotIndex > MAX_HAY_BALES then
		return false, "InvalidSlot"
	end

	local plot = get_player_plot(player)
	local hayBaleModel = find_hay_bale_model(plot, slotIndex)
	if not plot or not hayBaleModel or not is_player_close_enough(player, hayBaleModel) then
		return false, "TooFar"
	end

	local stable, placedCount = normalize_stable_hay_bales(player)
	if type(stable) ~= "table" then
		return false, "StableMissing"
	end

	local expectedSlotIndex = placedCount + 1
	if slotIndex ~= expectedSlotIndex then
		return false, placedCount >= MAX_HAY_BALES and "HayBalesFull" or "WrongSlotOrder"
	end

	local itemDefinition = ToolItemCatalog.GetItemDefinition(HAY_BALE_ITEM_ID)
	if not itemDefinition then
		return false, "HayBaleItemMissing"
	end

	local itemCount = InventoryService.GetItemCount(player, itemDefinition)
	if itemCount <= 0 then
		return false, "HayBaleUnavailable"
	end

	activeRequestByPlayer[player] = true

	DataUtility.server.begin_batch(player)
	InventoryService.SetItemCount(player, itemDefinition, itemCount - 1)
	stable[HAY_BALES_PLACED_FIELD] = slotIndex
	DataUtility.server.set(player, "Stable", stable)
	DataUtility.server.end_batch(player)

	sync_plot_visuals(plot, slotIndex)
	InventoryLoadoutService.SyncPlayerTools(player)
	activeRequestByPlayer[player] = nil

	return true, "Placed"
end

local function hide_all_stable_hay_bales()
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
		HayBaleService.SyncPlayerVisuals(player)
	end)

	task.defer(HayBaleService.SyncPlayerVisuals, player)
end

local function track_player(player: Player)
	disconnect_player(player)

	local trove = Trove.new()
	playerTroves[player] = trove

	local stableConnection = DataUtility.server.bind(player, "Stable", function()
		HayBaleService.SyncPlayerVisuals(player)
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

	task.defer(HayBaleService.SyncPlayerVisuals, player)
end

function HayBaleService.PlayerReady(player: Player)
	HayBaleService.SyncPlayerVisuals(player)
end

function HayBaleService.Init()
	if initialized then
		return
	end

	initialized = true
	Net.Function[PLACE_HAY_BALE_FUNCTION_NAME]:Respond(place_hay_bale)
	hide_all_stable_hay_bales()

	for _, player in ipairs(Players:GetPlayers()) do
		track_player(player)
	end

	Players.PlayerAdded:Connect(track_player)
	Players.PlayerRemoving:Connect(disconnect_player)

	Workspace.ChildAdded:Connect(function(child)
		if child.Name == STABLES_FOLDER_NAME then
			task.defer(hide_all_stable_hay_bales)
		end
	end)
end

return HayBaleService
