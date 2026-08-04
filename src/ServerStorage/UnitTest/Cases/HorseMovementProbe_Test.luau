--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local MovementDomain: any = require(ReplicatedStorage.Modules.Game.Horse.Mount.Movement)
local GroundProbe: any = MovementDomain.GroundProbe

local CONFIG = table.freeze({
	GroundProbeHeight = 12,
	GroundProbeDistance = 24,
	TerrainProbeSpacing = 3,
	MaxTerrainPitchDegrees = 22,
	MaxTerrainRollDegrees = 12,
	HorseProbeIntervalSeconds = 0.05,
	HorseObstacleProbeDistance = 8,
	HorseObstacleProbeMinHeight = 1.25,
	HorseObstacleProbeMaxHeight = 3.75,
	HorseObstacleStopDistance = 2,
})

local function CreatePart(Name: string, Size: Vector3, Position: Vector3, Parent: Instance): Part
	local PartValue: Part = Instance.new("Part")
	PartValue.Name = Name
	PartValue.Size = Size
	PartValue.Position = Position
	PartValue.Anchored = true
	PartValue.Parent = Parent
	return PartValue
end

return function(t: any): ()
	-- The cached probe resolves ground height and a blocking wall in one sample.
	t.test("samples terrain and obstacle clearance", function(): ()
		local Fixture: Folder = Instance.new("Folder")
		Fixture.Name = "HorseMovementProbeFixture"
		Fixture.Parent = workspace
		local Success: boolean, ErrorValue: any = pcall(function(): ()
			CreatePart("Ground", Vector3.new(40, 1, 40), Vector3.new(0, -10000, 0), Fixture)
			CreatePart("Wall", Vector3.new(4, 8, 1), Vector3.new(0, -9992, -4), Fixture)
			local Probe: any = GroundProbe.new(workspace, CONFIG)
			Probe:SetIgnore({})
			local Sample: any = Probe:Update(0, Vector3.new(0, -9995, 0), 0, 0)

			t.expect.truthy(math.abs((Sample.GroundY or 0) - (-9999.5)) < 0.01)
			t.expect.truthy(Sample.ObstacleSpeedAlpha > 0)
			t.expect.truthy(Sample.ObstacleSpeedAlpha < 1)
		end)
		Fixture:Destroy()
		if not Success then
			error(ErrorValue, 0)
		end
	end)

	-- Samples remain stable inside the interval and refresh after it elapses.
	t.test("bounds raycast refresh frequency", function(): ()
		local Fixture: Folder = Instance.new("Folder")
		Fixture.Name = "HorseMovementProbeIntervalFixture"
		Fixture.Parent = workspace
		local Success: boolean, ErrorValue: any = pcall(function(): ()
			CreatePart("Ground", Vector3.new(40, 1, 40), Vector3.new(0, -10000, 0), Fixture)
			local Wall: Part = CreatePart("Wall", Vector3.new(4, 8, 1), Vector3.new(0, -9992, -4), Fixture)
			local Probe: any = GroundProbe.new(workspace, CONFIG)
			Probe:SetIgnore({})
			local Initial: number = Probe:Update(0, Vector3.new(0, -9995, 0), 0, 0).ObstacleSpeedAlpha
			Wall.Position = Vector3.new(0, -9992, -20)
			local Cached: number = Probe:Update(0.01, Vector3.new(0, -9995, 0), 0, 0).ObstacleSpeedAlpha
			local Refreshed: number = Probe:Update(0.05, Vector3.new(0, -9995, 0), 0, 0).ObstacleSpeedAlpha

			t.expect.equal(Cached, Initial)
			t.expect.equal(Refreshed, 1)
		end)
		Fixture:Destroy()
		if not Success then
			error(ErrorValue, 0)
		end
	end)
end
