local ProfileSessionService = {}

local activeStore = nil
local profilesByUserId = {}
local messageHandlers = {}

local function normalize_user_id(value): number
	return math.max(0, math.floor(tonumber(value) or 0))
end

local function dispatch_profile_message(player: Player, profile, message, processed)
	for _, handler in pairs(messageHandlers) do
		local success, handled = pcall(handler, player, profile, message, processed)
		if not success then
			warn("[ProfileSessionService] Failed to process profile message.")
		elseif handled == true then
			return
		end
	end
end

function ProfileSessionService.SetStore(profileStore)
	activeStore = profileStore
end

function ProfileSessionService.GetStore()
	return activeStore
end

function ProfileSessionService.RegisterProfile(player: Player, profile)
	local userId = normalize_user_id(player and player.UserId)
	if userId <= 0 or not profile then
		return
	end

	profilesByUserId[userId] = profile

	profile:MessageHandler(function(message, processed)
		dispatch_profile_message(player, profile, message, processed)
	end)
end

function ProfileSessionService.UnregisterProfile(player: Player)
	local userId = normalize_user_id(player and player.UserId)
	if userId <= 0 then
		return
	end

	profilesByUserId[userId] = nil
end

function ProfileSessionService.GetProfile(playerOrUserId)
	if typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		return profilesByUserId[normalize_user_id(playerOrUserId.UserId)]
	end

	return profilesByUserId[normalize_user_id(playerOrUserId)]
end

function ProfileSessionService.AddMessageHandler(handlerId: string, fn)
	if type(handlerId) ~= "string" or handlerId == "" then
		error("ProfileSessionService.AddMessageHandler requires a valid handlerId.")
	end

	if type(fn) ~= "function" then
		error("ProfileSessionService.AddMessageHandler requires a function.")
	end

	messageHandlers[handlerId] = fn
end

function ProfileSessionService.RemoveMessageHandler(handlerId: string)
	messageHandlers[handlerId] = nil
end

function ProfileSessionService.SendMessageToUserId(userId: number, message)
	if not activeStore then
		return false
	end

	local normalizedUserId = normalize_user_id(userId)
	if normalizedUserId <= 0 then
		return false
	end

	local success, didSend = pcall(function()
		return activeStore:MessageAsync(tostring(normalizedUserId), message)
	end)

	if not success then
		warn(("[ProfileSessionService] Failed to send message to profile %d."):format(normalizedUserId))
		return false
	end

	return didSend == true
end

return ProfileSessionService
