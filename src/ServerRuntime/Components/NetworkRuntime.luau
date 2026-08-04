--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network: any = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Network"))

local NetworkRuntime = {
	Name = "NetworkRuntime",
}

function NetworkRuntime:Init(): ()
	Network.Init()
end

return NetworkRuntime
