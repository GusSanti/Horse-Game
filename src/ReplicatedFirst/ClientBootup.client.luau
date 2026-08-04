--!strict

local ContentProvider: ContentProvider = game:GetService("ContentProvider")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local FrameworkModule: ModuleScript = Modules:WaitForChild("Framework") :: ModuleScript
local Framework: any = require(FrameworkModule)
local HudAnim: any = require(Modules:WaitForChild("Libraries"):WaitForChild("HudAnim"))
local SoundUtility: any = require(Modules:WaitForChild("Utility"):WaitForChild("SoundUtility"))
local ToolItemCatalog: any = require(Modules:WaitForChild("GameData"):WaitForChild("ToolItemCatalog"))
local HorseMountConfig: any = require(
	Modules:WaitForChild("GameData"):WaitForChild("Horse"):WaitForChild("HorseMountConfig")
)
local LegacyClientRuntime: any = require(script.Parent:WaitForChild("LegacyClientRuntime"))
local UIRuntime: any = require(
	Modules:WaitForChild("Client"):WaitForChild("Hud"):WaitForChild("UIRuntime")
)

local CLIENT_READY_ATTRIBUTE: string = "ClientReady"
local CLIENT_FAILED_ATTRIBUTE: string = "ClientFailed"
local CLIENT_ERROR_ATTRIBUTE: string = "ClientError"

local AnimationPreloader = {
	Name = "AnimationPreloader",
}

local UIAssetPreloader = {
	Name = "UIAssetPreloader",
}

local PRELOAD_ANIMATION_IDS: { any } = {
	HorseMountConfig.PlayerHopOnAnimationId,
	HorseMountConfig.PlayerHopOffAnimationId,
	HorseMountConfig.PlayerIdleAnimationId,
	HorseMountConfig.PlayerRideAnimationId,
	HorseMountConfig.HorseIdleAnimationId,
	HorseMountConfig.HorseWalkAnimationId,
	HorseMountConfig.HorseRunAnimationId,
}

function AnimationPreloader:Start(): ()
	local PreloadTargets: { Animation } = {}
	for _Index: number, AnimationId: any in PRELOAD_ANIMATION_IDS do
		if type(AnimationId) ~= "string" or AnimationId == "" then
			continue
		end

		local AnimationValue: Animation = Instance.new("Animation")
		AnimationValue.AnimationId = AnimationId
		table.insert(PreloadTargets, AnimationValue)
	end

	if #PreloadTargets > 0 then
		local Success: boolean, ErrorValue: any = pcall(ContentProvider.PreloadAsync, ContentProvider, PreloadTargets)
		if not Success then
			warn(`[ClientBootup] Critical animation preload failed: {tostring(ErrorValue)}`)
		end
	end

	for _Index: number, AnimationValue: Animation in PreloadTargets do
		AnimationValue:Destroy()
	end
end

local function AddGuiPreloadTargets(Root: Instance?, Targets: { Instance }): ()
	if not Root then
		return
	end

	for _Index: number, Descendant: Instance in Root:GetDescendants() do
		if
			((Descendant:IsA("ImageLabel") or Descendant:IsA("ImageButton")) and Descendant.Image ~= "")
			or (Descendant:IsA("Sound") and Descendant.SoundId ~= "")
		then
			table.insert(Targets, Descendant)
		end
	end
end

local function WarnPreloadFailure(Label: string, Success: any, ErrorValue: any): ()
	if Success == true then
		return
	end

	warn(`[ClientBootup] {Label} preload failed: {tostring(ErrorValue)}`)
end

function UIAssetPreloader:Start(): ()
	local HudSoundCallSucceeded: boolean, HudSoundSucceeded: any, HudSoundError: any = pcall(HudAnim.preload_sfx)
	WarnPreloadFailure(
		"HUD sound",
		HudSoundCallSucceeded and HudSoundSucceeded,
		if HudSoundCallSucceeded then HudSoundError else HudSoundSucceeded
	)

	local GameSoundCallSucceeded: boolean, GameSoundSucceeded: any, GameSoundError: any =
		pcall(SoundUtility.PreloadGameSFX)
	WarnPreloadFailure(
		"game SFX",
		GameSoundCallSucceeded and GameSoundSucceeded,
		if GameSoundCallSucceeded then GameSoundError else GameSoundSucceeded
	)

	local PlayerGui: PlayerGui = Players.LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
	local MainUI: Instance? = PlayerGui:FindFirstChild("MainUI") or PlayerGui:FindFirstChild("MainUI", true)
	local Mainframe: Instance? = MainUI
		and (MainUI:FindFirstChild("MainframeFR") or MainUI:FindFirstChild("MainframeFR", true))
	local Dialogue: Instance? = Mainframe and Mainframe:FindFirstChild("DialogueFR", true)
	local Seller: Instance? = Mainframe and Mainframe:FindFirstChild("Seller", true)
	local PreloadTargets: { Instance } = {}
	local TemporaryTargets: { Instance } = {}
	AddGuiPreloadTargets(Dialogue, PreloadTargets)
	AddGuiPreloadTargets(Seller, PreloadTargets)

	for _Index: number, Item: any in ToolItemCatalog.GetItemsForShop("Noob") or {} do
		local IconImage: any = Item.IconImage or Item.IconImageId or Item.Image or Item.ImageId
		if type(IconImage) == "number" then
			IconImage = `rbxassetid://{IconImage}`
		end
		if type(IconImage) == "string" and IconImage ~= "" then
			local ImageTarget: ImageLabel = Instance.new("ImageLabel")
			ImageTarget.Image = IconImage
			table.insert(TemporaryTargets, ImageTarget)
			table.insert(PreloadTargets, ImageTarget)
		end
	end

	if #PreloadTargets > 0 then
		local Success: boolean, ErrorValue: any = pcall(ContentProvider.PreloadAsync, ContentProvider, PreloadTargets)
		WarnPreloadFailure("notification and seller UI", Success, ErrorValue)
	end

	for _Index: number, Target: Instance in TemporaryTargets do
		Target:Destroy()
	end
end

FrameworkModule:SetAttribute(CLIENT_READY_ATTRIBUTE, false)
FrameworkModule:SetAttribute(CLIENT_FAILED_ATTRIBUTE, false)
FrameworkModule:SetAttribute(CLIENT_ERROR_ATTRIBUTE, nil)

local Runtime: any = Framework.Lifecycle.new("Client", {
	AnimationPreloader,
	UIAssetPreloader,
	UIRuntime,
	LegacyClientRuntime,
})

local Success: boolean, ErrorValue: any = pcall(function(): ()
	Runtime:Start()
end)

if Success then
	Framework.RuntimeEvents.ClientStarted:Fire()
	FrameworkModule:SetAttribute(CLIENT_READY_ATTRIBUTE, true)
else
	local Message: string = tostring(ErrorValue)
	FrameworkModule:SetAttribute(CLIENT_FAILED_ATTRIBUTE, true)
	FrameworkModule:SetAttribute(CLIENT_ERROR_ATTRIBUTE, Message)
	warn(`[ClientBootup] {Message}`)
end
