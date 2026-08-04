local ReplicatedStorage = game:GetService("ReplicatedStorage")

local hudModules = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Client"):WaitForChild("Hud")
local HorseTaskBar = require(hudModules:WaitForChild("HorseTaskBar"))
local HudRefs = require(hudModules:WaitForChild("HudRefs"))
local Notifications = require(hudModules:WaitForChild("Notifications"))

local HorseInteractionUi = {}

HorseInteractionUi.TaskVariant = HorseTaskBar.Variant

local STAT_LABELS = {
	Hunger = "Hunger",
	Thirst = "Thirst",
	Happiness = "Happiness",
	Health = "Health",
	Cleanliness = "Cleanliness",
}

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
	local normalizedAction = HudRefs.NormalizeKey(resolvedActionText)

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
	config = config or {}
	config.title = config.title or "Horse Care"
	config.details = config.details or "This item improves your horse."

	HorseTaskBar.HideAllFrames()

	return Notifications.ShowDialogue(config)
end

function HorseInteractionUi.HideDialogue(): ()
	Notifications.HideDialogue()
end

function HorseInteractionUi.ShowTask(config): boolean
	return HorseTaskBar.Show(config)
end

function HorseInteractionUi.UpdateTask(config): ()
	HorseTaskBar.Update(config)
end

function HorseInteractionUi.HideTask(config): ()
	HorseTaskBar.Hide(config)
end

return HorseInteractionUi
