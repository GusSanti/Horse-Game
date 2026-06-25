------------------//SERVICES

------------------//VARIABLES
local SoapCleaningDictionary = {
	ActionName = "SoapCleaningMode",
	InstructionText = "Segure e arraste o mouse no cavalo",
	CompleteText = "Lado limpo",
	FinishingText = "Cavalo limpo",
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
		Right = "Lado direito",
		Front = "Frente",
		Left = "Lado esquerdo",
		Back = "Traseira",
		Top = "Parte de cima",
	},
	StageProgressGoal = 1,
	SideThreshold = 0.12,
	MinimumScrubDistance = 0.05,
	ProgressGainPerStud = 1.45,
	MaximumProgressStep = 0.14,
	BubbleSpawnDistance = 0.14,
	BubbleCountMin = 1,
	BubbleCountMax = 2,
	BubbleSpread = 0.42,
	BubbleNormalOffset = 0.12,
	BubbleSizeMin = 0.9,
	BubbleSizeMax = 1.2,
	BubbleLifetime = 0.8,
	CameraPadding = 4.6,
	CameraHeightRatio = 0.18,
	CameraDepthRatio = 0.15,
	CameraLerpSpeed = 9,
	TopCameraHeightMultiplier = 1.25,
	TopCameraSideRatio = 0.3,
	ProgressStudsOffset = 2.6,
	ProgressBarWidth = 208,
	ProgressBarHeight = 14,
	FinishDelay = 0.2,
	EffectsFolderName = "SoapEffects",
	AssetsFolderName = "Assets",
	ObjectsFolderName = "Objects",
	BubbleObjectName = "Bubble",
}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
return SoapCleaningDictionary
