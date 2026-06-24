------------------//SERVICES
local TweenService = game:GetService("TweenService")

------------------//VARIABLES
local Utils = {}

------------------//FUNCTIONS
function Utils.get_attr(inst, name, default)
	local v = inst:GetAttribute(name)
	return v ~= nil and v or default
end

function Utils.scale_udim2(u, mult)
	return UDim2.new(u.X.Scale * mult, u.X.Offset * mult, u.Y.Scale * mult, u.Y.Offset * mult)
end

function Utils.tween(inst, props, t, s, d)
	local info = TweenInfo.new(t or 0.15, s or Enum.EasingStyle.Quad, d or Enum.EasingDirection.Out)
	return TweenService:Create(inst, info, props)
end

------------------//MAIN FUNCTIONS

------------------//INIT
return Utils
