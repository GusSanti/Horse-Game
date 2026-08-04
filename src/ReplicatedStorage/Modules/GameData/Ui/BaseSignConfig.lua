local BaseSignConfig = {
	Enabled = true,

	StablesFolderName = "Stables",
	PlayerSpawnName = "PlayerSpawn",

	OwnerUserIdAttribute = "OwnerUserId",
	OwnerNameAttribute = "OwnerName",

	OwnBaseText = "Your Base",

	ScreenGuiName = "BaseSigns",
	BillboardName = "BaseSignBillboard",
	IgnoreAnimationAttribute = "IgnoreHudAnim",

	BillboardSize = UDim2.fromOffset(210, 62),
	StudsOffset = Vector3.new(0, 60, 0),
	MaxDistance = 220,

	PortraitPosition = UDim2.fromScale(0.13, 0.5),
	PortraitSize = UDim2.fromScale(0.2, 0.66),
	PortraitCornerRadius = UDim.new(1, 0),
	ThumbnailType = Enum.ThumbnailType.HeadShot,
	ThumbnailSize = Enum.ThumbnailSize.Size100x100,

	PlaquePosition = UDim2.fromScale(0.58, 0.5),
	PlaqueSize = UDim2.fromScale(0.76, 0.82),

	TextPosition = UDim2.fromScale(0.5, 0.5),
	TextSize = UDim2.fromScale(0.9, 0.52),
	TextShadowOffset = Vector2.new(0.016, 0.028),

	TemplateMainUiName = "MainUI",
	TemplateMainframeName = "MainframeFR",
	TemplatePath = { "HUDFR", "MoneyTabBG" },
	TemplatePortraitName = "CoinBG",
	TemplatePlaqueName = "MoneyBG",
	TemplateTextName = "MoneyTX",
	TemplateTextShadowName = "MoneyShadowTX",
	TemplateDiscardNames = { "AddBT" },
}

return BaseSignConfig
