--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Trove: any = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Libraries"):WaitForChild("Trove")
)
local Reveal: any = require(script.Reveal)
local ToolUse: any = require(script.ToolUse)

local HorseRuntime = {
	Name = "HorseRuntime",
	Trove = nil :: any,
}

function HorseRuntime:Init(): ()
	if self.Trove then
		return
	end

	self.Trove = Trove.new()
	Reveal.Bind(self.Trove)
	ToolUse.Bind(self.Trove)
end

function HorseRuntime:Destroy(): ()
	if self.Trove then
		self.Trove:Destroy()
		self.Trove = nil
	end
end

return HorseRuntime
