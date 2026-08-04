--!strict

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService: TweenService = game:GetService("TweenService")

local LocalPlayer: Player = Players.LocalPlayer
local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local HudAnim: any = require(Modules:WaitForChild("Libraries"):WaitForChild("HudAnim"))
local Network: any = require(Modules:WaitForChild("Network"))
local TaskBarConfig: any = require(
	Modules:WaitForChild("GameData"):WaitForChild("Ui"):WaitForChild("TaskBarConfig")
)
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))

type RatingStyle = {
	Title: string,
	Gradient: ColorSequence,
}

type Indicator = {
	Gui: ScreenGui,
	Root: Frame,
	Title: TextLabel,
	TitleShadow: TextLabel,
	Score: TextLabel,
	TitleGradient: UIGradient,
	ScoreGradient: UIGradient,
	Fill: Frame,
	ProgressGradient: UIGradient,
}

local DISPLAY_SECONDS: number = 1.55
local FILL_SECONDS: number = 0.32
local HORSESHOE_IMAGE: string = "rbxassetid://99923624079256"
local RATING_STYLES: { [string]: RatingStyle } = table.freeze({
	Perfect = table.freeze({
		Title = "Perfect Jump!",
		Gradient = ColorSequence.new(Color3.fromRGB(255, 247, 112), Color3.fromRGB(239, 174, 36)),
	}),
	Good = table.freeze({
		Title = "Good Jump!",
		Gradient = ColorSequence.new(Color3.fromRGB(190, 242, 111), Color3.fromRGB(49, 174, 71)),
	}),
	Bad = table.freeze({
		Title = "Bad Jump!",
		Gradient = ColorSequence.new(Color3.fromRGB(255, 137, 112), Color3.fromRGB(205, 47, 54)),
	}),
})

local RootTrove: any = Trove.new()
local IndicatorState: Indicator? = nil
local HideThread: thread? = nil
local FillTween: Tween? = nil
local FeedbackToken: number = 0

local function Place(GuiObjectValue: GuiObject, Position: UDim2, Size: UDim2, ZIndex: number): ()
	GuiObjectValue.AnchorPoint = Vector2.new(0.5, 0.5)
	GuiObjectValue.Position = Position
	GuiObjectValue.Size = Size
	GuiObjectValue.ZIndex = ZIndex
end

local function EnsureAspect(GuiObjectValue: GuiObject, AspectRatio: number): ()
	local Constraint: UIAspectRatioConstraint? = GuiObjectValue:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not Constraint then
		Constraint = Instance.new("UIAspectRatioConstraint")
		Constraint.Parent = GuiObjectValue
	end

	Constraint.AspectRatio = AspectRatio
	Constraint.AspectType = Enum.AspectType.FitWithinMaxSize
	Constraint.DominantAxis = Enum.DominantAxis.Width
end

local function FindCleaningTemplate(PlayerGui: PlayerGui): Frame?
	local MainUi: Instance? = PlayerGui:FindFirstChild("MainUI")
	local CleaningFrame: Instance? = MainUi and MainUi:FindFirstChild("CleaningFR", true) or nil
	return if CleaningFrame and CleaningFrame:IsA("Frame") then CleaningFrame else nil
end

local function GetRequiredChild<T>(Parent: Instance, Name: string, ClassName: string): T?
	local Child: Instance? = Parent:FindFirstChild(Name)
	return if Child and Child:IsA(ClassName) then (Child :: any) else nil
end

local function EnsureIndicator(): Indicator?
	if IndicatorState and IndicatorState.Gui.Parent then
		return IndicatorState
	end

	local PlayerGui: PlayerGui? = LocalPlayer:FindFirstChildOfClass("PlayerGui")
	if not PlayerGui then
		return nil
	end
	local Source: Frame? = FindCleaningTemplate(PlayerGui)
	if not Source then
		return nil
	end

	local Gui: ScreenGui = Instance.new("ScreenGui")
	Gui.Name = "ObstacleFeedbackGui"
	Gui.DisplayOrder = 25
	Gui.IgnoreGuiInset = true
	Gui.ResetOnSpawn = false
	Gui.ZIndexBehavior = Enum.ZIndexBehavior.Global

	local Root: Frame = Instance.new("Frame")
	Root.Name = "Indicator"
	Root.AnchorPoint = Vector2.new(0.5, 0.5)
	Root.Position = UDim2.fromScale(0.5, 0.2)
	Root.Size = UDim2.fromOffset(240, 77)
	Root.BackgroundTransparency = 1
	Root.Visible = false
	Root:SetAttribute("UIOpen", true)
	Root:SetAttribute("open_anim", "pop")
	Root:SetAttribute("open_fade", true)
	Root:SetAttribute("open_pop_scale", 0.84)
	Root:SetAttribute("open_t", 0.2)
	Root.Parent = Gui

	local Template: Frame = Source:Clone()
	Template.Name = "TaskBar"
	Template.Visible = true
	Template.BackgroundTransparency = 1
	Place(Template, UDim2.fromScale(0.5, 0.5), UDim2.fromScale(1, 1), 1)
	EnsureAspect(Template, TaskBarConfig.FrameAspectRatio)
	Template.Parent = Root

	local Icon: ImageLabel? = GetRequiredChild(Template, "SoapBG", "ImageLabel")
	local Title: TextLabel? = GetRequiredChild(Template, "CleaningHorseTX", "TextLabel")
	local TitleShadow: TextLabel? = GetRequiredChild(Template, "CleaningHorseShadowTX", "TextLabel")
	local Score: TextLabel? = GetRequiredChild(Template, "TimerTX", "TextLabel")
	local Track: ImageLabel? = GetRequiredChild(Template, "BarBG", "ImageLabel")
	local AuthoredFill: ImageLabel? = Track and GetRequiredChild(Track, "BarBG", "ImageLabel") or nil
	if not Icon or not Title or not TitleShadow or not Score or not Track or not AuthoredFill then
		Gui:Destroy()
		return nil
	end

	local ExistingPanel: Instance? = Template:FindFirstChild(TaskBarConfig.PanelName)
	local Panel: ImageLabel
	if ExistingPanel and ExistingPanel:IsA("ImageLabel") then
		Panel = ExistingPanel
	else
		if ExistingPanel then
			ExistingPanel:Destroy()
		end
		Panel = Instance.new("ImageLabel")
		Panel.Name = TaskBarConfig.PanelName
		Panel.BackgroundTransparency = 1
		Panel.BorderSizePixel = 0
		Panel.Parent = Template
	end
	Panel.Image = TaskBarConfig.PanelImage
	Panel.ScaleType = TaskBarConfig.PanelScaleType
	Place(Panel, TaskBarConfig.PanelPosition, TaskBarConfig.PanelSize, 0)

	Icon.Image = HORSESHOE_IMAGE
	Place(Icon, TaskBarConfig.IconPosition, TaskBarConfig.IconSize, 3)
	EnsureAspect(Icon, TaskBarConfig.IconAspectRatio)
	Place(Title, TaskBarConfig.TitlePosition, TaskBarConfig.TitleSize, 3)
	Place(
		TitleShadow,
		UDim2.fromScale(
			TaskBarConfig.TitlePosition.X.Scale + TaskBarConfig.TitleShadowOffset.X,
			TaskBarConfig.TitlePosition.Y.Scale + TaskBarConfig.TitleShadowOffset.Y
		),
		TaskBarConfig.TitleSize,
		2
	)
	Place(Score, TaskBarConfig.TimerPosition, TaskBarConfig.TimerSize, 3)
	Place(Track, TaskBarConfig.BarPosition, TaskBarConfig.BarSize, 3)
	EnsureAspect(Track, TaskBarConfig.BarAspectRatio)
	AuthoredFill.Visible = false

	local FillClip: Frame = Instance.new("Frame")
	FillClip.Name = "BarFillClip"
	FillClip.AnchorPoint = Vector2.new(0.5, 0.5)
	FillClip.Position = UDim2.fromScale(0.5, 0.5)
	FillClip.Size = UDim2.fromScale(0.96, 0.5)
	FillClip.BackgroundTransparency = 1
	FillClip.BorderSizePixel = 0
	FillClip.ClipsDescendants = true
	FillClip.ZIndex = 4
	FillClip.Parent = Track

	local Fill: Frame = Instance.new("Frame")
	Fill.Name = "BarFill"
	Fill.AnchorPoint = Vector2.new(0, 0.5)
	Fill.Position = UDim2.fromScale(0, 0.5)
	Fill.Size = UDim2.fromScale(0, 1)
	Fill.BackgroundColor3 = Color3.new(1, 1, 1)
	Fill.BorderSizePixel = 0
	Fill.ZIndex = 4
	Fill.Parent = FillClip

	local FillCorner: UICorner = Instance.new("UICorner")
	FillCorner.CornerRadius = UDim.new(0.5, 0)
	FillCorner.Parent = Fill

	local TitleGradient: UIGradient? = Title:FindFirstChildOfClass("UIGradient")
	if not TitleGradient then
		TitleGradient = Instance.new("UIGradient")
		TitleGradient.Parent = Title
	end
	TitleGradient.Rotation = 90

	local ScoreGradient: UIGradient? = Score:FindFirstChildOfClass("UIGradient")
	if not ScoreGradient then
		ScoreGradient = Instance.new("UIGradient")
		ScoreGradient.Parent = Score
	end
	ScoreGradient.Rotation = 90
	Title.TextColor3 = Color3.new(1, 1, 1)
	Score.TextColor3 = Color3.new(1, 1, 1)

	local ProgressGradient: UIGradient = Instance.new("UIGradient")
	ProgressGradient.Name = "ProgressGradient"
	ProgressGradient.Rotation = 0
	ProgressGradient.Parent = Fill

	Gui.Parent = PlayerGui
	RootTrove:Add(Gui)
	HudAnim.bind(Root)

	IndicatorState = {
		Gui = Gui,
		Root = Root,
		Title = Title,
		TitleShadow = TitleShadow,
		Score = Score,
		TitleGradient = TitleGradient,
		ScoreGradient = ScoreGradient,
		Fill = Fill,
		ProgressGradient = ProgressGradient,
	}
	return IndicatorState
end

local function CancelHide(): ()
	if not HideThread then
		return
	end

	pcall(task.cancel, HideThread)
	HideThread = nil
end

local function CancelFill(): ()
	if not FillTween then
		return
	end

	FillTween:Cancel()
	FillTween = nil
end

local function ShowFeedback(Rating: string, Score: number): ()
	local Style: RatingStyle? = RATING_STYLES[Rating]
	if not Style then
		return
	end

	local CurrentIndicator: Indicator? = EnsureIndicator()
	if not CurrentIndicator then
		return
	end

	FeedbackToken += 1
	local Token: number = FeedbackToken
	CancelHide()
	CancelFill()
	CurrentIndicator.Title.Text = Style.Title
	CurrentIndicator.TitleShadow.Text = Style.Title
	CurrentIndicator.Score.Text = tostring(Score)
	CurrentIndicator.TitleGradient.Color = Style.Gradient
	CurrentIndicator.ScoreGradient.Color = Style.Gradient
	CurrentIndicator.ProgressGradient.Color = Style.Gradient
	CurrentIndicator.Fill.Size = UDim2.fromScale(0, 1)
	FillTween = TweenService:Create(
		CurrentIndicator.Fill,
		TweenInfo.new(FILL_SECONDS, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(Score / 100, 1) }
	)
	FillTween:Play()
	HudAnim.set_visible(CurrentIndicator.Root, true, true)
	HudAnim.punch(CurrentIndicator.Root, {
		Scale = 1.05,
		InTime = 0.07,
		OutTime = 0.17,
	})

	HideThread = task.delay(DISPLAY_SECONDS, function(): ()
		if FeedbackToken ~= Token or not CurrentIndicator.Root.Parent then
			return
		end
		HideThread = nil
		HudAnim.set_visible(CurrentIndicator.Root, false, true)
	end)
end

RootTrove:Connect(Network.Horse.ObstacleFeedback, function(Payload: any): ()
	if type(Payload) ~= "table" or type(Payload.Rating) ~= "string" or type(Payload.Score) ~= "number" then
		return
	end

	local Score: number = math.clamp(math.floor(Payload.Score + 0.5), 0, 100)
	ShowFeedback(Payload.Rating, Score)
end)

RootTrove:Add(function(): ()
	FeedbackToken += 1
	CancelHide()
	CancelFill()
	if IndicatorState then
		HudAnim.unbind(IndicatorState.Root)
		IndicatorState = nil
	end
end)

script.Destroying:Connect(function(): ()
	RootTrove:Destroy()
end)

script:SetAttribute("RuntimeReady", true)
