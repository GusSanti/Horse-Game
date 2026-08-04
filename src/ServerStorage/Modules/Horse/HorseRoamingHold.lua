--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local GameData: Folder = Modules:WaitForChild("GameData") :: Folder
local HorseRoamingConfig: any = require(
	GameData:WaitForChild("Horse"):WaitForChild("HorseRoamingConfig")
)

local HorseRoamingHold = {}

local holdExpiryByState: {[any]: number} = setmetatable({}, {__mode = "k"}) :: any

function HorseRoamingHold.Set(state: any, active: boolean): ()
	if not state then
		return
	end

	if active then
		holdExpiryByState[state] = os.clock() + HorseRoamingConfig.MaxInteractionHoldSeconds
		return
	end

	holdExpiryByState[state] = nil
end

function HorseRoamingHold.IsHeld(state: any): boolean
	local expiresAt = holdExpiryByState[state]
	if not expiresAt then
		return false
	end

	if os.clock() >= expiresAt then
		holdExpiryByState[state] = nil
		return false
	end

	return true
end

function HorseRoamingHold.Clear(state: any): ()
	if not state then
		return
	end

	holdExpiryByState[state] = nil
end

return HorseRoamingHold
