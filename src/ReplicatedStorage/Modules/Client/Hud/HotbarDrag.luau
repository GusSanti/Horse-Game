--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService: UserInputService = game:GetService("UserInputService")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Libraries: Folder = Modules:WaitForChild("Libraries") :: Folder
local HudAnim: any = require(Libraries:WaitForChild("HudAnim"))
local TweenUtils: any = require(Libraries:WaitForChild("HudAnim"):WaitForChild("Utils"))
local Trove: any = require(Libraries:WaitForChild("Trove"))

export type Options = {
	PlayerGui: PlayerGui,
	CanStart: (() -> boolean)?,
	ResolveTarget: (Position: Vector2, SourceKey: string) -> (string?, GuiObject?),
	OnDrop: (SourceKey: string, TargetKey: string) -> (),
}

type Binding = {
	Key: string,
	Button: GuiButton,
	Slot: GuiObject,
	OnActivate: () -> (),
	SuppressUntil: number,
	Scope: any,
}

type ActiveDrag = {
	Binding: Binding,
	Input: InputObject,
	StartPosition: Vector2,
	Position: Vector2,
	Dragging: boolean,
	TargetKey: string?,
	TargetSlot: GuiObject?,
	TargetStroke: UIStroke?,
	VisualScope: any?,
	Group: CanvasGroup?,
	Scale: UIScale?,
}

export type HotbarDrag = {
	_Options: Options,
	_Scope: any,
	_Active: ActiveDrag?,
	_Update: (self: HotbarDrag, Position: Vector2) -> (),
	_Finish: (self: HotbarDrag, CommitDrop: boolean) -> (),
	Bind: (self: HotbarDrag, Button: GuiButton, Slot: GuiObject, Key: string, OnActivate: () -> ()) -> (() -> ()),
	Cancel: (self: HotbarDrag) -> (),
	Destroy: (self: HotbarDrag) -> (),
}

local DRAG_THRESHOLD: number = 8
local DRAG_SCALE: number = 1.06
local SOURCE_SCALE: number = 0.94
local OPEN_DURATION: number = 0.16
local CLOSE_DURATION: number = 0.12
local DROP_STROKE_NAME: string = "HotbarDropStroke"
local SOURCE_SCALE_NAME: string = "HotbarDragSourceScale"

local HotbarDrag = {}
HotbarDrag.__index = HotbarDrag

local function IsStartInput(Input: InputObject): boolean
	return Input.UserInputType == Enum.UserInputType.MouseButton1
		or Input.UserInputType == Enum.UserInputType.Touch
end

local function IsMatchingMove(Active: ActiveDrag, Input: InputObject): boolean
	if Active.Input.UserInputType == Enum.UserInputType.Touch then
		return Input == Active.Input
	end

	return Input.UserInputType == Enum.UserInputType.MouseMovement
end

local function IsMatchingEnd(Active: ActiveDrag, Input: InputObject): boolean
	if Active.Input.UserInputType == Enum.UserInputType.Touch then
		return Input == Active.Input
	end

	return Input.UserInputType == Enum.UserInputType.MouseButton1
end

local function DisableCloneInput(Root: Instance): ()
	if Root:IsA("GuiButton") then
		Root.Active = false
		Root.Selectable = false
	end

	for _Index: number, Descendant: Instance in Root:GetDescendants() do
		if Descendant:IsA("GuiButton") then
			Descendant.Active = false
			Descendant.Selectable = false
		end
	end
end

local function SetTargetStroke(Active: ActiveDrag, TargetSlot: GuiObject?): ()
	local Scope: any = Active.VisualScope
	if not Scope then
		return
	end

	if Active.TargetStroke then
		Scope:Remove(Active.TargetStroke)
		Active.TargetStroke = nil
	end
	if not TargetSlot then
		return
	end

	local Stroke: UIStroke = Instance.new("UIStroke")
	Stroke.Name = DROP_STROKE_NAME
	Stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	Stroke.Color = Color3.new(1, 1, 1)
	Stroke.LineJoinMode = Enum.LineJoinMode.Round
	Stroke.Thickness = 3
	Stroke.Transparency = 0.12
	Stroke.Parent = TargetSlot
	Scope:Add(Stroke)
	Active.TargetStroke = Stroke

	local ShineTarget: Instance? = if TargetSlot:IsA("GuiButton")
		then TargetSlot
		else TargetSlot:FindFirstChild("HotbarButton")
	if ShineTarget and ShineTarget:IsA("GuiButton") then
		HudAnim.play_shine(ShineTarget)
	end
end

local function CreateVisual(Self: HotbarDrag, Active: ActiveDrag): ()
	local Slot: GuiObject = Active.Binding.Slot
	if not Slot.Parent or Slot.AbsoluteSize.X <= 0 or Slot.AbsoluteSize.Y <= 0 then
		return
	end

	local Scope: any = Trove.new()
	Active.VisualScope = Scope

	local Overlay: ScreenGui = Instance.new("ScreenGui")
	Overlay.Name = "HotbarDragOverlay"
	Overlay.DisplayOrder = 1000
	Overlay.IgnoreGuiInset = true
	Overlay.ResetOnSpawn = false
	Overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	Overlay.Parent = Self._Options.PlayerGui
	Scope:Add(Overlay)

	local Group: CanvasGroup = Instance.new("CanvasGroup")
	Group.Name = "DragVisual"
	Group.AnchorPoint = Vector2.new(0.5, 0.5)
	Group.BackgroundTransparency = 1
	Group.BorderSizePixel = 0
	Group.Position = UDim2.fromOffset(Active.Position.X, Active.Position.Y)
	Group.Size = UDim2.fromOffset(Slot.AbsoluteSize.X, Slot.AbsoluteSize.Y)
	Group.Parent = Overlay
	Active.Group = Group

	local Clone: GuiObject = Slot:Clone() :: GuiObject
	Clone.Name = "Slot"
	Clone.AnchorPoint = Vector2.zero
	Clone.LayoutOrder = 0
	Clone.Position = UDim2.fromScale(0, 0)
	Clone.Size = UDim2.fromScale(1, 1)
	Clone.Visible = true
	Clone.Parent = Group
	DisableCloneInput(Clone)

	local Scale: UIScale = Instance.new("UIScale")
	Scale.Scale = 0.92
	Scale.Parent = Group
	Active.Scale = Scale

	local SourceScale: UIScale = Instance.new("UIScale")
	SourceScale.Name = SOURCE_SCALE_NAME
	SourceScale.Scale = 1
	SourceScale.Parent = Slot
	Scope:Add(SourceScale)

	local OpenTween: Tween = TweenUtils.tween(
		Scale,
		{ Scale = DRAG_SCALE },
		OPEN_DURATION,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)
	local SourceTween: Tween = TweenUtils.tween(
		SourceScale,
		{ Scale = SOURCE_SCALE },
		OPEN_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)
	Scope:Add(OpenTween)
	Scope:Add(SourceTween)
	OpenTween:Play()
	SourceTween:Play()
end

local function CloseVisual(Active: ActiveDrag): ()
	local Scope: any = Active.VisualScope
	local Group: CanvasGroup? = Active.Group
	local Scale: UIScale? = Active.Scale
	Active.VisualScope = nil
	Active.Group = nil
	Active.Scale = nil
	if not Scope then
		return
	end

	if Active.TargetStroke then
		Scope:Remove(Active.TargetStroke)
		Active.TargetStroke = nil
	end
	if not Group or not Group.Parent or not Scale then
		Scope:Destroy()
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
		{ Scale = 0.88 },
		CLOSE_DURATION,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	Scope:Add(FadeTween)
	Scope:Add(ScaleTween)
	Scope:Connect(ScaleTween.Completed, function(): ()
		Scope:Destroy()
	end)
	FadeTween:Play()
	ScaleTween:Play()
end

function HotbarDrag:_Update(Position: Vector2): ()
	local Active: ActiveDrag? = self._Active
	if not Active then
		return
	end

	Active.Position = Position
	if not Active.Dragging then
		if (Position - Active.StartPosition).Magnitude < DRAG_THRESHOLD then
			return
		end
		Active.Dragging = true
		CreateVisual(self, Active)
	end

	if Active.Group then
		Active.Group.Position = UDim2.fromOffset(Position.X, Position.Y)
	end

	local TargetKey: string?, TargetSlot: GuiObject? = self._Options.ResolveTarget(
		Position,
		Active.Binding.Key
	)
	if TargetKey == Active.TargetKey and TargetSlot == Active.TargetSlot then
		return
	end

	Active.TargetKey = TargetKey
	Active.TargetSlot = TargetSlot
	SetTargetStroke(Active, TargetSlot)
end

function HotbarDrag:_Finish(CommitDrop: boolean): ()
	local Active: ActiveDrag? = self._Active
	if not Active then
		return
	end

	self._Active = nil
	local DropTargetKey: string? = nil
	if Active.Dragging then
		Active.Binding.SuppressUntil = os.clock() + 0.25
		if CommitDrop and Active.TargetKey and Active.TargetKey ~= Active.Binding.Key then
			DropTargetKey = Active.TargetKey
		end
	end

	CloseVisual(Active)
	if DropTargetKey then
		self._Options.OnDrop(Active.Binding.Key, DropTargetKey)
	end
end

function HotbarDrag.new(OptionsValue: Options): HotbarDrag
	local Self: HotbarDrag = setmetatable({
		_Options = OptionsValue,
		_Scope = Trove.new(),
		_Active = nil,
	}, HotbarDrag) :: any

	Self._Scope:Connect(UserInputService.InputChanged, function(Input: InputObject): ()
		local Active: ActiveDrag? = Self._Active
		if Active and IsMatchingMove(Active, Input) then
			Self:_Update(Vector2.new(Input.Position.X, Input.Position.Y))
		end
	end)
	Self._Scope:Connect(UserInputService.InputEnded, function(Input: InputObject): ()
		local Active: ActiveDrag? = Self._Active
		if Active and IsMatchingEnd(Active, Input) then
			if Active.Input.UserInputType == Enum.UserInputType.Touch then
				Self:_Update(Vector2.new(Input.Position.X, Input.Position.Y))
			end
			Self:_Finish(true)
		end
	end)

	return Self
end

function HotbarDrag:Bind(
	Button: GuiButton,
	Slot: GuiObject,
	Key: string,
	OnActivate: () -> ()
): () -> ()
	local Scope: any = Trove.new()
	local Binding: Binding = {
		Key = Key,
		Button = Button,
		Slot = Slot,
		OnActivate = OnActivate,
		SuppressUntil = 0,
		Scope = Scope,
	}

	Scope:Connect(Button.InputBegan, function(Input: InputObject): ()
		if not IsStartInput(Input) or self._Active then
			return
		end
		if self._Options.CanStart and not self._Options.CanStart() then
			return
		end

		local Position: Vector2 = Vector2.new(Input.Position.X, Input.Position.Y)
		self._Active = {
			Binding = Binding,
			Input = Input,
			StartPosition = Position,
			Position = Position,
			Dragging = false,
			TargetKey = nil,
			TargetSlot = nil,
			TargetStroke = nil,
			VisualScope = nil,
			Group = nil,
			Scale = nil,
		}
	end)
	Scope:Connect(Button.Activated, function(): ()
		local Active: ActiveDrag? = self._Active
		if (Active and Active.Binding == Binding and Active.Dragging) or os.clock() < Binding.SuppressUntil then
			return
		end
		OnActivate()
	end)
	Scope:Add(function(): ()
		local Active: ActiveDrag? = self._Active
		if Active and Active.Binding == Binding then
			self:_Finish(false)
		end
	end)

	return function(): ()
		Scope:Destroy()
	end
end

function HotbarDrag:Cancel(): ()
	self:_Finish(false)
end

function HotbarDrag:Destroy(): ()
	self:Cancel()
	self._Scope:Destroy()
end

return HotbarDrag
