--!strict

export type Mode = "Idle" | "Gait" | "Trot" | "Gallop" | "Backward" | "Rear"

export type State = {
	Speed: number,
	Mode: Mode,
	ForwardWasDown: boolean,
	LastForwardPressAt: number,
	ForwardReleasedAt: number,
	BoostEndsAt: number,
	RearEndsAt: number,
	RearCooldownEndsAt: number,
}

export type Input = {
	Forward: number,
	Backward: number,
	Sprinting: boolean,
	ObstacleSpeedAlpha: number?,
}

export type Movement = {
	WalkSpeed: number?,
	TrotSpeed: number?,
	CanterSpeed: number?,
	SprintSpeed: number?,
	Acceleration: number?,
}

export type Config = {
	HorseForwardAccelerationSeconds: number?,
	HorseAccelerationBaseStat: number?,
	HorseBrakePerSecond: number?,
	HorseReverseAccelerationPerSecond: number?,
	HorseCoastDragPerSecond: number?,
	HorseDoubleTapWindowSeconds: number?,
	HorseDoubleTapMinReleaseSeconds: number?,
	HorseDoubleTapBoostSeconds: number?,
	HorseSprintAccelerationMultiplier: number?,
	HorseBackwardSpeedMultiplier: number?,
	HorseMovementStopEpsilon: number?,
	HorseRearDurationSeconds: number?,
	HorseRearCooldownSeconds: number?,
	HorseRearMaxStartSpeed: number?,
}

local DEFAULT_WALK_SPEED: number = 14
local DEFAULT_TROT_SPEED: number = 18
local DEFAULT_CANTER_SPEED: number = 22
local DEFAULT_SPRINT_SPEED: number = 26
local DEFAULT_ACCELERATION_STAT: number = 0.8
local INPUT_DEADZONE: number = 0.05

local StateMachine = {}

local function MoveTowards(Current: number, Target: number, MaxDelta: number): number
	if math.abs(Target - Current) <= MaxDelta then
		return Target
	end
	return Current + (if Target > Current then MaxDelta else -MaxDelta)
end

local function ResolveSpeeds(MovementValue: Movement): (number, number, number, number)
	local WalkSpeed: number = math.max(tonumber(MovementValue.WalkSpeed) or DEFAULT_WALK_SPEED, 0)
	local TrotSpeed: number = math.max(tonumber(MovementValue.TrotSpeed) or DEFAULT_TROT_SPEED, WalkSpeed)
	local CanterSpeed: number = math.max(tonumber(MovementValue.CanterSpeed) or DEFAULT_CANTER_SPEED, TrotSpeed)
	local SprintSpeed: number = math.max(tonumber(MovementValue.SprintSpeed) or DEFAULT_SPRINT_SPEED, CanterSpeed)
	return WalkSpeed, TrotSpeed, CanterSpeed, SprintSpeed
end

function StateMachine.Create(): State
	return {
		Speed = 0,
		Mode = "Idle",
		ForwardWasDown = false,
		LastForwardPressAt = -math.huge,
		ForwardReleasedAt = -math.huge,
		BoostEndsAt = 0,
		RearEndsAt = 0,
		RearCooldownEndsAt = 0,
	}
end

function StateMachine.ClassifySpeed(Speed: number, MovementValue: Movement, RearActive: boolean?): Mode
	if RearActive == true then
		return "Rear"
	end

	local WalkSpeed: number, _TrotSpeed: number, CanterSpeed: number = ResolveSpeeds(MovementValue)
	local StopEpsilon: number = 0.25
	if Speed < -StopEpsilon then
		return "Backward"
	end
	if Speed <= StopEpsilon then
		return "Idle"
	end
	if Speed <= WalkSpeed then
		return "Gait"
	end
	if Speed <= CanterSpeed then
		return "Trot"
	end
	return "Gallop"
end

function StateMachine.IsRearActive(StateValue: State, Now: number): boolean
	return StateValue.RearEndsAt > Now
end

function StateMachine.RequestRear(StateValue: State, ConfigValue: Config, Now: number): boolean
	local MaxStartSpeed: number = math.max(tonumber(ConfigValue.HorseRearMaxStartSpeed) or 0.75, 0)
	if math.abs(StateValue.Speed) > MaxStartSpeed or Now < StateValue.RearCooldownEndsAt then
		return false
	end

	local Duration: number = math.max(tonumber(ConfigValue.HorseRearDurationSeconds) or 1.15, 0.1)
	local Cooldown: number = math.max(tonumber(ConfigValue.HorseRearCooldownSeconds) or 1.75, Duration)
	StateValue.Speed = 0
	StateValue.RearEndsAt = Now + Duration
	StateValue.RearCooldownEndsAt = Now + Cooldown
	StateValue.Mode = "Rear"
	return true
end

local function ApplyForwardPress(
	StateValue: State,
	MovementValue: Movement,
	ConfigValue: Config,
	Now: number
): ()
	local DoubleTapWindow: number = math.max(tonumber(ConfigValue.HorseDoubleTapWindowSeconds) or 0.28, 0)
	local MinReleaseSeconds: number = math.max(
		tonumber(ConfigValue.HorseDoubleTapMinReleaseSeconds) or 0.04,
		0
	)
	local ReleaseSeconds: number = Now - StateValue.ForwardReleasedAt
	if Now - StateValue.LastForwardPressAt <= DoubleTapWindow and ReleaseSeconds >= MinReleaseSeconds then
		local _WalkSpeed: number, _TrotSpeed: number, CanterSpeed: number = ResolveSpeeds(MovementValue)
		StateValue.Speed = math.max(StateValue.Speed, CanterSpeed + 0.01)
		StateValue.BoostEndsAt = Now + math.max(tonumber(ConfigValue.HorseDoubleTapBoostSeconds) or 0.4, 0)
	end
	StateValue.LastForwardPressAt = Now
end

local function GetForwardAcceleration(MovementValue: Movement, ConfigValue: Config): number
	local _WalkSpeed: number, _TrotSpeed: number, _CanterSpeed: number, SprintSpeed: number = ResolveSpeeds(MovementValue)
	local AccelerationSeconds: number = math.max(tonumber(ConfigValue.HorseForwardAccelerationSeconds) or 3, 0.1)
	local BaseStat: number = math.max(tonumber(ConfigValue.HorseAccelerationBaseStat) or DEFAULT_ACCELERATION_STAT, 0.01)
	local AccelerationStat: number = math.max(tonumber(MovementValue.Acceleration) or BaseStat, 0)
	return (SprintSpeed / AccelerationSeconds) * math.clamp(AccelerationStat / BaseStat, 0.5, 1.75)
end

function StateMachine.Step(
	StateValue: State,
	InputValue: Input,
	MovementValue: Movement,
	ConfigValue: Config,
	DeltaTime: number,
	Now: number
): State
	local ClampedDelta: number = math.clamp(DeltaTime, 0, 0.1)
	local Forward: number = math.clamp(InputValue.Forward, 0, 1)
	local Backward: number = math.clamp(InputValue.Backward, 0, 1)
	local ForwardDown: boolean = Forward > INPUT_DEADZONE

	if StateMachine.IsRearActive(StateValue, Now) then
		StateValue.Speed = 0
		StateValue.Mode = "Rear"
		StateValue.ForwardWasDown = ForwardDown
		return StateValue
	end

	if not ForwardDown and StateValue.ForwardWasDown then
		StateValue.ForwardReleasedAt = Now
	elseif ForwardDown and not StateValue.ForwardWasDown then
		ApplyForwardPress(StateValue, MovementValue, ConfigValue, Now)
	end
	StateValue.ForwardWasDown = ForwardDown

	local _WalkSpeed: number, _TrotSpeed: number, _CanterSpeed: number, SprintSpeed: number = ResolveSpeeds(MovementValue)
	local Speed: number = StateValue.Speed
	if ForwardDown then
		local Acceleration: number = GetForwardAcceleration(MovementValue, ConfigValue)
		if InputValue.Sprinting or Now < StateValue.BoostEndsAt then
			Acceleration *= math.max(tonumber(ConfigValue.HorseSprintAccelerationMultiplier) or 1.45, 1)
		end
		Speed = MoveTowards(Speed, SprintSpeed, Acceleration * Forward * ClampedDelta)
	elseif Backward > INPUT_DEADZONE then
		if Speed > 0 then
			local BrakeRate: number = math.max(tonumber(ConfigValue.HorseBrakePerSecond) or 20, 0)
			Speed = MoveTowards(Speed, 0, BrakeRate * Backward * ClampedDelta)
		else
			local BackwardMultiplier: number = math.clamp(
				tonumber(ConfigValue.HorseBackwardSpeedMultiplier) or 0.48,
				0,
				1
			)
			local ReverseRate: number = math.max(tonumber(ConfigValue.HorseReverseAccelerationPerSecond) or 8, 0)
			Speed = MoveTowards(Speed, -(SprintSpeed * BackwardMultiplier), ReverseRate * Backward * ClampedDelta)
		end
	else
		local CoastDrag: number = math.max(tonumber(ConfigValue.HorseCoastDragPerSecond) or 0, 0)
		Speed = MoveTowards(Speed, 0, CoastDrag * ClampedDelta)
	end

	local ObstacleSpeedAlpha: number = math.clamp(tonumber(InputValue.ObstacleSpeedAlpha) or 1, 0, 1)
	if Speed > SprintSpeed * ObstacleSpeedAlpha then
		local BrakeRate: number = math.max(tonumber(ConfigValue.HorseBrakePerSecond) or 20, 0)
		Speed = MoveTowards(Speed, SprintSpeed * ObstacleSpeedAlpha, BrakeRate * ClampedDelta)
	end

	local StopEpsilon: number = math.max(tonumber(ConfigValue.HorseMovementStopEpsilon) or 0.01, 0)
	if math.abs(Speed) <= StopEpsilon then
		Speed = 0
	end
	StateValue.Speed = math.clamp(Speed, -(SprintSpeed), SprintSpeed)
	StateValue.Mode = StateMachine.ClassifySpeed(StateValue.Speed, MovementValue, false)
	return StateValue
end

function StateMachine.ReconcileSpeed(
	StateValue: State,
	AuthoritativeSpeed: number,
	Threshold: number,
	BlendAlpha: number
): boolean
	if math.abs(StateValue.Speed - AuthoritativeSpeed) <= math.max(Threshold, 0) then
		return false
	end
	StateValue.Speed += (AuthoritativeSpeed - StateValue.Speed) * math.clamp(BlendAlpha, 0, 1)
	return true
end

return table.freeze(StateMachine)
