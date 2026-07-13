local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local InventoryLoadout = require(Utility:WaitForChild("InventoryLoadout"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))

local FarmingShopService = {}

local initialized = false
local playerTroves = {}

local LEGACY_ITEM_ATTRIBUTE = "ItemId"
local LEGACY_TOOL_ITEM_ATTRIBUTE = "ToolItemId"

local function normalize_key(value): string?
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	local normalizedValue = string.lower(trimmedValue)
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function get_string_attribute(instance: Instance, attributeName: string): string?
	local value = instance:GetAttribute(attributeName)
	if type(value) == "string" then
		return value
	end

	return nil
end

local function ensure_path(root, path)
	if type(TableUtility.EnsurePath) == "function" then
		return TableUtility.EnsurePath(root, path)
	end

	local current = root

	for segment in string.gmatch(path or "", "[^%.]+") do
		if type(current[segment]) ~= "table" then
			current[segment] = {}
		end

		current = current[segment]
	end

	return current
end

local function get_by_path(root, path)
	if type(TableUtility.GetByPath) == "function" then
		return TableUtility.GetByPath(root, path)
	end

	if not path or path == "" then
		return root
	end

	local current = root

	for segment in string.gmatch(path, "[^%.]+") do
		if type(current) ~= "table" then
			return nil
		end

		current = current[segment]
		if current == nil then
			return nil
		end
	end

	return current
end

local function get_seed_items()
	if type(FarmingCatalog.GetSeedItems) == "function" then
		return FarmingCatalog.GetSeedItems() or {}
	end

	return type(FarmingCatalog.Seeds) == "table" and FarmingCatalog.Seeds or {}
end

local function get_fruit_items()
	if type(FarmingCatalog.GetFruitItems) == "function" then
		return FarmingCatalog.GetFruitItems() or {}
	end

	return type(FarmingCatalog.Fruits) == "table" and FarmingCatalog.Fruits or {}
end

local function get_item_definition(itemId)
	if type(FarmingCatalog.GetItem) == "function" then
		return FarmingCatalog.GetItem(itemId)
	end

	local normalizedItemId = normalize_key(itemId)
	if not normalizedItemId then
		return nil
	end

	for _, itemDefinition in ipairs(get_seed_items()) do
		if normalize_key(itemDefinition.ItemId) == normalizedItemId then
			return itemDefinition
		end
	end

	for _, itemDefinition in ipairs(get_fruit_items()) do
		if normalize_key(itemDefinition.ItemId) == normalizedItemId then
			return itemDefinition
		end
	end

	return nil
end

local function get_bucket_item_count(bucket, itemId): number
	if type(FarmingCatalog.GetItemCount) == "function" then
		return FarmingCatalog.GetItemCount(bucket, itemId)
	end

	if type(bucket) ~= "table" then
		return 0
	end

	return bucket[itemId] or 0
end

local function get_horseshoes(player: Player): number
	return DataUtility.server.get(player, "Currencies.Horseshoes") or 0
end

local function set_horseshoes(player: Player, amount: number): number
	local normalizedAmount = math.max(0, math.floor(amount))
	DataUtility.server.set(player, "Currencies.Horseshoes", normalizedAmount)
	return normalizedAmount
end

local function resolve_item_definition(itemOrId, expectedKind: string?)
	local itemDefinition = itemOrId

	if type(itemOrId) ~= "table" then
		itemDefinition = get_item_definition(itemOrId)
	end

	if not itemDefinition then
		return nil
	end

	if expectedKind and itemDefinition.Kind ~= expectedKind then
		return nil
	end

	return itemDefinition
end

local function get_item_count(player: Player, itemDefinition): number
	local bucket = DataUtility.server.get(player, itemDefinition.InventoryPath)
	return get_bucket_item_count(bucket, itemDefinition.ItemId)
end

local function is_item_selected_for_hotbar(player: Player, itemDefinition): boolean
	local initialized = DataUtility.server.get(player, InventoryLoadout.HOTBAR_INITIALIZED_PATH) == true
	if not initialized then
		return true
	end

	return InventoryLoadout.IsItemEquipped(
		DataUtility.server.get(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH),
		itemDefinition and itemDefinition.ItemId
	)
end

local function get_total_count(player: Player, itemDefinitions): number
	local total = 0

	for _, itemDefinition in ipairs(itemDefinitions) do
		total += get_item_count(player, itemDefinition)
	end

	return total
end

local function set_item_count(player: Player, itemDefinition, amount: number): number
	local profileData = DataUtility.server.get(player)
	if not profileData then
		return 0
	end

	local bucket = ensure_path(profileData, itemDefinition.InventoryPath)
	local normalizedAmount = math.max(0, math.floor(amount))

	if normalizedAmount > 0 then
		bucket[itemDefinition.ItemId] = normalizedAmount
	else
		bucket[itemDefinition.ItemId] = nil
	end

	DataUtility.server.set(player, itemDefinition.InventoryPath, bucket)
	return normalizedAmount
end

local function add_item_count(player: Player, itemDefinition, amount: number): number
	return set_item_count(player, itemDefinition, get_item_count(player, itemDefinition) + amount)
end

local function migrate_legacy_inventory(player: Player)
	local profileData = DataUtility.server.get(player)
	if not profileData then
		return
	end

	local fruitsBucket = ensure_path(profileData, "Inventory.Fruits")
	local legacyFoodBucket = get_by_path(profileData, "Inventory.Consumables.Food")
	local changed = false

	if type(legacyFoodBucket) ~= "table" then
		return
	end

	for _, fruitDefinition in ipairs(get_fruit_items()) do
		if get_bucket_item_count(fruitsBucket, fruitDefinition.ItemId) > 0 then
			continue
		end

		local migratedAmount = 0
		for _, legacyItemId in ipairs(fruitDefinition.LegacyInventoryItems or {}) do
			migratedAmount += legacyFoodBucket[legacyItemId] or 0
		end

		if migratedAmount > 0 then
			fruitsBucket[fruitDefinition.ItemId] = migratedAmount
			changed = true
		end
	end

	if changed then
		DataUtility.server.set(player, "Inventory.Fruits", fruitsBucket)
	end
end

local function is_matching_tool(tool: Tool, itemDefinition): boolean
	if normalize_key(get_string_attribute(tool, FarmingUtility.FARMING_ITEM_ATTRIBUTE)) == itemDefinition.NormalizedItemId then
		return true
	end

	local normalizedToolName = normalize_key(tool.Name)
	if normalizedToolName == normalize_key(itemDefinition.ToolName) then
		return true
	end

	if normalizedToolName == normalize_key(itemDefinition.DisplayName) then
		return true
	end

	for _, legacyName in ipairs(itemDefinition.LegacyToolNames or {}) do
		if normalizedToolName == normalize_key(legacyName) then
			return true
		end
	end

	if normalize_key(get_string_attribute(tool, LEGACY_ITEM_ATTRIBUTE)) == itemDefinition.NormalizedItemId then
		return true
	end

	if normalize_key(get_string_attribute(tool, LEGACY_TOOL_ITEM_ATTRIBUTE)) == itemDefinition.NormalizedItemId then
		return true
	end

	return false
end

local function create_placeholder_tool(itemDefinition): Tool
	local tool = Instance.new("Tool")
	tool.Name = itemDefinition.ToolName
	tool.RequiresHandle = false
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Material = Enum.Material.SmoothPlastic
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Color = itemDefinition.Kind == "Seed" and Color3.fromRGB(126, 97, 64) or Color3.fromRGB(209, 106, 62)
	handle.CanCollide = false
	handle.Parent = tool

	return tool
end

local function get_item_tool_template(itemDefinition): Instance
	local template = FarmingUtility.GetItemAsset(itemDefinition)
	if template then
		return template
	end

	return create_placeholder_tool(itemDefinition)
end

local function strip_tool_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function sanitize_tool(tool: Tool, itemDefinition)
	tool.Name = itemDefinition.ToolName
	tool.RequiresHandle = false
	tool.ToolTip = itemDefinition.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute(FarmingUtility.FARMING_ITEM_ATTRIBUTE, itemDefinition.ItemId)
	tool:SetAttribute(FarmingUtility.FARMING_CROP_ATTRIBUTE, itemDefinition.CropId)
	tool:SetAttribute(FarmingUtility.FARMING_KIND_ATTRIBUTE, itemDefinition.Kind)

	local handle = FarmingUtility.GetToolHandle(tool)
	if handle then
		handle.Anchored = false
		handle.CanCollide = false
	end

	local legacyAttributes = {
		"ToolItemId",
		"ItemId",
		"InventoryPath",
		"ToolCategory",
		"CategoryFolder",
		"PlaceholderPrice",
		"PlaceholderPriceLabel",
		"PlaceholderDescription",
		"ShopId",
		"CareType",
		"UseType",
	}

	for _, attributeName in ipairs(legacyAttributes) do
		if tool:GetAttribute(attributeName) ~= nil then
			tool:SetAttribute(attributeName, nil)
		end
	end
end

local function clone_item_tool(itemDefinition): Tool
	local template = get_item_tool_template(itemDefinition)
	local tool = nil

	if template:IsA("Tool") then
		tool = template:Clone()
	else
		tool = Instance.new("Tool")
		tool.Name = itemDefinition.ToolName
		tool.RequiresHandle = false
		tool.CanBeDropped = false
		template:Clone().Parent = tool
	end

	strip_tool_scripts(tool)
	sanitize_tool(tool, itemDefinition)
	return tool
end

local function collect_matching_tools(container: Instance?, itemDefinition): { Tool }
	local tools = {}

	if not container then
		return tools
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and is_matching_tool(child, itemDefinition) then
			tools[#tools + 1] = child
		end
	end

	return tools
end

local function sync_item_tools(player: Player, itemDefinition)
	if not player.Parent then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	local character = player.Character
	local ownedCount = get_item_count(player, itemDefinition)
	local desiredCount = if ownedCount > 0 and is_item_selected_for_hotbar(player, itemDefinition) then 1 else 0
	local backpackTools = collect_matching_tools(backpack, itemDefinition)
	local characterTools = collect_matching_tools(character, itemDefinition)
	local liveCount = #backpackTools + #characterTools

	if liveCount > desiredCount then
		local overflow = liveCount - desiredCount
		local destroyQueue = {}

		for _, tool in ipairs(characterTools) do
			destroyQueue[#destroyQueue + 1] = tool
		end

		for _, tool in ipairs(backpackTools) do
			destroyQueue[#destroyQueue + 1] = tool
		end

		for index = 1, overflow do
			local tool = destroyQueue[index]
			if tool and tool.Parent then
				tool:Destroy()
			end
		end
	elseif liveCount < desiredCount then
		for _ = 1, desiredCount - liveCount do
			local tool = clone_item_tool(itemDefinition)
			tool.Parent = backpack or player
		end
	end

	local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 5)
	if starterGear then
		local currentStarterTools = collect_matching_tools(starterGear, itemDefinition)
		if #currentStarterTools > desiredCount then
			for index = 1, #currentStarterTools - desiredCount do
				local tool = currentStarterTools[#currentStarterTools - index + 1]
				if tool and tool.Parent then
					tool:Destroy()
				end
			end
		else
			for _ = 1, desiredCount - #currentStarterTools do
				local tool = clone_item_tool(itemDefinition)
				tool.Parent = starterGear
			end
		end
	end
end

local function sync_seed_tools(player: Player)
	for _, itemDefinition in ipairs(get_seed_items()) do
		sync_item_tools(player, itemDefinition)
	end
end

local function sync_fruit_tools(player: Player)
	for _, itemDefinition in ipairs(get_fruit_items()) do
		sync_item_tools(player, itemDefinition)
	end
end

local function sync_player_tools(player: Player)
	migrate_legacy_inventory(player)
	sync_seed_tools(player)
	sync_fruit_tools(player)
end

local function disconnect_player(player: Player)
	local trove = playerTroves[player]
	if not trove then
		return
	end

	trove:Destroy()
	playerTroves[player] = nil
end

local function track_player(player: Player)
	disconnect_player(player)

	local trove = Trove.new()
	playerTroves[player] = trove

	local inventoryPaths = {
		"Inventory.Seeds",
		"Inventory.Fruits",
	}

	for _, inventoryPath in ipairs(inventoryPaths) do
		local connection = DataUtility.server.bind(player, inventoryPath, function()
			task.defer(sync_player_tools, player)
		end)

		if connection then
			trove:Add(connection)
		end
	end

	for _, loadoutPath in ipairs({
		InventoryLoadout.HOTBAR_ITEM_IDS_PATH,
		InventoryLoadout.HOTBAR_INITIALIZED_PATH,
	}) do
		local connection = DataUtility.server.bind(player, loadoutPath, function()
			task.defer(sync_player_tools, player)
		end)

		if connection then
			trove:Add(connection)
		end
	end

	trove:Add(player.CharacterAdded:Connect(function()
		task.defer(sync_player_tools, player)
	end))

	task.defer(sync_player_tools, player)
end

local function create_state_payload(player: Player, success: boolean, code: string, itemDefinition)
	return {
		Success = success,
		Code = code,
		ItemId = itemDefinition and itemDefinition.ItemId or nil,
		Horseshoes = get_horseshoes(player),
		SeedCount = get_total_count(player, get_seed_items()),
		FruitCount = get_total_count(player, get_fruit_items()),
		ItemCount = itemDefinition and get_item_count(player, itemDefinition) or 0,
	}
end

function FarmingShopService.SyncSeedTools(player: Player)
	sync_seed_tools(player)
end

function FarmingShopService.SyncFruitTools(player: Player)
	sync_fruit_tools(player)
end

function FarmingShopService.SyncPlayerTools(player: Player)
	sync_player_tools(player)
end

function FarmingShopService.GetSeedCount(player: Player, itemId): number
	local itemDefinition = resolve_item_definition(itemId, "Seed")
	if itemDefinition then
		return get_item_count(player, itemDefinition)
	end

	return get_total_count(player, get_seed_items())
end

function FarmingShopService.GetFruitCount(player: Player, itemId): number
	local itemDefinition = resolve_item_definition(itemId, "Fruit")
	if itemDefinition then
		return get_item_count(player, itemDefinition)
	end

	return get_total_count(player, get_fruit_items())
end

function FarmingShopService.BuySeed(player: Player, itemId)
	local itemDefinition = resolve_item_definition(itemId, "Seed")
	if not itemDefinition then
		return create_state_payload(player, false, "UnknownSeed", nil)
	end

	local currentHorseshoes = get_horseshoes(player)
	if currentHorseshoes < itemDefinition.Price then
		return create_state_payload(player, false, "NotEnoughHorseshoes", itemDefinition)
	end

	set_horseshoes(player, currentHorseshoes - itemDefinition.Price)
	add_item_count(player, itemDefinition, 1)

	return create_state_payload(player, true, "SeedPurchased", itemDefinition)
end

function FarmingShopService.SellFruit(player: Player, itemId)
	local itemDefinition = resolve_item_definition(itemId, "Fruit")
	if not itemDefinition then
		return create_state_payload(player, false, "UnknownFruit", nil)
	end

	local currentFruitCount = get_item_count(player, itemDefinition)
	if currentFruitCount < 1 then
		return create_state_payload(player, false, "NoFruitAvailable", itemDefinition)
	end

	set_item_count(player, itemDefinition, currentFruitCount - 1)
	set_horseshoes(player, get_horseshoes(player) + itemDefinition.SellPrice)

	return create_state_payload(player, true, "FruitSold", itemDefinition)
end

function FarmingShopService.ConsumeSeed(player: Player, itemId)
	local itemDefinition = resolve_item_definition(itemId, "Seed")
	if not itemDefinition then
		return false, create_state_payload(player, false, "UnknownSeed", nil)
	end

	local currentSeedCount = get_item_count(player, itemDefinition)
	if currentSeedCount < 1 then
		return false, create_state_payload(player, false, "NoSeedsAvailable", itemDefinition)
	end

	set_item_count(player, itemDefinition, currentSeedCount - 1)

	return true, create_state_payload(player, true, "SeedConsumed", itemDefinition)
end

function FarmingShopService.AwardHarvest(player: Player, itemId, amount: number?)
	local itemDefinition = resolve_item_definition(itemId, "Fruit")
	if not itemDefinition then
		return create_state_payload(player, false, "UnknownFruit", nil)
	end

	add_item_count(player, itemDefinition, amount or itemDefinition.HarvestYield or 1)
	return create_state_payload(player, true, "HarvestAwarded", itemDefinition)
end

function FarmingShopService.Init()
	if initialized then
		return
	end

	Net.Function.BuySeed:Respond(function(player, itemId)
		return FarmingShopService.BuySeed(player, itemId)
	end)

	Net.Function.SellFruit:Respond(function(player, itemId)
		return FarmingShopService.SellFruit(player, itemId)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		track_player(player)
	end

	Players.PlayerAdded:Connect(track_player)
	Players.PlayerRemoving:Connect(disconnect_player)

	initialized = true
end

return FarmingShopService