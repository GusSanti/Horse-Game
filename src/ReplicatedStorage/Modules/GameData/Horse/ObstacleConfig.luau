--!strict

local ObstacleConfig = {
	Tag = "obstacle",
	SampleIntervalSeconds = 1 / 30,
	ApproachDistance = 14,
	MaximumVerticalDistance = 12,
	LateralCaptureMargin = 3,
	MinimumPlanarSpeed = 4,
	LandingClearGraceSeconds = 0.45,
	MaximumAttemptSeconds = 3,
	RepeatCooldownSeconds = 1.25,
	PerfectEdgeClearance = 2.5,
}

return table.freeze(ObstacleConfig)
