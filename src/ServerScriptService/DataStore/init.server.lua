------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//CONSTANTS
local STORE_NAME: string = RunService:IsStudio() and "StudioData.01" or "Released_Data.01"

------------------//VARIABLES
local serverModules = ServerStorage:WaitForChild("Modules")
local dataStoreModules = serverModules:WaitForChild("DataStore")
local ProfileStore = require(dataStoreModules:WaitForChild("ProfileStore"))
local ProfileTemplate = require(dataStoreModules:WaitForChild("DataTemplate"))
local DataUtility = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility"):WaitForChild("DataUtility"))
local ProfileSessionService = require(serverModules:WaitForChild("ProfileSessionService"))

local store = ProfileStore.New(STORE_NAME, ProfileTemplate)
local profilesByUserId: {[number]: any} = {}

ProfileSessionService.SetStore(store)

------------------//FUNCTIONS
local function attach_player_profile(player)
	local profile = store:StartSessionAsync(tostring(player.UserId))
	if not profile then
		warn("Falha ao iniciar sessao do perfil para " .. player.Name)
		return
	end

	profile:Reconcile()
	profile:AddUserId(player.UserId)
	profilesByUserId[player.UserId] = profile

	task.spawn(function()
		while player.Parent and profilesByUserId[player.UserId] do
			task.wait(60)
			if profilesByUserId[player.UserId] then
				local currentTime = profile.Data.TimePlayed or 0
				DataUtility.server.set(player, "TimePlayed", currentTime + 60)
			end
		end
	end)

	DataUtility.server.attach_profile(player, profile)
	ProfileSessionService.RegisterProfile(player, profile)

	print(profile.Data, "- " .. player.Name .. " - " .. player.UserId)

	profile.OnSessionEnd:Connect(function()
		DataUtility.server.detach_profile(player)
		ProfileSessionService.UnregisterProfile(player)
		profilesByUserId[player.UserId] = nil
	end)
end

local function release_player_profile(player: Player): ()
	ProfileSessionService.UnregisterProfile(player)
	local profile = profilesByUserId[player.UserId]
	if profile then
		profile:EndSession()
		profilesByUserId[player.UserId] = nil
	end
end

------------------//MAIN FUNCTIONS
local function on_player_added(player: Player): ()
	attach_player_profile(player)
end

local function on_player_removing(player: Player): ()
	release_player_profile(player)
end

------------------//INIT
DataUtility.server.ensure_remotes()

for _, player in Players:GetPlayers() do
	on_player_added(player)
end

Players.PlayerAdded:Connect(on_player_added)
Players.PlayerRemoving:Connect(on_player_removing)

ProfileStore.OnError:Connect(function(msg: string, storeName: string, key: string)
	warn(("[ProfileStore:%s %s] %s"):format(storeName, key, msg))
end)