------------------//SERVICES

------------------//VARIABLES
local SoapCleaningDictionary = {
	InstructionText = "Hold and drag the mouse over the horse",
	StageInstructionFormat = "Scrub the %s",
	RinseInstructionText = "Move the shower across the horse",
	CompleteText = "All clean",
	FinishingText = "Horse cleaned",
	CancelKeys = {
		Enum.KeyCode.Escape,
		Enum.KeyCode.Q,
	},
	StageOrder = {
		"Right",
		"Front",
		"Left",
		"Back",
		"Top",
	},
	StageLabels = {
		Right = "Right side",
		Front = "Front",
		Left = "Left side",
		Back = "Back",
		Top = "Top",
	},
	StageProgressGoal = 5,
	SideThreshold = 0.12,
	MinimumScrubDistance = 0.05,
	MinimumMouseDragDistance = 1,
	ProgressStepDuration = 0.2,
	ProgressGainPerStep = 1,
	BubbleSpawnDistance = 0.22,
	BubbleCountMin = 1,
	BubbleCountMax = 1,
	BubbleSpread = 0.78,
	BubbleSurfaceOffsetMin = -0.18,
	BubbleSurfaceOffsetMax = -0.08,
	BubbleAppearTime = 0.16,
	BubbleAppearStartScale = 0.18,
	BubbleSizeMin = 0.9,
	BubbleSizeMax = 1.2,
	CameraPadding = 4.6,
	CameraHeightRatio = 0.18,
	CameraDepthRatio = 0.15,
	CameraLerpSpeed = 9,
	TopCameraHeightMultiplier = 1.25,
	TopCameraSideRatio = 0.3,
	RinseTitleText = "Rinse",
	RinseCoverageSegments = 36,
	RinseCoverageWidthRatio = 0.14,
	RinseMinimumCoverageWidth = 0.6,
	RinseBubbleClearWidthRatio = 0.18,
	RinseBubbleMinimumClearWidth = 0.8,
	RinseBubbleFadeTime = 0.12,
	ShowerObjectName = "Shower2",
	ShowerHeightOffset = 1.4,
	ShowerPitchDegrees = -90,
	ShowerFollowLerpSpeed = 18,
	StableBackgroundVisibility = 0.2,
	StableBackgroundMaxDistance = 100,
	FinishDelay = 0.2,
	EffectsFolderName = "SoapEffects",
	MouseHitboxName = "SoapMouseHitbox",
	MouseHitboxPadding = 0.15,
	AssetsFolderName = "Assets",
	ObjectsFolderName = "Objects",
	BubbleObjectName = "Bubble",
}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
return SoapCleaningDictionary
