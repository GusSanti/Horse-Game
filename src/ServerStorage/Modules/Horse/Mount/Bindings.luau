--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Net: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Net"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))

type Payload = { [string]: any }

export type Callbacks = {
	Mount: (Player, Payload) -> any,
	Dismount: (Player) -> any,
	GetState: (Player) -> any,
	Input: (Player, Payload) -> (),
	CharacterChanged: (Player, string) -> (),
	PlayerRemoving: (Player) -> (),
	Heartbeat: (number) -> (),
}

local Bindings = {}

function Bindings.Bind(CallbacksValue: Callbacks): any
	local Scope: any = Trove.new()
	Scope:Connect(Framework.RuntimeEvents.CharacterAdded, function(Player: Player): ()
		CallbacksValue.CharacterChanged(Player, "CharacterChanged")
	end)
	Scope:Connect(Framework.RuntimeEvents.CharacterRemoving, function(Player: Player): ()
		CallbacksValue.CharacterChanged(Player, "CharacterRemoving")
	end)
	Scope:Connect(Framework.RuntimeEvents.PlayerRemoving, CallbacksValue.PlayerRemoving)

	Net.Function.HorseMountAction:Respond(function(Player: Player, PayloadValue: any): any
		if type(PayloadValue) ~= "table" then
			return {
				Success = false,
				Code = "InvalidPayload",
			}
		end

		if PayloadValue.Action == "Mount" then
			return CallbacksValue.Mount(Player, PayloadValue)
		end
		if PayloadValue.Action == "Dismount" then
			return CallbacksValue.Dismount(Player)
		end
		if PayloadValue.Action == "GetState" then
			return CallbacksValue.GetState(Player)
		end

		return {
			Success = false,
			Code = "UnknownAction",
		}
	end, Scope)

	Net.Event.HorseMountInput:Connect(function(Player: Player, PayloadValue: any): ()
		if type(PayloadValue) == "table" then
			CallbacksValue.Input(Player, PayloadValue)
		end
	end, Scope)
	Scope:Connect(RunService.Heartbeat, CallbacksValue.Heartbeat)
	return Scope
end

return table.freeze(Bindings)
