local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local HudAnim = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Libraries"):WaitForChild("HudAnim"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function setupInterface(gui)
	if gui:IsA("ScreenGui") then
		HudAnim.apply_defaults_to_buttons(gui)
		HudAnim.bind_all(gui)
	end
end

for _, gui in playerGui:GetChildren() do
	setupInterface(gui)
end

playerGui.DescendantAdded:Connect(setupInterface)