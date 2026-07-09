local button = nil
local player = game.Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"
local FRAMES_CONTAINER_NAME = "Frames"
local BUTTON_SUFFIX = "BT"

if script.Parent:IsA("GuiButton") then
	button = script.Parent
else
	button = script.Parent:FindFirstChildWhichIsA("GuiButton", true)
end

if not button then
	return
end

local function get_target_frame_name()
	if string.len(button.Name) <= string.len(BUTTON_SUFFIX) then
		return nil
	end

	if string.sub(button.Name, -string.len(BUTTON_SUFFIX)) ~= BUTTON_SUFFIX then
		return nil
	end

	return string.sub(button.Name, 1, #button.Name - string.len(BUTTON_SUFFIX))
end

local function find_frames_container()
	local mainUi = playerGui:FindFirstChild(MAIN_UI_NAME) or playerGui:FindFirstChild(MAIN_UI_NAME, true)
	if not mainUi then
		return nil
	end

	local mainframe = mainUi:FindFirstChild(MAINFRAME_NAME) or mainUi:FindFirstChild(MAINFRAME_NAME, true)
	if not mainframe then
		return nil
	end

	return mainframe:FindFirstChild(FRAMES_CONTAINER_NAME) or mainframe:FindFirstChild(FRAMES_CONTAINER_NAME, true)
end

local function find_target_frame()
	local frameName = get_target_frame_name()
	if not frameName then
		return nil
	end

	local framesContainer = find_frames_container()
	if not framesContainer then
		return nil
	end

	local targetFrame = framesContainer:FindFirstChild(frameName)
	if targetFrame and targetFrame:IsA("GuiObject") then
		return targetFrame
	end

	return nil
end

button.MouseButton1Click:Connect(function()
	local targetFrame = find_target_frame()
	if not targetFrame then
		return
	end

	local framesContainer = targetFrame.Parent
	if framesContainer then
		for _, child in ipairs(framesContainer:GetChildren()) do
			if child ~= targetFrame and child:IsA("GuiObject") then
				child.Visible = false
			end
		end
	end

	targetFrame.Visible = true
end)
