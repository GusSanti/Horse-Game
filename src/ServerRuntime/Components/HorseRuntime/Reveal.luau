--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Network: any = require(Modules:WaitForChild("Network"))
local DataUtility: any = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))

local Reveal = {}

function Reveal.Bind(TroveValue: any): ()
	Network.Horse.AcknowledgeReveal:Connect(function(Player: Player, HorseId: any): ()
		local PendingReveal: any = DataUtility.server.get(Player, "Progression.PendingHorseReveal")
		if type(PendingReveal) ~= "table" then
			return
		end

		if type(HorseId) == "string" and HorseId ~= "" and PendingReveal.HorseId ~= HorseId then
			return
		end

		DataUtility.server.set(Player, "Progression.PendingHorseReveal", nil)
		DataUtility.server.set(Player, "Progression.StarterRevealAcknowledged", true)
	end, TroveValue)
end

return Reveal
