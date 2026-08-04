--!strict

local CollectionService: CollectionService = game:GetService("CollectionService")
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Network: any = require(Modules:WaitForChild("Network"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))
local ObstacleConfig: any = require(
	Modules:WaitForChild("GameData"):WaitForChild("Horse"):WaitForChild("ObstacleConfig")
)
local ObstacleDomain: any = require(
	Modules:WaitForChild("Game"):WaitForChild("Horse"):WaitForChild("Obstacle")
)
local HorseMountService: any = require(script.Parent:WaitForChild("HorseMountService"))

type Axis = "X" | "Z"

type Bounds = {
	CFrame: CFrame,
	Size: Vector3,
	Axis: Axis,
	DepthHalf: number,
	LengthHalf: number,
}

type CrossingMetrics = {
	TimingAlpha: number,
	AlignmentAlpha: number,
	EdgeAlpha: number,
}

type Attempt = {
	Obstacle: Instance,
	Bounds: Bounds,
	DirectionSign: number,
	TakeoffAt: number,
	ExpectedAirSeconds: number,
	ApproachSpeed: number,
	PreviousSignedCoordinate: number,
	CrossingMetrics: CrossingMetrics?,
	Cleared: boolean,
	LandedAt: number?,
}

type PlayerState = {
	Root: BasePart?,
	WasJumping: boolean,
	Attempt: Attempt?,
	LastCompletedByObstacle: { [Instance]: number },
}

local ObstacleFeedback: any = Network.Horse.ObstacleFeedback
local ObstacleCrossing: any = ObstacleDomain.Crossing
local ObstacleScoring: any = ObstacleDomain.Scoring

local ObstacleService = {}

local ServiceTrove: any = nil
local SampleElapsed: number = 0
local Obstacles: { [Instance]: boolean } = {}
local PlayerStates: { [Player]: PlayerState } = {}

local function GetAxisValue(VectorValue: Vector3, AxisValue: Axis): number
	return if AxisValue == "X" then VectorValue.X else VectorValue.Z
end

local function GetLengthValue(VectorValue: Vector3, AxisValue: Axis): number
	return if AxisValue == "X" then VectorValue.Z else VectorValue.X
end

local function ResolveAxis(Obstacle: Instance, Size: Vector3): Axis
	local ConfiguredAxis: any = Obstacle:GetAttribute("ObstacleAxis")
	if type(ConfiguredAxis) == "string" then
		local NormalizedAxis: string = string.upper(ConfiguredAxis)
		if NormalizedAxis == "X" or NormalizedAxis == "Z" then
			return NormalizedAxis :: Axis
		end
	end

	return if Size.X <= Size.Z then "X" else "Z"
end

local function ResolveBounds(Obstacle: Instance): Bounds?
	if not Obstacle:IsDescendantOf(workspace) then
		return nil
	end

	local BoundsCFrame: CFrame
	local BoundsSize: Vector3
	if Obstacle:IsA("BasePart") then
		BoundsCFrame = Obstacle.CFrame
		BoundsSize = Obstacle.Size
	elseif Obstacle:IsA("Model") then
		local Success: boolean, CFrameValue: any, SizeValue: any = pcall(Obstacle.GetBoundingBox, Obstacle)
		if not Success or typeof(CFrameValue) ~= "CFrame" or typeof(SizeValue) ~= "Vector3" then
			return nil
		end
		BoundsCFrame = CFrameValue
		BoundsSize = SizeValue
	else
		return nil
	end

	if BoundsSize.X <= 0 or BoundsSize.Y <= 0 or BoundsSize.Z <= 0 then
		return nil
	end

	local AxisValue: Axis = ResolveAxis(Obstacle, BoundsSize)
	local DepthHalf: number = GetAxisValue(BoundsSize, AxisValue) * 0.5
	local LengthHalf: number = GetLengthValue(BoundsSize, AxisValue) * 0.5
	return {
		CFrame = BoundsCFrame,
		Size = BoundsSize,
		Axis = AxisValue,
		DepthHalf = DepthHalf,
		LengthHalf = LengthHalf,
	}
end

local function AddPlayer(Player: Player): ()
	if PlayerStates[Player] then
		return
	end

	PlayerStates[Player] = {
		Root = nil,
		WasJumping = false,
		Attempt = nil,
		LastCompletedByObstacle = {},
	}
end

local function RemovePlayer(Player: Player): ()
	PlayerStates[Player] = nil
end

local function AddObstacle(Obstacle: Instance): ()
	if not Obstacle:IsA("BasePart") and not Obstacle:IsA("Model") then
		warn(`[ObstacleService] Ignored unsupported tagged instance {Obstacle:GetFullName()}`)
		return
	end

	Obstacles[Obstacle] = true
end

local function RemoveObstacle(Obstacle: Instance): ()
	Obstacles[Obstacle] = nil
	for _Player: Player, State: PlayerState in PlayerStates do
		if State.Attempt and State.Attempt.Obstacle == Obstacle then
			State.Attempt = nil
		end
		State.LastCompletedByObstacle[Obstacle] = nil
	end
end

local function GetPlanarVelocity(Root: BasePart): Vector3
	local Velocity: Vector3 = Root.AssemblyLinearVelocity
	return Vector3.new(Velocity.X, 0, Velocity.Z)
end

local function FindAttempt(
	State: PlayerState,
	Root: BasePart,
	JumpStartedAt: number,
	ExpectedAirSeconds: number,
	Now: number
): Attempt?
	local Position: Vector3 = Root.Position
	local PlanarVelocity: Vector3 = GetPlanarVelocity(Root)
	local PlanarSpeed: number = PlanarVelocity.Magnitude
	if PlanarSpeed < ObstacleConfig.MinimumPlanarSpeed then
		return nil
	end

	local BestAttempt: Attempt? = nil
	local BestDistance: number = math.huge
	for Obstacle: Instance in Obstacles do
		local LastCompletedAt: number = State.LastCompletedByObstacle[Obstacle] or 0
		if Now - LastCompletedAt < ObstacleConfig.RepeatCooldownSeconds then
			continue
		end

		local BoundsValue: Bounds? = ResolveBounds(Obstacle)
		if not BoundsValue then
			continue
		end

		local LocalPosition: Vector3 = BoundsValue.CFrame:PointToObjectSpace(Position)
		local LocalVelocity: Vector3 = BoundsValue.CFrame:VectorToObjectSpace(PlanarVelocity)
		local CrossCoordinate: number = GetAxisValue(LocalPosition, BoundsValue.Axis)
		local CrossVelocity: number = GetAxisValue(LocalVelocity, BoundsValue.Axis)
		local LengthCoordinate: number = GetLengthValue(LocalPosition, BoundsValue.Axis)
		local PlaneDistance: number = math.max(math.abs(CrossCoordinate) - BoundsValue.DepthHalf, 0)
		local VerticalDistance: number = math.abs(Position.Y - BoundsValue.CFrame.Position.Y)

		if CrossCoordinate * CrossVelocity >= 0
			or PlaneDistance > ObstacleConfig.ApproachDistance
			or math.abs(LengthCoordinate) > BoundsValue.LengthHalf + ObstacleConfig.LateralCaptureMargin
			or VerticalDistance > (BoundsValue.Size.Y * 0.5) + ObstacleConfig.MaximumVerticalDistance
		then
			continue
		end

		if PlaneDistance < BestDistance then
			local DirectionSign: number = if CrossCoordinate >= 0 then 1 else -1
			BestDistance = PlaneDistance
			BestAttempt = {
				Obstacle = Obstacle,
				Bounds = BoundsValue,
				DirectionSign = DirectionSign,
				TakeoffAt = if JumpStartedAt > 0 then JumpStartedAt else Now,
				ExpectedAirSeconds = math.max(ExpectedAirSeconds, 0.1),
				ApproachSpeed = PlanarSpeed,
				PreviousSignedCoordinate = DirectionSign * CrossCoordinate,
				CrossingMetrics = nil,
				Cleared = false,
				LandedAt = nil,
			}
		end
	end

	return BestAttempt
end

local function CaptureCrossingMetrics(AttemptValue: Attempt, Root: BasePart, LocalPosition: Vector3, Now: number): CrossingMetrics
	local BoundsValue: Bounds = AttemptValue.Bounds
	local PlanarVelocity: Vector3 = GetPlanarVelocity(Root)
	local LocalVelocity: Vector3 = BoundsValue.CFrame:VectorToObjectSpace(PlanarVelocity)
	local CrossSpeed: number = math.abs(GetAxisValue(LocalVelocity, BoundsValue.Axis))
	local AlignmentAlpha: number = if PlanarVelocity.Magnitude > 0
		then math.clamp(CrossSpeed / PlanarVelocity.Magnitude, 0, 1)
		else 0
	local LengthCoordinate: number = GetLengthValue(LocalPosition, BoundsValue.Axis)
	local EdgeClearance: number = BoundsValue.LengthHalf - math.abs(LengthCoordinate)
	local EdgeAlpha: number = math.clamp(EdgeClearance / ObstacleConfig.PerfectEdgeClearance, 0, 1)
	local IdealCrossingAt: number = AttemptValue.TakeoffAt + (AttemptValue.ExpectedAirSeconds * 0.5)
	local TimingTolerance: number = math.max(AttemptValue.ExpectedAirSeconds * 0.5, 0.1)
	local TimingAlpha: number = 1 - math.clamp(math.abs(Now - IdealCrossingAt) / TimingTolerance, 0, 1)

	return {
		TimingAlpha = TimingAlpha,
		AlignmentAlpha = AlignmentAlpha,
		EdgeAlpha = EdgeAlpha,
	}
end

local function CompleteAttempt(Player: Player, State: PlayerState, Root: BasePart, Now: number): ()
	local AttemptValue: Attempt? = State.Attempt
	local CrossingMetricsValue: CrossingMetrics? = AttemptValue and AttemptValue.CrossingMetrics or nil
	if not AttemptValue or not CrossingMetricsValue then
		State.Attempt = nil
		return
	end

	local LandingSpeed: number = GetPlanarVelocity(Root).Magnitude
	local SpeedReference: number = math.max(AttemptValue.ApproachSpeed, ObstacleConfig.MinimumPlanarSpeed)
	local RhythmAlpha: number = 1 - math.clamp(
		math.abs(LandingSpeed - AttemptValue.ApproachSpeed) / SpeedReference,
		0,
		1
	)
	local Rating: string, Score: number = ObstacleScoring.Calculate({
		TimingAlpha = CrossingMetricsValue.TimingAlpha,
		AlignmentAlpha = CrossingMetricsValue.AlignmentAlpha,
		EdgeAlpha = CrossingMetricsValue.EdgeAlpha,
		RhythmAlpha = RhythmAlpha,
	})

	State.LastCompletedByObstacle[AttemptValue.Obstacle] = Now
	State.Attempt = nil
	ObstacleFeedback:Fire(Player, {
		Rating = Rating,
		Score = Score,
	})
end

local function UpdateAttempt(Player: Player, State: PlayerState, Root: BasePart, IsJumping: boolean, Now: number): ()
	local AttemptValue: Attempt? = State.Attempt
	if not AttemptValue then
		return
	end
	if not Obstacles[AttemptValue.Obstacle]
		or not AttemptValue.Obstacle.Parent
		or Now - AttemptValue.TakeoffAt > ObstacleConfig.MaximumAttemptSeconds
	then
		State.Attempt = nil
		return
	end

	local BoundsValue: Bounds = AttemptValue.Bounds
	local LocalPosition: Vector3 = BoundsValue.CFrame:PointToObjectSpace(Root.Position)
	local CrossCoordinate: number = GetAxisValue(LocalPosition, BoundsValue.Axis)
	local SignedCoordinate: number = AttemptValue.DirectionSign * CrossCoordinate
	local LengthCoordinate: number = GetLengthValue(LocalPosition, BoundsValue.Axis)
	if math.abs(LengthCoordinate) > BoundsValue.LengthHalf + ObstacleConfig.LateralCaptureMargin then
		State.Attempt = nil
		return
	end

	if not IsJumping and not AttemptValue.LandedAt then
		AttemptValue.LandedAt = Now
	end
	if not AttemptValue.CrossingMetrics
		and ObstacleCrossing.CrossedCenter(AttemptValue.PreviousSignedCoordinate, SignedCoordinate)
		and ObstacleCrossing.CanCapture(
			IsJumping,
			State.WasJumping,
			AttemptValue.LandedAt,
			Now,
			ObstacleConfig.LandingClearGraceSeconds
		)
	then
		AttemptValue.CrossingMetrics = CaptureCrossingMetrics(AttemptValue, Root, LocalPosition, Now)
		AttemptValue.Cleared = true
	end
	AttemptValue.PreviousSignedCoordinate = SignedCoordinate

	if AttemptValue.Cleared and not IsJumping then
		CompleteAttempt(Player, State, Root, Now)
		return
	end
	if AttemptValue.LandedAt
		and Now - AttemptValue.LandedAt > ObstacleConfig.LandingClearGraceSeconds
	then
		State.Attempt = nil
	end
end

local function UpdatePlayer(Player: Player, State: PlayerState, Now: number): ()
	local Root: BasePart?, IsJumping: boolean, JumpStartedAt: number, ExpectedAirSeconds: number =
		HorseMountService.GetMovementSample(Player)
	if not Root or not Root.Parent then
		State.Root = nil
		State.WasJumping = false
		State.Attempt = nil
		return
	end

	if State.Root ~= Root then
		State.Root = Root
		State.WasJumping = false
		State.Attempt = nil
	end

	if IsJumping and not State.Attempt then
		State.Attempt = FindAttempt(State, Root, JumpStartedAt, ExpectedAirSeconds, Now)
	end
	UpdateAttempt(Player, State, Root, IsJumping, Now)
	State.WasJumping = IsJumping
end

local function Update(DeltaTime: number): ()
	SampleElapsed += DeltaTime
	if SampleElapsed < ObstacleConfig.SampleIntervalSeconds then
		return
	end
	SampleElapsed %= ObstacleConfig.SampleIntervalSeconds

	local Now: number = os.clock()
	for Player: Player, State: PlayerState in PlayerStates do
		UpdatePlayer(Player, State, Now)
	end
end

function ObstacleService.Init(): ()
	if ServiceTrove then
		return
	end

	local RuntimeTrove: any = Trove.new()
	ServiceTrove = RuntimeTrove
	RuntimeTrove:Connect(Framework.RuntimeEvents.PlayerAdded, AddPlayer)
	RuntimeTrove:Connect(Framework.RuntimeEvents.PlayerRemoving, RemovePlayer)
	RuntimeTrove:Connect(CollectionService:GetInstanceAddedSignal(ObstacleConfig.Tag), AddObstacle)
	RuntimeTrove:Connect(CollectionService:GetInstanceRemovedSignal(ObstacleConfig.Tag), RemoveObstacle)
	RuntimeTrove:Connect(RunService.Heartbeat, Update)

	for _Index: number, Player: Player in Players:GetPlayers() do
		AddPlayer(Player)
	end
	for _Index: number, Obstacle: Instance in CollectionService:GetTagged(ObstacleConfig.Tag) do
		AddObstacle(Obstacle)
	end
end

function ObstacleService.Destroy(): ()
	if not ServiceTrove then
		return
	end

	ServiceTrove:Destroy()
	ServiceTrove = nil
	SampleElapsed = 0
	table.clear(Obstacles)
	table.clear(PlayerStates)
end

return ObstacleService
