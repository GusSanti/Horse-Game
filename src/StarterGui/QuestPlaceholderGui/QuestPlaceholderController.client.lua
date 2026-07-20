local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

if not RunService:IsStudio() then
	script:Destroy()
	return
end

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Services = Modules:WaitForChild("Services")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local QuestCatalog = require(GameData:WaitForChild("QuestCatalog"))
local QuestClient = require(Services:WaitForChild("QuestClient"))

local TOGGLE_KEY = Enum.KeyCode.J
local EXPANDED_SIZE = UDim2.fromOffset(420, 560)
local COLLAPSED_SIZE = UDim2.fromOffset(420, 64)

local function create(className, properties)
	local instance = Instance.new(className)

	for propertyName, value in pairs(properties) do
		instance[propertyName] = value
	end

	return instance
end

local function clearChildren(parent)
	for _, child in ipairs(parent:GetChildren()) do
		if child ~= script then
			child:Destroy()
		end
	end
end

local function buildOrderedQuestIds()
	local ordered = {}
	local seen = {}

	for _, questId in ipairs(QuestCatalog.GetDailyQuestIds() or {}) do
		if not seen[questId] and QuestCatalog.GetDefinition(questId) then
			seen[questId] = true
			ordered[#ordered + 1] = questId
		end
	end

	local remaining = {}

	for questId, definition in pairs(QuestCatalog.Definitions or {}) do
		if definition and not seen[questId] then
			remaining[#remaining + 1] = questId
		end
	end

	table.sort(remaining)

	for _, questId in ipairs(remaining) do
		ordered[#ordered + 1] = questId
	end

	return ordered
end

local function formatRewardText(rewards)
	local parts = {}
	local horseshoes = rewards and rewards.Horseshoes or 0

	if horseshoes > 0 then
		parts[#parts + 1] = ("%d horseshoes"):format(horseshoes)
	end

	for _, itemReward in ipairs(rewards and rewards.Items or {}) do
		parts[#parts + 1] = ("%s x%d"):format(itemReward.ItemId or "item", itemReward.Amount or 1)
	end

	if #parts == 0 then
		return "No reward configured."
	end

	return table.concat(parts, " | ")
end

local function formatObjectiveText(questDefinition)
	local objective = questDefinition and questDefinition.Objective or nil
	if not objective then
		return "No objective configured."
	end

	local target = objective.Target or 0
	local mode = objective.Mode or "unknown"
	local statPath = objective.StatPath or "no stat"
	local estimatedMinutes = questDefinition.EstimatedMinutes or 0

	return ("Goal: %d | Type: %s | Stat: %s | ~%d min"):format(target, mode, statPath, estimatedMinutes)
end

local function formatRemainingTime(expiresAt)
	if type(expiresAt) ~= "number" or expiresAt <= 0 then
		return "no expiration"
	end

	local remaining = math.max(0, expiresAt - os.time())
	local hours = math.floor(remaining / 3600)
	local minutes = math.floor((remaining % 3600) / 60)
	local seconds = remaining % 60

	return ("%02dh %02dm %02ds"):format(hours, minutes, seconds)
end

local function resolveRowState(questId, questDefinition, dailyQuestState)
	local objective = questDefinition and questDefinition.Objective or {}
	local defaultState = {
		Text = "Status: outside the active rotation right now.",
		TextColor = Color3.fromRGB(173, 180, 190),
		BackgroundColor = Color3.fromRGB(42, 47, 56),
		AccentColor = Color3.fromRGB(77, 84, 96),
		TitleColor = Color3.fromRGB(240, 242, 247),
	}

	if not dailyQuestState or dailyQuestState.QuestId == "" then
		defaultState.Text = "Status: no daily assigned at the moment."
		return defaultState
	end

	if questId ~= dailyQuestState.QuestId then
		return defaultState
	end

	local progress = math.max(0, dailyQuestState.Progress or 0)
	local goal = math.max(0, dailyQuestState.Goal or objective.Target or 0)
	local state = {
		Text = ("Status: active daily | progress %d/%d | in progress"):format(progress, goal),
		TextColor = Color3.fromRGB(255, 241, 170),
		BackgroundColor = Color3.fromRGB(61, 56, 34),
		AccentColor = Color3.fromRGB(229, 194, 79),
		TitleColor = Color3.fromRGB(255, 249, 215),
	}

	if dailyQuestState.Completed then
		state.Text = ("Status: active daily | progress %d/%d | completed"):format(progress, goal)
		state.TextColor = Color3.fromRGB(175, 239, 176)
		state.BackgroundColor = Color3.fromRGB(34, 62, 41)
		state.AccentColor = Color3.fromRGB(92, 199, 111)
		state.TitleColor = Color3.fromRGB(233, 255, 233)
	end

	if dailyQuestState.Claimed then
		state.Text = ("Status: active daily | progress %d/%d | reward claimed"):format(progress, goal)
		state.TextColor = Color3.fromRGB(176, 227, 255)
		state.BackgroundColor = Color3.fromRGB(32, 54, 68)
		state.AccentColor = Color3.fromRGB(98, 177, 219)
		state.TitleColor = Color3.fromRGB(232, 247, 255)
	end

	return state
end

DataUtility.client.ensure_remotes()

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")
local scriptContainer = script.Parent
local screenGui = nil

if scriptContainer:IsA("ScreenGui") then
	screenGui = scriptContainer
else
	screenGui = scriptContainer:FindFirstChild("QuestPlaceholderScreenGui")

	if screenGui and not screenGui:IsA("ScreenGui") then
		screenGui:Destroy()
		screenGui = nil
	end

	if not screenGui then
		screenGui = Instance.new("ScreenGui")
		screenGui.Name = "QuestPlaceholderScreenGui"
		screenGui.Parent = playerGui
	end
end

screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

clearChildren(screenGui)

local rootFrame = create("Frame", {
	Name = "Root",
	AnchorPoint = Vector2.new(0, 0),
	BackgroundColor3 = Color3.fromRGB(24, 27, 33),
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(18, 65),
	Size = EXPANDED_SIZE,
	Parent = screenGui,
})

create("UICorner", {
	CornerRadius = UDim.new(0, 14),
	Parent = rootFrame,
})

create("UIStroke", {
	Color = Color3.fromRGB(67, 73, 84),
	Thickness = 1,
	Transparency = 0.15,
	Parent = rootFrame,
})

local header = create("Frame", {
	Name = "Header",
	BackgroundColor3 = Color3.fromRGB(31, 35, 43),
	BorderSizePixel = 0,
	Size = UDim2.new(1, 0, 0, 64),
	Parent = rootFrame,
})

create("UICorner", {
	CornerRadius = UDim.new(0, 14),
	Parent = header,
})

create("Frame", {
	Name = "HeaderMask",
	BackgroundColor3 = Color3.fromRGB(31, 35, 43),
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(0, 32),
	Size = UDim2.new(1, 0, 0, 32),
	Parent = header,
})

create("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Quest Placeholder",
	TextColor3 = Color3.fromRGB(245, 247, 250),
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(16, 10),
	Size = UDim2.new(1, -120, 0, 24),
	Parent = header,
})

create("TextLabel", {
	Name = "Subtitle",
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Reads the quest catalog and tracks the player's real daily quest.",
	TextColor3 = Color3.fromRGB(179, 188, 202),
	TextSize = 12,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(16, 34),
	Size = UDim2.new(1, -120, 0, 22),
	Parent = header,
})

local toggleButton = create("TextButton", {
	Name = "ToggleButton",
	AnchorPoint = Vector2.new(1, 0.5),
	AutoButtonColor = true,
	BackgroundColor3 = Color3.fromRGB(63, 82, 112),
	BorderSizePixel = 0,
	Font = Enum.Font.GothamBold,
	Position = UDim2.new(1, -16, 0.5, 0),
	Size = UDim2.fromOffset(88, 34),
	Text = "Hide",
	TextColor3 = Color3.fromRGB(247, 250, 255),
	TextSize = 13,
	Parent = header,
})

create("UICorner", {
	CornerRadius = UDim.new(0, 10),
	Parent = toggleButton,
})

local content = create("Frame", {
	Name = "Content",
	BackgroundTransparency = 1,
	Position = UDim2.fromOffset(0, 64),
	Size = UDim2.new(1, 0, 1, -64),
	Parent = rootFrame,
})

local summaryFrame = create("Frame", {
	Name = "Summary",
	BackgroundColor3 = Color3.fromRGB(31, 35, 43),
	BorderSizePixel = 0,
	Position = UDim2.fromOffset(14, 14),
	Size = UDim2.new(1, -28, 0, 96),
	Parent = content,
})

create("UICorner", {
	CornerRadius = UDim.new(0, 12),
	Parent = summaryFrame,
})

local catalogCountLabel = create("TextLabel", {
	Name = "CatalogCount",
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "Catalog: 0 quests",
	TextColor3 = Color3.fromRGB(234, 239, 247),
	TextSize = 15,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(14, 12),
	Size = UDim2.new(1, -28, 0, 18),
	Parent = summaryFrame,
})

local activeQuestLabel = create("TextLabel", {
	Name = "ActiveQuest",
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Current daily: loading...",
	TextColor3 = Color3.fromRGB(212, 219, 230),
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(14, 34),
	Size = UDim2.new(1, -28, 0, 18),
	Parent = summaryFrame,
})

local progressLabel = create("TextLabel", {
	Name = "Progress",
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Progress: loading...",
	TextColor3 = Color3.fromRGB(212, 219, 230),
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(14, 52),
	Size = UDim2.new(1, -28, 0, 18),
	Parent = summaryFrame,
})

local historyLabel = create("TextLabel", {
	Name = "History",
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "History: loading...",
	TextColor3 = Color3.fromRGB(212, 219, 230),
	TextSize = 13,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(14, 70),
	Size = UDim2.new(1, -28, 0, 18),
	Parent = summaryFrame,
})

local scrollFrame = create("ScrollingFrame", {
	Name = "QuestList",
	Active = true,
	AutomaticCanvasSize = Enum.AutomaticSize.None,
	BackgroundColor3 = Color3.fromRGB(19, 22, 27),
	BorderSizePixel = 0,
	CanvasSize = UDim2.new(),
	Position = UDim2.fromOffset(14, 120),
	ScrollBarImageColor3 = Color3.fromRGB(106, 116, 133),
	ScrollBarThickness = 6,
	Size = UDim2.new(1, -28, 1, -166),
	Parent = content,
})

create("UICorner", {
	CornerRadius = UDim.new(0, 12),
	Parent = scrollFrame,
})

local listPadding = create("UIPadding", {
	PaddingBottom = UDim.new(0, 10),
	PaddingLeft = UDim.new(0, 10),
	PaddingRight = UDim.new(0, 10),
	PaddingTop = UDim.new(0, 10),
	Parent = scrollFrame,
})

local listLayout = create("UIListLayout", {
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = scrollFrame,
})

local footerLabel = create("TextLabel", {
	Name = "Footer",
	BackgroundTransparency = 1,
	Font = Enum.Font.Gotham,
	Text = "Press J to show or hide this panel.",
	TextColor3 = Color3.fromRGB(165, 174, 189),
	TextSize = 12,
	TextXAlignment = Enum.TextXAlignment.Left,
	Position = UDim2.fromOffset(16, 1),
	AnchorPoint = Vector2.new(0, 1),
	Size = UDim2.new(1, -32, 0, 18),
	Parent = rootFrame,
})

local orderedQuestIds = buildOrderedQuestIds()
local rowsByQuestId = {}
local isExpanded = true
local isVisible = false

local function updateCanvasSize()
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + listPadding.PaddingTop.Offset + listPadding.PaddingBottom.Offset)
end

local function setExpanded(expanded)
	isExpanded = expanded
	content.Visible = expanded
	footerLabel.Visible = expanded
	rootFrame.Size = expanded and EXPANDED_SIZE or COLLAPSED_SIZE
	toggleButton.Text = expanded and "Hide" or "Show"
end

local function setVisible(visible)
	isVisible = visible == true
	screenGui.Enabled = isVisible
end

for layoutOrder, questId in ipairs(orderedQuestIds) do
	local questDefinition = QuestCatalog.GetDefinition(questId)

	if not questDefinition then
		continue
	end

	local row = create("Frame", {
		Name = questId,
		BackgroundColor3 = Color3.fromRGB(42, 47, 56),
		BorderSizePixel = 0,
		LayoutOrder = layoutOrder,
		Size = UDim2.new(1, 0, 0, 118),
		Parent = scrollFrame,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 12),
		Parent = row,
	})

	local accent = create("Frame", {
		Name = "Accent",
		BackgroundColor3 = Color3.fromRGB(77, 84, 96),
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(6, 118),
		Parent = row,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 12),
		Parent = accent,
	})

	local titleLabel = create("TextLabel", {
		Name = "Title",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = questDefinition.DisplayName or questId,
		TextColor3 = Color3.fromRGB(240, 242, 247),
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(16, 10),
		Size = UDim2.new(1, -28, 0, 20),
		Parent = row,
	})

	local descriptionLabel = create("TextLabel", {
		Name = "Description",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = questDefinition.Description or "No description.",
		TextColor3 = Color3.fromRGB(213, 220, 230),
		TextSize = 13,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 32),
		Size = UDim2.new(1, -28, 0, 28),
		Parent = row,
	})

	create("TextLabel", {
		Name = "Objective",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = formatObjectiveText(questDefinition),
		TextColor3 = Color3.fromRGB(166, 176, 191),
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 62),
		Size = UDim2.new(1, -28, 0, 26),
		Parent = row,
	})

	create("TextLabel", {
		Name = "Rewards",
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "Rewards: " .. formatRewardText(questDefinition.Rewards),
		TextColor3 = Color3.fromRGB(183, 198, 219),
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 84),
		Size = UDim2.new(1, -28, 0, 18),
		Parent = row,
	})

	local statusLabel = create("TextLabel", {
		Name = "Status",
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Status: loading...",
		TextColor3 = Color3.fromRGB(173, 180, 190),
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(16, 102),
		Size = UDim2.new(1, -28, 0, 14),
		Parent = row,
	})

	rowsByQuestId[questId] = {
		Frame = row,
		Accent = accent,
		Title = titleLabel,
		Status = statusLabel,
	}
end

updateCanvasSize()
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateCanvasSize)

local function render()
	local dailyQuestState = QuestClient.GetDailyQuestState() or {}
	local dailyQuestDefinition = QuestClient.GetDailyQuestDefinition()
	local history = DataUtility.client.get("Quests.History") or {}
	local progress = math.max(0, dailyQuestState.Progress or 0)
	local goal = math.max(0, dailyQuestState.Goal or (dailyQuestDefinition and dailyQuestDefinition.Objective and dailyQuestDefinition.Objective.Target) or 0)
	local statusText = "In progress"

	if dailyQuestState.Claimed then
		statusText = "Reward claimed"
	elseif dailyQuestState.Completed then
		statusText = "Completed"
	end

	catalogCountLabel.Text = ("Catalog: %d quests"):format(#orderedQuestIds)

	if dailyQuestDefinition then
		activeQuestLabel.Text = ("Current daily: %s"):format(dailyQuestDefinition.DisplayName or dailyQuestState.QuestId)
		progressLabel.Text = ("Progress: %d/%d | %s | expires in %s"):format(progress, goal, statusText, formatRemainingTime(dailyQuestState.ExpiresAt))
	else
		activeQuestLabel.Text = "Current daily: none assigned."
		progressLabel.Text = "Progress: no active daily quest."
	end

	historyLabel.Text = ("History: %d completed | current streak %d | best streak %d"):format(
		history.CompletedCount or 0,
		history.CurrentStreak or 0,
		history.BestStreak or 0
	)

	for questId, refs in pairs(rowsByQuestId) do
		local questDefinition = QuestCatalog.GetDefinition(questId)

		if questDefinition then
			local rowState = resolveRowState(questId, questDefinition, dailyQuestState)
			refs.Frame.BackgroundColor3 = rowState.BackgroundColor
			refs.Accent.BackgroundColor3 = rowState.AccentColor
			refs.Title.TextColor3 = rowState.TitleColor
			refs.Status.TextColor3 = rowState.TextColor
			refs.Status.Text = rowState.Text
		end
	end
end

toggleButton.MouseButton1Click:Connect(function()
	setExpanded(not isExpanded)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == TOGGLE_KEY then
		setVisible(not isVisible)
	end
end)

QuestClient.BindDailyQuestChanged(function()
	render()
end)

DataUtility.client.bind("Quests.History", function()
	render()
end)

task.spawn(function()
	while screenGui.Parent do
		task.wait(1)
		render()
	end
end)

setVisible(false)
render()
