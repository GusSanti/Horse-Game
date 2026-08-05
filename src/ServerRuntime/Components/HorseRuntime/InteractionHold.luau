--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Network: any = require(Modules:WaitForChild("Network"))

local HorseModules: Folder = ServerStorage:WaitForChild("Modules"):WaitForChild("Horse") :: Folder
local HorseService: any = require(HorseModules:WaitForChild("HorseService"))
local HorseRoamingService: any = require(HorseModules:WaitForChild("HorseRoamingService"))

local HeldHorseByPlayer: { [Player]: string } = {}
local InteractionHold = {}

local function ReleaseHold(Player: Player): ()
	local HeldHorseId: string? = HeldHorseByPlayer[Player]
	if not HeldHorseId then
		return
	end

	HeldHorseByPlayer[Player] = nil
	HorseRoamingService.SetInteractionHold(Player, HeldHorseId, false)
end

local function EngageHold(Player: Player, HorseId: any): ()
	if type(HorseId) ~= "string" or HorseId == "" then
		return
	end

	local Horse: any, ResolvedHorseId: string? = HorseService.GetPlayerHorse(Player, HorseId)
	if not Horse or not ResolvedHorseId then
		return
	end

	if HeldHorseByPlayer[Player] and HeldHorseByPlayer[Player] ~= ResolvedHorseId then
		ReleaseHold(Player)
	end

	HeldHorseByPlayer[Player] = ResolvedHorseId
	HorseRoamingService.SetInteractionHold(Player, ResolvedHorseId, true)
end

function InteractionHold.Bind(TroveValue: any): ()
	local InteractionHoldEvent: any = Network.Horse and Network.Horse.InteractionHold
	if InteractionHoldEvent and type(InteractionHoldEvent.Connect) == "function" then
		InteractionHoldEvent:Connect(function(Player: Player, HorseId: any, IsStarting: any): ()
			if IsStarting == true then
				EngageHold(Player, HorseId)
			else
				ReleaseHold(Player)
			end
		end, TroveValue)
	end

	TroveValue:Connect(Framework.RuntimeEvents.PlayerRemoving, function(Player: Player): ()
		HeldHorseByPlayer[Player] = nil
		HorseRoamingService.ReleaseInteractionHolds(Player)
	end)

	TroveValue:Add(function(): ()
		for Player: Player, _ in HeldHorseByPlayer do
			HorseRoamingService.ReleaseInteractionHolds(Player)
		end
		table.clear(HeldHorseByPlayer)
	end)
end

return InteractionHold
