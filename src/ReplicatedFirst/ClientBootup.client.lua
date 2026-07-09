------------------//SERVICES
local ContentProvider = game:GetService("ContentProvider")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------//VARIABLES
local localPlayer: Player = Players.LocalPlayer
local playerScripts: PlayerScripts = localPlayer:WaitForChild("PlayerScripts")
local sourceFolder: Folder = ReplicatedStorage:WaitForChild("PlayerScripts")
local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local gameDataFolder = modulesFolder:WaitForChild("GameData")
local HorseMountConfig = require(gameDataFolder:WaitForChild("HorseMountConfig"))

local PRELOAD_ANIMATION_IDS = {
	HorseMountConfig.PlayerHopOnAnimationId,
	HorseMountConfig.PlayerHopOffAnimationId,
	HorseMountConfig.PlayerIdleAnimationId,
	HorseMountConfig.PlayerRideAnimationId,
	HorseMountConfig.HorseIdleAnimationId,
	HorseMountConfig.HorseWalkAnimationId,
	HorseMountConfig.HorseRunAnimationId,
}

local function preload_animations()
	local preloadTargets = {}
	local createdAnimations = {}

	for _, animationId in ipairs(PRELOAD_ANIMATION_IDS) do
		if type(animationId) == "string" and animationId ~= "" then
			local animation = Instance.new("Animation")
			animation.AnimationId = animationId
			createdAnimations[#createdAnimations + 1] = animation
			preloadTargets[#preloadTargets + 1] = animation
		end
	end

	if #preloadTargets > 0 then
		pcall(function()
			ContentProvider:PreloadAsync(preloadTargets)
		end)
	end

	for _, animation in ipairs(createdAnimations) do
		animation:Destroy()
	end
end

------------------//MAIN FUNCTIONS
preload_animations()

for _, child in ipairs(sourceFolder:GetChildren()) do
	local existingChild = playerScripts:FindFirstChild(child.Name)
	if existingChild then
		existingChild:Destroy()
	end

	child:Clone().Parent = playerScripts
end
