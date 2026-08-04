--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players: Players = game:GetService("Players")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))
local HudAnim: any = require(Modules:WaitForChild("Libraries"):WaitForChild("HudAnim"))
local OutlinedText: any = require(script.Parent:WaitForChild("OutlinedText"))

local UIRouter: any = require(
	Modules
		:WaitForChild("Client")
		:WaitForChild("Hud")
		:WaitForChild("UIRouter")
)

local IGNORE_HUD_ANIM_ATTRIBUTE: string = "IgnoreHudAnim"

local UIRuntime = {
	Name = "UIRuntime",
	Trove = nil :: any,
	PlayerGui = nil :: PlayerGui?,
}

local function HasTrueAttribute(InstanceValue: Instance, AttributeName: string): boolean
	local Current: Instance? = InstanceValue
	while Current do
		if Current:GetAttribute(AttributeName) == true then
			return true
		end
		Current = Current.Parent
	end
	return false
end

local function SetupInterface(InstanceValue: Instance): ()
	local IsScreenGui: boolean = InstanceValue:IsA("ScreenGui")
	if IsScreenGui then
		OutlinedText.bind_all(InstanceValue)
	else
		OutlinedText.bind(InstanceValue)
	end

	if HasTrueAttribute(InstanceValue, IGNORE_HUD_ANIM_ATTRIBUTE) then
		return
	end

	if IsScreenGui then
		HudAnim.apply_defaults_to_buttons(InstanceValue)
		HudAnim.bind_all(InstanceValue)
		return
	end

	if InstanceValue:IsA("GuiButton") then
		InstanceValue:SetAttribute("UIAnim", true)
		HudAnim.bind(InstanceValue)
		return
	end

	if InstanceValue:IsA("GuiObject") then
		HudAnim.bind(InstanceValue)
	end
end

function UIRuntime:Init(): ()
	UIRouter.Init()
end

function UIRuntime:Start(): ()
	if self.Trove then
		return
	end

	local Player: Player = Players.LocalPlayer
	local PlayerGui: PlayerGui = Player:WaitForChild("PlayerGui") :: PlayerGui
	local RuntimeTrove: any = Trove.new()
	self.Trove = RuntimeTrove
	self.PlayerGui = PlayerGui
	script:SetAttribute("Started", true)
	RuntimeTrove:Connect(PlayerGui.DescendantAdded, SetupInterface)

	for _Index: number, Gui: Instance in PlayerGui:GetChildren() do
		SetupInterface(Gui)
	end
end

function UIRuntime:Destroy(): ()
	script:SetAttribute("Started", false)
	local PlayerGui: PlayerGui? = self.PlayerGui
	self.PlayerGui = nil
	if PlayerGui then
		HudAnim.unbind_all(PlayerGui)
		OutlinedText.unbind_all(PlayerGui)
	end

	if self.Trove then
		self.Trove:Destroy()
		self.Trove = nil
	end
	UIRouter.Destroy()
end

return UIRuntime
