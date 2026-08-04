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

local InventoryService = require(InventoryModules:WaitForChild("InventoryServer"))
local InventoryLoadoutService = require(InventoryModules:WaitForChild("InventoryLoadoutService"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local WellWaterService = {}

local WELL_WATER_FUNCTION_NAME = "WellWaterAction"
local FRESH_BUCKET_ITEM_ID = "fresh_bucket"
local WELL_NAME = "Well"
local WELL_HANDLE_NAME = "WellHandle"
local BUCKET_NAME = "Bucket"
local CAMERA_PART_NAME = "Cam"
local WATER_TIME_NAME = "WaterTime"
local PROMPT_NAME = "WellWaterPrompt"
local PLOT_VALUE_NAME = "Plot"
local OWNER_USER_ID_ATTRIBUTE = "OwnerUserId"

local DEFAULT_REQUIRED_TURNS = 3
local DEFAULT_COOLDOWN_SECONDS = 60
local MAX_INTERACTION_DISTANCE = 18
local BUSY_TIMEOUT_SECONDS = 45

local WELL_PROMPT_ATTRIBUTE = "WellWaterPrompt"
local SERVER_PROMPT_ENABLED_ATTRIBUTE = "WellWaterPromptEnabled"
local BUCKET_READY_ATTRIBUTE = "WellWaterBucketReady"
local BUSY_USER_ID_ATTRIBUTE = "WellWaterBusyUserId"
local BUSY_UNTIL_ATTRIBUTE = "WellWaterBusyUntil"
local STATE_ATTRIBUTE = "WellWaterState"
local REQUIRED_TURNS_ATTRIBUTE = "WellWaterRequiredTurns"
local COOLDOWN_SECONDS_ATTRIBUTE = "WellWaterCooldownSeconds"
local NEXT_READY_AT_ATTRIBUTE = "WellWaterNextReadyAt"
local LAST_OWNER_USER_ID_ATTRIBUTE = "WellWaterLastOwnerUserId"
local WELL_COOLDOWN_FIELD = "WellWaterReadyAt"
local ORIGINAL_TRANSPARENCY_ATTRIBUTE = "WellWaterOriginalTransparency"
local ORIGINAL_CAN_COLLIDE_ATTRIBUTE = "WellWaterOriginalCanCollide"
local ORIGINAL_CAN_TOUCH_ATTRIBUTE = "WellWaterOriginalCanTouch"
local ORIGINAL_CAN_QUERY_ATTRIBUTE = "WellWaterOriginalCanQuery"
local ORIGINAL_ENABLED_ATTRIBUTE = "WellWaterOriginalEnabled"

local configuredWells = {}
local initialized = false

local function trim(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	return if trimmedValue ~= "" then trimmedValue else nil
end

local function find_named_descendant(root, names, className)
	if not root then
		return nil
	end

	for _, name in ipairs(names) do
		local descendant = root:FindFirstChild(name, true)
		if descendant and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function find_bucket(well)
	return find_named_descendant(well, { BUCKET_NAME }, nil)
end

local function find_water_time_label(well)
	local waterTime = find_named_descendant(well, { WATER_TIME_NAME }, nil)
	if not waterTime then
		return nil
	end

	local billboard = waterTime:FindFirstChildWhichIsA("BillboardGui", true)
	local label = billboard and billboard:FindFirstChildWhichIsA("TextLabel", true)
		or waterTime:FindFirstChildWhichIsA("TextLabel", true)

	return if label and label:IsA("TextLabel") then label else nil
end

local function find_prompt_parent(well)
	local bucket = find_bucket(well)
	local handleRoot = find_named_descendant(well, { WELL_HANDLE_NAME }, nil)

	for _, name in ipairs({ "WaterDrak", "WellPromptPart", "PromptPart" }) do
		local preferredPart = find_named_descendant(well, { name }, "BasePart")
		if preferredPart
			and (not bucket or not preferredPart:IsDescendantOf(bucket))
			and (not handleRoot or not preferredPart:IsDescendantOf(handleRoot))
		then
			return preferredPart
		end
	end

	if well:IsA("Model")
		and well.PrimaryPart
		and (not bucket or not well.PrimaryPart:IsDescendantOf(bucket))
		and (not handleRoot or not well.PrimaryPart:IsDescendantOf(handleRoot))
	then
		return well.PrimaryPart
	end

	for _, descendant in ipairs(well:GetDescendants()) do
		if descendant:IsA("BasePart")
			and descendant.Name ~= CAMERA_PART_NAME
			and (not bucket or not descendant:IsDescendantOf(bucket))
			and (not handleRoot or not descendant:IsDescendantOf(handleRoot))
		then
			return descendant
		end
	end

	return well:FindFirstChildWhichIsA("BasePart", true)
end

local function get_required_turns(well)
	local requiredTurns = tonumber(well:GetAttribute(REQUIRED_TURNS_ATTRIBUTE)) or DEFAULT_REQUIRED_TURNS
	return math.max(1, requiredTurns)
end

local function get_cooldown_seconds(well)
	local cooldownSeconds = tonumber(well:GetAttribute(COOLDOWN_SECONDS_ATTRIBUTE)) or DEFAULT_COOLDOWN_SECONDS
	return math.max(0, math.floor(cooldownSeconds))
end

local function format_seconds(seconds)
	local remaining = math.max(0, math.ceil(tonumber(seconds) or 0))
	local minutes = math.floor(remaining / 60)
	local secondsPart = remaining % 60
	return ("%02d:%02d"):format(minutes, secondsPart)
end

local function store_part_originals(part)
	if part:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE) == nil then
		part:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, part.Transparency)
		part:SetAttribute(ORIGINAL_CAN_COLLIDE_ATTRIBUTE, part.CanCollide)
		part:SetAttribute(ORIGINAL_CAN_TOUCH_ATTRIBUTE, part.CanTouch)
		part:SetAttribute(ORIGINAL_CAN_QUERY_ATTRIBUTE, part.CanQuery)
	end
end

local function set_part_visible(part, isVisible)
	store_part_originals(part)

	if isVisible then
		part.Transparency = part:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE) or 0
		part.CanCollide = part:GetAttribute(ORIGINAL_CAN_COLLIDE_ATTRIBUTE) == true
		part.CanTouch = part:GetAttribute(ORIGINAL_CAN_TOUCH_ATTRIBUTE) == true
		part.CanQuery = part:GetAttribute(ORIGINAL_CAN_QUERY_ATTRIBUTE) == true
	else
		part.Transparency = 1
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
	end
end

local function store_enabled_original(instance)
	if instance:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE) == nil then
		instance:SetAttribute(ORIGINAL_ENABLED_ATTRIBUTE, instance.Enabled == true)
	end
end

local function set_enabled_visible(instance, isVisible)
	store_enabled_original(instance)
	instance.Enabled = isVisible and instance:GetAttribute(ORIGINAL_ENABLED_ATTRIBUTE) == true
end

local function set_bucket_visible(well, isVisible)
	local bucket = find_bucket(well)
	if not bucket then
		return
	end

	if bucket:IsA("BasePart") then
		set_part_visible(bucket, isVisible)
	end

	for _, descendant in ipairs(bucket:GetDescendants()) do
		if descendant:IsA("BasePart") then
			set_part_visible(descendant, isVisible)
		elseif descendant:IsA("Light") or descendant:IsA("ParticleEmitter") or descendant:IsA("Trail") or descendant:IsA("Beam") then
			set_enabled_visible(descendant, isVisible)
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			if descendant:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE) == nil then
				descendant:SetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE, descendant.Transparency)
			end
			descendant.Transparency = if isVisible then descendant:GetAttribute(ORIGINAL_TRANSPARENCY_ATTRIBUTE) or 0 else 1
		end
	end
end

local function clear_busy(well)
	well:SetAttribute(BUSY_USER_ID_ATTRIBUTE, nil)
	well:SetAttribute(BUSY_UNTIL_ATTRIBUTE, nil)
end

local function is_busy(well)
	local busyUserId = tonumber(well:GetAttribute(BUSY_USER_ID_ATTRIBUTE))
	local busyUntil = tonumber(well:GetAttribute(BUSY_UNTIL_ATTRIBUTE))

	if not busyUserId or busyUserId <= 0 then
		return false
	end

	if busyUntil and os.clock() > busyUntil then
		clear_busy(well)
		return false
	end

	return true, busyUserId
end

local function get_player_plot(player)
	local plotValue = player:FindFirstChild(PLOT_VALUE_NAME)
	if not plotValue or not plotValue:IsA("ObjectValue") then
		return nil
	end

	return plotValue.Value
end

local function get_owner_user_id(well)
	local current = well
	while current and current ~= Workspace do
		local ownerUserId = tonumber(current:GetAttribute(OWNER_USER_ID_ATTRIBUTE))
		if ownerUserId and ownerUserId > 0 then
			return ownerUserId
		end
		current = current.Parent
	end

	return nil
end

local function get_owner_player(well)
	local ownerUserId = get_owner_user_id(well)
	return ownerUserId and Players:GetPlayerByUserId(ownerUserId) or nil
end

local function is_well_in_player_plot(player, well)
	local plot = get_player_plot(player)
	if not plot or not well:IsDescendantOf(plot) then
		return false
	end

	local ownerUserId = get_owner_user_id(well)
	return ownerUserId == nil or ownerUserId == player.UserId
end

local function get_next_ready_at(player)
	local stable = DataUtility.server.get(player, "Stable")
	if type(stable) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(stable[WELL_COOLDOWN_FIELD]) or 0))
end

local function set_next_ready_at(player, nextReadyAt)
	local stable = DataUtility.server.get(player, "Stable")
	if type(stable) ~= "table" then
		return false
	end

	stable[WELL_COOLDOWN_FIELD] = math.max(0, math.floor(tonumber(nextReadyAt) or 0))
	DataUtility.server.set(player, "Stable", stable)
	return true
end

local function get_cooldown_remaining(player)
	return math.max(0, get_next_ready_at(player) - os.time())
end

local function sync_owner_state(well, owner)
	local ownerUserId = owner and owner.UserId or 0
	local previousOwnerUserId = tonumber(well:GetAttribute(LAST_OWNER_USER_ID_ATTRIBUTE)) or 0
	if ownerUserId == previousOwnerUserId then
		return
	end

	well:SetAttribute(LAST_OWNER_USER_ID_ATTRIBUTE, ownerUserId)
	well:SetAttribute(BUCKET_READY_ATTRIBUTE, false)
	clear_busy(well)
	set_bucket_visible(well, false)
end

local function update_water_time_label(well, owner, bucketReady, busy, cooldownRemaining)
	local label = find_water_time_label(well)
	if not label then
		return
	end

	if not owner then
		label.Text = ""
	elseif bucketReady then
		label.Text = "Collect"
	elseif busy then
		label.Text = "Cranking"
	elseif cooldownRemaining > 0 then
		label.Text = format_seconds(cooldownRemaining)
	else
		label.Text = "Ready"
	end
end

local function update_prompt(well)
	local promptParent = find_prompt_parent(well)
	if not promptParent then
		return
	end

	local prompt = promptParent:FindFirstChild(PROMPT_NAME)
	if prompt and not prompt:IsA("ProximityPrompt") then
		prompt:Destroy()
		prompt = nil
	end

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = 10
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Parent = promptParent
	end

	local owner = get_owner_player(well)
	sync_owner_state(well, owner)

	local bucketReady = well:GetAttribute(BUCKET_READY_ATTRIBUTE) == true
	local busy = is_busy(well)
	local cooldownRemaining = if owner then get_cooldown_remaining(owner) else 0
	local isCoolingDown = cooldownRemaining > 0 and not bucketReady
	local serverPromptEnabled = owner ~= nil and not busy and not isCoolingDown

	prompt:SetAttribute(WELL_PROMPT_ATTRIBUTE, true)
	prompt:SetAttribute(SERVER_PROMPT_ENABLED_ATTRIBUTE, serverPromptEnabled)
	prompt:SetAttribute(
		STATE_ATTRIBUTE,
		if bucketReady then "ReadyToCollect" elseif isCoolingDown then "Cooldown" else "ReadyToCrank"
	)
	prompt.Enabled = serverPromptEnabled
	prompt.ActionText = if bucketReady then "Collect" elseif isCoolingDown then "Wait" else "Crank"
	prompt.ObjectText = if bucketReady then "Fresh Bucket" elseif isCoolingDown then format_seconds(cooldownRemaining) else "Water Well"
	prompt.HoldDuration = if bucketReady then 0.35 else 0

	well:SetAttribute(NEXT_READY_AT_ATTRIBUTE, if owner then get_next_ready_at(owner) else 0)
	well:SetAttribute(
		STATE_ATTRIBUTE,
		if busy then "Cranking" elseif bucketReady then "ReadyToCollect" elseif isCoolingDown then "Cooldown" else "ReadyToCrank"
	)
	update_water_time_label(well, owner, bucketReady, busy, cooldownRemaining)
end

local function schedule_busy_timeout(well, busyUntil)
	task.delay(BUSY_TIMEOUT_SECONDS + 1, function()
		if not configuredWells[well] or not well.Parent then
			return
		end

		if tonumber(well:GetAttribute(BUSY_UNTIL_ATTRIBUTE)) ~= busyUntil then
			return
		end

		clear_busy(well)
		update_prompt(well)
	end)
end

local function is_well_model(instance)
	return instance
		and instance:IsA("Model")
		and (instance.Name == WELL_NAME or instance:GetAttribute("WellWaterSource") == true)
		and instance:FindFirstChild(WELL_HANDLE_NAME, true) ~= nil
		and instance:FindFirstChild(BUCKET_NAME, true) ~= nil
end

local function get_well_from_instance(instance)
	if typeof(instance) ~= "Instance" or not instance:IsDescendantOf(Workspace) then
		return nil
	end

	local current = instance
	while current and current ~= Workspace do
		if is_well_model(current) then
			return current
		end
		current = current.Parent
	end

	return nil
end

local function configure_well(well)
	if not is_well_model(well) then
		return
	end

	if configuredWells[well] then
		update_prompt(well)
		return
	end

	configuredWells[well] = true
	well:SetAttribute(REQUIRED_TURNS_ATTRIBUTE, get_required_turns(well))
	well:SetAttribute(BUCKET_READY_ATTRIBUTE, false)
	clear_busy(well)
	set_bucket_visible(well, false)
	update_prompt(well)

	well.Destroying:Connect(function()
		configuredWells[well] = nil
	end)
end

local function configure_related_well(instance)
	local well = get_well_from_instance(instance)
	if well then
		task.defer(configure_well, well)
	end
end

local function configure_existing_wells()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if is_well_model(descendant) then
			configure_well(descendant)
		end
	end
end

local function is_player_close_enough(player, well)
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local promptParent = find_prompt_parent(well)

	if not rootPart or not rootPart:IsA("BasePart") or not promptParent then
		return false
	end

	return (rootPart.Position - promptParent.Position).Magnitude <= MAX_INTERACTION_DISTANCE
end

local function begin_crank(player, well)
	configure_well(well)

	if not is_well_in_player_plot(player, well) then
		update_prompt(well)
		return { Success = false, Code = "NotYourWell" }
	end

	if well:GetAttribute(BUCKET_READY_ATTRIBUTE) == true then
		return { Success = false, Code = "BucketReady" }
	end

	local cooldownRemaining = get_cooldown_remaining(player)
	if cooldownRemaining > 0 then
		update_prompt(well)
		return { Success = false, Code = "Cooldown", RemainingSeconds = cooldownRemaining }
	end

	local busy, busyUserId = is_busy(well)
	if busy and busyUserId ~= player.UserId then
		update_prompt(well)
		return { Success = false, Code = "Busy" }
	end

	if not is_player_close_enough(player, well) then
		return { Success = false, Code = "TooFar" }
	end

	well:SetAttribute(BUSY_USER_ID_ATTRIBUTE, player.UserId)
	local busyUntil = os.clock() + BUSY_TIMEOUT_SECONDS
	well:SetAttribute(BUSY_UNTIL_ATTRIBUTE, busyUntil)
	update_prompt(well)
	schedule_busy_timeout(well, busyUntil)

	return {
		Success = true,
		Code = "CrankStarted",
		RequiredTurns = get_required_turns(well),
	}
end

local function complete_crank(player, well)
	configure_well(well)

	if not is_well_in_player_plot(player, well) then
		update_prompt(well)
		return { Success = false, Code = "NotYourWell" }
	end

	local busy, busyUserId = is_busy(well)
	if not busy or busyUserId ~= player.UserId then
		update_prompt(well)
		return { Success = false, Code = "NotCranking" }
	end

	if not is_player_close_enough(player, well) then
		clear_busy(well)
		update_prompt(well)
		return { Success = false, Code = "TooFar" }
	end

	well:SetAttribute(BUCKET_READY_ATTRIBUTE, true)
	clear_busy(well)
	set_bucket_visible(well, true)
	update_prompt(well)

	return { Success = true, Code = "BucketReady" }
end

local function cancel_crank(player, well)
	configure_well(well)

	if not is_well_in_player_plot(player, well) then
		return { Success = false, Code = "NotYourWell" }
	end

	local busy, busyUserId = is_busy(well)
	if busy and busyUserId == player.UserId then
		clear_busy(well)
		update_prompt(well)
	end

	return { Success = true, Code = "Cancelled" }
end

local function collect_bucket(player, well)
	configure_well(well)

	if not is_well_in_player_plot(player, well) then
		update_prompt(well)
		return { Success = false, Code = "NotYourWell" }
	end

	if well:GetAttribute(BUCKET_READY_ATTRIBUTE) ~= true then
		return { Success = false, Code = "BucketNotReady" }
	end

	if is_busy(well) then
		update_prompt(well)
		return { Success = false, Code = "Busy" }
	end

	if not is_player_close_enough(player, well) then
		return { Success = false, Code = "TooFar" }
	end

	local itemDefinition = ToolItemCatalog.GetItemDefinition(FRESH_BUCKET_ITEM_ID)
	if not itemDefinition then
		return { Success = false, Code = "FreshBucketItemMissing" }
	end

	local currentCount = InventoryService.GetItemCount(player, itemDefinition)
	if currentCount >= (itemDefinition.MaxStack or 99) then
		return { Success = false, Code = "InventoryFull", ItemId = itemDefinition.ItemId }
	end

	local updatedCount = InventoryService.AddItemCount(player, itemDefinition, 1)
	InventoryLoadoutService.SyncPlayerTools(player)

	well:SetAttribute(BUCKET_READY_ATTRIBUTE, false)
	set_next_ready_at(player, os.time() + get_cooldown_seconds(well))
	set_bucket_visible(well, false)
	update_prompt(well)
	SoundUtility.PlayGameSFXForPlayer(player, "Watering")

	return {
		Success = true,
		Code = "Collected",
		ItemId = itemDefinition.ItemId,
		ItemCount = updatedCount,
	}
end

local function respond(player, payload)
	if type(payload) ~= "table" then
		return { Success = false, Code = "InvalidPayload" }
	end

	local action = trim(payload.Action)
	local well = get_well_from_instance(payload.Well)
	if not action or not well then
		return { Success = false, Code = "InvalidWell" }
	end

	if action == "BeginCrank" then
		return begin_crank(player, well)
	elseif action == "CompleteCrank" then
		return complete_crank(player, well)
	elseif action == "CancelCrank" then
		return cancel_crank(player, well)
	elseif action == "CollectBucket" then
		return collect_bucket(player, well)
	end

	return { Success = false, Code = "UnknownAction" }
end

local function clear_player_busy(player)
	for well in pairs(configuredWells) do
		local busy, busyUserId = is_busy(well)
		if busy and busyUserId == player.UserId then
			clear_busy(well)
			update_prompt(well)
		end
	end
end

function WellWaterService.Init()
	if initialized then
		return
	end

	initialized = true
	Net.Function[WELL_WATER_FUNCTION_NAME]:Respond(respond)
	configure_existing_wells()

	Workspace.DescendantAdded:Connect(function(descendant)
		if descendant.Name == WELL_NAME or descendant.Name == WELL_HANDLE_NAME or descendant.Name == BUCKET_NAME then
			configure_related_well(descendant)
		end
	end)

	Players.PlayerRemoving:Connect(clear_player_busy)

	task.spawn(function()
		while initialized do
			for well in pairs(configuredWells) do
				if well.Parent then
					update_prompt(well)
				else
					configuredWells[well] = nil
				end
			end
			task.wait(1)
		end
	end)
end

return WellWaterService
