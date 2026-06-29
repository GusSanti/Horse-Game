------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//CONSTANTS
local modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local dictionary: Folder = modules:WaitForChild("Dictionary")
local gameModules: Folder = modules:WaitForChild("Game")
local serverModules: Folder = ServerStorage:WaitForChild("Modules")

local toolDictionary = require(dictionary:WaitForChild("ToolDictionary"))
local toolRegistry = require(gameModules:WaitForChild("Tools"):WaitForChild("Registry"))
local horseService = require(serverModules:WaitForChild("HorseService"))

local TOOL_REMOTES_FOLDER_NAME: string = toolDictionary.ToolRemotesFolderName
local USE_HORSE_TOOL_REMOTE_NAME: string = toolDictionary.UseHorseToolRemoteName

------------------//VARIABLES
local activeUseByPlayer: {[Player]: boolean} = {}

------------------//FUNCTIONS
local function ensure_remote_folder(): Folder
	local remotesFolder = ReplicatedStorage:FindFirstChild(TOOL_REMOTES_FOLDER_NAME)
	if remotesFolder and remotesFolder:IsA("Folder") then
		return remotesFolder
	end

	if remotesFolder then
		remotesFolder:Destroy()
	end

	local newRemotesFolder = Instance.new("Folder")
	newRemotesFolder.Name = TOOL_REMOTES_FOLDER_NAME
	newRemotesFolder.Parent = ReplicatedStorage

	return newRemotesFolder
end

local function ensure_use_remote(): RemoteFunction
	local remotesFolder = ensure_remote_folder()
	local useHorseToolRemote = remotesFolder:FindFirstChild(USE_HORSE_TOOL_REMOTE_NAME)

	if useHorseToolRemote and not useHorseToolRemote:IsA("RemoteFunction") then
		useHorseToolRemote:Destroy()
		useHorseToolRemote = nil
	end

	if not useHorseToolRemote then
		useHorseToolRemote = Instance.new("RemoteFunction")
		useHorseToolRemote.Name = USE_HORSE_TOOL_REMOTE_NAME
		useHorseToolRemote.Parent = remotesFolder
	end

	return useHorseToolRemote
end

local function is_tool_equipped_by_player(player: Player, tool: Tool): boolean
	local character = player.Character
	if not character then
		return false
	end

	return tool.Parent == character
end

local function use_horse_tool(player: Player, tool: Instance?, itemId: string?, horseId: string): (boolean, string)
	if activeUseByPlayer[player] then
		return false, "Busy"
	end

	if not tool or not tool:IsA("Tool") then
		return false, "InvalidTool"
	end

	if type(horseId) ~= "string" or horseId == "" then
		return false, "InvalidHorseId"
	end

	if not is_tool_equipped_by_player(player, tool) then
		return false, "ToolNotEquipped"
	end

	local definition, resolvedItemId = toolRegistry.resolve_definition_from_tool(tool)
	if not definition or not resolvedItemId then
		return false, "ToolNotRegistered"
	end

	local requestedItemId = itemId
	if type(requestedItemId) == "string" then
		requestedItemId = string.lower(requestedItemId)
	end

	if requestedItemId ~= nil and requestedItemId ~= resolvedItemId then
		return false, "ItemMismatch"
	end

	local horse, resolvedHorseId = horseService.get_player_horse(player, horseId)
	if not horse or not resolvedHorseId then
		return false, "HorseNotOwned"
	end

	local context = {
		player = player,
		tool = tool,
		itemId = resolvedItemId,
		horse = horse,
		horseId = resolvedHorseId,
	}

	if type(definition.canUse) == "function" then
		local canUse, canUseReason = definition.canUse(context)
		if canUse ~= true then
			return false, canUseReason or "CannotUse"
		end
	end

	activeUseByPlayer[player] = true

	local success, result, reason = pcall(function()
		if type(definition.onUse) == "function" then
			return definition.onUse(context)
		end

		return true, "Used"
	end)

	activeUseByPlayer[player] = nil

	if not success then
		warn(("ToolHandler failed to use '%s' for %s: %s"):format(resolvedItemId, player.Name, tostring(result)))
		return false, "UseFailed"
	end

	local wasUsed = result == true
	local responseReason = reason
	if responseReason == nil then
		responseReason = wasUsed and "Used" or "Rejected"
	end

	if wasUsed and definition.consumeOnUse ~= false and tool.Parent then
		tool:Destroy()
	end

	return wasUsed, responseReason
end

------------------//MAIN FUNCTIONS
local useHorseToolRemote: RemoteFunction = ensure_use_remote()
useHorseToolRemote.OnServerInvoke = use_horse_tool

------------------//INIT
Players.PlayerRemoving:Connect(function(player: Player)
	activeUseByPlayer[player] = nil
end)
