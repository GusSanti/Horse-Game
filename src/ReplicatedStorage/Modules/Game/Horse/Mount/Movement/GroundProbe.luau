--!strict

export type Sample = {
	GroundY: number?,
	Pitch: number,
	Roll: number,
	ObstacleSpeedAlpha: number,
}

export type Config = {
	GroundProbeHeight: number?,
	GroundProbeDistance: number?,
	TerrainProbeSpacing: number?,
	MaxTerrainPitchDegrees: number?,
	MaxTerrainRollDegrees: number?,
	HorseProbeIntervalSeconds: number?,
	HorseObstacleProbeDistance: number?,
	HorseObstacleProbeMinHeight: number?,
	HorseObstacleProbeMaxHeight: number?,
	HorseObstacleStopDistance: number?,
}

export type Probe = {
	WorldRoot: WorldRoot,
	Config: Config,
	Params: RaycastParams,
	Elapsed: number,
	HasSample: boolean,
	Sample: Sample,
	SetIgnore: (self: Probe, IgnoreList: { Instance }) -> (),
	Update: (self: Probe, DeltaTime: number, Position: Vector3, Yaw: number, GroundOffset: number) -> Sample,
	Reset: (self: Probe) -> (),
}

local GroundProbe = {}
GroundProbe.__index = GroundProbe

local function CastGround(Self: Probe, Position: Vector3): number?
	local ProbeHeight: number = math.max(tonumber(Self.Config.GroundProbeHeight) or 24, 1)
	local ProbeDistance: number = math.max(tonumber(Self.Config.GroundProbeDistance) or 64, 1)
	local Origin: Vector3 = Position + Vector3.new(0, ProbeHeight, 0)
	local Result: RaycastResult? = Self.WorldRoot:Raycast(
		Origin,
		Vector3.new(0, -(ProbeHeight + ProbeDistance), 0),
		Self.Params
	)
	return if Result then Result.Position.Y else nil
end

local function ResolveTerrainAngles(Self: Probe, Position: Vector3, Yaw: number): (number, number)
	local Spacing: number = math.max(tonumber(Self.Config.TerrainProbeSpacing) or 3, 0.5)
	local Orientation: CFrame = CFrame.Angles(0, Yaw, 0)
	local Forward: Vector3 = Orientation.LookVector
	local Right: Vector3 = Orientation.RightVector
	local FrontY: number? = CastGround(Self, Position + (Forward * Spacing))
	local BackY: number? = CastGround(Self, Position - (Forward * Spacing))
	local RightY: number? = CastGround(Self, Position + (Right * Spacing))
	local LeftY: number? = CastGround(Self, Position - (Right * Spacing))
	local Span: number = Spacing * 2

	local Pitch: number = 0
	if FrontY and BackY then
		local MaxPitch: number = math.rad(math.max(tonumber(Self.Config.MaxTerrainPitchDegrees) or 22, 0))
		Pitch = math.clamp(math.atan2(FrontY - BackY, Span), -MaxPitch, MaxPitch)
	end

	local Roll: number = 0
	if RightY and LeftY then
		local MaxRoll: number = math.rad(math.max(tonumber(Self.Config.MaxTerrainRollDegrees) or 12, 0))
		Roll = math.clamp(math.atan2(RightY - LeftY, Span), -MaxRoll, MaxRoll)
	end
	return Pitch, Roll
end

local function CastObstacle(
	Self: Probe,
	Position: Vector3,
	Direction: Vector3,
	Height: number,
	Distance: number
): RaycastResult?
	return Self.WorldRoot:Raycast(
		Position + Vector3.new(0, Height, 0),
		Direction * Distance,
		Self.Params
	)
end

local function ResolveObstacleSpeedAlpha(
	Self: Probe,
	Position: Vector3,
	Direction: Vector3,
	GroundOffset: number
): number
	local Distance: number = math.max(tonumber(Self.Config.HorseObstacleProbeDistance) or 8, 1)
	local StopDistance: number = math.clamp(tonumber(Self.Config.HorseObstacleStopDistance) or 2.25, 0, Distance)
	local MinHeight: number = math.max(tonumber(Self.Config.HorseObstacleProbeMinHeight) or 1.25, 0)
	local MaxHeight: number = math.max(tonumber(Self.Config.HorseObstacleProbeMaxHeight) or 3.75, MinHeight)
	local HeightScale: number = math.clamp(GroundOffset * 0.4, 0, 3)
	local LowResult: RaycastResult? = CastObstacle(Self, Position, Direction, MinHeight + HeightScale, Distance)
	local HighResult: RaycastResult? = CastObstacle(Self, Position, Direction, MaxHeight + HeightScale, Distance)
	local Result: RaycastResult? = LowResult or HighResult
	if not Result or Result.Normal.Y > 0.72 then
		return 1
	end

	return math.clamp((Result.Distance - StopDistance) / math.max(Distance - StopDistance, 0.01), 0, 1)
end

function GroundProbe.new(WorldRootValue: WorldRoot, ConfigValue: Config): Probe
	local Params: RaycastParams = RaycastParams.new()
	Params.FilterType = Enum.RaycastFilterType.Exclude
	Params.IgnoreWater = false
	return setmetatable({
		WorldRoot = WorldRootValue,
		Config = ConfigValue,
		Params = Params,
		Elapsed = 0,
		HasSample = false,
		Sample = {
			GroundY = nil,
			Pitch = 0,
			Roll = 0,
			ObstacleSpeedAlpha = 1,
		},
	}, GroundProbe) :: any
end

function GroundProbe.SetIgnore(Self: Probe, IgnoreList: { Instance }): ()
	Self.Params.FilterDescendantsInstances = IgnoreList
end

function GroundProbe.Update(
	Self: Probe,
	DeltaTime: number,
	Position: Vector3,
	Yaw: number,
	GroundOffset: number
): Sample
	Self.Elapsed += math.max(DeltaTime, 0)
	local Interval: number = math.max(tonumber(Self.Config.HorseProbeIntervalSeconds) or 0.05, 0.016)
	if Self.HasSample and Self.Elapsed < Interval then
		return Self.Sample
	end
	Self.Elapsed = 0
	Self.HasSample = true

	local Direction: Vector3 = CFrame.Angles(0, Yaw, 0).LookVector
	local Pitch: number, Roll: number = ResolveTerrainAngles(Self, Position, Yaw)
	Self.Sample.GroundY = CastGround(Self, Position)
	Self.Sample.Pitch = Pitch
	Self.Sample.Roll = Roll
	Self.Sample.ObstacleSpeedAlpha = ResolveObstacleSpeedAlpha(Self, Position, Direction, GroundOffset)
	return Self.Sample
end

function GroundProbe.Reset(Self: Probe): ()
	Self.Elapsed = 0
	Self.HasSample = false
	Self.Sample.GroundY = nil
	Self.Sample.Pitch = 0
	Self.Sample.Roll = 0
	Self.Sample.ObstacleSpeedAlpha = 1
	Self.Params.FilterDescendantsInstances = {}
end

return table.freeze(GroundProbe)
