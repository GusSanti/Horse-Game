local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local ROOT_FOLDER_NAME = "Net"
local EVENTS_FOLDER_NAME = "Events"
local FUNCTIONS_FOLDER_NAME = "Functions"

local rootFolder
local eventsFolder
local functionsFolder

local eventWrappers = {}
local functionWrappers = {}

local function attach_to_trove(connection, trove)
	if trove and type(trove.Add) == "function" then
		trove:Add(connection)
	end

	return connection
end

local function ensure_child(parent, className, childName)
	local child = parent:FindFirstChild(childName)

	if child then
		if not child:IsA(className) then
			error(("%s exists but is not a %s"):format(childName, className), 3)
		end

		return child
	end

	child = Instance.new(className)
	child.Name = childName
	child.Parent = parent

	return child
end

local function get_root()
	if rootFolder and eventsFolder and functionsFolder then
		return rootFolder, eventsFolder, functionsFolder
	end

	if IS_SERVER then
		rootFolder = ReplicatedStorage:FindFirstChild(ROOT_FOLDER_NAME)

		if not rootFolder then
			rootFolder = Instance.new("Folder")
			rootFolder.Name = ROOT_FOLDER_NAME
			rootFolder.Parent = ReplicatedStorage
		end

		eventsFolder = ensure_child(rootFolder, "Folder", EVENTS_FOLDER_NAME)
		functionsFolder = ensure_child(rootFolder, "Folder", FUNCTIONS_FOLDER_NAME)
	else
		rootFolder = ReplicatedStorage:WaitForChild(ROOT_FOLDER_NAME)
		eventsFolder = rootFolder:WaitForChild(EVENTS_FOLDER_NAME)
		functionsFolder = rootFolder:WaitForChild(FUNCTIONS_FOLDER_NAME)
	end

	return rootFolder, eventsFolder, functionsFolder
end

local function get_folder(kind)
	local _, resolvedEventsFolder, resolvedFunctionsFolder = get_root()

	if kind == "Event" then
		return resolvedEventsFolder
	end

	return resolvedFunctionsFolder
end

local function get_remote(kind, name)
	local folder = get_folder(kind)
	local className = kind == "Event" and "RemoteEvent" or "RemoteFunction"

	if IS_SERVER then
		return ensure_child(folder, className, name)
	end

	local remote = folder:WaitForChild(name)

	if not remote:IsA(className) then
		error(("%s exists but is not a %s"):format(name, className), 3)
	end

	return remote
end

local function get_event_signal(remote)
	if IS_SERVER then
		return remote.OnServerEvent
	end

	return remote.OnClientEvent
end

local function create_event_wrapper(name)
	local wrapper = {}

	function wrapper:Connect(fn, trove)
		local remote = get_remote("Event", name)
		local connection = get_event_signal(remote):Connect(fn)
		return attach_to_trove(connection, trove)
	end

	function wrapper:Once(fn, trove)
		local remote = get_remote("Event", name)
		local connection

		connection = get_event_signal(remote):Connect(function(...)
			if connection then
				connection:Disconnect()
				connection = nil
			end

			fn(...)
		end)

		return attach_to_trove(connection, trove)
	end

	function wrapper:Fire(...)
		local remote = get_remote("Event", name)

		if IS_SERVER then
			local target = select(1, ...)

			if typeof(target) == "Instance" and target:IsA("Player") then
				remote:FireClient(...)
				return
			end

			remote:FireAllClients(...)
			return
		end

		remote:FireServer(...)
	end

	function wrapper:FireAll(...)
		if not IS_SERVER then
			error("FireAll can only be used on the server", 2)
		end

		local remote = get_remote("Event", name)
		remote:FireAllClients(...)
	end

	return wrapper
end

local function create_function_wrapper(name)
	local wrapper = {}

	function wrapper:Respond(fn)
		local remote = get_remote("Function", name)

		if IS_SERVER then
			remote.OnServerInvoke = fn
		else
			remote.OnClientInvoke = fn
		end

		return fn
	end

	function wrapper:Call(...)
		local remote = get_remote("Function", name)

		if IS_SERVER then
			return remote:InvokeClient(...)
		end

		return remote:InvokeServer(...)
	end

	return wrapper
end

local function get_event_wrapper(name)
	local wrapper = eventWrappers[name]

	if not wrapper then
		if IS_SERVER then
			get_remote("Event", name)
		end

		wrapper = create_event_wrapper(name)
		eventWrappers[name] = wrapper
	end

	return wrapper
end

local function get_function_wrapper(name)
	local wrapper = functionWrappers[name]

	if not wrapper then
		if IS_SERVER then
			get_remote("Function", name)
		end

		wrapper = create_function_wrapper(name)
		functionWrappers[name] = wrapper
	end

	return wrapper
end

local Net = {}

Net.Event = setmetatable({}, {
	__index = function(_, name)
		return get_event_wrapper(name)
	end,
})

Net.Function = setmetatable({}, {
	__index = function(_, name)
		return get_function_wrapper(name)
	end,
})

function Net.Init()
	get_root()
end

if IS_SERVER then
	Net.Init()
end

return Net
