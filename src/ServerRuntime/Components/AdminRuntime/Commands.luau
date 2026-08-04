--!strict

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local DataUtility: any = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))
local ToolItemCatalog: any = require(Modules:WaitForChild("GameData"):WaitForChild("ToolItemCatalog"))
local AdminAccessService: any = require(
	ServerStorage:WaitForChild("Modules"):WaitForChild("Admin"):WaitForChild("AdminAccessService")
)
local InventoryService: any = require(
	ServerStorage:WaitForChild("Modules"):WaitForChild("Inventory"):WaitForChild("InventoryServer")
)

local Commands = {}

local COMMAND_NAME = "!setcoins"
local EAT_COMMAND_NAME = "!eat"
local MAX_HORSESHOES = 1000000000
local randomGenerator = Random.new()

local function normalize(value: string): string
	return string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
end

local function resolve_target_player(requestingPlayer: Player, playerName: string): Player?
	local normalizedName = normalize(playerName)
	if normalizedName == "me" then
		return requestingPlayer
	end

	for _, player: Player in Players:GetPlayers() do
		if normalize(player.Name) == normalizedName then
			return player
		end
	end

	local matches: { Player } = {}
	for _, player: Player in Players:GetPlayers() do
		if string.sub(normalize(player.Name), 1, #normalizedName) == normalizedName then
			matches[#matches + 1] = player
		end
	end

	return if #matches == 1 then matches[1] else nil
end

local function parse_set_coins_command(message: string): (string?, number?)
	local targetName, amountText = string.match(message, "^%s*!setcoins%s+(%S+)%s+(%S+)%s*$")
	if not targetName or not amountText then
		return nil, nil
	end

	local amount = tonumber(amountText)
	if not amount or amount ~= math.floor(amount) or amount < 0 or amount > MAX_HORSESHOES then
		return nil, nil
	end

	return targetName, amount
end

local function grant_random_food(player: Player): ()
	local foodDefinitions = ToolItemCatalog.GetItemsByToolCategory("Food")
	if #foodDefinitions == 0 then
		warn(("[AdminCommands] No food definitions are available for %s"):format(EAT_COMMAND_NAME))
		return
	end

	local foodDefinition = foodDefinitions[randomGenerator:NextInteger(1, #foodDefinitions)]
	local updatedCount = InventoryService.AddItemCount(player, foodDefinition, 1)
	print(("[AdminCommands] %s received %s from %s (total: %d)"):format(
		player.Name,
		foodDefinition.DisplayName or foodDefinition.ItemId,
		EAT_COMMAND_NAME,
		updatedCount
	))
end

local function handle_chat_command(requestingPlayer: Player, message: string): ()
	local normalizedMessage = normalize(message)
	local isEatCommand = normalizedMessage == EAT_COMMAND_NAME
	local isSetCoinsCommand = string.match(normalizedMessage, "^!setcoins") ~= nil
	if not isEatCommand and not isSetCoinsCommand then
		return
	end

	local hasAccess = AdminAccessService.HasAccess(requestingPlayer)
	if not hasAccess then
		warn(("[AdminCommands] %s tried to use %s without elevated permission"):format(
			requestingPlayer.Name,
			COMMAND_NAME
		))
		return
	end

	if isEatCommand then
		grant_random_food(requestingPlayer)
		return
	end

	local targetName, amount = parse_set_coins_command(message)
	if not targetName or amount == nil then
		warn(("[AdminCommands] Invalid %s syntax from %s. Expected: %s <player> <amount>"):format(
			COMMAND_NAME,
			requestingPlayer.Name,
			COMMAND_NAME
		))
		return
	end

	local targetPlayer = resolve_target_player(requestingPlayer, targetName)
	if not targetPlayer then
		warn(("[AdminCommands] %s could not find a unique online player for %q"):format(
			requestingPlayer.Name,
			targetName
		))
		return
	end

	DataUtility.server.set(targetPlayer, "Currencies.Horseshoes", amount)
	print(("[AdminCommands] %s set %s's Horseshoes to %d"):format(
		requestingPlayer.Name,
		targetPlayer.Name,
		amount
	))
end

function Commands.Bind(TroveValue: any): ()
	local boundPlayers: { [Player]: boolean } = {}

	local function bind_player(player: Player): ()
		if boundPlayers[player] then
			return
		end

		boundPlayers[player] = true
		TroveValue:Connect(player.Chatted, function(message: string): ()
			task.spawn(handle_chat_command, player, message)
		end)
	end

	for _, player: Player in Players:GetPlayers() do
		bind_player(player)
	end

	TroveValue:Connect(Framework.RuntimeEvents.PlayerAdded, bind_player)
	TroveValue:Connect(Framework.RuntimeEvents.PlayerRemoving, function(player: Player): ()
		boundPlayers[player] = nil
	end)
end

return Commands
