local button = nil
local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

if script.Parent:IsA("GuiButton") then
	button = script.Parent
else
	button = script.Parent:FindFirstChildWhichIsA("GuiButton", true)
end

if not button then
	return
end

local function find_stable_gui()
	local stableGui = playerGui:FindFirstChild("Stable", true)
	if stableGui and stableGui:IsA("GuiObject") then
		return stableGui
	end

	return nil
end

button.MouseButton1Click:Connect(function()
	local mainGui = find_stable_gui()
	if not mainGui then
		return
	end

	mainGui.Visible = not mainGui.Visible
end)
