--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local FrameworkModule: ModuleScript = ReplicatedStorage
	:WaitForChild("Modules")
	:WaitForChild("Framework") :: ModuleScript
local Framework: any = require(FrameworkModule)
local Components: Folder = script.Parent:WaitForChild("Components") :: Folder
local NetworkRuntime: any = require(Components:WaitForChild("NetworkRuntime"))
local DataRuntime: any = require(Components:WaitForChild("DataRuntime"))
local PlayerLifecycle: any = require(Components:WaitForChild("PlayerLifecycle"))
local AdminRuntime: any = require(Components:WaitForChild("AdminRuntime"))
local HorseRuntime: any = require(Components:WaitForChild("HorseRuntime"))
local GameplayRuntime: any = require(Components:WaitForChild("GameplayRuntime"))
local CommerceRuntime: any = require(Components:WaitForChild("CommerceRuntime"))
local PlotRuntime: any = require(Components:WaitForChild("PlotRuntime"))
local CharacterFolderRuntime: any = require(Components:WaitForChild("CharacterFolderRuntime"))
local NpcIdleRuntime: any = require(Components:WaitForChild("NpcIdleRuntime"))

local SERVER_READY_ATTRIBUTE: string = "ServerReady"
local SERVER_FAILED_ATTRIBUTE: string = "ServerFailed"
local SERVER_ERROR_ATTRIBUTE: string = "ServerError"

FrameworkModule:SetAttribute(SERVER_READY_ATTRIBUTE, false)
FrameworkModule:SetAttribute(SERVER_FAILED_ATTRIBUTE, false)
FrameworkModule:SetAttribute(SERVER_ERROR_ATTRIBUTE, nil)

local Runtime: any = Framework.Lifecycle.new("Server", {
	NetworkRuntime,
	DataRuntime,
	PlayerLifecycle,
	AdminRuntime,
	HorseRuntime,
	GameplayRuntime,
	CommerceRuntime,
	PlotRuntime,
	CharacterFolderRuntime,
	NpcIdleRuntime,
})

local Success: boolean, ErrorValue: any = pcall(function(): ()
	Runtime:Start()
end)

if Success then
	Framework.RuntimeEvents.ServerStarted:Fire()
	FrameworkModule:SetAttribute(SERVER_READY_ATTRIBUTE, true)
else
	local Message: string = tostring(ErrorValue)
	FrameworkModule:SetAttribute(SERVER_FAILED_ATTRIBUTE, true)
	FrameworkModule:SetAttribute(SERVER_ERROR_ATTRIBUTE, Message)
	warn(`[ServerBootup] {Message}`)
end

game:BindToClose(function(): ()
	Framework.RuntimeEvents.ServerStopping:Fire()
	Runtime:Destroy()
end)
