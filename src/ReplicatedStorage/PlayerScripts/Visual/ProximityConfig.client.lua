local ReplicatedFirst = game:GetService("ReplicatedFirst")
local Packages = ReplicatedFirst:WaitForChild("Packages")
local ExpressivePrompts = require(Packages:WaitForChild("ExpressivePrompts"))

ExpressivePrompts.Config.BackgroundTransparency.Value = 0.3
ExpressivePrompts.Config.BackgroundColor.Value = Color3.fromRGB(15, 15, 25)
ExpressivePrompts.Config.TextColor.Value = Color3.fromRGB(255, 255, 255)
ExpressivePrompts.Config.SubTextColor.Value = Color3.fromRGB(150, 150, 170)
ExpressivePrompts.Config.CornerRadius.Value = 24

ExpressivePrompts.Config.MainSizeSpringSpeed.Value = 35
ExpressivePrompts.Config.MainSizeSpringDampening.Value = 0.35
ExpressivePrompts.Config.MainRotationSpringSpeed.Value = 45
ExpressivePrompts.Config.MainRotationSpringDampening.Value = 0.25
ExpressivePrompts.Config.MainRotationStrength.Value = 15

ExpressivePrompts.Config.AspectRatioSpringSpeed.Value = 30
ExpressivePrompts.Config.AspectRatioSpringDampening.Value = 0.4

ExpressivePrompts.Config.ProgressBarYScale.Value = 0.15
ExpressivePrompts.Config.ProgressBarColor.Value = Color3.fromRGB(255, 255, 255)
ExpressivePrompts.Config.ProgressBarTransparency.Value = 0.15

ExpressivePrompts.Config.GuiOffsetSpringSpeed.Value = 25
ExpressivePrompts.Config.GuiOffsetSpringDampening.Value = 0.4

ExpressivePrompts.Init()