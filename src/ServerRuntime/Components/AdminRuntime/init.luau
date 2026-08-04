--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))
local AdminAccessService: any = require(
	ServerStorage:WaitForChild("Modules"):WaitForChild("Admin"):WaitForChild("AdminAccessService")
)
local Commands: any = require(script.Commands)
local Operations: any = require(script.Operations)

local AdminRuntime = {
	Name = "AdminRuntime",
	Trove = nil :: any,
}

function AdminRuntime:Init(): ()
	if self.Trove then
		return
	end

	self.Trove = Trove.new()
	Operations.Bind(self.Trove)
	Commands.Bind(self.Trove)
	self.Trove:Connect(Framework.RuntimeEvents.PlayerAdded, function(Player: Player): ()
		task.spawn(AdminAccessService.ApplyAccessAttributes, Player)
	end)
end

function AdminRuntime:Destroy(): ()
	if self.Trove then
		self.Trove:Destroy()
		self.Trove = nil
	end
end

return AdminRuntime
