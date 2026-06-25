local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local ToolItems = GameData:WaitForChild("ToolItems")
local ToolRegistry = require(ToolItems:WaitForChild("Registry"))
local HorseService = require(script.Parent:WaitForChild("HorseService"))

local REMOTE_FOLDER_NAME = "ToolRemotes"
local USE_HORSE_TOOL_REMOTE_NAME = "UseHorseTool"

local ToolService = {}

local useHorseToolRemote = nil
local activeUseByPlayer = {}

local function ensure_remote_folder()
	local remotesFolder = ReplicatedStorage:FindFirstChild(REMOTE_FOLDER_NAME)
	if remotesFolder and remotesFolder:IsA("Folder") then
		return remotesFolder
	end

	if remotesFolder then
		remotesFolder:Destroy()
	end

	local newRemotesFolder = Instance.new("Folder")
	newRemotesFolder.Name = REMOTE_FOLDER_NAME
	newRemotesFolder.Parent = ReplicatedStorage

	return newRemotesFolder
end

local function ensure_use_remote()
	if useHorseToolRemote then
		return useHorseToolRemote
	end

	local remotesFolder = ensure_remote_folder()
	local existingRemote = remotesFolder:FindFirstChild(USE_HORSE_TOOL_REMOTE_NAME)

	if existingRemote and not existingRemote:IsA("RemoteFunction") then
		existingRemote:Destroy()
		existingRemote = nil
	end

	if not existingRemote then
		existingRemote = Instance.new("RemoteFunction")
		existingRemote.Name = USE_HORSE_TOOL_REMOTE_NAME
		existingRemote.Parent = remotesFolder
	end

	useHorseToolRemote = existingRemote
	return useHorseToolRemote
end

local function is_tool_equipped_by_player(player, tool)
	local character = player.Character
	if not character then
		return false
	end

	return tool:IsA("Tool") and tool.Parent == character
end

local function use_horse_tool(player, tool, itemId, horseId)
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

	local definition, resolvedItemId = ToolRegistry.ResolveDefinitionFromTool(tool)
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

	local horse, resolvedHorseId = HorseService.get_player_horse(player, horseId)
	if not horse or not resolvedHorseId then
		return false, "HorseNotOwned"
	end

	local context = {
		Player = player,
		Tool = tool,
		ItemId = resolvedItemId,
		Horse = horse,
		HorseId = resolvedHorseId,
	}

	if type(definition.CanUse) == "function" then
		local canUse, canUseReason = definition.CanUse(context)
		if canUse ~= true then
			return false, canUseReason or "CannotUse"
		end
	end

	activeUseByPlayer[player] = true

	local success, result, reason = pcall(function()
		if type(definition.OnUse) == "function" then
			return definition.OnUse(context)
		end

		return true, "Used"
	end)

	activeUseByPlayer[player] = nil

	if not success then
		warn(("ToolService failed to use '%s' for %s: %s"):format(resolvedItemId, player.Name, tostring(result)))
		return false, "UseFailed"
	end

	local wasUsed = result == true
	local responseReason = reason
	if responseReason == nil then
		responseReason = wasUsed and "Used" or "Rejected"
	end

	if wasUsed and definition.ConsumeOnUse ~= false and tool.Parent then
		tool:Destroy()
	end

	return wasUsed, responseReason
end

function ToolService.Init()
	local remote = ensure_use_remote()
	remote.OnServerInvoke = use_horse_tool
end

return ToolService
