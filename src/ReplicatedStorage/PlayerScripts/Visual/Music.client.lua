local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Utility = Modules:WaitForChild("Utility")

local SoundController = require(Utility:WaitForChild("SoundUtility"))

SoundController.PlayMusicQueue({
	"rbxassetid://109380353547781",
}, true)
SoundController.BindRemoteSFX()
