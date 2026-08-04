--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trove: any = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Libraries"):WaitForChild("Trove")
)
local Gifts: any = require(script.Gifts)

local CommerceRuntime = {
	Name = "CommerceRuntime",
	Trove = nil :: any,
}

function CommerceRuntime:Init(): ()
	if self.Trove then
		return
	end

	self.Trove = Trove.new()
	Gifts.Bind(self.Trove)
end

function CommerceRuntime:Destroy(): ()
	if self.Trove then
		self.Trove:Destroy()
		self.Trove = nil
	end
end

return CommerceRuntime
