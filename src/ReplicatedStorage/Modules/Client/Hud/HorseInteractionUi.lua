local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

local HorseInteractionUi = {}

local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"

local CONFIRMATION_FRAME_NAMES = { "ConfirmationFR" }
local DIALOGUE_FRAME_NAMES = { "DialogueFR" }
local TASKS_FRAME_NAMES = { "TasksFR" }
local FEEDING_FRAME_NAMES = { "FeedingFR" }

local DIALOGUE_TITLE_NAMES = { "DialogueNameTX" }
local DIALOGUE_TITLE_SHADOW_NAMES = { "DialogueNameShadowTX" }
local DIALOGUE_DETAILS_NAMES = { "DetailsTX" }
local ACCEPT_BUTTON_NAMES = { "Accept" }
local DENY_BUTTON_NAMES = { "Deny" }

local FEEDING_TEXT_NAMES = { "FeedingHorseTX" }
local FEEDING_TEXT_SHADOW_NAMES = { "FeedingHorseShadowTX" }
local TIMER_TEXT_NAMES = { "TimerTX" }
local TIMER_TEXT_SHADOW_NAMES = { "TimerShadowTX" }

local BAR_NAMES = { "BarBG" }

local STAT_LABELS = {
	Hunger = "Hunger",
	Thirst = "Thirst",
	Happiness = "Happiness",
	Health = "Health",
	Cleanliness = "Cleanliness",
}

local cachedRefs = nil
local buttonConnections = {}

local function normalize_key(value: string?): string?
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function matches_alias(instance: Instance, aliases: {string}): boolean
	local normalizedName = normalize_key(instance.Name)
	if not normalizedName then
		return false
	end

	for _, alias in ipairs(aliases) do
		if normalize_key(alias) == normalizedName then
			return true
		end
	end

	return false
end

local function disconnect_buttons(): ()
	for _, connection in ipairs(buttonConnections) do
		connection:Disconnect()
	end

	table.clear(buttonConnections)
end

local function find_named_instance(root: Instance?, aliases: {string}, className: string?, recursive: boolean?): Instance?
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if matches_alias(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	if recursive == false then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if matches_alias(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function find_text_label(root: Instance?, aliases: {string}): TextLabel?
	local instance = find_named_instance(root, aliases, "TextLabel")
	if instance then
		return instance :: TextLabel
	end

	return nil
end

local function find_gui_button(root: Instance?, aliases: {string}): GuiButton?
	local instance = find_named_instance(root, aliases, "GuiButton")
	if instance then
		return instance :: GuiButton
	end

	return nil
end

local function find_gui_object(root: Instance?, aliases: {string}, recursive: boolean?): GuiObject?
	local instance = find_named_instance(root, aliases, "GuiObject", recursive)
	if instance then
		return instance :: GuiObject
	end

	return nil
end

local function get_player_gui(): PlayerGui?
	return localPlayer:FindFirstChildOfClass("PlayerGui")
end

local function get_mainframe_root(): Instance?
	local playerGui = get_player_gui()
	if not playerGui then
		return nil
	end

	local mainUi = playerGui:FindFirstChild(MAIN_UI_NAME) or playerGui:FindFirstChild(MAIN_UI_NAME, true)
	if not mainUi then
		return nil
	end

	return mainUi:FindFirstChild(MAINFRAME_NAME) or mainUi:FindFirstChild(MAINFRAME_NAME, true)
end

local function find_progress_gradient(root: Instance?): UIGradient?
	if not root then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("UIGradient") then
			return descendant
		end
	end

	return nil
end

local function find_bar_fill(root: Instance?): GuiObject?
	if not root then
		return nil
	end

	local fallback = nil

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("GuiObject") and matches_alias(descendant, BAR_NAMES) then
			if descendant:FindFirstChildWhichIsA("UIGradient", true) then
				return descendant
			end

			fallback = fallback or descendant
		end
	end

	return fallback
end

local function get_refs()
	local mainframe = get_mainframe_root()
	if not mainframe then
		cachedRefs = nil
		return nil
	end

	local dialogue = find_gui_object(mainframe, DIALOGUE_FRAME_NAMES, true)
	local tasks = find_gui_object(mainframe, TASKS_FRAME_NAMES, true)
	local feeding = find_gui_object(tasks or mainframe, FEEDING_FRAME_NAMES, true)

	cachedRefs = {
		Dialogue = dialogue,
		Tasks = tasks,
		Feeding = feeding,
		DialogueTitle = find_text_label(dialogue, DIALOGUE_TITLE_NAMES),
		DialogueTitleShadow = find_text_label(dialogue, DIALOGUE_TITLE_SHADOW_NAMES),
		DialogueDetails = find_text_label(dialogue, DIALOGUE_DETAILS_NAMES),
		AcceptButton = find_gui_button(dialogue, ACCEPT_BUTTON_NAMES),
		DenyButton = find_gui_button(dialogue, DENY_BUTTON_NAMES),
		FeedingText = find_text_label(feeding, FEEDING_TEXT_NAMES),
		FeedingTextShadow = find_text_label(feeding, FEEDING_TEXT_SHADOW_NAMES),
		TimerText = find_text_label(feeding, TIMER_TEXT_NAMES),
		TimerTextShadow = find_text_label(feeding, TIMER_TEXT_SHADOW_NAMES),
		ProgressGradient = find_progress_gradient(feeding),
		ProgressBarFill = find_bar_fill(feeding),
	}

	return cachedRefs
end

local function hide_confirmation_root(): ()
	local mainframe = get_mainframe_root()
	if not mainframe then
		return
	end

	local confirmation = find_gui_object(mainframe, CONFIRMATION_FRAME_NAMES, true)
	if confirmation then
		confirmation.Visible = false
	end
end

local function set_visible(guiObject: GuiObject?, isVisible: boolean): ()
	if guiObject then
		guiObject.Visible = isVisible
	end
end

local function set_text_pair(primary: TextLabel?, shadow: TextLabel?, text: string): ()
	if primary then
		primary.Text = text
	end

	if shadow then
		shadow.Text = text
	end
end

local function format_number(value: number): string
	local roundedValue = math.floor((value * 10) + 0.5) / 10
	if roundedValue == math.floor(roundedValue) then
		return tostring(math.floor(roundedValue))
	end

	return ("%.1f"):format(roundedValue)
end

local function format_signed_number(value: number): string
	if value > 0 then
		return ("+%s"):format(format_number(value))
	end

	return format_number(value)
end

local function join_phrases(phrases: {string}): string
	if #phrases == 0 then
		return ""
	end

	if #phrases == 1 then
		return phrases[1]
	end

	if #phrases == 2 then
		return ("%s and %s"):format(phrases[1], phrases[2])
	end

	local finalPhrase = phrases[#phrases]
	local leadingPhrases = table.clone(phrases)
	table.remove(leadingPhrases, #leadingPhrases)

	return ("%s, and %s"):format(table.concat(leadingPhrases, ", "), finalPhrase)
end

local function append_change(positiveChanges: {string}, negativeChanges: {string}, label: string, amount: number?, prefix: string?): ()
	if type(amount) ~= "number" or amount == 0 then
		return
	end

	local text
	if prefix then
		text = ("%s %s"):format(label, prefix)
	else
		text = ("%s by %s"):format(label, format_signed_number(amount))
	end

	if amount > 0 then
		positiveChanges[#positiveChanges + 1] = text
	else
		negativeChanges[#negativeChanges + 1] = text
	end
end

local function append_secondary_adjustments(positiveChanges: {string}, negativeChanges: {string}, adjustments): ()
	if type(adjustments) ~= "table" then
		return
	end

	for needKey, amount in pairs(adjustments) do
		append_change(positiveChanges, negativeChanges, STAT_LABELS[needKey] or tostring(needKey), amount)
	end
end

local function build_improvement_text(itemDefinition): string
	if type(itemDefinition) ~= "table" then
		return "This item improves your horse."
	end

	local effects = itemDefinition.Effects or {}
	local positiveChanges = {}
	local negativeChanges = {}
	local extraSentences = {}

	local needKey = itemDefinition.NeedKey
	local needLabel = STAT_LABELS[needKey]
	if type(needLabel) == "string" and type(effects.NeedGain) == "number" and effects.NeedGain ~= 0 then
		append_change(positiveChanges, negativeChanges, needLabel, effects.NeedGain, ("by up to %s"):format(format_signed_number(effects.NeedGain)))
	end

	if type(effects.CleanlinessGain) == "number" and effects.CleanlinessGain > 0 then
		if effects.CleanlinessGain >= 100 then
			positiveChanges[#positiveChanges + 1] = "Cleanliness to 100%"
		else
			append_change(positiveChanges, negativeChanges, "Cleanliness", effects.CleanlinessGain)
		end
	end

	append_change(positiveChanges, negativeChanges, "Health", effects.HealthGain)
	append_change(positiveChanges, negativeChanges, "Happiness", effects.HappinessGain)
	append_secondary_adjustments(positiveChanges, negativeChanges, effects.SecondaryNeedAdjustments)

	local healthRegen = effects.HealthRegen
	if type(healthRegen) == "table" and type(healthRegen.TotalGain) == "number" and type(healthRegen.DurationMinutes) == "number" then
		extraSentences[#extraSentences + 1] = ("Adds +%s Health over %s min"):format(
			format_number(healthRegen.TotalGain),
			format_number(healthRegen.DurationMinutes)
		)
	end

	local decayBuff = effects.DecayBuff
	if type(decayBuff) == "table" and type(decayBuff.DurationMinutes) == "number" and needLabel then
		extraSentences[#extraSentences + 1] = ("Slows %s decay for %s min"):format(
			needLabel,
			format_number(decayBuff.DurationMinutes)
		)
	end

	if type(effects.OverflowRelief) == "table" and #effects.OverflowRelief > 0 then
		local relievedStats = {}
		for _, need in ipairs(effects.OverflowRelief) do
			relievedStats[#relievedStats + 1] = STAT_LABELS[need] or tostring(need)
		end

		extraSentences[#extraSentences + 1] = ("Relieves extra %s overflow"):format(join_phrases(relievedStats))
	end

	local sentences = {}

	if #positiveChanges > 0 then
		sentences[#sentences + 1] = ("Improves %s."):format(join_phrases(positiveChanges))
	end

	if #negativeChanges > 0 then
		sentences[#sentences + 1] = ("Also changes %s."):format(join_phrases(negativeChanges))
	end

	for _, extraSentence in ipairs(extraSentences) do
		sentences[#sentences + 1] = extraSentence .. "."
	end

	if #sentences == 0 then
		local description = itemDefinition.Description
		if type(description) == "string" and description ~= "" then
			return description
		end

		return "This item helps with horse care."
	end

	return table.concat(sentences, " ")
end

local function build_action_label(itemDefinition, actionText: string?): string
	local resolvedActionText = actionText or itemDefinition.PromptActionText or "Use"
	local itemName = itemDefinition.DisplayName or resolvedActionText
	local normalizedAction = normalize_key(resolvedActionText)

	if normalizedAction == "feed" then
		return ("Feeding %s..."):format(itemName)
	end

	if normalizedAction == "give water" then
		return ("Giving %s..."):format(itemName)
	end

	if normalizedAction == "wash" then
		return "Cleaning your horse..."
	end

	if normalizedAction == "brush" then
		return "Brushing your horse..."
	end

	if normalizedAction == "treat" then
		return ("Applying %s..."):format(itemName)
	end

	return ("%s %s..."):format(resolvedActionText, itemName)
end

local function build_progress_sequence(alpha: number): NumberSequence
	local clampedAlpha = math.clamp(alpha, 0, 1)
	local edgeWidth = 0.015

	if clampedAlpha <= 0 then
		return NumberSequence.new(1)
	end

	if clampedAlpha >= 1 then
		return NumberSequence.new(0)
	end

	local leftEdge = math.max(0, clampedAlpha - edgeWidth)
	local rightEdge = math.min(1, clampedAlpha + edgeWidth)

	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(leftEdge, 0),
		NumberSequenceKeypoint.new(rightEdge, 1),
		NumberSequenceKeypoint.new(1, 1),
	})
end

local function apply_progress(alpha: number): ()
	local refs = get_refs()
	if not refs then
		return
	end

	if refs.ProgressGradient then
		refs.ProgressGradient.Transparency = build_progress_sequence(alpha)
	end

	if refs.ProgressBarFill and not refs.ProgressGradient then
		refs.ProgressBarFill.Size = UDim2.fromScale(math.clamp(alpha, 0, 1), 1)
	end
end

function HorseInteractionUi.BuildDialogueTitle(itemDefinition): string
	if type(itemDefinition) ~= "table" then
		return "Horse Care"
	end

	return itemDefinition.DisplayName or itemDefinition.PromptActionText or "Horse Care"
end

function HorseInteractionUi.BuildDialogueText(itemDefinition): string
	return build_improvement_text(itemDefinition)
end

function HorseInteractionUi.BuildActionLabel(itemDefinition, actionText: string?): string
	return build_action_label(itemDefinition or {}, actionText)
end

function HorseInteractionUi.ShowDialogue(config): boolean
	local refs = get_refs()
	if not refs or not refs.Dialogue then
		return false
	end

	if not refs.AcceptButton or not refs.DenyButton then
		return false
	end

	disconnect_buttons()
	hide_confirmation_root()

	set_visible(refs.Dialogue, true)
	set_visible(refs.Tasks, false)
	set_visible(refs.Feeding, false)

	set_text_pair(
		refs.DialogueTitle,
		refs.DialogueTitleShadow,
		config.title or "Horse Care"
	)

	if refs.DialogueDetails then
		refs.DialogueDetails.Text = config.details or "This item improves your horse."
	end

	if refs.AcceptButton then
		if refs.AcceptButton:IsA("TextButton") and type(config.acceptText) == "string" and config.acceptText ~= "" then
			refs.AcceptButton.Text = config.acceptText
		end

		buttonConnections[#buttonConnections + 1] = refs.AcceptButton.MouseButton1Click:Connect(function()
			HorseInteractionUi.HideDialogue()
			if type(config.onAccept) == "function" then
				config.onAccept()
			end
		end)
	end

	if refs.DenyButton then
		if refs.DenyButton:IsA("TextButton") and type(config.denyText) == "string" and config.denyText ~= "" then
			refs.DenyButton.Text = config.denyText
		end

		buttonConnections[#buttonConnections + 1] = refs.DenyButton.MouseButton1Click:Connect(function()
			HorseInteractionUi.HideDialogue()
			if type(config.onDeny) == "function" then
				config.onDeny()
			end
		end)
	end

	return true
end

function HorseInteractionUi.HideDialogue(): ()
	local refs = get_refs()
	if not refs then
		return
	end

	disconnect_buttons()
	hide_confirmation_root()
	set_visible(refs.Dialogue, false)
end

function HorseInteractionUi.ShowTask(config): boolean
	local refs = get_refs()
	if not refs or not refs.Feeding then
		return false
	end

	hide_confirmation_root()
	set_visible(refs.Dialogue, false)
	set_visible(refs.Tasks, true)
	set_visible(refs.Feeding, true)

	HorseInteractionUi.UpdateTask(config or {})
	return true
end

function HorseInteractionUi.UpdateTask(config): ()
	local refs = get_refs()
	if not refs then
		return
	end

	local actionText = config.text or "Caring for your horse..."
	local timerText = config.timerText or ""
	local progressAlpha = math.clamp(config.progress or 0, 0, 1)

	set_text_pair(refs.FeedingText, refs.FeedingTextShadow, actionText)
	set_text_pair(refs.TimerText, refs.TimerTextShadow, timerText)
	apply_progress(progressAlpha)
end

function HorseInteractionUi.HideTask(): ()
	local refs = get_refs()
	if not refs then
		return
	end

	hide_confirmation_root()
	set_visible(refs.Feeding, false)
	set_visible(refs.Tasks, false)
	apply_progress(0)
end

return HorseInteractionUi
