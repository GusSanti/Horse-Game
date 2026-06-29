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
local TableUtility = require(Utility:WaitForChild("TableUtility"))

local FarmingShopService = {}

local initialized = false
local playerTroves = {}

local TOOL_ITEM_ATTRIBUTE = "ToolItemId"
local LEGACY_ITEM_ATTRIBUTE = "ItemId"
local SHOP_ITEM_ATTRIBUTE = "FarmingShopItemId"
local SHOP_KIND_ATTRIBUTE = "FarmingShopItemKind"

local ITEM_DEFINITIONS = {
	Seed = {
		Kind = "Seed",
		Catalog = FarmingCatalog.Seed,
	},
	Fruit = {
		Kind = "Fruit",
		Catalog = FarmingCatalog.Fruit,
	},
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

local function get_horseshoes(player: Player): number
	return DataUtility.server.get(player, "Currencies.Horseshoes") or 0
end

local function set_horseshoes(player: Player, amount: number): number
	local normalizedAmount = math.max(0, math.floor(amount))
	DataUtility.server.set(player, "Currencies.Horseshoes", normalizedAmount)
	return normalizedAmount
end

local function get_item_count(player: Player, itemDefinition): number
	local bucket = DataUtility.server.get(player, itemDefinition.InventoryPath)
	return FarmingCatalog.GetItemCount(bucket, itemDefinition.ItemId)
end

local function set_item_count(player: Player, itemDefinition, amount: number): number
	local profileData = DataUtility.server.get(player)
	if not profileData then
		return 0
	end

	local bucket = TableUtility.EnsurePath(profileData, itemDefinition.InventoryPath)
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

local function get_nested_child(root: Instance?, pathParts): Instance?
	local current = root

	for _, part in ipairs(pathParts or {}) do
		if not current then
			return nil
		end

		current = current:FindFirstChild(part)
	end

	return current
end

local function is_matching_tool(tool: Tool, itemDefinition): boolean
	local itemId = normalize_key(itemDefinition.ItemId)

	if normalize_key(tool:GetAttribute(SHOP_ITEM_ATTRIBUTE)) == itemId then
		return true
	end

	if normalize_key(tool:GetAttribute(TOOL_ITEM_ATTRIBUTE)) == itemId then
		return true
	end

	if normalize_key(tool:GetAttribute(LEGACY_ITEM_ATTRIBUTE)) == itemId then
		return true
	end

	local normalizedName = normalize_key(tool.Name)
	if not normalizedName then
		return false
	end

	if normalize_key(itemDefinition.ToolName) == normalizedName then
		return true
	end

	if normalize_key(itemDefinition.DisplayName) == normalizedName then
		return true
	end

	for _, legacyName in ipairs(itemDefinition.LegacyToolNames or {}) do
		if normalize_key(legacyName) == normalizedName then
			return true
		end
	end

	return false
end

local function resolve_tool_source(candidate: Instance?, itemDefinition): Instance?
	if not candidate then
		return nil
	end

	if candidate:IsA("Tool") then
		return candidate
	end

	for _, descendant in ipairs(candidate:GetDescendants()) do
		if descendant:IsA("Tool") and is_matching_tool(descendant, itemDefinition) then
			return descendant
		end
	end

	for _, descendant in ipairs(candidate:GetDescendants()) do
		if descendant:IsA("Tool") then
			return descendant
		end
	end

	if candidate:IsA("Model") or candidate:IsA("BasePart") then
		return candidate
	end

	for _, child in ipairs(candidate:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			return child
		end
	end

	return nil
end

local function create_placeholder_tool(itemDefinition): Tool
	local tool = Instance.new("Tool")
	tool.Name = itemDefinition.ToolName or itemDefinition.DisplayName or itemDefinition.ItemId
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Material = Enum.Material.SmoothPlastic
	handle.Color = itemDefinition.Kind == "Seed" and Color3.fromRGB(121, 85, 58) or Color3.fromRGB(235, 122, 52)
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.CanCollide = false
	handle.Parent = tool

	return tool
end

local function get_first_base_part(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function ensure_tool_handle(tool: Tool): BasePart
	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		return handle
	end

	local firstBasePart = get_first_base_part(tool)
	if firstBasePart then
		firstBasePart.Name = "Handle"
		return firstBasePart
	end

	local newHandle = Instance.new("Part")
	newHandle.Name = "Handle"
	newHandle.Size = Vector3.new(1, 1, 1)
	newHandle.Material = Enum.Material.SmoothPlastic
	newHandle.TopSurface = Enum.SurfaceType.Smooth
	newHandle.BottomSurface = Enum.SurfaceType.Smooth
	newHandle.Parent = tool

	return newHandle
end

local function get_tool_template(itemDefinition): Instance
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")

	if assetsFolder then
		for _, pathParts in ipairs(itemDefinition.TemplatePaths or {}) do
			local candidate = resolve_tool_source(get_nested_child(assetsFolder, pathParts), itemDefinition)
			if candidate then
				return candidate
			end
		end

		for _, descendant in ipairs(assetsFolder:GetDescendants()) do
			if descendant:IsA("Tool") and is_matching_tool(descendant, itemDefinition) then
				return descendant
			end
		end
	end

	return create_placeholder_tool(itemDefinition)
end

local function clone_item_tool(itemDefinition): Tool
	local template = get_tool_template(itemDefinition)
	local tool = nil

	if template:IsA("Tool") then
		tool = template:Clone()
	else
		tool = Instance.new("Tool")
		tool.Name = itemDefinition.ToolName or itemDefinition.DisplayName or itemDefinition.ItemId
		tool.CanBeDropped = false
		template:Clone().Parent = tool
	end

	local handle = ensure_tool_handle(tool)
	handle.Anchored = false
	handle.CanCollide = false

	if itemDefinition.Kind == "Seed" and itemDefinition.ToolName then
		tool.Name = itemDefinition.ToolName
	end

	tool.CanBeDropped = false
	tool:SetAttribute(TOOL_ITEM_ATTRIBUTE, itemDefinition.ItemId)
	tool:SetAttribute(LEGACY_ITEM_ATTRIBUTE, itemDefinition.ItemId)
	tool:SetAttribute(SHOP_ITEM_ATTRIBUTE, itemDefinition.ItemId)
	tool:SetAttribute(SHOP_KIND_ATTRIBUTE, itemDefinition.Kind)

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

local function sync_container_tools(container: Instance?, desiredCount: number, itemDefinition, removeFromEnd: boolean?)
	if not container then
		return
	end

	local tools = collect_matching_tools(container, itemDefinition)
	local currentCount = #tools

	if currentCount > desiredCount then
		local difference = currentCount - desiredCount

		for index = 1, difference do
			local toolIndex = removeFromEnd and (currentCount - index + 1) or index
			local tool = tools[toolIndex]
			if tool and tool.Parent then
				tool:Destroy()
			end
		end

		return
	end

	if currentCount < desiredCount then
		for _ = 1, desiredCount - currentCount do
			local tool = clone_item_tool(itemDefinition)
			tool.Parent = container
		end
	end
end

local function sync_live_tools(player: Player, itemDefinition)
	local desiredCount = get_item_count(player, itemDefinition)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	local character = player.Character

	local backpackTools = collect_matching_tools(backpack, itemDefinition)
	local characterTools = collect_matching_tools(character, itemDefinition)
	local liveCount = #backpackTools + #characterTools

	if liveCount > desiredCount then
		local difference = liveCount - desiredCount
		local destroyQueue = {}

		for _, tool in ipairs(backpackTools) do
			destroyQueue[#destroyQueue + 1] = tool
		end

		for _, tool in ipairs(characterTools) do
			destroyQueue[#destroyQueue + 1] = tool
		end

		for index = 1, difference do
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
end

local function sync_starter_gear(player: Player, itemDefinition)
	local desiredCount = get_item_count(player, itemDefinition)
	local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 5)
	sync_container_tools(starterGear, desiredCount, itemDefinition, true)
end

local function sync_item_tools(player: Player, itemDefinition)
	if not player.Parent then
		return
	end

	sync_live_tools(player, itemDefinition)
	sync_starter_gear(player, itemDefinition)
end

local function sync_all_player_tools(player: Player)
	for _, definition in pairs(ITEM_DEFINITIONS) do
		sync_item_tools(player, definition.Catalog)
	end
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

	for _, definition in pairs(ITEM_DEFINITIONS) do
		local connection = DataUtility.server.bind(player, definition.Catalog.InventoryPath, function()
			sync_item_tools(player, definition.Catalog)
		end)

		if connection then
			trove:Add(connection)
		end
	end

	trove:Add(player.CharacterAdded:Connect(function()
		task.defer(sync_all_player_tools, player)
	end))

	task.defer(sync_all_player_tools, player)
end

local function create_state_payload(player: Player, success: boolean, code: string)
	return {
		Success = success,
		Code = code,
		Horseshoes = get_horseshoes(player),
		SeedCount = get_item_count(player, FarmingCatalog.Seed),
		FruitCount = get_item_count(player, FarmingCatalog.Fruit),
	}
end

function FarmingShopService.SyncSeedTools(player: Player)
	sync_item_tools(player, FarmingCatalog.Seed)
end

function FarmingShopService.SyncFruitTools(player: Player)
	sync_item_tools(player, FarmingCatalog.Fruit)
end

function FarmingShopService.SyncPlayerTools(player: Player)
	sync_all_player_tools(player)
end

function FarmingShopService.GetSeedCount(player: Player): number
	return get_item_count(player, FarmingCatalog.Seed)
end

function FarmingShopService.GetFruitCount(player: Player): number
	return get_item_count(player, FarmingCatalog.Fruit)
end

function FarmingShopService.BuySeed(player: Player)
	local currentHorseshoes = get_horseshoes(player)
	if currentHorseshoes < FarmingCatalog.Seed.Price then
		return create_state_payload(player, false, "NotEnoughHorseshoes")
	end

	set_horseshoes(player, currentHorseshoes - FarmingCatalog.Seed.Price)
	add_item_count(player, FarmingCatalog.Seed, 1)

	return create_state_payload(player, true, "SeedPurchased")
end

function FarmingShopService.SellFruit(player: Player)
	local currentFruitCount = get_item_count(player, FarmingCatalog.Fruit)
	if currentFruitCount < 1 then
		return create_state_payload(player, false, "NoFruitAvailable")
	end

	set_item_count(player, FarmingCatalog.Fruit, currentFruitCount - 1)
	set_horseshoes(player, get_horseshoes(player) + FarmingCatalog.Fruit.SellPrice)

	return create_state_payload(player, true, "FruitSold")
end

function FarmingShopService.ConsumeSeed(player: Player)
	local currentSeedCount = get_item_count(player, FarmingCatalog.Seed)
	if currentSeedCount < 1 then
		return false, create_state_payload(player, false, "NoSeedsAvailable")
	end

	set_item_count(player, FarmingCatalog.Seed, currentSeedCount - 1)

	return true, create_state_payload(player, true, "SeedConsumed")
end

function FarmingShopService.AwardHarvest(player: Player, amount: number?)
	add_item_count(player, FarmingCatalog.Fruit, amount or FarmingCatalog.Fruit.HarvestYield)
	return create_state_payload(player, true, "HarvestAwarded")
end

function FarmingShopService.Init()
	if initialized then
		return
	end

	Net.Function.BuySeed:Respond(function(player)
		return FarmingShopService.BuySeed(player)
	end)

	Net.Function.SellFruit:Respond(function(player)
		return FarmingShopService.SellFruit(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		track_player(player)
	end

	Players.PlayerAdded:Connect(track_player)
	Players.PlayerRemoving:Connect(disconnect_player)

	initialized = true
end

return FarmingShopService
