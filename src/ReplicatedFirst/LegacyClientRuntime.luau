--!strict

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer: Player = Players.LocalPlayer
local PlayerScripts: PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts") :: PlayerScripts
local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local FrameworkModule: ModuleScript = Modules:WaitForChild("Framework") :: ModuleScript
local Framework: any = require(FrameworkModule)
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))

local SOURCE_FOLDER_NAME: string = "PlayerScripts"
local ENTRYPOINT_READY_ATTRIBUTE: string = "RuntimeReady"
local SERVER_READY_ATTRIBUTE: string = "ServerReady"
local SERVER_FAILED_ATTRIBUTE: string = "ServerFailed"
local SERVER_ERROR_ATTRIBUTE: string = "ServerError"
local SERVER_READY_TIMEOUT_SECONDS: number = 120
local ENTRYPOINT_TIMEOUT_SECONDS: number = 30

local LegacyClientRuntime = {
	Name = "LegacyClientRuntime",
	Trove = nil :: any,
	Categories = {} :: { [string]: Folder },
}

local function ResolvePath(Root: Instance, Path: { string }): Instance
	local Current: Instance = Root
	for _Index: number, Name: string in Path do
		Current = Current:WaitForChild(Name)
	end
	return Current
end

local function WaitForServer(): ()
	local StartedAt: number = os.clock()
	while FrameworkModule:GetAttribute(SERVER_READY_ATTRIBUTE) ~= true do
		if FrameworkModule:GetAttribute(SERVER_FAILED_ATTRIBUTE) == true then
			error(
				`Server startup failed: {tostring(FrameworkModule:GetAttribute(SERVER_ERROR_ATTRIBUTE))}`,
				0
			)
		end
		if os.clock() - StartedAt >= SERVER_READY_TIMEOUT_SECONDS then
			error(`Server did not become ready after {SERVER_READY_TIMEOUT_SECONDS} seconds`, 0)
		end
		task.wait()
	end
end

local function WaitUntilReady(RuntimeScript: LocalScript, EntrypointName: string): ()
	local StartedAt: number = os.clock()
	while RuntimeScript.Parent and RuntimeScript:GetAttribute(ENTRYPOINT_READY_ATTRIBUTE) ~= true do
		if os.clock() - StartedAt >= ENTRYPOINT_TIMEOUT_SECONDS then
			error(`Client entrypoint {EntrypointName} did not become ready after {ENTRYPOINT_TIMEOUT_SECONDS} seconds`, 0)
		end
		task.wait()
	end

	if not RuntimeScript.Parent then
		error(`Client entrypoint {EntrypointName} was destroyed during startup`, 0)
	end
end

function LegacyClientRuntime:Init(): ()
	if self.Trove then
		return
	end

	self.Trove = Trove.new()
	for CategoryName: string in { Hud = true, Tools = true, Visual = true } do
		local ExistingCategory: Instance? = PlayerScripts:FindFirstChild(CategoryName)
		if ExistingCategory then
			ExistingCategory:Destroy()
		end

		local Category: Folder = Instance.new("Folder")
		Category.Name = CategoryName
		Category.Parent = PlayerScripts
		self.Categories[CategoryName] = Category
		self.Trove:Add(Category)
	end
end

function LegacyClientRuntime:Start(): ()
	WaitForServer()

	local SourceFolder: Folder = ReplicatedStorage:WaitForChild(SOURCE_FOLDER_NAME) :: Folder
	for _Index: number, Definition: any in Framework.RuntimeManifest.Client do
		local Template: Instance = ResolvePath(SourceFolder, Definition.Path)
		if not Template:IsA("LocalScript") then
			error(`Client entrypoint {Definition.Name} is not a LocalScript`, 0)
		end

		local CategoryName: string = Definition.Path[1]
		local Category: Folder? = self.Categories[CategoryName]
		if not Category then
			error(`Client entrypoint {Definition.Name} has unknown category {CategoryName}`, 0)
		end

		local RuntimeScript: LocalScript = Template:Clone()
		RuntimeScript.Name = Definition.Name
		RuntimeScript.Disabled = true
		RuntimeScript.Parent = Category
		RuntimeScript.Disabled = false
		WaitUntilReady(RuntimeScript, Definition.Name)
	end
end

function LegacyClientRuntime:Destroy(): ()
	if not self.Trove then
		return
	end

	self.Trove:Destroy()
	self.Trove = nil
	table.clear(self.Categories)
end

return LegacyClientRuntime
