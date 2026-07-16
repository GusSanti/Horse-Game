local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local HudAnim = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Libraries"):WaitForChild("HudAnim"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local IGNORE_HUD_ANIM_ATTRIBUTE = "IgnoreHudAnim"

local function has_true_attribute(instance, attributeName)
	local current = instance

	while current do
		if current:GetAttribute(attributeName) == true then
			return true
		end

		current = current.Parent
	end

	return false
end

local function setupInterface(instance)
	if has_true_attribute(instance, IGNORE_HUD_ANIM_ATTRIBUTE) then
		return
	end

	if instance:IsA("ScreenGui") then
		HudAnim.apply_defaults_to_buttons(instance)
		HudAnim.bind_all(instance)
		return
	end

	if instance:IsA("GuiButton") then
		instance:SetAttribute("UIAnim", true)
		HudAnim.bind(instance)
		return
	end

	if instance:IsA("GuiObject") then
		HudAnim.bind(instance)
	end
end

for _, gui in playerGui:GetChildren() do
	setupInterface(gui)
end

playerGui.DescendantAdded:Connect(setupInterface)	