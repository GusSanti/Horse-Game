local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))

local function ensure_folder(parent, folderName)
	local folder = parent:FindFirstChild(folderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = parent
	return folder
end

local function ensure_remote_event(parent, remoteName)
	local remote = parent:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parent
	return remote
end

local gameplayRemotes = ensure_folder(ReplicatedStorage, NetworkConfig.GameplayFolderName)
local horseFolder = ensure_folder(gameplayRemotes, NetworkConfig.Horse.FolderName)
local acknowledgeRevealRemote = ensure_remote_event(horseFolder, NetworkConfig.Horse.AcknowledgeReveal)

acknowledgeRevealRemote.OnServerEvent:Connect(function(player, horseId)
	local pendingReveal = DataUtility.server.get(player, "Progression.PendingHorseReveal")
	if type(pendingReveal) ~= "table" then
		return
	end

	if type(horseId) == "string" and horseId ~= "" and pendingReveal.HorseId ~= horseId then
		return
	end

	DataUtility.server.set(player, "Progression.PendingHorseReveal", nil)
	DataUtility.server.set(player, "Progression.StarterRevealAcknowledged", true)
end)
