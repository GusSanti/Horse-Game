--!strict

local ContentProvider: ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local FrameworkModule: ModuleScript = Modules:WaitForChild("Framework") :: ModuleScript
local Framework: any = require(FrameworkModule)
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

FrameworkModule:SetAttribute(CLIENT_READY_ATTRIBUTE, false)
FrameworkModule:SetAttribute(CLIENT_FAILED_ATTRIBUTE, false)
FrameworkModule:SetAttribute(CLIENT_ERROR_ATTRIBUTE, nil)

local Runtime: any = Framework.Lifecycle.new("Client", {
	AnimationPreloader,
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
