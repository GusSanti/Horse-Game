------------------//SERVICES
local TweenService = game:GetService("TweenService")

------------------//VARIABLES
local Utils = {}

local EASING_STYLE_BY_NAME = {}
for _, easingStyle in ipairs(Enum.EasingStyle:GetEnumItems()) do
	EASING_STYLE_BY_NAME[string.lower(easingStyle.Name)] = easingStyle
end

local EASING_DIRECTION_BY_NAME = {}
for _, easingDirection in ipairs(Enum.EasingDirection:GetEnumItems()) do
	EASING_DIRECTION_BY_NAME[string.lower(easingDirection.Name)] = easingDirection
end

function Utils.scale_udim2(u, mult)
	return UDim2.new(u.X.Scale * mult, u.X.Offset * mult, u.Y.Scale * mult, u.Y.Offset * mult)
end

function Utils.offset_udim2(u, xOffset, yOffset)
	return UDim2.new(u.X.Scale, u.X.Offset + xOffset, u.Y.Scale, u.Y.Offset + yOffset)
end

function Utils.get_number_attribute(inst, attributeName, fallback)
	local value = inst and inst:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	local convertedValue = tonumber(value)
	if convertedValue ~= nil then
		return convertedValue
	end

	return fallback
end

function Utils.get_optional_number_attribute(inst, attributeName)
	local value = inst and inst:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end

	return tonumber(value)
end

function Utils.tween(inst, props, t, s, d)
	local info = TweenInfo.new(t or 0.15, s or Enum.EasingStyle.Quad, d or Enum.EasingDirection.Out)
	return TweenService:Create(inst, info, props)
end

function Utils.get_easing_style(inst, attributeName, fallback)
	local value = inst and inst:GetAttribute(attributeName)
	if typeof(value) == "EnumItem" and value.EnumType == Enum.EasingStyle then
		return value
	end

	if type(value) == "string" then
		return EASING_STYLE_BY_NAME[string.lower(value)] or fallback
	end

	return fallback
end

function Utils.get_easing_direction(inst, attributeName, fallback)
	local value = inst and inst:GetAttribute(attributeName)
	if typeof(value) == "EnumItem" and value.EnumType == Enum.EasingDirection then
		return value
	end

	if type(value) == "string" then
		return EASING_DIRECTION_BY_NAME[string.lower(value)] or fallback
	end

	return fallback
end

function Utils.get_ui_scale(inst, name)
	if not inst or not inst:IsA("GuiObject") then
		return nil
	end

	local existingScale = inst:FindFirstChildWhichIsA("UIScale")
	if existingScale then
		return existingScale
	end

	local scale = Instance.new("UIScale")
	scale.Name = name or "HudAnimScale"
	scale.Scale = 1
	scale.Parent = inst
	return scale
end

function Utils.cancel_tweens(tweens)
	for _, tween in ipairs(tweens or {}) do
		pcall(function()
			tween:Cancel()
		end)
	end

	table.clear(tweens or {})
end

------------------//MAIN FUNCTIONS

------------------//INIT
return Utils
