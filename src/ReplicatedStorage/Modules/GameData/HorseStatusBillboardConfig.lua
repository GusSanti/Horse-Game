local HorseStatusBillboardConfig = {
	-- Toggle this placeholder UI without touching the horse status system.
	Enabled = true,
	RefreshInterval = 0.25,
	MaxDistance = 80,
	StudsOffset = 1.6,
	BillboardSize = Vector2.new(220, 158),
	BackgroundColor = Color3.fromRGB(20, 24, 30),
	BackgroundTransparency = 0.15,
	StrokeColor = Color3.fromRGB(255, 255, 255),
	StrokeTransparency = 0.8,
	TitleColor = Color3.fromRGB(255, 244, 196),
	LabelColor = Color3.fromRGB(201, 209, 220),
	ValueColor = Color3.fromRGB(255, 255, 255),
	ValueSuffix = "%",
	ValueDecimals = 0,
	TitleTextSize = 16,
	StatusTextSize = 14,
}

return HorseStatusBillboardConfig
