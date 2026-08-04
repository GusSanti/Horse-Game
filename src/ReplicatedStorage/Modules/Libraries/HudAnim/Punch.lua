------------------//VARIABLES
local Punch = {}

local Utils = require(script.Parent.Utils)

local SCALE_NAME = "HudAnimPunchScale"

local punchTokens = setmetatable({}, { __mode = "k" })
local punchTweens = setmetatable({}, { __mode = "k" })

local DEFAULTS = {
	Scale = 1.14,
	InTime = 0.07,
	OutTime = 0.16,
}

------------------//FUNCTIONS
local function get_option(options, key)
	local value = options and options[key]
	if value == nil then
		return DEFAULTS[key]
	end

	return value
end

local function cancel_tween(instance)
	local tween = punchTweens[instance]
	if tween then
		pcall(function()
			tween:Cancel()
		end)
		punchTweens[instance] = nil
	end
end

------------------//MAIN FUNCTIONS
function Punch.play(instance, options)
	if not instance or not instance:IsA("GuiObject") or not instance.Parent then
		return
	end

	local scale = Utils.get_ui_scale(instance, SCALE_NAME)
	if not scale then
		return
	end

	cancel_tween(instance)

	punchTokens[instance] = (punchTokens[instance] or 0) + 1
	local token = punchTokens[instance]

	local baseScale = get_option(options, "BaseScale") or instance:GetAttribute("HudAnimBaseScale")
	if type(baseScale) ~= "number" or baseScale <= 0 then
		baseScale = if scale.Scale > 0 then scale.Scale else 1
		instance:SetAttribute("HudAnimBaseScale", baseScale)
	end

	local peakScale = baseScale * get_option(options, "Scale")
	local inTime = math.max(0.01, get_option(options, "InTime"))
	local outTime = math.max(0.01, get_option(options, "OutTime"))

	scale.Scale = baseScale

	local inTween = Utils.tween(scale, { Scale = peakScale }, inTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	punchTweens[instance] = inTween
	inTween:Play()

	task.delay(inTime, function()
		if punchTokens[instance] ~= token or not instance.Parent or not scale.Parent then
			return
		end

		local outTween = Utils.tween(scale, { Scale = baseScale }, outTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		punchTweens[instance] = outTween
		outTween:Play()

		task.delay(outTime, function()
			if punchTokens[instance] ~= token or not scale.Parent then
				return
			end

			punchTweens[instance] = nil
			scale.Scale = baseScale
		end)
	end)
end

function Punch.cancel(instance)
	if not instance then
		return
	end

	punchTokens[instance] = (punchTokens[instance] or 0) + 1
	cancel_tween(instance)
end

------------------//INIT
return Punch
