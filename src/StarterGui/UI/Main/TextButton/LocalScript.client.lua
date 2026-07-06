local button = script.Parent
local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainGui = playerGui:WaitForChild("UI"):WaitForChild("Main"):WaitForChild("Stable")

button.MouseButton1Click:Connect(function()
	mainGui.Visible = not mainGui.Visible
end)
