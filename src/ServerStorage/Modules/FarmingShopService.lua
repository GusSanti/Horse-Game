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
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))
local InventoryLoadoutService = require(script.Parent:WaitForChild("InventoryLoadoutService"))

local FarmingShopService = {}

local initialized = false
local playerTroves = {}
local queuedToolSyncs = {}

local LEGACY_ITEM_ATTRIBUTE = "ItemId"
local LEGACY_TOOL_ITEM_ATTRIBUTE = "ToolItemId"
local SHOP_ACTION_FUNCTION_NAME = "FarmingShopAction"
local SEED_INVENTORY_PATH = "Inventory.Seeds"
local FRUIT_INVENTORY_PATH = "Inventory.Fruits"
local SEED_TOOL_VERSION_ATTRIBUTE = "FarmingSeedToolVersion"
local SEED_TOOL_VERSION = 1
local SEED_TOOL_PACKET_COLOR = Color3.fromRGB(227, 197, 148)
local SEED_TOOL_EDGE_COLOR = Color3.fromRGB(117, 83, 52)
local SEED_TOOL_STRIPE_COLOR = Color3.fromRGB(248, 231, 190)
local SEED_TOOL_COLOR_RULES = {
	{ "beetroot", Color3.fromRGB(137, 47, 92) },
	{ "carrot", Color3.fromRGB(236, 121, 43) },
	{ "corn", Color3.fromRGB(240, 193, 58) },
	{ "eggplant", Color3.fromRGB(96, 63, 144) },
	{ "garlic", Color3.fromRGB(235, 226, 199) },
	{ "grape", Color3.fromRGB(110, 73, 173) },
	{ "lettuce", Color3.fromRGB(93, 178, 77) },
	{ "pepper", Color3.fromRGB(204, 62, 52) },
	{ "pineapple", Color3.fromRGB(226, 165, 54) },
	{ "potato", Color3.fromRGB(166, 117, 72) },
	{ "pumpkin", Color3.fromRGB(220, 117, 41) },
	{ "radish", Color3.fromRGB(220, 67, 94) },
	{ "strawberry", Color3.fromRGB(211, 55, 65) },
	{ "tomato", Color3.fromRGB(216, 62, 55) },
	{ "wheat", Color3.fromRGB(214, 171, 72) },
}
local SEED_TOOL_FALLBACK_COLORS = {
	Color3.fromRGB(93, 178, 77),
	Color3.fromRGB(236, 121, 43),
	Color3.fromRGB(214, 171, 72),
	Color3.fromRGB(204, 62, 52),
	Color3.fromRGB(110, 73, 173),
}

local function normalize_key(value): string?
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
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

local seedItems = if type(FarmingCatalog.GetSeedItems) == "function" then (FarmingCatalog.GetSeedItems() or {}) else (type(FarmingCatalog.Seeds) == "table" and FarmingCatalog.Seeds or {})
local fruitItems = if type(FarmingCatalog.GetFruitItems) == "function" then (FarmingCatalog.GetFruitItems() or {}) else (type(FarmingCatalog.Fruits) == "table" and FarmingCatalog.Fruits or {})
local itemDefinitionsById = {}

for _, itemDefinition in ipairs(seedItems) do
	itemDefinition.NormalizedItemId = itemDefinition.NormalizedItemId or normalize_key(itemDefinition.ItemId)
	itemDefinitionsById[itemDefinition.NormalizedItemId] = itemDefinition
end

for _, itemDefinition in ipairs(fruitItems) do
	itemDefinition.NormalizedItemId = itemDefinition.NormalizedItemId or normalize_key(itemDefinition.ItemId)
	itemDefinitionsById[itemDefinition.NormalizedItemId] = itemDefinition
end

local function get_seed_items()
	return seedItems
end

local function get_fruit_items()
	return fruitItems
end

local function get_item_definition(itemId)
	local normalizedItemId = normalize_key(itemId)
	if not normalizedItemId then
		return nil
	end

	return itemDefinitionsById[normalizedItemId]
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

local function get_profile_data(player: Player)
	return DataUtility.server.get(player)
end

local function get_horseshoes_from_profile(profileData): number
	return math.max(0, math.floor(tonumber(get_by_path(profileData, "Currencies.Horseshoes")) or 0))
end

local function get_horseshoes(player: Player): number
	local profileData = get_profile_data(player)
	if not profileData then
		return 0
	end

	return get_horseshoes_from_profile(profileData)
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

local function get_item_count_from_profile(profileData, itemDefinition): number
	return get_bucket_item_count(get_by_path(profileData, itemDefinition.InventoryPath), itemDefinition.ItemId)
end

local function is_item_selected_for_hotbar(player: Player, itemDefinition): boolean
	local initializedLoadout = DataUtility.server.get(player, InventoryLoadout.HOTBAR_INITIALIZED_PATH) == true
	if not initializedLoadout then
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

local function get_total_count_from_profile(profileData, itemDefinitions): number
	local total = 0

	for _, itemDefinition in ipairs(itemDefinitions) do
		total += get_item_count_from_profile(profileData, itemDefinition)
	end

	return total
end

local function write_item_count(profileData, itemDefinition, amount: number): (table, number)
	local bucket = ensure_path(profileData, itemDefinition.InventoryPath)
	local normalizedAmount = math.max(0, math.floor(amount))

	if normalizedAmount > 0 then
		bucket[itemDefinition.ItemId] = normalizedAmount
	else
		bucket[itemDefinition.ItemId] = nil
	end

	return bucket, normalizedAmount
end

local function migrate_legacy_inventory(player: Player)
	local profileData = get_profile_data(player)
	if not profileData then
		return
	end

	local fruitsBucket = ensure_path(profileData, FRUIT_INVENTORY_PATH)
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
		DataUtility.server.set(player, FRUIT_INVENTORY_PATH, fruitsBucket)
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

local function get_seed_tool_color(itemDefinition): Color3
	local normalizedItemId = normalize_key(itemDefinition.ItemId)
	local normalizedCropId = normalize_key(itemDefinition.CropId)
	local normalizedDisplayName = normalize_key(itemDefinition.DisplayName)

	for _, rule in ipairs(SEED_TOOL_COLOR_RULES) do
		local token = rule[1]
		if (normalizedItemId and string.find(normalizedItemId, token, 1, true))
			or (normalizedCropId and string.find(normalizedCropId, token, 1, true))
			or (normalizedDisplayName and string.find(normalizedDisplayName, token, 1, true))
		then
			return rule[2]
		end
	end

	local source = normalizedItemId or normalizedCropId or normalizedDisplayName or "seed"
	local hash = 0
	for index = 1, #source do
		hash += string.byte(source, index) or 0
	end

	return SEED_TOOL_FALLBACK_COLORS[(hash % #SEED_TOOL_FALLBACK_COLORS) + 1]
end

local function configure_seed_tool_part(part: BasePart, color: Color3, material)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = false
	part.Material = material or Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = color
end

local function weld_seed_tool_part(part: BasePart, handle: BasePart)
	if part == handle then
		return
	end

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = part
end

local function create_seed_tool_part(
	parent: Instance,
	handle: BasePart?,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = offset
	configure_seed_tool_part(part, color, material)
	part.Parent = parent

	if handle then
		weld_seed_tool_part(part, handle)
	end

	return part
end

local function create_seed_tool_disc(
	parent: Instance,
	handle: BasePart,
	name: string,
	position: Vector3,
	scale: Vector3,
	color: Color3
): Part
	local part = create_seed_tool_part(
		parent,
		handle,
		name,
		Vector3.new(1, 1, 1),
		CFrame.new(position),
		color,
		Enum.Material.SmoothPlastic
	)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = scale
	mesh.Parent = part
	return part
end

local function create_seed_tool(itemDefinition): Tool
	local tool = Instance.new("Tool")
	tool.Name = itemDefinition.ToolName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.ToolTip = itemDefinition.DisplayName
	tool.Grip = CFrame.new(0, -0.12, -0.18) * CFrame.Angles(math.rad(-12), math.rad(8), 0)
	tool:SetAttribute(SEED_TOOL_VERSION_ATTRIBUTE, SEED_TOOL_VERSION)

	local cropColor = get_seed_tool_color(itemDefinition)
	local handle = create_seed_tool_part(
		tool,
		nil,
		"Handle",
		Vector3.new(0.64, 0.78, 0.08),
		CFrame.new(),
		SEED_TOOL_PACKET_COLOR,
		Enum.Material.SmoothPlastic
	)
	handle.Massless = false

	create_seed_tool_part(tool, handle, "TopStripe", Vector3.new(0.56, 0.11, 0.09), CFrame.new(0, 0.27, -0.04), SEED_TOOL_STRIPE_COLOR, Enum.Material.SmoothPlastic)
	create_seed_tool_part(tool, handle, "BottomStripe", Vector3.new(0.56, 0.08, 0.09), CFrame.new(0, -0.28, -0.04), SEED_TOOL_EDGE_COLOR, Enum.Material.SmoothPlastic)
	create_seed_tool_part(tool, handle, "ColorPatch", Vector3.new(0.32, 0.27, 0.1), CFrame.new(0, -0.02, -0.08), cropColor, Enum.Material.SmoothPlastic)
	create_seed_tool_disc(tool, handle, "SeedA", Vector3.new(-0.08, 0.01, -0.14), Vector3.new(0.11, 0.16, 0.03), Color3.fromRGB(65, 56, 37))
	create_seed_tool_disc(tool, handle, "SeedB", Vector3.new(0.07, -0.05, -0.14), Vector3.new(0.1, 0.15, 0.03), Color3.fromRGB(83, 66, 38))
	create_seed_tool_disc(tool, handle, "Highlight", Vector3.new(-0.04, 0.12, -0.15), Vector3.new(0.11, 0.04, 0.02), Color3.fromRGB(255, 245, 202))

	return tool
end

local function create_placeholder_tool(itemDefinition): Tool
	if itemDefinition.Kind == "Seed" then
		return create_seed_tool(itemDefinition)
	end

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
	handle.Color = if itemDefinition.Kind == "Seed" then Color3.fromRGB(126, 97, 64) else Color3.fromRGB(209, 106, 62)
	handle.CanCollide = false
	handle.Parent = tool

	return tool
end

local function get_item_tool_template(itemDefinition): Instance
	if itemDefinition.Kind == "Seed" then
		return create_seed_tool(itemDefinition)
	end

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
	tool.ToolTip = itemDefinition.DisplayName
	tool.CanBeDropped = false
	tool:SetAttribute(FarmingUtility.FARMING_ITEM_ATTRIBUTE, itemDefinition.ItemId)
	tool:SetAttribute(FarmingUtility.FARMING_CROP_ATTRIBUTE, itemDefinition.CropId)
	tool:SetAttribute(FarmingUtility.FARMING_KIND_ATTRIBUTE, itemDefinition.Kind)

	local directHandle = tool:FindFirstChild("Handle")
	local handle = FarmingUtility.GetToolHandle(tool)
	tool.RequiresHandle = itemDefinition.Kind == "Seed" and directHandle ~= nil and directHandle:IsA("BasePart")
	if handle then
		handle.Anchored = false
		handle.CanCollide = false
		handle.CanTouch = false
		handle.CanQuery = false
		handle.Massless = false
	end

	for _, attributeName in ipairs({
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
	}) do
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

local function collect_matching_tools(container: Instance?, itemDefinition): {Tool}
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

local function remove_stale_seed_tools(tools: { Tool }, itemDefinition): { Tool }
	if itemDefinition.Kind ~= "Seed" then
		return tools
	end

	local currentTools = {}
	for _, tool in ipairs(tools) do
		if tool:GetAttribute(SEED_TOOL_VERSION_ATTRIBUTE) == SEED_TOOL_VERSION then
			currentTools[#currentTools + 1] = tool
		elseif tool.Parent then
			tool:Destroy()
		end
	end

	return currentTools
end

local function sync_item_tools(player: Player, itemDefinition)
	if not player.Parent then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	local character = player.Character
	local ownedCount = get_item_count(player, itemDefinition)
	local desiredCount = if ownedCount > 0 and is_item_selected_for_hotbar(player, itemDefinition) then 1 else 0
	local backpackTools = remove_stale_seed_tools(collect_matching_tools(backpack, itemDefinition), itemDefinition)
	local characterTools = remove_stale_seed_tools(collect_matching_tools(character, itemDefinition), itemDefinition)
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
			clone_item_tool(itemDefinition).Parent = backpack or player
		end
	end

	local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 5)
	if starterGear then
		local starterTools = remove_stale_seed_tools(collect_matching_tools(starterGear, itemDefinition), itemDefinition)
		if #starterTools > desiredCount then
			for index = 1, #starterTools - desiredCount do
				local tool = starterTools[#starterTools - index + 1]
				if tool and tool.Parent then
					tool:Destroy()
				end
			end
		elseif #starterTools < desiredCount then
			for _ = 1, desiredCount - #starterTools do
				clone_item_tool(itemDefinition).Parent = starterGear
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

local function request_tool_sync(player: Player, mode: string)
	local state = queuedToolSyncs[player]
	if not state then
		state = {
			Queued = false,
			Full = false,
			Seed = false,
			Fruit = false,
		}
		queuedToolSyncs[player] = state
	end

	if mode == "Full" then
		state.Full = true
		state.Seed = true
		state.Fruit = true
	elseif mode == "Seed" then
		state.Seed = true
	elseif mode == "Fruit" then
		state.Fruit = true
	end

	if state.Queued then
		return
	end

	state.Queued = true

	task.defer(function()
		local queuedState = queuedToolSyncs[player]
		queuedToolSyncs[player] = nil

		if not queuedState or not player.Parent then
			return
		end

		if queuedState.Full or queuedState.Fruit then
			migrate_legacy_inventory(player)
		end

		if queuedState.Full or queuedState.Seed then
			sync_seed_tools(player)
		end

		if queuedState.Full or queuedState.Fruit then
			sync_fruit_tools(player)
		end
	end)
end

local function disconnect_player(player: Player)
	queuedToolSyncs[player] = nil

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

	local seedConnection = DataUtility.server.bind(player, SEED_INVENTORY_PATH, function()
		request_tool_sync(player, "Seed")
	end)
	if seedConnection then
		trove:Add(seedConnection)
	end

	local fruitConnection = DataUtility.server.bind(player, FRUIT_INVENTORY_PATH, function()
		request_tool_sync(player, "Fruit")
	end)
	if fruitConnection then
		trove:Add(fruitConnection)
	end

	for _, loadoutPath in ipairs({
		InventoryLoadout.HOTBAR_ITEM_IDS_PATH,
		InventoryLoadout.HOTBAR_INITIALIZED_PATH,
	}) do
		local connection = DataUtility.server.bind(player, loadoutPath, function()
			request_tool_sync(player, "Full")
		end)

		if connection then
			trove:Add(connection)
		end
	end

	trove:Add(player.CharacterAdded:Connect(function()
		request_tool_sync(player, "Full")
	end))

	request_tool_sync(player, "Full")
end

local function create_state_payload(player: Player, success: boolean, code: string, itemDefinition, profileDataOverride)
	local profileData = profileDataOverride or get_profile_data(player)
	local horseshoes = 0
	local seedCount = 0
	local fruitCount = 0
	local itemCount = 0

	if profileData then
		horseshoes = get_horseshoes_from_profile(profileData)
		seedCount = get_total_count_from_profile(profileData, get_seed_items())
		fruitCount = get_total_count_from_profile(profileData, get_fruit_items())

		if itemDefinition then
			itemCount = get_item_count_from_profile(profileData, itemDefinition)
		end
	else
		horseshoes = get_horseshoes(player)
		seedCount = get_total_count(player, get_seed_items())
		fruitCount = get_total_count(player, get_fruit_items())

		if itemDefinition then
			itemCount = get_item_count(player, itemDefinition)
		end
	end

	return {
		Success = success,
		Code = code,
		ItemId = itemDefinition and itemDefinition.ItemId or nil,
		Horseshoes = horseshoes,
		SeedCount = seedCount,
		FruitCount = fruitCount,
		ItemCount = itemCount,
	}
end

local function handle_shop_action(player: Player, actionOrPayload, itemId: string?)
	local actionName = actionOrPayload
	local resolvedItemId = itemId

	if type(actionOrPayload) == "table" then
		actionName = actionOrPayload.Action or actionOrPayload.Type
		resolvedItemId = actionOrPayload.ItemId
	end

	if actionName == "BuySeed" then
		return FarmingShopService.BuySeed(player, resolvedItemId)
	end

	if actionName == "SellFruit" then
		return FarmingShopService.SellFruit(player, resolvedItemId)
	end

	local itemDefinition = resolve_item_definition(resolvedItemId, nil)
	return create_state_payload(player, false, "UnknownAction", itemDefinition)
end

function FarmingShopService.SyncSeedTools(player: Player)
	sync_seed_tools(player)
end

function FarmingShopService.SyncFruitTools(player: Player)
	sync_fruit_tools(player)
end

function FarmingShopService.SyncPlayerTools(player: Player)
	if not player or not player.Parent then
		return
	end

	migrate_legacy_inventory(player)
	sync_seed_tools(player)
	sync_fruit_tools(player)
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

	local profileData = get_profile_data(player)
	if not profileData then
		return create_state_payload(player, false, "ProfileUnavailable", itemDefinition)
	end

	local currentHorseshoes = get_horseshoes_from_profile(profileData)
	if currentHorseshoes < itemDefinition.Price then
		return create_state_payload(player, false, "NotEnoughHorseshoes", itemDefinition, profileData)
	end

	local previousCount = get_item_count_from_profile(profileData, itemDefinition)
	local bucket = select(1, write_item_count(profileData, itemDefinition, previousCount + 1))

	DataUtility.server.set_many(player, {
		{ Path = "Currencies.Horseshoes", Value = currentHorseshoes - itemDefinition.Price },
		{ Path = itemDefinition.InventoryPath, Value = bucket },
	})

	InventoryLoadoutService.TryAutoEquipNewItem(player, itemDefinition.ItemId, previousCount)
	SoundUtility.PlayGameSFXForPlayer(player, "MoneyGet")

	return create_state_payload(player, true, "SeedPurchased", itemDefinition, profileData)
end

function FarmingShopService.SellFruit(player: Player, itemId)
	local itemDefinition = resolve_item_definition(itemId, "Fruit")
	if not itemDefinition then
		return create_state_payload(player, false, "UnknownFruit", nil)
	end

	local profileData = get_profile_data(player)
	if not profileData then
		return create_state_payload(player, false, "ProfileUnavailable", itemDefinition)
	end

	local currentFruitCount = get_item_count_from_profile(profileData, itemDefinition)
	if currentFruitCount < 1 then
		return create_state_payload(player, false, "NoFruitAvailable", itemDefinition, profileData)
	end

	local bucket = select(1, write_item_count(profileData, itemDefinition, currentFruitCount - 1))

	DataUtility.server.set_many(player, {
		{ Path = itemDefinition.InventoryPath, Value = bucket },
		{ Path = "Currencies.Horseshoes", Value = get_horseshoes_from_profile(profileData) + itemDefinition.SellPrice },
	})
	SoundUtility.PlayGameSFXForPlayer(player, "MoneyGet")

	return create_state_payload(player, true, "FruitSold", itemDefinition, profileData)
end

function FarmingShopService.ConsumeSeed(player: Player, itemId)
	local itemDefinition = resolve_item_definition(itemId, "Seed")
	if not itemDefinition then
		return false, create_state_payload(player, false, "UnknownSeed", nil)
	end

	local profileData = get_profile_data(player)
	if not profileData then
		return false, create_state_payload(player, false, "ProfileUnavailable", itemDefinition)
	end

	local currentSeedCount = get_item_count_from_profile(profileData, itemDefinition)
	if currentSeedCount < 1 then
		return false, create_state_payload(player, false, "NoSeedsAvailable", itemDefinition, profileData)
	end

	local bucket = select(1, write_item_count(profileData, itemDefinition, currentSeedCount - 1))

	DataUtility.server.set_many(player, {
		{ Path = itemDefinition.InventoryPath, Value = bucket },
	})

	return true, create_state_payload(player, true, "SeedConsumed", itemDefinition, profileData)
end

function FarmingShopService.AwardHarvest(player: Player, itemId, amount: number?)
	local itemDefinition = resolve_item_definition(itemId, "Fruit")
	if not itemDefinition then
		return create_state_payload(player, false, "UnknownFruit", nil)
	end

	local profileData = get_profile_data(player)
	if not profileData then
		return create_state_payload(player, false, "ProfileUnavailable", itemDefinition)
	end

	local previousCount = get_item_count_from_profile(profileData, itemDefinition)
	local bucket = select(1, write_item_count(
		profileData,
		itemDefinition,
		previousCount + (amount or itemDefinition.HarvestYield or 1)
	))

	DataUtility.server.set_many(player, {
		{ Path = itemDefinition.InventoryPath, Value = bucket },
	})

	InventoryLoadoutService.TryAutoEquipNewItem(player, itemDefinition.ItemId, previousCount)

	return create_state_payload(player, true, "HarvestAwarded", itemDefinition, profileData)
end

function FarmingShopService.Init()
	if initialized then
		return
	end

	Net.Function[SHOP_ACTION_FUNCTION_NAME]:Respond(function(player, payload)
		return handle_shop_action(player, payload)
	end)

	Net.Function.BuySeed:Respond(function(player, itemId)
		return handle_shop_action(player, "BuySeed", itemId)
	end)

	Net.Function.SellFruit:Respond(function(player, itemId)
		return handle_shop_action(player, "SellFruit", itemId)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		track_player(player)
	end

	Players.PlayerAdded:Connect(track_player)
	Players.PlayerRemoving:Connect(disconnect_player)

	initialized = true
end

return FarmingShopService
