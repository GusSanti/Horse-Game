------------------//SERVICES
local TweenService = game:GetService("TweenService")

------------------//VARIABLES
local Utils = {}

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

------------------//MAIN FUNCTIONS

------------------//INIT
return Utils
