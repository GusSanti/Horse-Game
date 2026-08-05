--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))
local TweenUtils: any = require(script.Parent:WaitForChild("Utils"))

local IGNORE_HUD_ANIM_ATTRIBUTE: string = "IgnoreHudAnim"
local IGNORE_SHINE_ATTRIBUTE: string = "IgnoreHoverShine"
local SHINE_ANGLE_ATTRIBUTE: string = "ShineAngle"
local SHINE_DURATION_ATTRIBUTE: string = "ShineDuration"
local SHINE_NAME: string = "HoverShine"
local SHINE_TRANSPARENCY_ATTRIBUTE: string = "ShineTransparency"
local SHINE_WIDTH_ATTRIBUTE: string = "ShineWidth"
local SQUARE_SHINE_ATTRIBUTE: string = "SquareShine"
local SQUARE_RATIO_TOLERANCE: number = 0.2
local DEFAULT_SHINE_WIDTH: number = 0.14
local DEFAULT_SHINE_HEIGHT: number = 1
local DEFAULT_SHINE_ANGLE: number = 12
local DEFAULT_SHINE_DURATION: number = 0.55

type ShineState = {
	AnimationTrove: any,
	Overlay: Frame,
	Shine: Frame,
	Token: number,
	Trove: any,
}

local States: { [GuiButton]: ShineState } = setmetatable({}, { __mode = "k" }) :: any

local HoverShine = {
	IgnoreAttribute = IGNORE_SHINE_ATTRIBUTE,
}

local function HasTrueAttribute(InstanceValue: Instance, AttributeName: string): boolean
	local Current: Instance? = InstanceValue
	while Current do
		if Current:GetAttribute(AttributeName) == true then
			return true
		end
		Current = Current.Parent
	end
	return false
end

local function IsIgnored(Button: GuiButton): boolean
	return HasTrueAttribute(Button, IGNORE_HUD_ANIM_ATTRIBUTE) or HasTrueAttribute(Button, IGNORE_SHINE_ATTRIBUTE)
end

local function IsSquareTarget(Button: GuiButton): boolean
	if Button:GetAttribute(SQUARE_SHINE_ATTRIBUTE) == true then
		return true
	end

	local AbsoluteSize: Vector2 = Button.AbsoluteSize
	local Width: number = AbsoluteSize.X
	local Height: number = AbsoluteSize.Y
	if Width <= 0 or Height <= 0 then
		local Size: UDim2 = Button.Size
		Width = math.max(math.abs(Size.X.Offset), math.abs(Size.X.Scale))
		Height = math.max(math.abs(Size.Y.Offset), math.abs(Size.Y.Scale))
	end

	if Width <= 0 or Height <= 0 then
		return false
	end

	return math.abs(Width - Height) / math.max(Width, Height) <= SQUARE_RATIO_TOLERANCE
end

local function GetNumberAttribute(InstanceValue: Instance, AttributeName: string, Fallback: number): number
	local Value: any = InstanceValue:GetAttribute(AttributeName)
	if type(Value) == "number" then
		return Value
	end
	return Fallback
end

local function IsVisible(InstanceValue: Instance): boolean
	local Current: Instance? = InstanceValue
	while Current do
		if Current:IsA("GuiObject") and not Current.Visible then
			return false
		end
		if Current:IsA("LayerCollector") and not Current.Enabled then
			return false
		end
		Current = Current.Parent
	end
	return InstanceValue.Parent ~= nil
end

local function CreateOverlay(Button: GuiButton, ShineTrove: any): (Frame, Frame)
	local Overlay: Frame = Instance.new("Frame")
	Overlay.Name = SHINE_NAME
	Overlay.Active = false
	Overlay.AnchorPoint = Vector2.zero
	Overlay.BackgroundTransparency = 1
	Overlay.BorderSizePixel = 0
	Overlay.ClipsDescendants = true
	Overlay.Position = UDim2.fromScale(0, 0)
	Overlay.Selectable = false
	Overlay.Size = UDim2.fromScale(1, 1)
	Overlay.Visible = false
	Overlay.ZIndex = Button.ZIndex + 2
	Overlay.Parent = Button
	ShineTrove:Add(Overlay)

	local ButtonCorner: UICorner? = Button:FindFirstChildWhichIsA("UICorner")
	if ButtonCorner then
		local OverlayCorner: UICorner = Instance.new("UICorner")
		OverlayCorner.CornerRadius = ButtonCorner.CornerRadius
		OverlayCorner.Parent = Overlay
	end

	local Shine: Frame = Instance.new("Frame")
	Shine.Name = "Sweep"
	Shine.Active = false
	Shine.AnchorPoint = Vector2.new(0.5, 0.5)
	Shine.BackgroundColor3 = Color3.new(1, 1, 1)
	Shine.BorderSizePixel = 0
	Shine.Position = UDim2.fromScale(-0.22, 0.5)
	Shine.Selectable = false
	Shine.Size = UDim2.fromScale(DEFAULT_SHINE_WIDTH, DEFAULT_SHINE_HEIGHT)
	Shine.ZIndex = Overlay.ZIndex
	Shine.Parent = Overlay

	local Gradient: UIGradient = Instance.new("UIGradient")
	Gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	})
	Gradient.Parent = Shine

	return Overlay, Shine
end

local function ApplyVisual(Button: GuiButton, State: ShineState): ()
	local Width: number = math.clamp(
		GetNumberAttribute(Button, SHINE_WIDTH_ATTRIBUTE, DEFAULT_SHINE_WIDTH),
		0.04,
		0.24
	)
	State.Overlay.ZIndex = Button.ZIndex + 2
	State.Shine.BackgroundTransparency =
		math.clamp(GetNumberAttribute(Button, SHINE_TRANSPARENCY_ATTRIBUTE, 0.72), 0, 1)
	local Gradient: UIGradient? = State.Shine:FindFirstChildWhichIsA("UIGradient")
	State.Shine.Rotation = 0
	if Gradient then
		Gradient.Rotation = GetNumberAttribute(Button, SHINE_ANGLE_ATTRIBUTE, DEFAULT_SHINE_ANGLE)
	end
	State.Shine.Size = UDim2.fromScale(Width, DEFAULT_SHINE_HEIGHT)
	State.Shine.ZIndex = State.Overlay.ZIndex
end

local function Stop(State: ShineState): ()
	State.Token += 1
	State.AnimationTrove:Clean()
	State.Overlay.Visible = false
	State.Shine.Position = UDim2.fromScale(-0.22, 0.5)
end

function HoverShine.play(Button: GuiButton): ()
	local State: ShineState? = States[Button]
	if not State or IsIgnored(Button) or not IsVisible(Button) then
		return
	end

	Stop(State)
	ApplyVisual(Button, State)
	State.Token += 1
	local Token: number = State.Token
	State.Overlay.Visible = true

	local Duration: number = math.clamp(
		GetNumberAttribute(Button, SHINE_DURATION_ATTRIBUTE, DEFAULT_SHINE_DURATION),
		0.16,
		1.5
	)
	local Tween: Tween = TweenUtils.tween(
		State.Shine,
		{ Position = UDim2.fromScale(1.22, 0.5) },
		Duration,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	State.AnimationTrove:Add(function(): ()
		Tween:Cancel()
		Tween:Destroy()
	end)
	State.AnimationTrove:Connect(Tween.Completed, function(): ()
		if States[Button] ~= State or State.Token ~= Token then
			return
		end
		State.Overlay.Visible = false
	end)
	Tween:Play()
end

function HoverShine.bind(InstanceValue: Instance): ()
	if not InstanceValue:IsA("GuiButton") then
		return
	end

	local Button: GuiButton = InstanceValue
	local ExistingState: ShineState? = States[Button]
	if ExistingState then
		ApplyVisual(Button, ExistingState)
		return
	end

	if IsIgnored(Button) or not IsSquareTarget(Button) then
		return
	end

	local ShineTrove: any = Trove.new()
	local AnimationTrove: any = ShineTrove:Extend()
	local Overlay: Frame, Shine: Frame = CreateOverlay(Button, ShineTrove)
	local State: ShineState = {
		AnimationTrove = AnimationTrove,
		Overlay = Overlay,
		Shine = Shine,
		Token = 0,
		Trove = ShineTrove,
	}
	States[Button] = State

	ShineTrove:Connect(Button.MouseEnter, function(): ()
		HoverShine.play(Button)
	end)
	ShineTrove:Connect(Button.SelectionGained, function(): ()
		HoverShine.play(Button)
	end)
	ShineTrove:Connect(Button.Activated, function(): ()
		HoverShine.play(Button)
	end)
	ShineTrove:Connect(Button:GetPropertyChangedSignal("ZIndex"), function(): ()
		if States[Button] == State then
			ApplyVisual(Button, State)
		end
	end)
	ShineTrove:Connect(Button:GetAttributeChangedSignal(IGNORE_SHINE_ATTRIBUTE), function(): ()
		if States[Button] ~= State then
			return
		end
		if IsIgnored(Button) then
			Stop(State)
		else
			ApplyVisual(Button, State)
		end
	end)
	ShineTrove:Connect(Button.AncestryChanged, function(_Child: Instance, Parent: Instance?): ()
		if Parent or States[Button] ~= State then
			return
		end
		States[Button] = nil
		ShineTrove:Destroy()
	end)

	ApplyVisual(Button, State)
end

function HoverShine.unbind(InstanceValue: Instance): ()
	if not InstanceValue:IsA("GuiButton") then
		return
	end

	local Button: GuiButton = InstanceValue
	local State: ShineState? = States[Button]
	if not State then
		return
	end

	States[Button] = nil
	State.Trove:Destroy()
end

function HoverShine.bind_all(Root: Instance): ()
	HoverShine.bind(Root)
	for _Index: number, Descendant: Instance in Root:GetDescendants() do
		HoverShine.bind(Descendant)
	end
end

function HoverShine.unbind_all(Root: Instance): ()
	HoverShine.unbind(Root)
	for _Index: number, Descendant: Instance in Root:GetDescendants() do
		HoverShine.unbind(Descendant)
	end
end

function HoverShine.destroy(): ()
	local BoundButtons: { GuiButton } = {}
	for Button: GuiButton in States do
		table.insert(BoundButtons, Button)
	end

	for _Index: number, Button: GuiButton in BoundButtons do
		HoverShine.unbind(Button)
	end
end

return HoverShine
