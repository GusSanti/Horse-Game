--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementDomain: any = require(
	ReplicatedStorage.Modules.Game.Horse.Mount.Movement
)
local StateMachine: any = MovementDomain.StateMachine

local MOVEMENT = table.freeze({
	WalkSpeed = 14,
	TrotSpeed = 18,
	CanterSpeed = 22,
	SprintSpeed = 26,
	Acceleration = 0.8,
})

local CONFIG = table.freeze({
	HorseForwardAccelerationSeconds = 3,
	HorseAccelerationBaseStat = 0.8,
	HorseBrakePerSecond = 20,
	HorseReverseAccelerationPerSecond = 8,
	HorseReverseCoastDragPerSecond = 10,
	HorseReverseStopEpsilon = 0.15,
	HorseCoastDragPerSecond = 0,
	HorseDismountBrakePerSecond = 14,
	HorseDoubleTapWindowSeconds = 0.28,
	HorseDoubleTapMinReleaseSeconds = 0.04,
	HorseDoubleTapBoostSeconds = 0.4,
	HorseSprintAccelerationMultiplier = 1.45,
	HorseBackwardSpeedMultiplier = 0.48,
	HorseMovementStopEpsilon = 0.01,
	HorseRearDurationSeconds = 1.15,
	HorseRearCooldownSeconds = 1.75,
	HorseRearMaxStartSpeed = 0.75,
})

local function Step(State: any, Forward: number, Backward: number, Now: number, Stopping: boolean?): ()
	StateMachine.Step(State, {
		Forward = Forward,
		Backward = Backward,
		Sprinting = false,
		Stopping = Stopping == true,
		ObstacleSpeedAlpha = 1,
	}, MOVEMENT, CONFIG, 0.1, Now)
end

return function(t: any): ()
	-- Forward release preserves the currently selected gait speed.
	t.test("keeps the selected speed when forward input is released", function(): ()
		local State: any = StateMachine.Create()
		for Index: number = 1, 30 do
			Step(State, 1, 0, Index * 0.1)
		end
		local SelectedSpeed: number = State.Speed
		for Index: number = 31, 40 do
			Step(State, 0, 0, Index * 0.1)
		end

		t.expect.truthy(SelectedSpeed > MOVEMENT.CanterSpeed)
		t.expect.equal(State.Speed, SelectedSpeed)
	end)

	-- A second forward press inside the reference timing window enters gallop.
	t.test("enters gallop on a forward double tap", function(): ()
		local State: any = StateMachine.Create()
		Step(State, 1, 0, 1)
		Step(State, 0, 0, 1.1)
		Step(State, 1, 0, 1.2)

		t.expect.truthy(State.Speed > MOVEMENT.CanterSpeed)
		t.expect.equal(State.Mode, "Gallop")
	end)

	-- A one-frame input dropout must not look like an intentional double tap.
	t.test("ignores transient forward input dropout", function(): ()
		local State: any = StateMachine.Create()
		Step(State, 1, 0, 1)
		Step(State, 0, 0, 1.1)
		Step(State, 1, 0, 1.11)

		t.expect.truthy(State.Speed < MOVEMENT.CanterSpeed)
		t.expect.falsy(State.Mode == "Gallop")
	end)

	t.test("requires a fresh backward press after braking", function(): ()
		local State: any = StateMachine.Create()
		State.Speed = 10
		for Index: number = 1, 5 do
			Step(State, 0, 1, Index * 0.1)
		end
		t.expect.equal(State.Speed, 0)

		Step(State, 0, 1, 0.6)
		t.expect.equal(State.Speed, 0)
		Step(State, 0, 0, 0.7)
		Step(State, 0, 1, 0.8)
		t.expect.truthy(State.Speed < 0)
		t.expect.equal(State.Mode, "Backward")
	end)

	t.test("stops reverse drift after backward input is released", function(): ()
		local State: any = StateMachine.Create()
		State.Speed = -4
		for Index: number = 1, 4 do
			Step(State, 0, 0, Index * 0.1)
		end

		t.expect.equal(State.Speed, 0)
		t.expect.equal(State.Mode, "Idle")
	end)

	t.test("uses the stopping brake without changing direction", function(): ()
		local State: any = StateMachine.Create()
		State.Speed = 7
		for Index: number = 1, 5 do
			Step(State, 1, 0, Index * 0.1, true)
		end

		t.expect.equal(State.Speed, 0)
		t.expect.equal(State.Mode, "Idle")
	end)

	-- Effective horse speed thresholds map to the public locomotion modes.
	t.test("classifies every normalized locomotion band", function(): ()
		t.expect.equal(StateMachine.ClassifySpeed(0, MOVEMENT, false), "Idle")
		t.expect.equal(StateMachine.ClassifySpeed(8, MOVEMENT, false), "Gait")
		t.expect.equal(StateMachine.ClassifySpeed(18, MOVEMENT, false), "Trot")
		t.expect.equal(StateMachine.ClassifySpeed(24, MOVEMENT, false), "Gallop")
		t.expect.equal(StateMachine.ClassifySpeed(-4, MOVEMENT, false), "Backward")
		t.expect.equal(StateMachine.ClassifySpeed(0, MOVEMENT, true), "Rear")
	end)

	-- Rear is restricted to stopped horses and observes its cooldown.
	t.test("only starts rear while stopped and outside cooldown", function(): ()
		local State: any = StateMachine.Create()
		State.Speed = 4
		t.expect.falsy(StateMachine.RequestRear(State, CONFIG, 1))
		State.Speed = 0
		t.expect.truthy(StateMachine.RequestRear(State, CONFIG, 1))
		t.expect.equal(State.Mode, "Rear")
		t.expect.falsy(StateMachine.RequestRear(State, CONFIG, 1.2))
	end)

	-- Small speed drift is ignored while a material mismatch is blended.
	t.test("reconciles only meaningful authoritative speed differences", function(): ()
		local State: any = StateMachine.Create()
		State.Speed = 20
		t.expect.falsy(StateMachine.ReconcileSpeed(State, 18, 5, 0.2))
		t.expect.equal(State.Speed, 20)
		t.expect.truthy(StateMachine.ReconcileSpeed(State, 10, 5, 0.2))
		t.expect.equal(State.Speed, 18)
	end)
end
