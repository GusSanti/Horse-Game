local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local StarterPack = game:GetService("StarterPack")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local InventoryLoadout = require(Utility:WaitForChild("InventoryLoadout"))
local Net = require(Libraries:WaitForChild("Net"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local FarmingCatalog = require(GameData:WaitForChild("FarmingCatalog"))

local InventoryLoadoutService = {}

local initialized = false
local UPDATE_LOADOUT_REMOTE_NAME = "UpdateInventoryLoadout"

local function get_server_modules()
	local modulesFolder = ServerStorage:WaitForChild("Modules")
	return {
		ConsumableToolService = require(modulesFolder:WaitForChild("ConsumableToolService")),
		FarmingShopService = require(modulesFolder:WaitForChild("FarmingShopService")),
		PersistentToolService = require(modulesFolder:WaitForChild("PersistentToolService")),
	}
end

local function get_inventory_item_count(player, itemDefinition)
	if not itemDefinition then
		return 0
	end

	local inventoryPath = itemDefinition.InventoryPath
	if type(inventoryPath) ~= "string" or inventoryPath == "" then
		return 0
	end

	local normalizedPath = inventoryPath
	if string.sub(inventoryPath, 1, #"Inventory.") ~= "Inventory." then
		normalizedPath = ("Inventory.%s"):format(inventoryPath)
	end
	local bucket = DataUtility.server.get(player, normalizedPath)
	if type(bucket) ~= "table" then
		return 0
	end

	return math.max(0, math.floor(tonumber(bucket[itemDefinition.ItemId]) or 0))
end

local function resolve_item_definition(itemId)
	return ToolItemCatalog.GetItemDefinition(itemId) or FarmingCatalog.GetItem(itemId)
end

local function for_each_tool_in_container(container, callback)
	if not container then
		return
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("Tool") then
			callback(descendant)
		end
	end
end

local function collect_owned_tool_item_ids(player)
	local ownedItemIds = {}

	for _, itemDefinition in ipairs(ToolItemCatalog.GetAllItems() or {}) do
		if get_inventory_item_count(player, itemDefinition) > 0 then
			ownedItemIds[itemDefinition.ItemId] = true
		end
	end

	for _, farmingDefinition in ipairs(FarmingCatalog.GetSeedItems() or {}) do
		if get_inventory_item_count(player, farmingDefinition) > 0 then
			ownedItemIds[farmingDefinition.ItemId] = true
		end
	end

	for _, farmingDefinition in ipairs(FarmingCatalog.GetFruitItems() or {}) do
		if get_inventory_item_count(player, farmingDefinition) > 0 then
			ownedItemIds[farmingDefinition.ItemId] = true
		end
	end

	for _, itemId in ipairs(InventoryLoadout.GetDefaultItemIds()) do
		local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
		if itemDefinition then
			ownedItemIds[itemDefinition.ItemId] = true
		end
	end

	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player.Character,
		player:FindFirstChild("StarterGear"),
	}

	for _, container in ipairs(containers) do
		for_each_tool_in_container(container, function(tool)
			local itemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
				or FarmingCatalog.GetItem(tool:GetAttribute("FarmingItemId"))
			if itemDefinition then
				ownedItemIds[itemDefinition.ItemId] = true
			end
		end)
	end

	local orderedItemIds = {}
	for itemId in pairs(ownedItemIds) do
		orderedItemIds[#orderedItemIds + 1] = itemId
	end

	table.sort(orderedItemIds)
	return orderedItemIds
end

local function collect_owned_generic_tool_names(player)
	local ownedToolNames = {}
	local defaultGenericTools = InventoryLoadout.GetDefaultGenericToolDefinitions()

	for _, definition in ipairs(defaultGenericTools) do
		local toolName = InventoryLoadout.NormalizeGenericToolName(definition.ToolName)
		if toolName then
			ownedToolNames[toolName] = definition.ToolName
		end
	end

	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player.Character,
		player:FindFirstChild("StarterGear"),
		StarterPack,
	}

	for _, container in ipairs(containers) do
		for_each_tool_in_container(container, function(tool)
			if ToolItemCatalog.ResolveDefinitionFromTool(tool) == nil then
				local toolName = InventoryLoadout.NormalizeGenericToolName(tool.Name)
				if toolName then
					ownedToolNames[toolName] = tool.Name
				end
			end
		end)
	end

	local orderedToolNames = {}
	for _, toolName in pairs(ownedToolNames) do
		orderedToolNames[#orderedToolNames + 1] = toolName
	end

	table.sort(orderedToolNames)
	return orderedToolNames
end

local function sync_player_tools(player)
	local serverModules = get_server_modules()
	serverModules.FarmingShopService.SyncPlayerTools(player)
	serverModules.ConsumableToolService.SyncPlayerTools(player)
	serverModules.PersistentToolService.SyncPlayerTools(player)
end

local function ensure_loadout_initialized(player)
	if DataUtility.server.get(player, InventoryLoadout.HOTBAR_INITIALIZED_PATH) == true then
		return
	end

	DataUtility.server.set(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH, collect_owned_tool_item_ids(player))
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH, collect_owned_generic_tool_names(player))
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_INITIALIZED_PATH, true)
end

local function player_has_access_to_item(player, itemDefinition)
	if not itemDefinition then
		return false
	end

	if InventoryLoadout.IsDefaultItemId(itemDefinition.ItemId) then
		return true
	end

	if get_inventory_item_count(player, itemDefinition) > 0 then
		return true
	end

	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player.Character,
		player:FindFirstChild("StarterGear"),
		StarterPack,
	}

	for _, container in ipairs(containers) do
		local hasAccess = false
		for_each_tool_in_container(container, function(tool)
			if hasAccess then
				return
			end

			local resolvedItemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
				or FarmingCatalog.GetItem(tool:GetAttribute("FarmingItemId"))
			if resolvedItemDefinition and resolvedItemDefinition.ItemId == itemDefinition.ItemId then
				hasAccess = true
			end
		end)
		if hasAccess then
			return true
		end
	end

	return false
end

local function player_has_access_to_generic_tool(player, toolName)
	local normalizedToolName = InventoryLoadout.NormalizeGenericToolName(toolName)
	if not normalizedToolName then
		return false
	end

	for _, definition in ipairs(InventoryLoadout.GetDefaultGenericToolDefinitions()) do
		if InventoryLoadout.NormalizeGenericToolName(definition.ToolName) == normalizedToolName then
			return true
		end
	end

	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player.Character,
		player:FindFirstChild("StarterGear"),
		StarterPack,
	}

	for _, container in ipairs(containers) do
		local hasAccess = false
		for_each_tool_in_container(container, function(tool)
			if hasAccess then
				return
			end

			if ToolItemCatalog.ResolveDefinitionFromTool(tool) == nil
				and InventoryLoadout.NormalizeGenericToolName(tool.Name) == normalizedToolName
			then
				hasAccess = true
			end
		end)
		if hasAccess then
			return true
		end
	end

	return false
end

local function update_item_loadout(player, itemId, isEquipped)
	local itemDefinition = resolve_item_definition(itemId)
	if not itemDefinition then
		return false, "UnknownItem"
	end

	ensure_loadout_initialized(player)

	if isEquipped and not player_has_access_to_item(player, itemDefinition) then
		return false, "ItemUnavailable"
	end

	local nextItemIds = InventoryLoadout.SetItemEquipped(
		DataUtility.server.get(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH),
		itemDefinition.ItemId,
		isEquipped
	)
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH, nextItemIds)
	sync_player_tools(player)
	return true, "Updated"
end

local function update_generic_loadout(player, toolName, isEquipped)
	local normalizedToolName = InventoryLoadout.NormalizeGenericToolName(toolName)
	if not normalizedToolName then
		return false, "UnknownTool"
	end

	ensure_loadout_initialized(player)

	if isEquipped and not player_has_access_to_generic_tool(player, toolName) then
		return false, "ToolUnavailable"
	end

	local nextToolNames = InventoryLoadout.SetGenericToolEquipped(
		DataUtility.server.get(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH),
		toolName,
		isEquipped
	)
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH, nextToolNames)
	sync_player_tools(player)
	return true, "Updated"
end

function InventoryLoadoutService.SyncPlayerTools(player)
	ensure_loadout_initialized(player)
	sync_player_tools(player)
end

function InventoryLoadoutService.UpdateLoadout(player, payload)
	if type(payload) ~= "table" then
		return false, "InvalidPayload"
	end

	local kind = payload.Kind
	local isEquipped = payload.Equipped == true

	if kind == "item" then
		return update_item_loadout(player, payload.Value, isEquipped)
	end

	if kind == "generic" then
		return update_generic_loadout(player, payload.Value, isEquipped)
	end

	return false, "UnknownKind"
end

function InventoryLoadoutService.Init()
	if initialized then
		return
	end

	Net.Function[UPDATE_LOADOUT_REMOTE_NAME]:Respond(function(player, payload)
		return InventoryLoadoutService.UpdateLoadout(player, payload)
	end)

	initialized = true
end

return InventoryLoadoutService