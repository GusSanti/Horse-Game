local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local modules = ReplicatedStorage:WaitForChild("Modules")
local HudRefs = require(modules:WaitForChild("Client"):WaitForChild("Hud"):WaitForChild("HudRefs"))
local HudAnim = require(modules:WaitForChild("Libraries"):WaitForChild("HudAnim"))
local TaskBarConfig = require(modules:WaitForChild("GameData"):WaitForChild("Ui"):WaitForChild("TaskBarConfig"))

local HorseTaskBar = {}

local DIALOGUE_FRAME_NAMES = { "DialogueFR" }
local CONFIRMATION_FRAME_NAMES = { "ConfirmationFR" }
local TASKS_FRAME_NAMES = { "TasksFR" }
local TIMER_TEXT_NAMES = { "TimerTX" }
local TIMER_TEXT_SHADOW_NAMES = { "TimerShadowTX" }
local BAR_NAMES = { "BarBG" }

local PROGRESS_EDGE_WIDTH = 0.015

local DEFAULT_VARIANT = "Default"
local CLEANING_VARIANT = "Cleaning"

local VARIANTS = {
	[DEFAULT_VARIANT] = {
		FrameNames = { "FeedingFR", "LoadingFR" },
		TextNames = { "FeedingHorseTX" },
		TextShadowNames = { "FeedingHorseShadowTX" },
		IconNames = { "HayBG" },
	},
	[CLEANING_VARIANT] = {
		FrameNames = { "CleaningFR" },
		TextNames = { "CleaningHorseTX" },
		TextShadowNames = { "CleaningHorseShadowTX" },
		IconNames = { "SoapBG" },
	},
}

local cachedRefsByVariant = {}

HorseTaskBar.Variant = table.freeze({
	Default = DEFAULT_VARIANT,
	Cleaning = CLEANING_VARIANT,
})

local function find_bar_fill(root: Instance?): GuiObject?
	if not root then
		return nil
	end

	local fallback = nil

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") and HudRefs.MatchesAlias(descendant, BAR_NAMES) then
			local parent = descendant.Parent
			if parent and HudRefs.MatchesAlias(parent, BAR_NAMES) then
				return descendant
			end

			fallback = fallback or descendant
		end
	end

	return fallback
end

local function ensure_progress_gradient(fill: GuiObject?): UIGradient?
	if not fill then
		return nil
	end

	local gradient = fill:FindFirstChildWhichIsA("UIGradient")
	if not gradient then
		gradient = Instance.new("UIGradient")
		gradient.Name = "ProgressGradient"
		gradient.Parent = fill
	end

	gradient.Rotation = 0
	return gradient
end

local function place(guiObject: GuiObject?, position: UDim2, size: UDim2, zIndex: number): ()
	if not guiObject then
		return
	end

	guiObject.AnchorPoint = Vector2.new(0.5, 0.5)
	guiObject.Position = position
	guiObject.Size = size
	guiObject.ZIndex = zIndex
end

local function preload_images(frame: GuiObject): ()
	local images = {}
	for _, descendant in frame:GetDescendants() do
		if descendant:IsA("ImageLabel") and descendant.Image ~= "" then
			images[#images + 1] = descendant
		end
	end

	if #images == 0 then
		return
	end

	task.spawn(function(): ()
		pcall(function(): ()
			ContentProvider:PreloadAsync(images)
		end)
	end)
end

local function ensure_aspect(guiObject: GuiObject?, aspectRatio: number): ()
	if not guiObject then
		return
	end

	local constraint = guiObject:FindFirstChildOfClass("UIAspectRatioConstraint")
	if not constraint then
		constraint = Instance.new("UIAspectRatioConstraint")
		constraint.Parent = guiObject
	end

	constraint.AspectRatio = aspectRatio
	constraint.AspectType = Enum.AspectType.FitWithinMaxSize
	constraint.DominantAxis = Enum.DominantAxis.Width
end

local function ensure_panel(frame: GuiObject): ()
	local panel = frame:FindFirstChild(TaskBarConfig.PanelName)
	if not panel then
		local createdPanel = Instance.new("ImageLabel")
		createdPanel.Name = TaskBarConfig.PanelName
		createdPanel.BackgroundTransparency = 1
		createdPanel.BorderSizePixel = 0
		createdPanel.Image = TaskBarConfig.PanelImage
		createdPanel.ScaleType = TaskBarConfig.PanelScaleType
		createdPanel.Parent = frame
		panel = createdPanel
	end

	place(panel :: GuiObject, TaskBarConfig.PanelPosition, TaskBarConfig.PanelSize, 0)
end

local function apply_layout(refs, variantConfig): ()
	local frame = refs.Frame
	if frame:GetAttribute(TaskBarConfig.LayoutAppliedAttribute) == true then
		return
	end

	place(frame, TaskBarConfig.FramePosition, TaskBarConfig.FrameSize, 1)
	ensure_aspect(frame, TaskBarConfig.FrameAspectRatio)
	ensure_panel(frame)

	local icon = HudRefs.FindGuiObject(frame, variantConfig.IconNames, true)
	if icon then
		place(icon, TaskBarConfig.IconPosition, TaskBarConfig.IconSize, 3)
		ensure_aspect(icon, TaskBarConfig.IconAspectRatio)
		icon.Visible = true
	end

	place(refs.Text, TaskBarConfig.TitlePosition, TaskBarConfig.TitleSize, 3)
	place(
		refs.TextShadow,
		UDim2.fromScale(
			TaskBarConfig.TitlePosition.X.Scale + TaskBarConfig.TitleShadowOffset.X,
			TaskBarConfig.TitlePosition.Y.Scale + TaskBarConfig.TitleShadowOffset.Y
		),
		TaskBarConfig.TitleSize,
		2
	)
	place(refs.TimerText, TaskBarConfig.TimerPosition, TaskBarConfig.TimerSize, 3)
	place(refs.BarTrack, TaskBarConfig.BarPosition, TaskBarConfig.BarSize, 3)
	ensure_aspect(refs.BarTrack, TaskBarConfig.BarAspectRatio)

	if refs.BarFill then
		refs.BarFill.ZIndex = 4
	end

	preload_images(frame)
	frame:SetAttribute(TaskBarConfig.LayoutAppliedAttribute, true)
end

local function is_refs_alive(refs): boolean
	return refs ~= nil and refs.Frame ~= nil and refs.Frame.Parent ~= nil
end

local function resolve_variant_name(variant: string?): string
	if variant and VARIANTS[variant] then
		return variant
	end

	return DEFAULT_VARIANT
end

local function get_refs(variant: string?)
	local variantName = resolve_variant_name(variant)
	local cachedRefs = cachedRefsByVariant[variantName]
	if is_refs_alive(cachedRefs) then
		return cachedRefs
	end

	local mainframe = HudRefs.GetMainframeRoot()
	if not mainframe then
		cachedRefsByVariant[variantName] = nil
		return nil
	end

	local variantConfig = VARIANTS[variantName]
	local tasks = HudRefs.FindGuiObject(mainframe, TASKS_FRAME_NAMES, true)
	local frame = HudRefs.FindGuiObject(tasks or mainframe, variantConfig.FrameNames, true)
	if not frame then
		cachedRefsByVariant[variantName] = nil
		return nil
	end

	local barFill = find_bar_fill(frame)
	local barTrack = barFill and barFill.Parent
	if barTrack and not barTrack:IsA("GuiObject") then
		barTrack = nil
	end

	local refs = {
		Dialogue = HudRefs.FindGuiObject(mainframe, DIALOGUE_FRAME_NAMES, true),
		Tasks = tasks,
		Frame = frame,
		Text = HudRefs.FindTextLabel(frame, variantConfig.TextNames),
		TextShadow = HudRefs.FindTextLabel(frame, variantConfig.TextShadowNames),
		TimerText = HudRefs.FindTextLabel(frame, TIMER_TEXT_NAMES),
		TimerTextShadow = HudRefs.FindTextLabel(frame, TIMER_TEXT_SHADOW_NAMES),
		BarTrack = barTrack,
		BarFill = barFill,
		ProgressGradient = ensure_progress_gradient(barFill),
	}

	apply_layout(refs, variantConfig)

	cachedRefsByVariant[variantName] = refs
	return refs
end

local function build_progress_sequence(alpha: number): NumberSequence
	local clampedAlpha = math.clamp(alpha, 0, 1)

	if clampedAlpha <= 0 then
		return NumberSequence.new(1)
	end

	if clampedAlpha >= 1 then
		return NumberSequence.new(0)
	end

	local leftEdge = math.max(0, clampedAlpha - PROGRESS_EDGE_WIDTH)
	local rightEdge = math.min(1, clampedAlpha + PROGRESS_EDGE_WIDTH)

	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(leftEdge, 0),
		NumberSequenceKeypoint.new(rightEdge, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function apply_progress(refs, alpha: number): ()
	if not refs then
		return
	end

	if refs.ProgressGradient then
		refs.ProgressGradient.Transparency = build_progress_sequence(alpha)
		return
	end

	if refs.BarFill then
		refs.BarFill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	end
end

local function hide_confirmation_root(): ()
	local mainframe = HudRefs.GetMainframeRoot()
	if not mainframe then
		return
	end

	HudRefs.SetVisible(HudRefs.FindGuiObject(mainframe, CONFIRMATION_FRAME_NAMES, true), false)
end

local function hide_variant(variantName: string): ()
	local refs = get_refs(variantName)
	if not refs then
		return
	end

	HudRefs.SetVisible(refs.Frame, false)
	apply_progress(refs, 0)
end

function HorseTaskBar.HideAllFrames(): ()
	local tasks = nil

	for variantName in VARIANTS do
		hide_variant(variantName)

		local refs = cachedRefsByVariant[variantName]
		tasks = tasks or (refs and refs.Tasks)
	end

	HudRefs.SetVisible(tasks, false)
end

function HorseTaskBar.Show(config): boolean
	config = config or {}

	local refs = get_refs(config.variant)
	if not refs or not refs.Frame then
		return false
	end

	for variantName in VARIANTS do
		if variantName ~= resolve_variant_name(config.variant) then
			hide_variant(variantName)
		end
	end

	local taskLivesInsideDialogue = HudRefs.IsDescendantOf(refs.Tasks, refs.Dialogue)
		or HudRefs.IsDescendantOf(refs.Frame, refs.Dialogue)

	hide_confirmation_root()
	if taskLivesInsideDialogue and refs.Dialogue then
		HudAnim.set_visible(refs.Dialogue, true, false)
	end
	HudRefs.SetVisible(refs.Tasks, true)
	HudRefs.SetVisible(refs.Frame, true)

	HorseTaskBar.Update(config)
	return true
end

function HorseTaskBar.Update(config): ()
	config = config or {}

	local refs = get_refs(config.variant)
	if not refs then
		return
	end

	HudRefs.SetTextPair(refs.Text, refs.TextShadow, config.text or "Caring for your horse...")
	HudRefs.SetTextPair(refs.TimerText, refs.TimerTextShadow, config.timerText or "")
	apply_progress(refs, math.clamp(config.progress or 0, 0, 1))
end

function HorseTaskBar.Hide(config): ()
	config = config or {}

	local refs = get_refs(config.variant)
	if not refs then
		return
	end

	local taskLivesInsideDialogue = HudRefs.IsDescendantOf(refs.Tasks, refs.Dialogue)
		or HudRefs.IsDescendantOf(refs.Frame, refs.Dialogue)

	hide_confirmation_root()
	HorseTaskBar.HideAllFrames()
	if taskLivesInsideDialogue and refs.Dialogue then
		HudAnim.set_visible(refs.Dialogue, false, false)
	end
end

return HorseTaskBar
