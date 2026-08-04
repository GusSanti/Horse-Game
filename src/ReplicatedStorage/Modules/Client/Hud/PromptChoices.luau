--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Libraries: Folder = Modules:WaitForChild("Libraries") :: Folder
local HudAnim: any = require(Libraries:WaitForChild("HudAnim"))
local TweenUtils: any = require(Libraries:WaitForChild("HudAnim"):WaitForChild("Utils"))
local Trove: any = require(Libraries:WaitForChild("Trove"))

export type Choice = {
	Id: string,
	Text: string,
	Activate: () -> (),
}

export type PromptChoices = {
	_PlayerGui: PlayerGui,
	_Session: any?,
	_Prompt: ProximityPrompt?,
	Open: (self: PromptChoices, Prompt: ProximityPrompt, Choices: { Choice }) -> (),
	Close: (self: PromptChoices, Immediate: boolean?) -> (),
	Destroy: (self: PromptChoices) -> (),
}

local PANEL_WIDTH: number = 218
local CHOICE_HEIGHT: number = 42
local CHOICE_GAP: number = 7
local PANEL_PADDING: number = 8
local OPEN_DURATION: number = 0.24
local CLOSE_DURATION: number = 0.12
local OPEN_SCALE: number = 0.82
local CORNER_RADIUS: number = 7
local PANEL_COLOR: Color3 = Color3.fromRGB(24, 24, 24)
local BUTTON_COLOR: Color3 = Color3.fromRGB(38, 38, 38)
local STROKE_COLOR: Color3 = Color3.fromRGB(0, 0, 0)

local PromptChoices = {}
PromptChoices.__index = PromptChoices

local function AddCorner(Parent: Instance, Radius: number): UICorner
	local Corner: UICorner = Instance.new("UICorner")
	Corner.CornerRadius = UDim.new(0, Radius)
	Corner.Parent = Parent
	return Corner
end

local function AddStroke(Parent: Instance, Thickness: number, Transparency: number): UIStroke
	local Stroke: UIStroke = Instance.new("UIStroke")
	Stroke.Color = STROKE_COLOR
	Stroke.Thickness = Thickness
	Stroke.Transparency = Transparency
	Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Stroke.Parent = Parent
	return Stroke
end

local function ResolveAdornee(Prompt: ProximityPrompt): Instance?
	local Parent: Instance? = Prompt.Parent
	if Parent and (Parent:IsA("Attachment") or Parent:IsA("BasePart")) then
		return Parent
	end
	return nil
end

local function BuildChoice(ButtonParent: Instance, ChoiceValue: Choice, LayoutOrder: number): TextButton
	local Button: TextButton = Instance.new("TextButton")
	Button.Name = ChoiceValue.Id
	Button.AutoButtonColor = false
	Button.BackgroundColor3 = BUTTON_COLOR
	Button.BackgroundTransparency = 0.08
	Button.BorderSizePixel = 0
	Button.Font = Enum.Font.GothamBlack
	Button.LayoutOrder = LayoutOrder
	Button.Size = UDim2.new(1, 0, 0, CHOICE_HEIGHT)
	Button.Text = ChoiceValue.Text
	Button.TextColor3 = Color3.new(1, 1, 1)
	Button.TextScaled = true
	Button.TextStrokeColor3 = STROKE_COLOR
	Button.TextStrokeTransparency = 0
	Button:SetAttribute("UIAnim", true)
	Button.Parent = ButtonParent

	local TextConstraint: UITextSizeConstraint = Instance.new("UITextSizeConstraint")
	TextConstraint.MinTextSize = 13
	TextConstraint.MaxTextSize = 19
	TextConstraint.Parent = Button

	AddCorner(Button, CORNER_RADIUS)
	AddStroke(Button, 2, 0)
	HudAnim.bind(Button)
	return Button
end

function PromptChoices.new(PlayerGuiValue: PlayerGui): PromptChoices
	local Self: PromptChoices = setmetatable({
		_PlayerGui = PlayerGuiValue,
		_Session = nil,
		_Prompt = nil,
	}, PromptChoices) :: any
	return Self
end

function PromptChoices:Close(Immediate: boolean?): ()
	local Session: any = self._Session
	if not Session then
		return
	end

	self._Session = nil
	self._Prompt = nil
	local Billboard: BillboardGui? = Session.Billboard
	local Group: CanvasGroup? = Session.Group
	local Scale: UIScale? = Session.Scale
	if Immediate == true or not Billboard or not Billboard.Parent or not Group or not Scale then
		Session.Scope:Destroy()
		return
	end

	local FadeTween: Tween = TweenUtils.tween(
		Group,
		{ GroupTransparency = 1 },
		CLOSE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	local ScaleTween: Tween = TweenUtils.tween(
		Scale,
		{ Scale = OPEN_SCALE },
		CLOSE_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.In
	)
	Session.Scope:Add(FadeTween)
	Session.Scope:Add(ScaleTween)
	Session.Scope:Connect(ScaleTween.Completed, function(): ()
		Session.Scope:Destroy()
	end)
	FadeTween:Play()
	ScaleTween:Play()
end

function PromptChoices:Open(Prompt: ProximityPrompt, Choices: { Choice }): ()
	if self._Prompt == Prompt and self._Session then
		self:Close(false)
		return
	end
	self:Close(true)

	local Adornee: Instance? = ResolveAdornee(Prompt)
	if not Adornee or #Choices == 0 then
		return
	end

	local Scope: any = Trove.new()
	local Height: number = (PANEL_PADDING * 2) + (#Choices * CHOICE_HEIGHT) + (math.max(#Choices - 1, 0) * CHOICE_GAP)
	local Billboard: BillboardGui = Instance.new("BillboardGui")
	Billboard.Name = "PromptChoices"
	Billboard.Adornee = Adornee
	Billboard.AlwaysOnTop = true
	Billboard.LightInfluence = 0
	Billboard.MaxDistance = Prompt.MaxActivationDistance + 3
	Billboard.Size = UDim2.fromOffset(PANEL_WIDTH, Height)
	Billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.3, 0)
	Billboard.ResetOnSpawn = false
	Billboard.Parent = self._PlayerGui
	Scope:Add(Billboard)

	local Group: CanvasGroup = Instance.new("CanvasGroup")
	Group.Name = "Choices"
	Group.AnchorPoint = Vector2.new(0.5, 0.5)
	Group.BackgroundColor3 = PANEL_COLOR
	Group.BackgroundTransparency = 0.04
	Group.BorderSizePixel = 0
	Group.GroupTransparency = 1
	Group.Position = UDim2.fromScale(0.5, 0.5)
	Group.Size = UDim2.fromScale(1, 1)
	Group.Parent = Billboard
	AddCorner(Group, CORNER_RADIUS + 2)
	AddStroke(Group, 2, 0)

	local Scale: UIScale = Instance.new("UIScale")
	Scale.Scale = OPEN_SCALE
	Scale.Parent = Group

	local Padding: UIPadding = Instance.new("UIPadding")
	Padding.PaddingBottom = UDim.new(0, PANEL_PADDING)
	Padding.PaddingLeft = UDim.new(0, PANEL_PADDING)
	Padding.PaddingRight = UDim.new(0, PANEL_PADDING)
	Padding.PaddingTop = UDim.new(0, PANEL_PADDING)
	Padding.Parent = Group

	local Layout: UIListLayout = Instance.new("UIListLayout")
	Layout.FillDirection = Enum.FillDirection.Vertical
	Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	Layout.Padding = UDim.new(0, CHOICE_GAP)
	Layout.SortOrder = Enum.SortOrder.LayoutOrder
	Layout.VerticalAlignment = Enum.VerticalAlignment.Center
	Layout.Parent = Group

	local Busy: boolean = false
	for Index: number, ChoiceValue: Choice in Choices do
		local Button: TextButton = BuildChoice(Group, ChoiceValue, Index)
		Scope:Connect(Button.Activated, function(): ()
			if Busy then
				return
			end
			Busy = true
			self:Close(false)
			task.spawn(ChoiceValue.Activate)
		end)
	end

	Scope:Add(function(): ()
		HudAnim.unbind_all(Billboard)
	end)
	Scope:Connect(Prompt.PromptHidden, function(): ()
		self:Close(false)
	end)
	Scope:Connect(Prompt.Destroying, function(): ()
		self:Close(true)
	end)
	Scope:Connect(Prompt:GetPropertyChangedSignal("Enabled"), function(): ()
		if not Prompt.Enabled then
			self:Close(false)
		end
	end)

	self._Prompt = Prompt
	self._Session = {
		Scope = Scope,
		Billboard = Billboard,
		Group = Group,
		Scale = Scale,
	}

	local FadeTween: Tween = TweenUtils.tween(
		Group,
		{ GroupTransparency = 0 },
		OPEN_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	local ScaleTween: Tween = TweenUtils.tween(
		Scale,
		{ Scale = 1 },
		OPEN_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)
	Scope:Add(FadeTween)
	Scope:Add(ScaleTween)
	FadeTween:Play()
	ScaleTween:Play()
end

function PromptChoices:Destroy(): ()
	self:Close(true)
end

return PromptChoices
