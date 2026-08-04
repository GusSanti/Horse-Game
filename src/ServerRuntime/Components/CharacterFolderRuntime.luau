--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))

local CHARACTERS_FOLDER_NAME: string = "Characters"

local CharacterFolderRuntime = {
	Name = "CharacterFolderRuntime",
	Trove = nil :: any,
	CharactersFolder = nil :: Folder?,
}

function CharacterFolderRuntime:_EnsureFolder(): Folder
	if self.CharactersFolder and self.CharactersFolder.Parent == workspace then
		return self.CharactersFolder
	end

	local Existing: Instance? = workspace:FindFirstChild(CHARACTERS_FOLDER_NAME)
	if Existing and Existing:IsA("Folder") then
		self.CharactersFolder = Existing
		return Existing
	end

	local FolderValue: Folder = Instance.new("Folder")
	FolderValue.Name = CHARACTERS_FOLDER_NAME
	FolderValue.Parent = workspace
	self.CharactersFolder = FolderValue
	return FolderValue
end

function CharacterFolderRuntime:Init(): ()
	if self.Trove then
		return
	end

	self.Trove = Trove.new()
	self.Trove:Connect(Framework.RuntimeEvents.CharacterAdded, function(_Player: Player, Character: Model): ()
		if Character.Parent then
			Character.Parent = self:_EnsureFolder()
		end
	end)
end

function CharacterFolderRuntime:Start(): ()
	self:_EnsureFolder()
end

function CharacterFolderRuntime:Destroy(): ()
	if self.Trove then
		self.Trove:Destroy()
		self.Trove = nil
	end
	self.CharactersFolder = nil
end

return CharacterFolderRuntime
