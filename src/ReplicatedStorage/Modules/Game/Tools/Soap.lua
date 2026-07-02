------------------//SERVICES
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//VARIABLES
local Modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local GameData: Folder = Modules:WaitForChild("GameData")
local Utility: Folder = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local MANAGED_TOOL_ATTRIBUTE = "InventoryManaged"

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

local function get_inventory_path(itemDefinition): string?
	if not itemDefinition then
		return nil
	end

	return normalize_inventory_path(itemDefinition.InventoryPath)
end

local function consume_managed_tool(player: Player, tool: Tool?, itemId: string, amount: number?): boolean
	if not tool or tool:GetAttribute(MANAGED_TOOL_ATTRIBUTE) ~= true then
		return true
	end

	local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
	local inventoryPath = get_inventory_path(itemDefinition)
	if not itemDefinition or not inventoryPath then
		return false
	end

	local bucket = DataUtility.server.get(player, inventoryPath)
	if type(bucket) ~= "table" then
		return false
	end

	local consumeAmount = math.max(1, math.floor(amount or 1))
	local currentCount = bucket[itemDefinition.ItemId] or 0
	if currentCount < consumeAmount then
		return false
	end

	local updatedCount = currentCount - consumeAmount
	if updatedCount > 0 then
		bucket[itemDefinition.ItemId] = updatedCount
	else
		bucket[itemDefinition.ItemId] = nil
	end

	DataUtility.server.set(player, inventoryPath, bucket)
	return true
end

local soap = {
	id = "soap",
	toolNames = {
		"soap",
	},
	clientHandlerName = "SoapClient",
	prompt = {
		actionText = "Wash",
		objectText = "Your horse",
		holdDuration = 0.2,
		maxActivationDistance = 10,
		requiresLineOfSight = false,
	},
	consumeOnUse = true,
	onUse = function(context)
		local QuestService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("QuestService"))

		local horses = DataUtility.server.get(context.player, "Horses")
		local stats = DataUtility.server.get(context.player, "Stats")
		if not horses or not horses.Owned or not horses.Owned[context.horseId] then
			return false, "HorseNotOwned"
		end

		local horse = horses.Owned[context.horseId]
		local now = os.time()
		local cleanBonus = 0

		local consumedFromInventory = consume_managed_tool(context.player, context.tool, soap.id, 1)
		if consumedFromInventory ~= true then
			return false, "ItemUnavailable"
		end

		if horse.Bond and horse.Bond.CareBonus then
			cleanBonus = horse.Bond.CareBonus.Clean or 0
		end

		if horse.Needs and horse.Needs.Values and horse.Needs.Max then
			horse.Needs.Values.Cleanliness = horse.Needs.Max.Cleanliness or horse.Needs.Values.Cleanliness
			horse.Needs.Values.Happiness = math.clamp(
				(horse.Needs.Values.Happiness or 0) + math.max(2, math.floor(cleanBonus * 0.5)),
				0,
				horse.Needs.Max.Happiness or 100
			)
		end

		if horse.State then
			horse.State.IsDirty = false
			horse.State.LastCleanedAt = now
			horse.State.LastCareAt = now
			horse.State.Mood = "Fresh"
		end

		if horse.Stats then
			horse.Stats.CareActions = (horse.Stats.CareActions or 0) + 1
		end

		if horse.Bond then
			horse.Bond.Friendship = math.clamp(
				(horse.Bond.Friendship or 0) + cleanBonus,
				0,
				horse.Bond.MaxFriendship or 100
			)
		end

		DataUtility.server.set(context.player, "Horses", horses)

		if stats then
			stats.TotalCareActions = (stats.TotalCareActions or 0) + 1
			stats.TotalCleanActions = (stats.TotalCleanActions or 0) + 1
			DataUtility.server.set(context.player, "Stats", stats)
			QuestService.RefreshDailyQuestProgress(context.player)
		end

		return true, "Cleaned"
	end,
}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
return soap
