local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local FoodHoverTooltip = {}

local TOOLTIP_GUI_NAME = "FoodHoverTooltipGui"
local TOOLTIP_WIDTH = 238
local TOOLTIP_PADDING = 10
local TOOLTIP_OFFSET = Vector2.new(16, 18)
local TOOLTIP_ZINDEX = 10000

local localPlayer = Players.LocalPlayer
local tooltipGui = nil
local tooltipFrame = nil
local titleLabel = nil
local bodyLabel = nil
local activeTarget = nil
local positionConnection = nil

local function format_number(value)
	local numberValue = tonumber(value) or 0
	if math.abs(numberValue - math.floor(numberValue + 0.5)) < 0.001 then
		return tostring(math.floor(numberValue + 0.5))
	end

	return string.format("%.1f", numberValue)
end

local function format_signed(value)
	local numberValue = tonumber(value) or 0
	if numberValue >= 0 then
		return "+" .. format_number(numberValue)
	end

	return format_number(numberValue)
end

local function get_player_gui()
	if not localPlayer then
		return nil
	end

	return localPlayer:FindFirstChildOfClass("PlayerGui") or localPlayer:WaitForChild("PlayerGui", 5)
end

local function ensure_tooltip()
	if tooltipGui and tooltipGui.Parent and tooltipFrame and tooltipFrame.Parent then
		return tooltipFrame
	end

	local playerGui = get_player_gui()
	if not playerGui then
		return nil
	end

	tooltipGui = playerGui:FindFirstChild(TOOLTIP_GUI_NAME)
	if not tooltipGui then
		tooltipGui = Instance.new("ScreenGui")
		tooltipGui.Name = TOOLTIP_GUI_NAME
		tooltipGui.IgnoreGuiInset = true
		tooltipGui.ResetOnSpawn = false
		tooltipGui.DisplayOrder = TOOLTIP_ZINDEX
		tooltipGui.Parent = playerGui
	end

	tooltipFrame = tooltipGui:FindFirstChild("Tooltip")
	if not tooltipFrame then
		tooltipFrame = Instance.new("Frame")
		tooltipFrame.Name = "Tooltip"
		tooltipFrame.BackgroundColor3 = Color3.fromRGB(24, 22, 20)
		tooltipFrame.BackgroundTransparency = 0.08
		tooltipFrame.BorderSizePixel = 0
		tooltipFrame.AutomaticSize = Enum.AutomaticSize.Y
		tooltipFrame.Size = UDim2.fromOffset(TOOLTIP_WIDTH, 0)
		tooltipFrame.Visible = false
		tooltipFrame.ZIndex = TOOLTIP_ZINDEX
		tooltipFrame.Parent = tooltipGui

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = tooltipFrame

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(255, 225, 170)
		stroke.Transparency = 0.28
		stroke.Thickness = 1
		stroke.Parent = tooltipFrame

		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0, TOOLTIP_PADDING)
		padding.PaddingRight = UDim.new(0, TOOLTIP_PADDING)
		padding.PaddingTop = UDim.new(0, TOOLTIP_PADDING)
		padding.PaddingBottom = UDim.new(0, TOOLTIP_PADDING)
		padding.Parent = tooltipFrame

		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 5)
		layout.Parent = tooltipFrame

		titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.BackgroundTransparency = 1
		titleLabel.Font = Enum.Font.GothamBold
		titleLabel.TextColor3 = Color3.fromRGB(255, 236, 192)
		titleLabel.TextSize = 15
		titleLabel.TextXAlignment = Enum.TextXAlignment.Left
		titleLabel.TextYAlignment = Enum.TextYAlignment.Top
		titleLabel.TextWrapped = true
		titleLabel.AutomaticSize = Enum.AutomaticSize.Y
		titleLabel.Size = UDim2.fromScale(1, 0)
		titleLabel.LayoutOrder = 1
		titleLabel.ZIndex = TOOLTIP_ZINDEX + 1
		titleLabel.Parent = tooltipFrame

		bodyLabel = Instance.new("TextLabel")
		bodyLabel.Name = "Body"
		bodyLabel.BackgroundTransparency = 1
		bodyLabel.Font = Enum.Font.Gotham
		bodyLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
		bodyLabel.TextSize = 13
		bodyLabel.TextXAlignment = Enum.TextXAlignment.Left
		bodyLabel.TextYAlignment = Enum.TextYAlignment.Top
		bodyLabel.TextWrapped = true
		bodyLabel.AutomaticSize = Enum.AutomaticSize.Y
		bodyLabel.Size = UDim2.fromScale(1, 0)
		bodyLabel.LayoutOrder = 2
		bodyLabel.ZIndex = TOOLTIP_ZINDEX + 1
		bodyLabel.Parent = tooltipFrame
	else
		titleLabel = tooltipFrame:FindFirstChild("Title")
		bodyLabel = tooltipFrame:FindFirstChild("Body")
	end

	return tooltipFrame
end

local function get_viewport_size()
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end

	return Vector2.new(1280, 720)
end

local function is_target_visible(target)
	local current = target

	while current do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end

		if current:IsA("LayerCollector") and not current.Enabled then
			return false
		end

		current = current.Parent
	end

	return target ~= nil and target.Parent ~= nil
end

local function update_position()
	if not tooltipFrame or not tooltipFrame.Visible then
		return
	end

	if activeTarget and not is_target_visible(activeTarget) then
		FoodHoverTooltip.Hide(activeTarget)
		return
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local viewportSize = get_viewport_size()
	local frameSize = tooltipFrame.AbsoluteSize
	local x = mousePosition.X + TOOLTIP_OFFSET.X
	local y = mousePosition.Y + TOOLTIP_OFFSET.Y

	if x + frameSize.X + TOOLTIP_PADDING > viewportSize.X then
		x = mousePosition.X - frameSize.X - TOOLTIP_OFFSET.X
	end

	if y + frameSize.Y + TOOLTIP_PADDING > viewportSize.Y then
		y = mousePosition.Y - frameSize.Y - TOOLTIP_OFFSET.Y
	end

	tooltipFrame.Position = UDim2.fromOffset(
		math.max(TOOLTIP_PADDING, x),
		math.max(TOOLTIP_PADDING, y)
	)
end

local function start_position_updates()
	if positionConnection then
		return
	end

	positionConnection = RunService.RenderStepped:Connect(update_position)
end

local function stop_position_updates()
	if positionConnection then
		positionConnection:Disconnect()
		positionConnection = nil
	end
end

local function resolve_definition(source)
	if type(source) == "function" then
		local ok, result = pcall(source)
		if ok then
			source = result
		else
			source = nil
		end
	end

	if type(source) == "table" and type(source.FoodDefinition) == "table" then
		return source.FoodDefinition
	end

	if type(source) == "table" and type(source.Definition) == "table" then
		return source.Definition
	end

	return type(source) == "table" and source or nil
end

local function has_food_tag(itemDefinition)
	for _, tag in ipairs(itemDefinition and itemDefinition.Tags or {}) do
		if type(tag) == "string" and string.lower(tag) == "food" then
			return true
		end
	end

	return false
end

local function build_effect_lines(itemDefinition)
	local effects = itemDefinition and itemDefinition.Effects or {}
	local lines = {}

	if itemDefinition and itemDefinition.NeedKey == "Hunger" and effects.NeedGain ~= nil then
		lines[#lines + 1] = "Fome: +" .. format_number(effects.NeedGain)
	elseif itemDefinition and itemDefinition.NeedKey and effects.NeedGain ~= nil then
		lines[#lines + 1] = tostring(itemDefinition.NeedKey) .. ": +" .. format_number(effects.NeedGain)
	end

	if effects.HealthGain ~= nil then
		lines[#lines + 1] = "Saude: " .. format_signed(effects.HealthGain)
	end

	if effects.HappinessGain ~= nil then
		lines[#lines + 1] = "Felicidade: " .. format_signed(effects.HappinessGain)
	end

	if effects.FriendshipGain ~= nil then
		lines[#lines + 1] = "Amizade: " .. format_signed(effects.FriendshipGain)
	end

	local decayBuff = effects.DecayBuff
	if type(decayBuff) == "table" and tonumber(decayBuff.Multiplier) then
		local multiplier = tonumber(decayBuff.Multiplier)
		local duration = tonumber(decayBuff.DurationMinutes)
		if multiplier and multiplier < 1 then
			local percent = math.max(0, math.floor((1 - multiplier) * 100 + 0.5))
			local suffix = duration and duration > 0 and (" por " .. format_number(duration) .. " min") or ""
			lines[#lines + 1] = "Queda de fome: -" .. percent .. "%" .. suffix
		end
	end

	if effects.MoodText ~= nil and tostring(effects.MoodText) ~= "" then
		lines[#lines + 1] = "Humor: " .. tostring(effects.MoodText)
	end

	if #lines == 0 and type(itemDefinition.EffectsSummary) == "string" and itemDefinition.EffectsSummary ~= "" then
		lines[#lines + 1] = itemDefinition.EffectsSummary
	end

	if #lines == 0 and type(itemDefinition.Description) == "string" and itemDefinition.Description ~= "" then
		lines[#lines + 1] = itemDefinition.Description
	end

	return lines
end

function FoodHoverTooltip.HasTooltip(source)
	local itemDefinition = resolve_definition(source)
	if not itemDefinition then
		return false
	end

	if itemDefinition.ToolCategory ~= "Food" and itemDefinition.CareType ~= "Food" and not has_food_tag(itemDefinition) then
		return false
	end

	return #build_effect_lines(itemDefinition) > 0
end

function FoodHoverTooltip.Show(source, target)
	local itemDefinition = resolve_definition(source)
	if not FoodHoverTooltip.HasTooltip(itemDefinition) then
		return
	end

	local frame = ensure_tooltip()
	if not frame or not titleLabel or not bodyLabel then
		return
	end

	activeTarget = target
	titleLabel.Text = itemDefinition.DisplayName or itemDefinition.ToolName or itemDefinition.ItemId or "Food"
	bodyLabel.Text = table.concat(build_effect_lines(itemDefinition), "\n")
	frame.Visible = true
	update_position()
	start_position_updates()
end

function FoodHoverTooltip.Hide(target)
	if target and activeTarget ~= target then
		return
	end

	activeTarget = nil
	if tooltipFrame then
		tooltipFrame.Visible = false
	end

	stop_position_updates()
end

function FoodHoverTooltip.Bind(target, source, trove)
	if not target or not target:IsA("GuiObject") then
		return nil
	end

	local function show()
		FoodHoverTooltip.Show(source, target)
	end

	local function hide()
		FoodHoverTooltip.Hide(target)
	end

	if trove and type(trove.Connect) == "function" then
		trove:Connect(target.MouseEnter, show)
		trove:Connect(target.MouseLeave, hide)
		trove:Connect(target.AncestryChanged, function(_, parent)
			if not parent then
				hide()
			end
		end)
		return nil
	end

	local enterConnection = target.MouseEnter:Connect(show)
	local leaveConnection = target.MouseLeave:Connect(hide)
	local ancestryConnection = target.AncestryChanged:Connect(function(_, parent)
		if not parent then
			hide()
		end
	end)

	return function()
		enterConnection:Disconnect()
		leaveConnection:Disconnect()
		ancestryConnection:Disconnect()
		hide()
	end
end

return FoodHoverTooltip