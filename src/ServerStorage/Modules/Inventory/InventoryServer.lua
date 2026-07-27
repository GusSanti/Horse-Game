local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local InventoryLoadoutService = require(script.Parent:WaitForChild("InventoryLoadoutService"))

local InventoryService = {}

local function normalize_inventory_path(path: string?): string?
	if type(path) ~= "string" then
		return nil
	end

	local trimmedPath = string.gsub(path, "^%s*(.-)%s*$", "%1")
	if trimmedPath == "" then
		return nil
	end

	if string.sub(trimmedPath, 1, #"Inventory.") == "Inventory." then
		return trimmedPath
	end

	return ("Inventory.%s"):format(trimmedPath)
end

local function resolve_item_definition(itemDefinitionOrId)
	if type(itemDefinitionOrId) == "table" then
		return itemDefinitionOrId
	end

	return ToolItemCatalog.GetItemDefinition(itemDefinitionOrId)
end

function InventoryService.GetItemDefinition(itemDefinitionOrId)
	return resolve_item_definition(itemDefinitionOrId)
end

function InventoryService.GetInventoryPath(itemDefinitionOrId): string?
	local itemDefinition = resolve_item_definition(itemDefinitionOrId)
	if not itemDefinition then
		return nil
	end

	return normalize_inventory_path(itemDefinition.InventoryPath)
end

function InventoryService.GetItemCount(player: Player, itemDefinitionOrId): number
	local itemDefinition = resolve_item_definition(itemDefinitionOrId)
	local inventoryPath = InventoryService.GetInventoryPath(itemDefinition)
	if not itemDefinition or not inventoryPath then
		return 0
	end

	local bucket = DataUtility.server.get(player, inventoryPath)
	if type(bucket) ~= "table" then
		return 0
	end

	return bucket[itemDefinition.ItemId] or 0
end

function InventoryService.SetItemCount(player: Player, itemDefinitionOrId, amount: number): number
	local itemDefinition = resolve_item_definition(itemDefinitionOrId)
	local inventoryPath = InventoryService.GetInventoryPath(itemDefinition)
	local profileData = DataUtility.server.get(player)

	if not itemDefinition or not inventoryPath or not profileData then
		return 0
	end

	local bucket = TableUtility.EnsurePath(profileData, inventoryPath)
	local normalizedAmount = math.max(0, math.floor(amount or 0))

	if normalizedAmount > 0 then
		bucket[itemDefinition.ItemId] = normalizedAmount
	else
		bucket[itemDefinition.ItemId] = nil
	end

	DataUtility.server.set(player, inventoryPath, bucket)
	return normalizedAmount
end

function InventoryService.AddItemCount(player: Player, itemDefinitionOrId, amount: number): number
	local itemDefinition = resolve_item_definition(itemDefinitionOrId)
	local previousCount = InventoryService.GetItemCount(player, itemDefinition)
	local updatedCount = InventoryService.SetItemCount(player, itemDefinition, previousCount + (amount or 0))

	if itemDefinition and updatedCount > previousCount then
		InventoryLoadoutService.TryAutoEquipNewItem(player, itemDefinition.ItemId, previousCount)
	end

	return updatedCount
end

return InventoryService
