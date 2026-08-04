local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Network = require(Modules:WaitForChild("Network"))
local HorseBrushClient = require(script.Parent:WaitForChild("HorseBrushClient"))

local HorseFeedClient = {}

function HorseFeedClient.start(context): boolean
	context.playerAnimationId = "rbxassetid://120683562864703"
	context.horseAnimationEvent = Network.Horse.FeedAnimation
	context.matchPlayerAnimationDuration = true
	context.tweenCharacterPosition = true
	context.taskText = context.taskText or "Feeding your horse..."

	return HorseBrushClient.start(context)
end

return HorseFeedClient
