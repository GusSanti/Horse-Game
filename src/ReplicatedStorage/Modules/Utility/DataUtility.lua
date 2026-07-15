------------------//SERVICES
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

------------------//CONSTANTS
local PROFILE_WAIT_TIMEOUT = 10
local CLIENT_PROFILE_WAIT_TIMEOUT = 5
local SAVE_DEBOUNCE_SECONDS = 2

local DATA_GET_FUNCTION_NAME = "DataUtilityGet"
local DATA_CHANGED_EVENT_NAME = "DataUtilityChanged"

------------------//VARIABLES
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Net = require(Libraries:WaitForChild("Net"))

local isServer: boolean = RunService:IsServer()
local isClient: boolean = RunService:IsClient()

local serverProfiles: {[number]: any} = {}
local serverSignals: {[number]: {[string]: any}} = {}
local serverTransactionChanges: {[number]: {[string]: any}} = {}
local serverTransactionDepths: {[number]: number} = {}
local serverDirtyProfiles: {[number]: boolean} = {}
local serverSaveTokens: {[number]: number} = {}

local clientCache: any = nil
local clientSignals: {[string]: any} = {}
local clientInitialized = false
local clientEventConnected = false
local clientRemoteFailureWarned = false
local serverInitialized = false

------------------//FUNCTIONS
local function new_signal()
	local listeners: {(...any) -> ()} = {}
	local signal = {}

	function signal:Connect(fn: (...any) -> ())
		listeners[#listeners + 1] = fn

		local connection = {}

		function connection:Disconnect()
			for index, listener in ipairs(listeners) do
				if listener == fn then
					table.remove(listeners, index)
					break
				end
			end
		end

		return connection
	end

	function signal:Fire(...)
		for _, fn in ipairs(listeners) do
			fn(...)
		end
	end

	return signal
end

local function split_path(path: string): {string}
	local out: {string} = {}

	for part in string.gmatch(path, "[^%.]+") do
		out[#out + 1] = part
	end

	return out
end

local function get_by_path(root: any, path: string?)
	if not path or path == "" then
		return root
	end

	local current = root

	for _, key in ipairs(split_path(path)) do
		if type(current) ~= "table" then
			return nil
		end

		current = current[key]
		if current == nil then
			return nil
		end
	end

	return current
end

local function set_by_path(root: any, path: string, value: any)
	local current = root
	local parts = split_path(path)

	for index, key in ipairs(parts) do
		if index < #parts then
			if type(current[key]) ~= "table" then
				current[key] = {}
			end

			current = current[key]
		else
			current[key] = value
		end
	end
end

local function wait_for_profile(player: Player, timeoutSeconds: number): any
	local profile = serverProfiles[player.UserId]
	local startedAt = os.clock()

	while not profile and os.clock() - startedAt < timeoutSeconds do
		task.wait()
		profile = serverProfiles[player.UserId]
	end

	return profile
end

local function get_server_signal(userId: number, path: string)
	local userSignals = serverSignals[userId]
	if not userSignals then
		userSignals = {}
		serverSignals[userId] = userSignals
	end

	local signal = userSignals[path]
	if not signal then
		signal = new_signal()
		userSignals[path] = signal
	end

	return signal
end

local function fire_server_signal(userId: number, path: string, value: any)
	local userSignals = serverSignals[userId]
	if not userSignals then
		return
	end

	local signal = userSignals[path]
	if signal then
		signal:Fire(value)
	end
end

local function normalize_updates(updates): {{Path: string, Value: any}}
	local normalized = {}

	if type(updates) ~= "table" then
		return normalized
	end

	local singlePath = updates.Path or updates.path
	if type(singlePath) == "string" and singlePath ~= "" then
		normalized[#normalized + 1] = {
			Path = singlePath,
			Value = updates.Value ~= nil and updates.Value or updates.value,
		}

		return normalized
	end

	for key, value in pairs(updates) do
		if type(key) == "number" and type(value) == "table" then
			local path = value.Path or value.path
			if type(path) == "string" and path ~= "" then
				normalized[#normalized + 1] = {
					Path = path,
					Value = value.Value ~= nil and value.Value or value.value,
				}
			end
		elseif type(key) == "string" and key ~= "" then
			normalized[#normalized + 1] = {
				Path = key,
				Value = value,
			}
		end
	end

	return normalized
end

local schedule_profile_save

local function flush_profile_save(player: Player): boolean
	local userId = player.UserId
	local profile = serverProfiles[userId]

	if not profile or not serverDirtyProfiles[userId] then
		return true
	end

	serverDirtyProfiles[userId] = nil

	local success, err = pcall(function()
		profile:Save()
	end)

	if not success then
		warn(("[DataUtility] Failed to save profile for %s (%d): %s"):format(player.Name, player.UserId, tostring(err)))
		serverDirtyProfiles[userId] = true
	end

	return success
end

schedule_profile_save = function(player: Player, immediate: boolean?)
	local userId = player.UserId
	if not serverProfiles[userId] then
		return
	end

	serverDirtyProfiles[userId] = true
	serverSaveTokens[userId] = (serverSaveTokens[userId] or 0) + 1

	local token = serverSaveTokens[userId]
	local delaySeconds = immediate and 0 or SAVE_DEBOUNCE_SECONDS

	task.delay(delaySeconds, function()
		if serverSaveTokens[userId] ~= token then
			return
		end

		if not serverProfiles[userId] or not serverDirtyProfiles[userId] then
			return
		end

		if not flush_profile_save(player) and serverProfiles[userId] then
			schedule_profile_save(player, false)
		end
	end)
end

local function emit_changes(player: Player, changesByPath: {[string]: any})
	local outgoingChanges = {}

	for path, value in pairs(changesByPath) do
		outgoingChanges[#outgoingChanges + 1] = {
			Path = path,
			Value = value,
		}
	end

	if #outgoingChanges == 0 then
		return
	end

	table.sort(outgoingChanges, function(left, right)
		return left.Path < right.Path
	end)

	for _, change in ipairs(outgoingChanges) do
		fire_server_signal(player.UserId, change.Path, change.Value)
	end

	Net.Event[DATA_CHANGED_EVENT_NAME]:Fire(player, outgoingChanges)
	schedule_profile_save(player, false)
end

local function queue_transaction_change(userId: number, path: string, value: any)
	local changes = serverTransactionChanges[userId]
	if not changes then
		changes = {}
		serverTransactionChanges[userId] = changes
	end

	changes[path] = value
end

local function ensure_remotes_server(): ()
	if serverInitialized then
		return
	end

	Net.Function[DATA_GET_FUNCTION_NAME]:Respond(function(player: Player, path: string?)
		local profile = wait_for_profile(player, CLIENT_PROFILE_WAIT_TIMEOUT)
		if not profile then
			return nil
		end

		return get_by_path(profile.Data, path)
	end)

	serverInitialized = true
end

local function apply_client_changes(payload)
	local normalized = normalize_updates(payload)
	if #normalized == 0 then
		return
	end

	if not clientCache then
		clientCache = {}
	end

	for _, change in ipairs(normalized) do
		set_by_path(clientCache, change.Path, change.Value)

		local signal = clientSignals[change.Path]
		if signal then
			signal:Fire(change.Value)
		end
	end
end

local function ensure_remotes_client(): boolean
	if clientInitialized then
		return true
	end

	local success, result = pcall(function()
		return Net.Function[DATA_GET_FUNCTION_NAME]:Call(nil)
	end)

	if not success then
		if not clientRemoteFailureWarned then
			clientRemoteFailureWarned = true
			warn("[DataUtility] Failed to initialize client remotes: " .. tostring(result))
		end

		clientCache = clientCache or {}
		return false
	end

	clientCache = result
	if clientCache == nil then
		clientCache = {}
	end

	if not clientEventConnected then
		Net.Event[DATA_CHANGED_EVENT_NAME]:Connect(apply_client_changes)
		clientEventConnected = true
	end

	clientInitialized = true
	clientRemoteFailureWarned = false
	return true
end

------------------//MAIN FUNCTIONS
local DataUtility = {}

DataUtility.server = {}
DataUtility.client = {}

function DataUtility.server.ensure_remotes(): ()
	if isServer then
		ensure_remotes_server()
	end
end

function DataUtility.server.attach_profile(player: Player, profile: any): ()
	serverProfiles[player.UserId] = profile
	serverSignals[player.UserId] = serverSignals[player.UserId] or {}
	serverTransactionChanges[player.UserId] = nil
	serverTransactionDepths[player.UserId] = nil
	serverDirtyProfiles[player.UserId] = nil
	serverSaveTokens[player.UserId] = nil
end

function DataUtility.server.detach_profile(player: Player): ()
	serverProfiles[player.UserId] = nil
	serverSignals[player.UserId] = nil
	serverTransactionChanges[player.UserId] = nil
	serverTransactionDepths[player.UserId] = nil
	serverDirtyProfiles[player.UserId] = nil
	serverSaveTokens[player.UserId] = nil
end

function DataUtility.server.get(player: Player, path: string?): any
	local profile = wait_for_profile(player, PROFILE_WAIT_TIMEOUT)
	if not profile then
		return nil
	end

	return get_by_path(profile.Data, path)
end

function DataUtility.server.begin_batch(player: Player): ()
	local userId = player.UserId
	serverTransactionDepths[userId] = (serverTransactionDepths[userId] or 0) + 1
	serverTransactionChanges[userId] = serverTransactionChanges[userId] or {}
end

function DataUtility.server.end_batch(player: Player): ()
	local userId = player.UserId
	local depth = serverTransactionDepths[userId]
	if not depth then
		return
	end

	if depth > 1 then
		serverTransactionDepths[userId] = depth - 1
		return
	end

	serverTransactionDepths[userId] = nil

	local pendingChanges = serverTransactionChanges[userId]
	serverTransactionChanges[userId] = nil

	if pendingChanges then
		emit_changes(player, pendingChanges)
	end
end

function DataUtility.server.set(player: Player, path: string, value: any): ()
	if type(path) ~= "string" or path == "" then
		return
	end

	local profile = wait_for_profile(player, PROFILE_WAIT_TIMEOUT)
	if not profile then
		return
	end

	set_by_path(profile.Data, path, value)

	local userId = player.UserId
	if (serverTransactionDepths[userId] or 0) > 0 then
		queue_transaction_change(userId, path, value)
		return
	end

	emit_changes(player, {
		[path] = value,
	})
end

function DataUtility.server.set_many(player: Player, updates): ()
	local normalized = normalize_updates(updates)
	if #normalized == 0 then
		return
	end

	local profile = wait_for_profile(player, PROFILE_WAIT_TIMEOUT)
	if not profile then
		return
	end

	local changedPaths = {}

	for _, update in ipairs(normalized) do
		set_by_path(profile.Data, update.Path, update.Value)
		changedPaths[update.Path] = update.Value
	end

	local userId = player.UserId
	if (serverTransactionDepths[userId] or 0) > 0 then
		for path, value in pairs(changedPaths) do
			queue_transaction_change(userId, path, value)
		end

		return
	end

	emit_changes(player, changedPaths)
end

function DataUtility.server.flush(player: Player): boolean
	local userId = player.UserId
	serverSaveTokens[userId] = (serverSaveTokens[userId] or 0) + 1
	return flush_profile_save(player)
end

function DataUtility.server.bind(player: Player, path: string, fn: (any) -> ()): ({Disconnect: (self: any) -> ()})?
	if type(path) ~= "string" or path == "" then
		return nil
	end

	return get_server_signal(player.UserId, path):Connect(fn)
end

function DataUtility.client.ensure_remotes(): ()
	if isClient then
		ensure_remotes_client()
	end
end

function DataUtility.client.get(path: string?): any
	if isClient and not clientInitialized then
		local success = ensure_remotes_client()
		if not success then
			return get_by_path(clientCache, path)
		end
	end

	return get_by_path(clientCache, path)
end

function DataUtility.client.bind(path: string, fn: (any) -> ()): ({Disconnect: (self: any) -> ()})?
	if isClient and not clientInitialized then
		ensure_remotes_client()
	end

	local signal = clientSignals[path]
	if not signal then
		signal = new_signal()
		clientSignals[path] = signal
	end

	return signal:Connect(fn)
end

------------------//INIT
return DataUtility