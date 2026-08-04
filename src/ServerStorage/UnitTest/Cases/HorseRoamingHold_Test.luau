--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local HorseRoamingHold: any = require(ServerStorage.Modules.Horse.HorseRoamingHold)
local HorseRoamingConfig: any = require(ReplicatedStorage.Modules.GameData.Horse.HorseRoamingConfig)

local function WithHoldTimeout(Seconds: number, Callback: () -> ()): ()
	local PreviousTimeout: number = HorseRoamingConfig.MaxInteractionHoldSeconds
	HorseRoamingConfig.MaxInteractionHoldSeconds = Seconds
	local Success: boolean, ErrorValue: any = pcall(Callback)
	HorseRoamingConfig.MaxInteractionHoldSeconds = PreviousTimeout
	if not Success then
		error(ErrorValue, 0)
	end
end

return function(t: any): ()
	t.test("holds and releases a roaming state", function(): ()
		local State: any = {}

		t.expect.falsy(HorseRoamingHold.IsHeld(State))
		HorseRoamingHold.Set(State, true)
		t.expect.truthy(HorseRoamingHold.IsHeld(State))
		HorseRoamingHold.Set(State, false)
		t.expect.falsy(HorseRoamingHold.IsHeld(State))
	end)

	t.test("expires a hold the client never released", function(): ()
		WithHoldTimeout(0.05, function(): ()
			local State: any = {}
			HorseRoamingHold.Set(State, true)
			t.expect.truthy(HorseRoamingHold.IsHeld(State))

			task.wait(0.1)
			t.expect.falsy(HorseRoamingHold.IsHeld(State))
		end)
	end)

	t.test("keeps holds independent per state", function(): ()
		local First: any = {}
		local Second: any = {}

		HorseRoamingHold.Set(First, true)
		t.expect.truthy(HorseRoamingHold.IsHeld(First))
		t.expect.falsy(HorseRoamingHold.IsHeld(Second))

		HorseRoamingHold.Clear(First)
		t.expect.falsy(HorseRoamingHold.IsHeld(First))
	end)

	t.test("ignores clearing an unheld state", function(): ()
		local State: any = {}

		HorseRoamingHold.Clear(State)
		HorseRoamingHold.Clear(nil)
		t.expect.falsy(HorseRoamingHold.IsHeld(State))
	end)
end
