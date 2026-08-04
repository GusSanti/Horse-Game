--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Crossing: any = require(ReplicatedStorage.Modules.Game.Horse.Obstacle.Crossing)

return function(t: any): ()
	t.test("detects crossing the obstacle center in one sample", function(): ()
		t.expect.truthy(Crossing.CrossedCenter(0.2, -0.4))
		t.expect.falsy(Crossing.CrossedCenter(0.2, 0.1))
		t.expect.falsy(Crossing.CrossedCenter(-0.2, -0.4))
	end)

	t.test("accepts the first landing sample", function(): ()
		t.expect.truthy(Crossing.CanCapture(false, true, 10, 10, 0.45))
	end)

	t.test("accepts delayed landing replication inside grace", function(): ()
		t.expect.truthy(Crossing.CanCapture(false, false, 10, 10.4, 0.45))
		t.expect.falsy(Crossing.CanCapture(false, false, 10, 10.5, 0.45))
	end)
end
