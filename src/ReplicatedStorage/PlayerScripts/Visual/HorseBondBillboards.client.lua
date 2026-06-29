------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

------------------//CONSTANTS
local ENABLED = false
local PLOT_VALUE_NAME = "Plot"
local HORSE_FOLDER_NAME = "HorseFolder"
local VISUAL_HORSE_ATTRIBUTE = "IsStableVisualHorse"
local HORSE_ID_ATTRIBUTE = "HorseId"
local BILLBOARD_NAME = "HorseBondBillboard"
local IGNORE_REFRESH_ATTRIBUTE = "IgnoreHorseBondBillboardRefresh"
local REFRESH_INTERVAL = 0.5
local MAX_DISTANCE = 80
local EXTRA_STUDS_OFFSET = 1.75

------------------//VARIABLES
local localPlayer: Player = Players.LocalPlayer
local modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local gameData: Folder = modules:WaitForChild("GameData")
local services: Folder = modules:WaitForChild("Services")
local utility: Folder = modules:WaitForChild("Utility")

local DataUtility = require(utility:WaitForChild("DataUtility"))
local HorseBondService = require(services:WaitForChild("HorseBondService"))
local HorseStatusBillboardConfig = require(gameData:WaitForChild("HorseStatusBillboardConfig"))

local plotValue: ObjectValue = localPlayer:WaitForChild(PLOT_VALUE_NAME)

local plotConnections: {RBXScriptConnection} = {}
local activeBillboards: {[Instance]: any} = {}
local elapsedSinceRefresh = 0
local refreshQueued = false

------------------//FUNCTIONS
local function disconnect_all(connections: {RBXScriptConnection}): ()
	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function destroy_billboard(horseVisual: Instance): ()
	local entry = activeBillboards[horseVisual]
	if not entry then
		return
	end

	if entry.gui and entry.gui.Parent then
		entry.gui:Destroy()
	end

	activeBillboards[horseVisual] = nil
end

local function destroy_all_billboards(): ()
	local visualsToDestroy = {}

	for horseVisual in activeBillboards do
		visualsToDestroy[#visualsToDestroy + 1] = horseVisual
	end

	for _, horseVisual in visualsToDestroy do
		destroy_billboard(horseVisual)
	end
end

local function remove_stale_billboard_gui(horseVisual: Instance): ()
	for _, child: Instance in horseVisual:GetChildren() do
		if child.Name == BILLBOARD_NAME and child:IsA("BillboardGui") then
			child:Destroy()
		end
	end
end

local function mark_placeholder(instance: Instance): Instance
	instance:SetAttribute(IGNORE_REFRESH_ATTRIBUTE, true)
	return instance
end

local function find_focus_part(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end

		for _, descendant: Instance in instance:GetDescendants() do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
	end

	return nil
end

local function get_horse_extents(horseVisual: Instance): Vector3
	if horseVisual:IsA("Model") then
		return horseVisual:GetExtentsSize()
	end

	if horseVisual:IsA("BasePart") then
		return horseVisual.Size
	end

	return Vector3.new(4, 4, 4)
end

local function get_horse_visuals(): {Instance}
	local plot = plotValue.Value
	if not plot then
		return {}
	end

	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return {}
	end

	local visuals = {}

	for _, slotFolder: Instance in horseFolder:GetChildren() do
		for _, child: Instance in slotFolder:GetChildren() do
			if child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true then
				visuals[#visuals + 1] = child
			end
		end
	end

	return visuals
end

local function create_text_label(parent: Instance, name: string, textSize: number, font: Enum.Font, color: Color3)
	local label = mark_placeholder(Instance.new("TextLabel"))
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = font
	label.Text = ""
	label.TextColor3 = color
	label.TextSize = textSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(1, 0, 0, textSize + 2)
	label.Parent = parent

	return label
end

local function should_ignore_descendant(descendant: Instance): boolean
	local current = descendant

	while current do
		if current:GetAttribute(IGNORE_REFRESH_ATTRIBUTE) == true then
			return true
		end

		current = current.Parent
	end

	return false
end

local function create_billboard(horseVisual: Instance)
	local horseId = horseVisual:GetAttribute(HORSE_ID_ATTRIBUTE)
	if type(horseId) ~= "string" or horseId == "" then
		return nil
	end

	local focusPart = find_focus_part(horseVisual)
	if not focusPart then
		return nil
	end

	remove_stale_billboard_gui(horseVisual)

	local extents = get_horse_extents(horseVisual)
	local stackedOffset = HorseStatusBillboardConfig.Enabled and 3.25 or 0

	local billboardGui = mark_placeholder(Instance.new("BillboardGui"))
	billboardGui.Name = BILLBOARD_NAME
	billboardGui.Adornee = focusPart
	billboardGui.AlwaysOnTop = true
	billboardGui.LightInfluence = 0
	billboardGui.MaxDistance = MAX_DISTANCE
	billboardGui.Size = UDim2.fromOffset(220, 132)
	billboardGui.StudsOffset = Vector3.new(0, (extents.Y * 0.5) + EXTRA_STUDS_OFFSET + stackedOffset, 0)
	billboardGui.Parent = horseVisual

	local mainFrame = mark_placeholder(Instance.new("Frame"))
	mainFrame.Name = "MainFrame"
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = Color3.fromRGB(19, 24, 31)
	mainFrame.BackgroundTransparency = 0.14
	mainFrame.BorderSizePixel = 0
	mainFrame.Position = UDim2.fromScale(0.5, 0.5)
	mainFrame.Size = UDim2.fromScale(1, 1)
	mainFrame.Parent = billboardGui

	local corner = mark_placeholder(Instance.new("UICorner"))
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = mainFrame

	local stroke = mark_placeholder(Instance.new("UIStroke"))
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.82
	stroke.Parent = mainFrame

	local padding = mark_placeholder(Instance.new("UIPadding"))
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = mainFrame

	local layout = mark_placeholder(Instance.new("UIListLayout"))
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = mainFrame

	local titleLabel = create_text_label(mainFrame, "TitleLabel", 16, Enum.Font.GothamBold, Color3.fromRGB(255, 243, 201))
	local trustLabel = create_text_label(mainFrame, "TrustLabel", 14, Enum.Font.GothamMedium, Color3.fromRGB(228, 236, 247))
	local levelLabel = create_text_label(mainFrame, "LevelLabel", 14, Enum.Font.GothamMedium, Color3.fromRGB(228, 236, 247))
	local xpLabel = create_text_label(mainFrame, "XPLabel", 13, Enum.Font.Gotham, Color3.fromRGB(198, 206, 218))
	local streakLabel = create_text_label(mainFrame, "StreakLabel", 13, Enum.Font.Gotham, Color3.fromRGB(198, 206, 218))
	local qualityLabel = create_text_label(mainFrame, "QualityLabel", 13, Enum.Font.Gotham, Color3.fromRGB(198, 206, 218))

	return {
		gui = billboardGui,
		horseId = horseId,
		titleLabel = titleLabel,
		trustLabel = trustLabel,
		levelLabel = levelLabel,
		xpLabel = xpLabel,
		streakLabel = streakLabel,
		qualityLabel = qualityLabel,
	}
end

local function update_billboard(entry): ()
	local horse = nil
	local resolvedHorseId = nil
	local displayData = nil

	horse, resolvedHorseId = HorseBondService.GetHorse(entry.horseId)
	if horse then
		displayData = HorseBondService.GetDisplayData(horse)
	end

	entry.titleLabel.Text = if horse then (horse.Nickname or horse.DisplayName or resolvedHorseId or entry.horseId) else entry.horseId

	if not displayData then
		entry.trustLabel.Text = "Trust: --"
		entry.levelLabel.Text = "Bond Level: --"
		entry.xpLabel.Text = "XP: --"
		entry.streakLabel.Text = "Care Streak: --"
		entry.qualityLabel.Text = "Care Quality: --"
		return
	end

	entry.trustLabel.Text = ("Trust: %s  (%d/%d)"):format(
		displayData.TrustState,
		math.round(displayData.Friendship),
		math.round(displayData.MaxFriendship)
	)
	entry.levelLabel.Text = ("Bond Level: %d"):format(displayData.Level)

	if displayData.XPToNextLevel > 0 then
		entry.xpLabel.Text = ("XP: %d / %d"):format(
			math.floor(displayData.XP + 0.5),
			displayData.XPToNextLevel
		)
	else
		entry.xpLabel.Text = "XP: MAX"
	end

	entry.streakLabel.Text = ("Care Streak: %d"):format(displayData.CareStreak)
	entry.qualityLabel.Text = ("Care Quality: %s"):format(displayData.CareQuality)
end

local function sync_billboards(): ()
	if not ENABLED then
		destroy_all_billboards()
		return
	end

	local visuals = get_horse_visuals()
	local activeVisuals: {[Instance]: boolean} = {}
	local visualsToDestroy = {}

	for _, horseVisual: Instance in visuals do
		activeVisuals[horseVisual] = true

		if not activeBillboards[horseVisual] then
			local entry = create_billboard(horseVisual)
			if entry then
				activeBillboards[horseVisual] = entry
			end
		end
	end

	for horseVisual in activeBillboards do
		if not activeVisuals[horseVisual] or not horseVisual.Parent then
			visualsToDestroy[#visualsToDestroy + 1] = horseVisual
		end
	end

	for _, horseVisual in visualsToDestroy do
		destroy_billboard(horseVisual)
	end

	for _, entry in activeBillboards do
		update_billboard(entry)
	end
end

local function queue_refresh(): ()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		sync_billboards()
	end)
end

local function bind_plot(plot: Instance?): ()
	disconnect_all(plotConnections)

	if not plot then
		destroy_all_billboards()
		return
	end

	plotConnections[#plotConnections + 1] = plot.DescendantAdded:Connect(function(descendant: Instance)
		if should_ignore_descendant(descendant) then
			return
		end

		queue_refresh()
	end)

	plotConnections[#plotConnections + 1] = plot.DescendantRemoving:Connect(function(descendant: Instance)
		if should_ignore_descendant(descendant) then
			return
		end

		queue_refresh()
	end)

	queue_refresh()
end

------------------//MAIN FUNCTIONS
plotValue:GetPropertyChangedSignal("Value"):Connect(function()
	bind_plot(plotValue.Value)
end)

DataUtility.client.bind("Horses.Owned", function()
	queue_refresh()
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	if not ENABLED then
		if next(activeBillboards) then
			destroy_all_billboards()
		end

		return
	end

	elapsedSinceRefresh += deltaTime

	if elapsedSinceRefresh < REFRESH_INTERVAL then
		return
	end

	elapsedSinceRefresh = 0

	for horseVisual, entry in activeBillboards do
		if not horseVisual.Parent then
			destroy_billboard(horseVisual)
		else
			update_billboard(entry)
		end
	end
end)

------------------//INIT
if ENABLED then
	bind_plot(plotValue.Value)
end
