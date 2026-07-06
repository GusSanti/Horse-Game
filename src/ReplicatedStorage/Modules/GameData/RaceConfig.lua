local RunService = game:GetService("RunService")

local isStudio = RunService:IsStudio()

local RaceConfig = {
	InviteInterval = isStudio and 60 or 300,
	InitialInviteDelay = isStudio and 10 or 300,
	InviteDuration = 20,
	RaceDistance = 440,
	SegmentLength = 30,
	BaseSpeed = 24.5,
	MinSpeed = 19,
	MaxSpeed = 31,
	SegmentVariance = 3.8,
	RankBiasStep = 0.55,
	CatchupBonusPerStud = 0.035,
	MaxCatchupBonus = 3.25,
	AffinityScale = 4.5,
	SprintScale = 0.22,
	AccelerationScale = 2.4,
	StaminaScale = 0.045,
	FinishKick = 1.2,
	CameraSpeed = 24.25,
	StatusBroadcastInterval = 0.15,
	ResultDuration = 6,
	IntroTagDuration = 3.5,
	WinnerReward = 125,
	MaxParticipants = 8,
}

return RaceConfig
