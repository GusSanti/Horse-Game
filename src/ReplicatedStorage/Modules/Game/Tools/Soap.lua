------------------//SERVICES
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//VARIABLES
local Modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local GameData: Folder = Modules:WaitForChild("GameData")
local Utility: Folder = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local SOAP_ITEM_ID = "soap"
local MANAGED_TOOL_ATTRIBUTE = "InventoryManaged"
local cachedServerModules = nil

local function format_debug_number(value): string
	if type(value) ~= "number" then
		return "nil"
	end

	return ("%.2f"):format(value)
end

local function debug_log_soap(context, stage: string, horse, extra: string?)
	local needs = type(horse) == "table" and horse.Needs or nil
	local values = type(needs) == "table" and needs.Values or nil
	local maxValues = type(needs) == "table" and needs.Max or nil
	local state = type(horse) == "table" and horse.State or nil
	local horseName = context.horseId

	if type(horse) == "table" then
		horseName = horse.Nickname or horse.DisplayName or horse.Id or context.horseId
	end

	local suffix = if type(extra) == "string" and extra ~= "" then (" | %s"):format(extra) else ""

	print(
		("[Soap][%s] player=%s horseId=%s horseName=%s tool=%s rawCleanliness=%s maxCleanliness=%s lastUpdatedAt=%s isDirty=%s%s"):format(
			stage,
			context.player and context.player.Name or "nil",
			tostring(context.horseId),
			tostring(horseName),
			context.tool and context.tool.Name or tostring(context.itemId),
			format_debug_number(type(values) == "table" and values.Cleanliness or nil),
			format_debug_number(type(maxValues) == "table" and maxValues.Cleanliness or nil),
			tostring(type(needs) == "table" and needs.LastUpdatedAt or nil),
			tostring(type(state) == "table" and state.IsDirty or nil),
			suffix
		)
	)
end

local function get_server_modules()
	if cachedServerModules then
		return cachedServerModules
	end

	local modulesFolder = ServerStorage:WaitForChild("Modules")
	cachedServerModules = {
		HorseCareService = require(modulesFolder:WaitForChild("HorseCareService")),
		QuestService = require(modulesFolder:WaitForChild("QuestService")),
	}

	return cachedServerModules
end

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
	id = SOAP_ITEM_ID,
	toolNames = {
		SOAP_ITEM_ID,
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
		local serverModules = get_server_modules()

		local horses = DataUtility.server.get(context.player, "Horses")
		local stats = DataUtility.server.get(context.player, "Stats")
		if not horses or not horses.Owned or not horses.Owned[context.horseId] then
			print(("[Soap][reject] player=%s horseId=%s reason=HorseNotOwned"):format(
				context.player and context.player.Name or "nil",
				tostring(context.horseId)
			))
			return false, "HorseNotOwned"
		end

		local horse = horses.Owned[context.horseId]
		local now = os.time()
		local cleanBonus = 0

		debug_log_soap(context, "before-consume", horse)

		local consumedFromInventory = consume_managed_tool(context.player, context.tool, SOAP_ITEM_ID, 1)
		if consumedFromInventory ~= true then
			debug_log_soap(context, "consume-failed", horse, "reason=ItemUnavailable")
			return false, "ItemUnavailable"
		end
		serverModules.QuestService.EnsureDailyQuest(context.player)

		serverModules.HorseCareService.RefreshHorse(horse, now)
		debug_log_soap(context, "after-refresh", horse)

		if horse.Bond and horse.Bond.CareBonus then
			cleanBonus = horse.Bond.CareBonus.Clean or 0
		end

		if horse.Needs and horse.Needs.Values and horse.Needs.Max then
			horse.Needs.Values.Cleanliness = 100
			horse.Needs.LastUpdatedAt = now
			horse.Needs.Values.Happiness = math.clamp(
				(horse.Needs.Values.Happiness or 0) + math.max(2, math.floor(cleanBonus * 0.5)),
				0,
				horse.Needs.Max.Happiness or 100
			)
		end

		debug_log_soap(context, "after-set-100", horse, ("cleanBonus=%s"):format(format_debug_number(cleanBonus)))

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
		debug_log_soap(context, "after-save-local", horse)

		local savedHorses = DataUtility.server.get(context.player, "Horses")
		local savedHorse = savedHorses and savedHorses.Owned and savedHorses.Owned[context.horseId] or nil
		debug_log_soap(context, "after-save-readback", savedHorse)

		if stats then
			stats.TotalCareActions = (stats.TotalCareActions or 0) + 1
			stats.TotalCleanActions = (stats.TotalCleanActions or 0) + 1
			DataUtility.server.set(context.player, "Stats", stats)
			serverModules.QuestService.RefreshDailyQuestProgress(context.player)
		end

		debug_log_soap(context, "completed", savedHorse or horse, "response=Cleaned")

		return true, "Cleaned"
	end,
}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
return soap
