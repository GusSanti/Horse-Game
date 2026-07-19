local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local HorseIndexService = {}

local INDEX_STATE_FUNCTION_NAME = "HorseIndexGetState"
local INDEX_STATE_CHANGED_EVENT_NAME = "HorseIndexStateChanged"
local STATE_DEBOUNCE_SECONDS = 0.15

local initialized = false
local orderedCatalogIds = nil
local playerTroves = {}
local pendingStateTokens = {}

local function build_ordered_catalog_ids()
	if orderedCatalogIds then
		return orderedCatalogIds
	end

	local ordered = {}
	local seen = {
		Default = true,
	}

	for _, rouletteEntry in ipairs(HorseCatalog.GetRoulettePool() or {}) do
		local catalogId = rouletteEntry and rouletteEntry.CatalogId
		if type(catalogId) == "string" and not seen[catalogId] and HorseCatalog.GetDefinition(catalogId) then
			seen[catalogId] = true
			ordered[#ordered + 1] = catalogId
		end
	end

	local remaining = {}
	for catalogId, definition in pairs(HorseCatalog.Definitions or {}) do
		if definition and not seen[catalogId] then
			remaining[#remaining + 1] = catalogId
		end
	end

	table.sort(remaining, function(leftCatalogId, rightCatalogId)
		local leftDefinition = HorseCatalog.GetDefinition(leftCatalogId)
		local rightDefinition = HorseCatalog.GetDefinition(rightCatalogId)
		local leftName = leftDefinition and leftDefinition.DisplayName or leftCatalogId
		local rightName = rightDefinition and rightDefinition.DisplayName or rightCatalogId
		return string.lower(leftName) < string.lower(rightName)
	end)

	for _, catalogId in ipairs(remaining) do
		ordered[#ordered + 1] = catalogId
	end

	orderedCatalogIds = ordered
	return orderedCatalogIds
end

local function build_unlocked_lookup(player)
	local unlocked = {}
	local profileData = DataUtility.server.get(player)
	local collection = type(profileData) == "table" and profileData.Collection or nil
	local horses = type(profileData) == "table" and profileData.Horses or nil
	local dataReady = type(profileData) == "table"

	local function push_catalog_id(catalogId)
		if type(catalogId) == "string" and catalogId ~= "" then
			unlocked[catalogId] = true
		end
	end

	if type(collection) == "table" then
		for _, catalogId in ipairs(collection.DiscoveredHorseIds or {}) do
			push_catalog_id(catalogId)
		end

		for _, catalogId in ipairs(collection.OwnedHorseCatalogIds or {}) do
			push_catalog_id(catalogId)
		end
	end

	if type(horses) == "table" and type(horses.Owned) == "table" then
		for _, horse in pairs(horses.Owned) do
			if type(horse) == "table" then
				push_catalog_id(horse.CatalogId)
			end
		end
	end

	return unlocked, dataReady
end

local function build_state_payload(player)
	local unlockedLookup, dataReady = build_unlocked_lookup(player)
	local entries = {}

	for index, catalogId in ipairs(build_ordered_catalog_ids()) do
		local definition = HorseCatalog.GetDefinition(catalogId)
		if not definition then
			continue
		end

		entries[#entries + 1] = {
			CatalogId = catalogId,
			DisplayName = definition.DisplayName,
			Description = definition.Description or "",
			Rarity = definition.Rarity or "",
			Tier = definition.Tier or "",
			ModelKey = definition.PlaceholderModelKey or "",
			IsUnlocked = unlockedLookup[catalogId] == true,
			SortOrder = index,
		}
	end

	return {
		Success = dataReady,
		Entries = entries,
	}
end

local function fire_state_update(player)
	if not player or not player.Parent then
		return
	end

	Net.Event[INDEX_STATE_CHANGED_EVENT_NAME]:Fire(player, build_state_payload(player))
end

local function queue_state_update(player)
	if not player or not player.Parent then
		return
	end

	pendingStateTokens[player] = (pendingStateTokens[player] or 0) + 1
	local token = pendingStateTokens[player]

	task.delay(STATE_DEBOUNCE_SECONDS, function()
		if pendingStateTokens[player] ~= token then
			return
		end

		pendingStateTokens[player] = nil
		fire_state_update(player)
	end)
end

local function disconnect_player(player)
	pendingStateTokens[player] = nil

	local trove = playerTroves[player]
	if not trove then
		return
	end

	trove:Destroy()
	playerTroves[player] = nil
end

local function track_player(player)
	disconnect_player(player)

	local trove = Trove.new()
	playerTroves[player] = trove

	for _, path in ipairs({ "Collection", "Horses", "Horses.Owned" }) do
		local connection = DataUtility.server.bind(player, path, function()
			queue_state_update(player)
		end)

		if connection then
			trove:Add(connection)
		end
	end
end

function HorseIndexService.GetState(player)
	return build_state_payload(player)
end

function HorseIndexService.Init()
	if initialized then
		return
	end

	Net.Function[INDEX_STATE_FUNCTION_NAME]:Respond(function(player)
		return HorseIndexService.GetState(player)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		track_player(player)
	end

	Players.PlayerAdded:Connect(track_player)
	Players.PlayerRemoving:Connect(disconnect_player)

	initialized = true
end

return HorseIndexService
