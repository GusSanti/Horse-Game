--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))
local DataUtility: any = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))
local DataStoreModules: Folder = ServerStorage:WaitForChild("Modules"):WaitForChild("DataStore") :: Folder
local ProfileStore: any = require(DataStoreModules:WaitForChild("ProfileStore"))
local ProfileTemplate: any = require(DataStoreModules:WaitForChild("DataTemplate"))
local ProfileSessionService: any = require(DataStoreModules:WaitForChild("ProfileSessionService"))

local STORE_NAME: string = if RunService:IsStudio() then "StudioData.01" else "Released_Data.01"
local PLAY_TIME_INTERVAL_SECONDS: number = 60

local DataRuntime = {
	Name = "DataRuntime",
	Trove = nil :: any,
	Store = nil :: any,
	ProfilesByUserId = {} :: { [number]: any },
	PlayerTroves = {} :: { [Player]: any },
}

function DataRuntime:_ReleasePlayer(Player: Player): ()
	local Profile: any = self.ProfilesByUserId[Player.UserId]
	if Profile then
		self.ProfilesByUserId[Player.UserId] = nil
		Profile:EndSession()
	end

	local PlayerTrove: any = self.PlayerTroves[Player]
	if PlayerTrove then
		PlayerTrove:Destroy()
		self.PlayerTroves[Player] = nil
	end
end

function DataRuntime:_AttachPlayer(Player: Player): ()
	if self.ProfilesByUserId[Player.UserId] or self.PlayerTroves[Player] then
		return
	end

	local Store: any = self.Store
	if not Store then
		error("DataRuntime store is unavailable", 0)
	end

	local Profile: any = Store:StartSessionAsync(tostring(Player.UserId))
	if not Profile then
		warn(`[DataRuntime] Failed to start a profile session for {Player.Name}`)
		return
	end

	Profile:Reconcile()
	Profile:AddUserId(Player.UserId)
	self.ProfilesByUserId[Player.UserId] = Profile

	local PlayerTrove: any = Trove.new()
	self.PlayerTroves[Player] = PlayerTrove
	PlayerTrove:Add(task.spawn(function(): ()
		while Player.Parent and self.ProfilesByUserId[Player.UserId] == Profile do
			task.wait(PLAY_TIME_INTERVAL_SECONDS)
			if self.ProfilesByUserId[Player.UserId] == Profile then
				local CurrentTime: number = tonumber(Profile.Data.TimePlayed) or 0
				DataUtility.server.set(Player, "TimePlayed", CurrentTime + PLAY_TIME_INTERVAL_SECONDS)
			end
		end
	end))

	DataUtility.server.attach_profile(Player, Profile)
	ProfileSessionService.RegisterProfile(Player, Profile)
	PlayerTrove:Add(Profile.OnSessionEnd:Connect(function(): ()
		DataUtility.server.detach_profile(Player)
		if self.ProfilesByUserId[Player.UserId] == Profile then
			self.ProfilesByUserId[Player.UserId] = nil
		end
	end))
end

function DataRuntime:Init(): ()
	if self.Trove then
		return
	end

	self.Trove = Trove.new()
	self.Store = ProfileStore.New(STORE_NAME, ProfileTemplate)
	ProfileSessionService.SetStore(self.Store)
	DataUtility.server.ensure_remotes()

	self.Trove:Connect(Framework.RuntimeEvents.PlayerAdded, function(Player: Player): ()
		self:_AttachPlayer(Player)
	end)
	self.Trove:Connect(Framework.RuntimeEvents.PlayerRemoving, function(Player: Player): ()
		self:_ReleasePlayer(Player)
	end)
	self.Trove:Add(ProfileStore.OnError:Connect(function(Message: string, StoreName: string, Key: string): ()
		warn(`[ProfileStore:{StoreName} {Key}] {Message}`)
	end))
end

function DataRuntime:Destroy(): ()
	if not self.Trove then
		return
	end

	for Player: Player in table.clone(self.PlayerTroves) do
		self:_ReleasePlayer(Player)
	end
	self.Trove:Destroy()
	self.Trove = nil
	self.Store = nil
	ProfileSessionService.SetStore(nil)
end

return DataRuntime
