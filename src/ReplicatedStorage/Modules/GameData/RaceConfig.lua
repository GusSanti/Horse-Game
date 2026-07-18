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
	RaceConditionMinimumPercent = 50,
	RaceConditionFastChanceAtMinimum = 0.1,
	RaceConditionFastChanceAtMaximum = 0.75,
	RaceConditionFastSegmentBonus = 1.35,
	CameraSpeed = 24.25,
	StatusBroadcastInterval = 0.35,
	ResultDuration = 6,
	IntroTagDuration = 3.5,
	PlacementRewards = {
		[1] = {
			Horseshoes = 125,
			Items = {
				{ ItemId = "oat_crunch", Amount = 2 },
				{ ItemId = "recovery_tonic", Amount = 1 },
			},
		},
		[2] = {
			Horseshoes = 85,
			Items = {
				{ ItemId = "carrot_bunch", Amount = 2 },
				{ ItemId = "cool_stream", Amount = 1 },
			},
		},
		[3] = {
			Horseshoes = 55,
			Items = {
				{ ItemId = "apple_treat", Amount = 2 },
				{ ItemId = "fresh_bucket", Amount = 1 },
			},
		},
	},
	ParticipationReward = {
		Horseshoes = 25,
		Items = {
			{ ItemId = "hay_bale", Amount = 1 },
		},
	},
	MaxParticipants = 8,
}

return RaceConfig
