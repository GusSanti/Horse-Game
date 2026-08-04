------------------//VARIABLES
local Hover = {}
local Rotate = require(script.Parent.Rotate)

------------------//MAIN FUNCTIONS
function Hover.get_target(inst, state, defaults, utils)
	local baseSize = state.BaseSize or state.origSize or inst.Size
	local basePosition = state.BasePosition or state.origPos or inst.Position
	local hoverScale = utils.get_number_attribute(
		inst,
		"hover_scale",
		defaults and defaults.hover_scale or 0.04
	)
	local hoverLift = utils.get_number_attribute(
		inst,
		"hover_lift_px",
		defaults and defaults.hover_lift_px or 0
	)
	local scale = state.Hovered and (1 + math.max(0, hoverScale)) or 1
	local targetPosition = if state.Hovered and hoverLift ~= 0
		then utils.offset_udim2(basePosition, 0, -hoverLift)
		else basePosition
	local properties = {
		Size = utils.scale_udim2(baseSize, scale),
		Position = targetPosition,
		Rotation = Rotate.get_hover_rotation(inst, state, defaults),
	}

	local hoverBackground = inst:GetAttribute("hover_bg")
	local baseBackground = state.BaseBackgroundColor or state.origBg
	if typeof(hoverBackground) == "Color3" and baseBackground then
		properties.BackgroundColor3 = state.Hovered and hoverBackground or baseBackground
	end

	if inst:IsA("ImageButton") then
		local hoverImageColor = inst:GetAttribute("hover_img")
		local baseImageColor = state.BaseImageColor or state.origImg
		if typeof(hoverImageColor) == "Color3" and baseImageColor then
			properties.ImageColor3 = state.Hovered and hoverImageColor or baseImageColor
		elseif baseImageColor then
			properties.ImageColor3 = baseImageColor
		end
	end

	return properties
end

------------------//INIT
return Hover
