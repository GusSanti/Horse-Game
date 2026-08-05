--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))

local FONT_FACE: Font = Font.fromEnum(Enum.Font.GothamBlack)
local ICON_ATTRIBUTE: string = "IsTextIcon"
local IGNORE_ATTRIBUTE: string = "IgnoreOutlinedText"
local OUTLINE_NAME: string = "TextOutline"
local THICKNESS_ATTRIBUTE: string = "TextOutlineThickness"
local TRANSPARENCY_ATTRIBUTE: string = "TextOutlineTransparency"

type StyledText = TextLabel | TextButton | TextBox
type TextState = {
	OriginalFontFace: Font,
	OriginalStrokeColor: Color3,
	OriginalStrokeTransparency: number,
	OriginalOutlineColor: Color3,
	OriginalOutlineThickness: number,
	OriginalOutlineTransparency: number,
	OriginalOutlineEnabled: boolean,
	Outline: UIStroke,
	Trove: any,
}

local States: { [StyledText]: TextState } = setmetatable({}, { __mode = "k" }) :: any

local OutlinedText = {
	IconAttribute = ICON_ATTRIBUTE,
	IgnoreAttribute = IGNORE_ATTRIBUTE,
}

local function IsStyledText(InstanceValue: Instance): boolean
	return InstanceValue:IsA("TextLabel") or InstanceValue:IsA("TextButton") or InstanceValue:IsA("TextBox")
end

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

local function IsIgnored(TextObject: StyledText): boolean
	return HasTrueAttribute(TextObject, IGNORE_ATTRIBUTE) or HasTrueAttribute(TextObject, ICON_ATTRIBUTE)
end

local function GetNumberAttribute(InstanceValue: Instance, AttributeName: string): number?
	local Value: any = InstanceValue:GetAttribute(AttributeName)
	if type(Value) == "number" then
		return Value
	end
	return nil
end

local function ResolveThickness(TextObject: StyledText): number
	local Override: number? = GetNumberAttribute(TextObject, THICKNESS_ATTRIBUTE)
	if Override then
		return math.clamp(Override, 0, 8)
	end

	local ReferenceSize: number = TextObject.TextSize
	if TextObject.TextScaled and TextObject.AbsoluteSize.Y > 0 then
		ReferenceSize = math.min(48, math.max(12, TextObject.AbsoluteSize.Y * 0.48))
	end

	return math.clamp(ReferenceSize * 0.075, 1, 3.5)
end

local function ResolveTransparency(TextObject: StyledText): number
	local Override: number? = GetNumberAttribute(TextObject, TRANSPARENCY_ATTRIBUTE)
	if Override then
		return math.clamp(Override, 0, 1)
	end
	return 0.05
end

local function ApplyVisual(TextObject: StyledText, State: TextState): ()
	if IsIgnored(TextObject) then
		if TextObject.FontFace ~= State.OriginalFontFace then
			TextObject.FontFace = State.OriginalFontFace
		end
		TextObject.TextStrokeColor3 = State.OriginalStrokeColor
		TextObject.TextStrokeTransparency = State.OriginalStrokeTransparency
		State.Outline.Enabled = false
		return
	end

	if TextObject.FontFace ~= FONT_FACE then
		TextObject.FontFace = FONT_FACE
	end
	TextObject.TextStrokeTransparency = 1
	State.Outline.Enabled = true
	State.Outline.Color = Color3.new(0, 0, 0)
	State.Outline.Thickness = ResolveThickness(TextObject)
	State.Outline.Transparency = ResolveTransparency(TextObject)
end

local function Restore(TextObject: StyledText, State: TextState): ()
	pcall(function(): ()
		TextObject.FontFace = State.OriginalFontFace
		TextObject.TextStrokeColor3 = State.OriginalStrokeColor
		TextObject.TextStrokeTransparency = State.OriginalStrokeTransparency
		State.Outline.Color = State.OriginalOutlineColor
		State.Outline.Thickness = State.OriginalOutlineThickness
		State.Outline.Transparency = State.OriginalOutlineTransparency
		State.Outline.Enabled = State.OriginalOutlineEnabled
	end)
end

function OutlinedText.bind(InstanceValue: Instance): ()
	if not IsStyledText(InstanceValue) then
		return
	end

	local TextObject: StyledText = InstanceValue :: StyledText
	local ExistingState: TextState? = States[TextObject]
	if ExistingState then
		ApplyVisual(TextObject, ExistingState)
		return
	end

	if IsIgnored(TextObject) then
		return
	end

	local TextTrove: any = Trove.new()
	local Outline: UIStroke? = TextObject:FindFirstChild(OUTLINE_NAME) :: UIStroke?
	if not Outline or not Outline:IsA("UIStroke") then
		Outline = TextObject:FindFirstChildWhichIsA("UIStroke")
	end
	if not Outline then
		Outline = Instance.new("UIStroke")
		Outline.Name = OUTLINE_NAME
		Outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		Outline.LineJoinMode = Enum.LineJoinMode.Round
		Outline.Parent = TextObject
		TextTrove:Add(Outline)
	end
	Outline = Outline :: UIStroke
	Outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	Outline.LineJoinMode = Enum.LineJoinMode.Round

	local State: TextState = {
		OriginalFontFace = TextObject.FontFace,
		OriginalStrokeColor = TextObject.TextStrokeColor3,
		OriginalStrokeTransparency = TextObject.TextStrokeTransparency,
		OriginalOutlineColor = Outline.Color,
		OriginalOutlineThickness = Outline.Thickness,
		OriginalOutlineTransparency = Outline.Transparency,
		OriginalOutlineEnabled = Outline.Enabled,
		Outline = Outline,
		Trove = TextTrove,
	}
	States[TextObject] = State

	local function Refresh(): ()
		if States[TextObject] == State and TextObject.Parent then
			ApplyVisual(TextObject, State)
		end
	end

	TextTrove:Connect(TextObject:GetPropertyChangedSignal("TextSize"), Refresh)
	TextTrove:Connect(TextObject:GetPropertyChangedSignal("TextScaled"), Refresh)
	TextTrove:Connect(TextObject:GetPropertyChangedSignal("AbsoluteSize"), Refresh)
	TextTrove:Connect(TextObject:GetPropertyChangedSignal("FontFace"), Refresh)
	TextTrove:Connect(TextObject:GetAttributeChangedSignal(ICON_ATTRIBUTE), Refresh)
	TextTrove:Connect(TextObject:GetAttributeChangedSignal(IGNORE_ATTRIBUTE), Refresh)
	TextTrove:Connect(TextObject:GetAttributeChangedSignal(THICKNESS_ATTRIBUTE), Refresh)
	TextTrove:Connect(TextObject:GetAttributeChangedSignal(TRANSPARENCY_ATTRIBUTE), Refresh)
	TextTrove:Connect(TextObject.AncestryChanged, function(_Child: Instance, Parent: Instance?): ()
		if Parent or States[TextObject] ~= State then
			return
		end

		States[TextObject] = nil
		Restore(TextObject, State)
		TextTrove:Destroy()
	end)

	ApplyVisual(TextObject, State)
end

function OutlinedText.unbind(InstanceValue: Instance): ()
	if not IsStyledText(InstanceValue) then
		return
	end

	local TextObject: StyledText = InstanceValue :: StyledText
	local State: TextState? = States[TextObject]
	if not State then
		return
	end

	States[TextObject] = nil
	Restore(TextObject, State)
	State.Trove:Destroy()
end

function OutlinedText.bind_all(Root: Instance): ()
	OutlinedText.bind(Root)
	for _Index: number, Descendant: Instance in Root:GetDescendants() do
		OutlinedText.bind(Descendant)
	end
end

function OutlinedText.unbind_all(Root: Instance): ()
	OutlinedText.unbind(Root)
	for _Index: number, Descendant: Instance in Root:GetDescendants() do
		OutlinedText.unbind(Descendant)
	end
end

function OutlinedText.destroy(): ()
	local BoundText: { StyledText } = {}
	for TextObject: StyledText in States do
		table.insert(BoundText, TextObject)
	end

	for _Index: number, TextObject: StyledText in BoundText do
		OutlinedText.unbind(TextObject)
	end
end

return OutlinedText
