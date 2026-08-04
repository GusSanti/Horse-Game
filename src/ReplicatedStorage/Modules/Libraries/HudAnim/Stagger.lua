------------------//VARIABLES
local Stagger = {}

local Utils = require(script.Parent.Utils)

local SCALE_NAME = "HudAnimStaggerScale"
local MAX_ITEMS = 30

local staggerTokens = setmetatable({}, { __mode = "k" })
local staggerTweens = setmetatable({}, { __mode = "k" })

local DEFAULTS = {
	Delay = 0.035,
	Duration = 0.26,
	StartScale = 0.86,
	EasingStyle = Enum.EasingStyle.Back,
	EasingDirection = Enum.EasingDirection.Out,
}

------------------//FUNCTIONS
local function get_option(options, key)
	local value = options and options[key]
	if value == nil then
		return DEFAULTS[key]
	end

	return value
end

local function collect_items(container)
	local items = {}

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child.Visible then
			items[#items + 1] = child
		end
	end

	table.sort(items, function(left, right)
		if left.LayoutOrder ~= right.LayoutOrder then
			return left.LayoutOrder < right.LayoutOrder
		end

		local leftPosition = left.AbsolutePosition
		local rightPosition = right.AbsolutePosition
		if leftPosition.Y ~= rightPosition.Y then
			return leftPosition.Y < rightPosition.Y
		end

		return leftPosition.X < rightPosition.X
	end)

	return items
end

------------------//MAIN FUNCTIONS
function Stagger.cancel(container)
	if not container then
		return
	end

	staggerTokens[container] = (staggerTokens[container] or 0) + 1

	local tweens = staggerTweens[container]
	if tweens then
		Utils.cancel_tweens(tweens)
		staggerTweens[container] = nil
	end
end

function Stagger.play(container, options)
	if not container or not container:IsA("GuiObject") or not container.Parent then
		return
	end

	Stagger.cancel(container)

	local token = staggerTokens[container] or 0
	local items = collect_items(container)
	if #items == 0 then
		return
	end

	local stepDelay = math.max(0, get_option(options, "Delay"))
	local duration = math.max(0.01, get_option(options, "Duration"))
	local startScale = math.clamp(get_option(options, "StartScale"), 0.01, 1)
	local easingStyle = get_option(options, "EasingStyle")
	local easingDirection = get_option(options, "EasingDirection")
	local scaleName = get_option(options, "ScaleName") or SCALE_NAME
	local maxItems = math.min(#items, get_option(options, "MaxItems") or MAX_ITEMS)

	local tweens = {}
	staggerTweens[container] = tweens

	for index = 1, maxItems do
		local item = items[index]
		local scale = Utils.get_ui_scale(item, scaleName)
		if scale then
			local baseScale = item:GetAttribute("HudAnimBaseScale")
			if type(baseScale) ~= "number" or baseScale <= 0 then
				baseScale = if scale.Scale > 0 then scale.Scale else 1
				item:SetAttribute("HudAnimBaseScale", baseScale)
			end

			scale.Scale = baseScale * startScale

			task.delay(stepDelay * (index - 1), function()
				if staggerTokens[container] ~= token or not item.Parent or not scale.Parent then
					return
				end

				local tween = Utils.tween(scale, { Scale = baseScale }, duration, easingStyle, easingDirection)
				tweens[#tweens + 1] = tween
				tween:Play()
			end)
		end
	end

	task.delay(duration + (stepDelay * maxItems), function()
		if staggerTokens[container] ~= token then
			return
		end

		staggerTweens[container] = nil

		for index = 1, maxItems do
			local item = items[index]
			local scale = item and item.Parent and item:FindFirstChildWhichIsA("UIScale")
			if scale then
				local baseScale = item:GetAttribute("HudAnimBaseScale")
				scale.Scale = if type(baseScale) == "number" and baseScale > 0 then baseScale else 1
			end
		end
	end)
end

------------------//INIT
return Stagger
