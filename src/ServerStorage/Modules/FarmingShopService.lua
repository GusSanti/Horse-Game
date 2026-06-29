local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))

local FarmingShopService = {}

local initialized = false
local playerTroves = {}
local serviceTrove = Trove.new()
local toolTemplateCache = {}

local function normalize_amount(amount: number?): number
	return math.max(0, math.floor(tonumber(amount) or 0))
end

local function get_horseshoes(player: Player): number
	return normalize_amount(DataUtility.server.get(player, "Currencies.Horseshoes"))
end

local function set_horseshoes(player: Player, amount: number): number
	local normalizedAmount = normalize_amount(amount)
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

	local inventoryBucket = TableUtility.EnsurePath(profileData, itemDefinition.InventoryPath)
	local normalizedAmount = normalize_amount(amount)

	if normalizedAmount > 0 then
		inventoryBucket[itemDefinition.ItemId] = normalizedAmount
	else
		inventoryBucket[itemDefinition.ItemId] = nil
	end

	DataUtility.server.set(player, itemDefinition.InventoryPath, inventoryBucket)
	return normalizedAmount
end

local function add_item_count(player: Player, itemDefinition, amount: number): number
	return set_item_count(player, itemDefinition, get_item_count(player, itemDefinition) + amount)
end

local function add_search_name(searchNames: { string }, value: string?)
	if type(value) ~= "string" or value == "" then
		return
	end

	for _, existingValue in ipairs(searchNames) do
		if existingValue == value then
			return
		end
	end

	searchNames[#searchNames + 1] = value
end

local function get_template_search_names(itemDefinition): { string }
	local searchNames = {}

	for _, searchName in ipairs(itemDefinition.TemplateSearchNames or {}) do
		add_search_name(searchNames, searchName)
	end

	add_search_name(searchNames, itemDefinition.ToolName)
	add_search_name(searchNames, itemDefinition.ItemId)
	add_search_name(searchNames, itemDefinition.DisplayName)

	return searchNames
end

local function get_fallback_color(itemDefinition): Color3
	if itemDefinition.ItemId == FarmingCatalog.Seed.ItemId then
		return Color3.fromRGB(121, 85, 58)
	end

	return Color3.fromRGB(236, 145, 48)
end

local function create_fallback_tool(itemDefinition): Tool
	local tool = Instance.new("Tool")
	tool.Name = itemDefinition.ToolName
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Color = get_fallback_color(itemDefinition)
	handle.Material = Enum.Material.SmoothPlastic
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	return tool
end

local function search_for_tool_template(container: Instance?, searchNames: { string }): Tool?
	if not container then
		return nil
	end

	for _, searchName in ipairs(searchNames) do
		local directMatch = container:FindFirstChild(searchName)
		if directMatch and directMatch:IsA("Tool") then
			return directMatch
		end

		local recursiveMatch = container:FindFirstChild(searchName, true)
		if recursiveMatch and recursiveMatch:IsA("Tool") then
			return recursiveMatch
		end
	end

	return nil
end

local function get_tool_template(itemDefinition): Tool
	local cacheKey = itemDefinition.ItemId
	local cachedTemplate = toolTemplateCache[cacheKey]

	if cachedTemplate then
		return cachedTemplate
	end

	local searchNames = get_template_search_names(itemDefinition)
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")

	local template = search_for_tool_template(assetsFolder, searchNames)
		or search_for_tool_template(ReplicatedStorage, searchNames)
		or search_for_tool_template(ServerStorage, searchNames)
		or create_fallback_tool(itemDefinition)

	toolTemplateCache[cacheKey] = template
	return template
end

local function ensure_tool_handle(tool: Tool, itemDefinition): BasePart
	local handle = FarmingUtility.GetToolHandle(tool)
	if handle then
		return handle
	end

	handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Color = get_fallback_color(itemDefinition)
	handle.Material = Enum.Material.SmoothPlastic
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	return handle
end

local function clone_inventory_tool(itemDefinition): Tool
	local tool = get_tool_template(itemDefinition):Clone()
	tool.Name = itemDefinition.ToolName
	tool.CanBeDropped = false
	tool:SetAttribute("InventoryManaged", true)
	tool:SetAttribute("InventoryItemId", itemDefinition.ItemId)

	local handle = ensure_tool_handle(tool, itemDefinition)
	handle.Anchored = false
	handle.CanCollide = false

	return tool
end

local function is_managed_tool(tool: Tool, itemDefinition): boolean
	local inventoryItemId = tool:GetAttribute("InventoryItemId")

	if inventoryItemId == itemDefinition.ItemId then
		return true
	end

	return tool.Name == itemDefinition.ToolName
end

local function collect_tools(container: Instance?, itemDefinition): { Tool }
	local tools = {}

	if not container then
		return tools
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and is_managed_tool(child, itemDefinition) then
			tools[#tools + 1] = child
		end
	end

	return tools
end

local function destroy_tools(tools: { Tool }, amountToRemove: number): number
	local removed = 0

	for _, tool in ipairs(tools) do
		if removed >= amountToRemove then
			break
		end

		if tool.Parent then
			tool:Destroy()
			removed += 1
		end
	end

	return removed
end

local function sync_runtime_tools(player: Player, itemDefinition, desiredCount: number)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	local character = player.Character
	local backpackTools = collect_tools(backpack, itemDefinition)
	local characterTools = collect_tools(character, itemDefinition)
	local currentCount = #backpackTools + #characterTools

	if currentCount > desiredCount then
		local excess = currentCount - desiredCount
		excess -= destroy_tools(backpackTools, excess)

		if excess > 0 then
			destroy_tools(characterTools, excess)
		end

		return
	end

	if currentCount < desiredCount then
		if not backpack then
			return
		end

		for _ = 1, desiredCount - currentCount do
			local tool = clone_inventory_tool(itemDefinition)
			tool.Parent = backpack
		end
	end
end

local function sync_starter_gear(player: Player, itemDefinition, desiredCount: number)
	local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 5)
	if not starterGear then
		return
	end

	local starterGearTools = collect_tools(starterGear, itemDefinition)
	local currentCount = #starterGearTools

	if currentCount > desiredCount then
		destroy_tools(starterGearTools, currentCount - desiredCount)
		return
	end

	if currentCount < desiredCount then
		for _ = 1, desiredCount - currentCount do
			local tool = clone_inventory_tool(itemDefinition)
			tool.Parent = starterGear
		end
	end
end

local function sync_item_tools(player: Player, itemDefinition)
	if not player.Parent then
		return
	end

	local desiredCount = get_item_count(player, itemDefinition)
	sync_runtime_tools(player, itemDefinition, desiredCount)
	sync_starter_gear(player, itemDefinition, desiredCount)
end

local function build_shop_response(player: Player, success: boolean, code: string, extraFields)
	local response = {
		Success = success,
		Code = code,
		Horseshoes = get_horseshoes(player),
		SeedCount = get_item_count(player, FarmingCatalog.Seed),
		FruitCount = get_item_count(player, FarmingCatalog.Fruit),
	}

	if type(extraFields) == "table" then
		for key, value in pairs(extraFields) do
			response[key] = value
		end
	end

	return response
end

local function cleanup_player(player: Player)
	local trove = playerTroves[player]
	if not trove then
		return
	end

	trove:Destroy()
	playerTroves[player] = nil
end

local function track_player(player: Player)
	cleanup_player(player)

	local trove = Trove.new()
	playerTroves[player] = trove

	trove:Add(function()
		if playerTroves[player] == trove then
			playerTroves[player] = nil
		end
	end)

	for _, itemDefinition in ipairs(FarmingCatalog.GetManagedItems()) do
		local connection = DataUtility.server.bind(player, itemDefinition.InventoryPath, function()
			FarmingShopService.SyncInventoryTools(player, itemDefinition)
		end)

		if connection then
			trove:Add(connection)
		end
	end

	trove:Add(player.CharacterAdded:Connect(function()
		task.defer(FarmingShopService.SyncInventoryTools, player)
	end))

	trove:Add(player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") or child.Name == "StarterGear" then
			task.defer(FarmingShopService.SyncInventoryTools, player)
		end
	end))

	task.defer(FarmingShopService.SyncInventoryTools, player)
end

function FarmingShopService.SyncInventoryTools(player: Player, itemDefinition)
	if itemDefinition then
		sync_item_tools(player, itemDefinition)
		return
	end

	for _, definition in ipairs(FarmingCatalog.GetManagedItems()) do
		sync_item_tools(player, definition)
	end
end

function FarmingShopService.SyncSeedTools(player: Player)
	FarmingShopService.SyncInventoryTools(player, FarmingCatalog.Seed)
end

function FarmingShopService.SyncFruitTools(player: Player)
	FarmingShopService.SyncInventoryTools(player, FarmingCatalog.Fruit)
end

function FarmingShopService.GetSeedCount(player: Player): number
	return get_item_count(player, FarmingCatalog.Seed)
end

function FarmingShopService.GetFruitCount(player: Player): number
	return get_item_count(player, FarmingCatalog.Fruit)
end

function FarmingShopService.BuySeed(player: Player)
	if not DataUtility.server.get(player) then
		return build_shop_response(player, false, "DataUnavailable")
	end

	local currentHorseshoes = get_horseshoes(player)
	if currentHorseshoes < FarmingCatalog.Seed.Price then
		return build_shop_response(player, false, "NotEnoughHorseshoes")
	end

	set_horseshoes(player, currentHorseshoes - FarmingCatalog.Seed.Price)
	add_item_count(player, FarmingCatalog.Seed, 1)

	return build_shop_response(player, true, "SeedPurchased")
end

function FarmingShopService.SellFruit(player: Player)
	if not DataUtility.server.get(player) then
		return build_shop_response(player, false, "DataUnavailable")
	end

	local currentFruitCount = get_item_count(player, FarmingCatalog.Fruit)
	if currentFruitCount < 1 then
		return build_shop_response(player, false, "NoFruitAvailable")
	end

	set_item_count(player, FarmingCatalog.Fruit, currentFruitCount - 1)
	set_horseshoes(player, get_horseshoes(player) + FarmingCatalog.Fruit.SellPrice)

	return build_shop_response(player, true, "FruitSold")
end

function FarmingShopService.ConsumeSeed(player: Player)
	if not DataUtility.server.get(player) then
		return false, build_shop_response(player, false, "DataUnavailable")
	end

	local currentSeedCount = get_item_count(player, FarmingCatalog.Seed)
	if currentSeedCount < 1 then
		return false, build_shop_response(player, false, "NoSeedsAvailable")
	end

	set_item_count(player, FarmingCatalog.Seed, currentSeedCount - 1)

	return true, build_shop_response(player, true, "SeedConsumed")
end

function FarmingShopService.AwardHarvest(player: Player, amount: number?)
	if not DataUtility.server.get(player) then
		return build_shop_response(player, false, "DataUnavailable")
	end

	local harvestAmount = normalize_amount(amount or FarmingCatalog.Fruit.HarvestYield)
	if harvestAmount < 1 then
		harvestAmount = 1
	end

	add_item_count(player, FarmingCatalog.Fruit, harvestAmount)

	return build_shop_response(player, true, "HarvestAwarded", {
		HarvestAmount = harvestAmount,
	})
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

	serviceTrove:Add(Players.PlayerAdded:Connect(track_player))
	serviceTrove:Add(Players.PlayerRemoving:Connect(cleanup_player))

	initialized = true
end

return FarmingShopService
