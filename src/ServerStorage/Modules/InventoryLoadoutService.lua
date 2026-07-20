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

local function trim_hotbar_to_max_slots(player)
	local itemIds = DataUtility.server.get(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH)
	local toolNames = DataUtility.server.get(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH)
	local changed = false

	while InventoryLoadout.CountHotbarSlots(itemIds, toolNames) > InventoryLoadout.MAX_HOTBAR_SLOTS do
		local kind, value = InventoryLoadout.GetLastHotbarEntry(itemIds, toolNames)
		if not kind then
			break
		end

		itemIds, toolNames = InventoryLoadout.RemoveHotbarEntry(itemIds, toolNames, kind, value)
		changed = true
	end

	if changed then
		DataUtility.server.set(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH, itemIds)
		DataUtility.server.set(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH, toolNames)
	end
end

local function ensure_loadout_initialized(player)
	if DataUtility.server.get(player, InventoryLoadout.HOTBAR_INITIALIZED_PATH) == true then
		trim_hotbar_to_max_slots(player)
		return
	end

	DataUtility.server.set(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH, collect_owned_tool_item_ids(player))
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH, collect_owned_generic_tool_names(player))
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_INITIALIZED_PATH, true)
	trim_hotbar_to_max_slots(player)
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

local function get_accessible_hotbar_entries(player, itemIds, genericToolNames)
	local entries = {}
	local seen = {}

	local function push(kind, value, normalizedValue)
		if not normalizedValue then
			return
		end

		local key = ("%s:%s"):format(kind, normalizedValue)
		if seen[key] then
			return
		end

		seen[key] = true
		entries[#entries + 1] = {
			Kind = kind,
			Value = value,
		}
	end

	for _, itemId in ipairs(itemIds or {}) do
		local itemDefinition = resolve_item_definition(itemId)
		if itemDefinition and player_has_access_to_item(player, itemDefinition) then
			push("item", itemDefinition.ItemId, InventoryLoadout.NormalizeItemId(itemDefinition.ItemId))
		end
	end

	for _, toolName in ipairs(genericToolNames or {}) do
		local normalizedToolName = InventoryLoadout.NormalizeGenericToolName(toolName)
		if normalizedToolName and player_has_access_to_generic_tool(player, toolName) then
			push("generic", toolName, normalizedToolName)
		end
	end

	return entries
end

local function count_accessible_hotbar_slots(player, itemIds, genericToolNames)
	return #get_accessible_hotbar_entries(player, itemIds, genericToolNames)
end

local function is_tool_for_item(tool: Tool, itemDefinition): boolean
	local resolvedItemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
		or FarmingCatalog.GetItem(tool:GetAttribute("FarmingItemId"))

	return resolvedItemDefinition ~= nil and resolvedItemDefinition.ItemId == itemDefinition.ItemId
end

local function find_item_tool_in_container(container: Instance?, itemDefinition): Tool?
	if not container then
		return nil
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and is_tool_for_item(child, itemDefinition) then
			return child
		end
	end

	return nil
end

local function equip_item_tool_in_hand(player, itemDefinition): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return false
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	local tool = find_item_tool_in_container(backpack, itemDefinition)
		or find_item_tool_in_container(character, itemDefinition)
	if not tool then
		return false
	end

	humanoid:UnequipTools()
	humanoid:EquipTool(tool)
	return true
end

local function get_ninth_accessible_hotbar_entry(player, itemIds, genericToolNames)
	local entries = get_accessible_hotbar_entries(player, itemIds, genericToolNames)
	return entries[InventoryLoadout.MAX_HOTBAR_SLOTS]
end

local function can_use_hotbar_entry(player, kind, value)
	if kind == "item" then
		local itemDefinition = resolve_item_definition(value)
		return itemDefinition ~= nil and player_has_access_to_item(player, itemDefinition), itemDefinition and itemDefinition.ItemId or value
	end

	if kind == "generic" then
		return player_has_access_to_generic_tool(player, value), value
	end

	return false, nil
end

local function split_hotbar_entries(entries)
	local itemIds = {}
	local genericToolNames = {}

	for _, entry in ipairs(entries) do
		if entry.Kind == "item" then
			itemIds[#itemIds + 1] = entry.Value
		elseif entry.Kind == "generic" then
			genericToolNames[#genericToolNames + 1] = entry.Value
		end
	end

	return itemIds, genericToolNames
end

local function save_visible_hotbar_with_target(player, targetKind, targetValue, visibleEntries)
	if type(visibleEntries) ~= "table" then
		return false
	end

	local entries = {}
	local seen = {}

	local function push(kind, value)
		local canUse, resolvedValue = can_use_hotbar_entry(player, kind, value)
		if not canUse or not resolvedValue then
			return
		end

		local normalizedValue = if kind == "item"
			then InventoryLoadout.NormalizeItemId(resolvedValue)
			else InventoryLoadout.NormalizeGenericToolName(resolvedValue)
		if not normalizedValue then
			return
		end

		local key = ("%s:%s"):format(kind, normalizedValue)
		if seen[key] then
			return
		end

		seen[key] = true
		entries[#entries + 1] = {
			Kind = kind,
			Value = resolvedValue,
		}
	end

	for _, entry in ipairs(visibleEntries) do
		if #entries >= InventoryLoadout.MAX_HOTBAR_SLOTS then
			break
		end

		if type(entry) == "table" then
			push(entry.Kind, entry.Value)
		end
	end

	local targetKey = ("%s:%s"):format(
		targetKind,
		targetKind == "item"
			and (InventoryLoadout.NormalizeItemId(targetValue) or "")
			or (InventoryLoadout.NormalizeGenericToolName(targetValue) or "")
	)

	if not seen[targetKey] then
		if #entries >= InventoryLoadout.MAX_HOTBAR_SLOTS then
			entries[InventoryLoadout.MAX_HOTBAR_SLOTS] = nil
		end

		push(targetKind, targetValue)
	end

	if not seen[targetKey] then
		return false
	end

	local nextItemIds, nextToolNames = split_hotbar_entries(entries)
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH, nextItemIds)
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH, nextToolNames)
	sync_player_tools(player)
	return true
end

local function remove_replacement_or_last(player, itemIds, genericToolNames, replacementKind, replacementValue)
	local nextItemIds = itemIds
	local nextToolNames = genericToolNames

	if replacementKind == "item" or replacementKind == "generic" then
		local currentVisibleCount = count_accessible_hotbar_slots(player, nextItemIds, nextToolNames)
		local replacedItemIds, replacedToolNames = InventoryLoadout.RemoveHotbarEntry(
			nextItemIds,
			nextToolNames,
			replacementKind,
			replacementValue
		)

		if count_accessible_hotbar_slots(player, replacedItemIds, replacedToolNames) < currentVisibleCount then
			return replacedItemIds, replacedToolNames
		end
	end

	local ninthEntry = get_ninth_accessible_hotbar_entry(player, nextItemIds, nextToolNames)
	if ninthEntry then
		return InventoryLoadout.RemoveHotbarEntry(nextItemIds, nextToolNames, ninthEntry.Kind, ninthEntry.Value)
	end

	return nextItemIds, nextToolNames
end

local function reserve_hotbar_slot(player, targetKind, targetValue, replacementKind, replacementValue)
	local itemIds = DataUtility.server.get(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH)
	local toolNames = DataUtility.server.get(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH)

	local alreadyEquipped = if targetKind == "item"
		then InventoryLoadout.IsItemEquipped(itemIds, targetValue)
		else InventoryLoadout.IsGenericToolEquipped(toolNames, targetValue)

	if alreadyEquipped
		or count_accessible_hotbar_slots(player, itemIds, toolNames) < InventoryLoadout.MAX_HOTBAR_SLOTS
	then
		return itemIds, toolNames
	end

	local nextItemIds, nextToolNames = remove_replacement_or_last(
		player,
		itemIds,
		toolNames,
		replacementKind,
		replacementValue
	)
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH, nextItemIds)
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH, nextToolNames)
	return nextItemIds, nextToolNames
end

local function update_item_loadout(player, itemId, isEquipped, replacementKind, replacementValue, visibleEntries)
	local itemDefinition = resolve_item_definition(itemId)
	if not itemDefinition then
		return false, "UnknownItem"
	end

	ensure_loadout_initialized(player)

	if isEquipped and not player_has_access_to_item(player, itemDefinition) then
		return false, "ItemUnavailable"
	end

	if isEquipped and type(visibleEntries) == "table" then
		if save_visible_hotbar_with_target(player, "item", itemDefinition.ItemId, visibleEntries) then
			return true, "Updated"
		end

		return false, "InvalidHotbarEntries"
	end

	local itemIds = DataUtility.server.get(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH)
	if isEquipped then
		itemIds = select(1, reserve_hotbar_slot(player, "item", itemDefinition.ItemId, replacementKind, replacementValue))
	end

	local nextItemIds = InventoryLoadout.SetItemEquipped(
		itemIds,
		itemDefinition.ItemId,
		isEquipped
	)
	DataUtility.server.set(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH, nextItemIds)
	sync_player_tools(player)
	return true, "Updated"
end

local function update_generic_loadout(player, toolName, isEquipped, replacementKind, replacementValue, visibleEntries)
	local normalizedToolName = InventoryLoadout.NormalizeGenericToolName(toolName)
	if not normalizedToolName then
		return false, "UnknownTool"
	end

	ensure_loadout_initialized(player)

	if isEquipped and not player_has_access_to_generic_tool(player, toolName) then
		return false, "ToolUnavailable"
	end

	if isEquipped and type(visibleEntries) == "table" then
		if save_visible_hotbar_with_target(player, "generic", toolName, visibleEntries) then
			return true, "Updated"
		end

		return false, "InvalidHotbarEntries"
	end

	local toolNames = DataUtility.server.get(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH)
	if isEquipped then
		local _reservedItemIds, reservedToolNames = reserve_hotbar_slot(player, "generic", toolName, replacementKind, replacementValue)
		toolNames = reservedToolNames
	end

	local nextToolNames = InventoryLoadout.SetGenericToolEquipped(
		toolNames,
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

function InventoryLoadoutService.TryAutoEquipNewItem(player, itemId, previousCount: number?): (boolean, string)
	local itemDefinition = resolve_item_definition(itemId)
	if not itemDefinition then
		return false, "UnknownItem"
	end

	if math.max(0, math.floor(tonumber(previousCount) or 0)) > 0 then
		return false, "AlreadyOwned"
	end

	ensure_loadout_initialized(player)

	local itemIds = DataUtility.server.get(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH)
	local toolNames = DataUtility.server.get(player, InventoryLoadout.HOTBAR_GENERIC_TOOL_NAMES_PATH)
	local alreadyEquipped = InventoryLoadout.IsItemEquipped(itemIds, itemDefinition.ItemId)

	if not alreadyEquipped then
		if count_accessible_hotbar_slots(player, itemIds, toolNames) >= InventoryLoadout.MAX_HOTBAR_SLOTS then
			return false, "HotbarFull"
		end

		itemIds = InventoryLoadout.SetItemEquipped(itemIds, itemDefinition.ItemId, true)
		DataUtility.server.set(player, InventoryLoadout.HOTBAR_ITEM_IDS_PATH, itemIds)
	end

	sync_player_tools(player)

	if equip_item_tool_in_hand(player, itemDefinition) then
		return true, "EquippedInHand"
	end

	return true, "AddedToHotbar"
end

function InventoryLoadoutService.UpdateLoadout(player, payload)
	if type(payload) ~= "table" then
		return false, "InvalidPayload"
	end

	local kind = payload.Kind
	local isEquipped = payload.Equipped == true
	local replacementKind = payload.ReplaceKind
	local replacementValue = payload.ReplaceValue
	local visibleEntries = payload.HotbarEntries

	if kind == "item" then
		return update_item_loadout(player, payload.Value, isEquipped, replacementKind, replacementValue, visibleEntries)
	end

	if kind == "generic" then
		return update_generic_loadout(player, payload.Value, isEquipped, replacementKind, replacementValue, visibleEntries)
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
