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
	local updatedAmount = get_item_count(player, itemDefinition) + amount
	return set_item_count(player, itemDefinition, updatedAmount)
end

local function create_fallback_seed_tool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = FarmingUtility.SEED_TOOL_NAME
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Color = Color3.fromRGB(121, 85, 58)
	handle.Material = Enum.Material.SmoothPlastic
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Parent = tool

	return tool
end

local function get_seed_tool_template(): Tool
	local success, template = pcall(FarmingUtility.GetSeedToolTemplate)
	if success and template then
		return template
	end

	local fallbackTemplate = ServerStorage:FindFirstChild(FarmingUtility.SEED_TOOL_NAME, true)
	if fallbackTemplate and fallbackTemplate:IsA("Tool") then
		return fallbackTemplate
	end

	return create_fallback_seed_tool()
end

local function clone_seed_tool(): Tool
	local tool = get_seed_tool_template():Clone()
	tool.Name = FarmingUtility.SEED_TOOL_NAME
	tool.CanBeDropped = false

	local handle = FarmingUtility.GetToolHandle(tool)
	if handle then
		handle.Anchored = false
		handle.CanCollide = false
	end

	return tool
end

local function collect_seed_tools(player: Player): { Tool }
	local seedTools = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	local function collect_from(container: Instance?)
		if not container then
			return
		end

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Tool") and child.Name == FarmingUtility.SEED_TOOL_NAME then
				seedTools[#seedTools + 1] = child
			end
		end
	end

	collect_from(backpack)
	collect_from(character)

	return seedTools
end

function FarmingShopService.SyncSeedTools(player: Player)
	if not player.Parent then
		return
	end

	local desiredCount = get_item_count(player, FarmingCatalog.Seed)
	local seedTools = collect_seed_tools(player)
	local currentCount = #seedTools

	if currentCount > desiredCount then
		for index = 1, currentCount - desiredCount do
			local tool = seedTools[index]
			if tool and tool.Parent then
				tool:Destroy()
			end
		end

		return
	end

	if currentCount < desiredCount then
		local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)

		for _ = 1, desiredCount - currentCount do
			local tool = clone_seed_tool()
			tool.Parent = backpack or player
		end
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

	local seedInventoryConnection = DataUtility.server.bind(player, FarmingCatalog.Seed.InventoryPath, function()
		FarmingShopService.SyncSeedTools(player)
	end)

	if seedInventoryConnection then
		trove:Add(seedInventoryConnection)
	end

	trove:Add(player.CharacterAdded:Connect(function()
		task.defer(FarmingShopService.SyncSeedTools, player)
	end))

	task.defer(FarmingShopService.SyncSeedTools, player)
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
		return {
			Success = false,
			Code = "NotEnoughHorseshoes",
			Horseshoes = currentHorseshoes,
			SeedCount = get_item_count(player, FarmingCatalog.Seed),
		}
	end

	local updatedHorseshoes = set_horseshoes(player, currentHorseshoes - FarmingCatalog.Seed.Price)
	local updatedSeedCount = add_item_count(player, FarmingCatalog.Seed, 1)

	return {
		Success = true,
		Code = "SeedPurchased",
		Horseshoes = updatedHorseshoes,
		SeedCount = updatedSeedCount,
	}
end

function FarmingShopService.SellFruit(player: Player)
	local currentFruitCount = get_item_count(player, FarmingCatalog.Fruit)
	if currentFruitCount < 1 then
		return {
			Success = false,
			Code = "NoFruitAvailable",
			Horseshoes = get_horseshoes(player),
			FruitCount = currentFruitCount,
		}
	end

	local updatedFruitCount = set_item_count(player, FarmingCatalog.Fruit, currentFruitCount - 1)
	local updatedHorseshoes = set_horseshoes(player, get_horseshoes(player) + FarmingCatalog.Fruit.SellPrice)

	return {
		Success = true,
		Code = "FruitSold",
		Horseshoes = updatedHorseshoes,
		FruitCount = updatedFruitCount,
	}
end

function FarmingShopService.ConsumeSeed(player: Player)
	local currentSeedCount = get_item_count(player, FarmingCatalog.Seed)
	if currentSeedCount < 1 then
		return false, {
			Success = false,
			Code = "NoSeedsAvailable",
			SeedCount = currentSeedCount,
		}
	end

	local updatedSeedCount = set_item_count(player, FarmingCatalog.Seed, currentSeedCount - 1)

	return true, {
		Success = true,
		Code = "SeedConsumed",
		SeedCount = updatedSeedCount,
	}
end

function FarmingShopService.AwardHarvest(player: Player, amount: number?)
	local updatedFruitCount = add_item_count(player, FarmingCatalog.Fruit, amount or FarmingCatalog.Fruit.HarvestYield)

	return {
		Success = true,
		Code = "HarvestAwarded",
		FruitCount = updatedFruitCount,
	}
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
