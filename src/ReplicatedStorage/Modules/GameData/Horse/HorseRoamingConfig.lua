local HorseRoamingConfig = {
	FolderName = "RoamingHorses",
	RoamingAttribute = "IsHorseRoaming",
	FreeAttribute = "IsHorseFree",
	BehaviorAttribute = "HorseRoamingBehavior",
	FreeHorsePartName = "FreeHorse",
	FreePromptName = "FreeHorsePrompt",
	FreePromptActionText = "Release Horse",
	ReturnPromptActionText = "Return to Stable",
	FreePromptObjectText = "Your Horse",
	FreePromptHoldDuration = 1,
	FreePromptMaxActivationDistance = 12,
	FreePromptKeyboardKeyCode = Enum.KeyCode.H,

	-- Released horses always wander around the owner's plot spawn. When a rider
	-- dismounts outside this radius, the horse is placed in a valid point inside it.
	MaxDistanceFromPlayerSpawn = 52,
	FarReleaseTeleportMinRadius = 12,
	FarReleaseTeleportMaxRadius = 38,
	MinWanderDistance = 8,
	MaxWanderDistance = 22,
	ArrivalDistance = 0.8,
	WalkSpeed = 6.5,
	TurnSpeedDegrees = 95,

	IdleDuration = NumberRange.new(2.5, 6),
	LookPauseDuration = NumberRange.new(0.6, 1.4),
	LookAngleDegrees = NumberRange.new(22, 55),
	GrazeDuration = NumberRange.new(4, 7),
	GrazeInterval = NumberRange.new(13, 24),

	-- Happiness is intentionally noticeable while the horse is free. Hunger is
	-- restored only during grazing, in small amounts that never overflow its max.
	HappinessPerSecond = 1,
	HungerPerGraze = 3,
	NeedUpdateInterval = 1,

	PathAgentRadius = 3,
	PathAgentHeight = 6,
	PathWaypointSpacing = 5,
}

return HorseRoamingConfig
