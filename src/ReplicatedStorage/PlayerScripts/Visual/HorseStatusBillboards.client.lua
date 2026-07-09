------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

------------------//CONSTANTS
local BILLBOARD_NAME = "HorseStatusBillboard"

------------------//VARIABLES
local localPlayer: Player = Players.LocalPlayer
local modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local dictionary: Folder = modules:WaitForChild("Dictionary")
local gameData: Folder = modules:WaitForChild("GameData")
local services: Folder = modules:WaitForChild("Services")
local utility: Folder = modules:WaitForChild("Utility")

local DataUtility = require(utility:WaitForChild("DataUtility"))
local HorseStatusBillboardConfig = require(gameData:WaitForChild("HorseStatusBillboardConfig"))
local HorseBondService = require(services:WaitForChild("HorseBondService"))
local horseStatusModule = services:WaitForChild("HorseStatusService", 10)
if not horseStatusModule then
	warn("HorseStatusBillboards could not find ReplicatedStorage.Modules.Services.HorseStatusService")
	return
end

local HorseStatusService = require(horseStatusModule)
local ToolDictionary = require(dictionary:WaitForChild("ToolDictionary"))

local PLOT_VALUE_NAME: string = ToolDictionary.PlotValueName
local HORSE_FOLDER_NAME: string = ToolDictionary.HorseFolderName
local VISUAL_HORSE_ATTRIBUTE: string = ToolDictionary.VisualHorseAttribute
local HORSE_ID_ATTRIBUTE: string = ToolDictionary.HorseIdAttribute
local MOUNTED_USER_ID_ATTRIBUTE: string = ToolDictionary.MountedUserIdAttribute
local IGNORE_REFRESH_ATTRIBUTE: string = ToolDictionary.IgnoreRefreshAttribute

local plotValue: ObjectValue = localPlayer:WaitForChild(PLOT_VALUE_NAME)

local plotConnections: {RBXScriptConnection} = {}
local activeBillboards: {[Instance]: any} = {}
local refreshQueued: boolean = false
local elapsedSinceRefresh: number = 0

------------------//FUNCTIONS
local function disconnect_all(connections: {RBXScriptConnection}): ()
	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function mark_placeholder(instance: Instance): Instance
	instance:SetAttribute(IGNORE_REFRESH_ATTRIBUTE, true)
	return instance
end

local function format_status_value(value: number?): string
	if type(value) ~= "number" then
		return "--"
	end

	local decimals = math.max(0, HorseStatusBillboardConfig.ValueDecimals or 0)
	local suffix = HorseStatusBillboardConfig.ValueSuffix or ""

	if decimals == 0 then
		return ("%d%s"):format(math.round(value), suffix)
	end

	return ("%." .. decimals .. "f%s"):format(value, suffix)
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

local function get_horse_visuals(): {Instance}
	local plot = plotValue.Value
	if not plot then
		return {}
	end

	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return {}
	end

	local visuals: {Instance} = {}

	for _, slotFolder: Instance in horseFolder:GetChildren() do
		for _, child: Instance in slotFolder:GetChildren() do
			if child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true then
				visuals[#visuals + 1] = child
			end
		end
	end

	return visuals
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

local function is_horse_mounted(horseVisual: Instance): boolean
	return horseVisual:GetAttribute(MOUNTED_USER_ID_ATTRIBUTE) ~= nil
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
		if child:IsA("BillboardGui") and child.Name == BILLBOARD_NAME then
			child:Destroy()
		end
	end
end

local function create_info_label(parent: Instance, name: string)
	local label = mark_placeholder(Instance.new("TextLabel"))
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = "--"
	label.TextColor3 = HorseStatusBillboardConfig.LabelColor
	label.TextSize = HorseStatusBillboardConfig.StatusTextSize
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Parent = parent

	return label
end

local function create_status_row(parent: Instance, statusName: string)
	local row = mark_placeholder(Instance.new("Frame"))
	row.Name = statusName .. "Row"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 18)
	row.Parent = parent

	local label = mark_placeholder(Instance.new("TextLabel"))
	label.Name = statusName .. "Label"
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.Text = statusName
	label.TextColor3 = HorseStatusBillboardConfig.LabelColor
	label.TextSize = HorseStatusBillboardConfig.StatusTextSize
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Size = UDim2.new(0.58, 0, 1, 0)
	label.Parent = row

	local value = mark_placeholder(Instance.new("TextLabel"))
	value.Name = statusName .. "Value"
	value.BackgroundTransparency = 1
	value.Font = Enum.Font.GothamBold
	value.Text = "--"
	value.TextColor3 = HorseStatusBillboardConfig.ValueColor
	value.TextSize = HorseStatusBillboardConfig.StatusTextSize
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.Position = UDim2.fromScale(0.58, 0)
	value.Size = UDim2.new(0.42, 0, 1, 0)
	value.Parent = row

	return value
end

local function create_billboard(horseVisual: Instance)
	if is_horse_mounted(horseVisual) then
		return nil
	end

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
	local billboardSize = HorseStatusBillboardConfig.BillboardSize
	local studsOffset = (extents.Y * 0.5) + (HorseStatusBillboardConfig.StudsOffset or 0)

	local billboardGui = mark_placeholder(Instance.new("BillboardGui"))
	billboardGui.Name = BILLBOARD_NAME
	billboardGui.Adornee = focusPart
	billboardGui.AlwaysOnTop = true
	billboardGui.LightInfluence = 0
	billboardGui.MaxDistance = HorseStatusBillboardConfig.MaxDistance or 80
	billboardGui.Size = UDim2.fromOffset(billboardSize.X, billboardSize.Y)
	billboardGui.StudsOffset = Vector3.new(0, studsOffset, 0)
	billboardGui.Parent = horseVisual

	local mainFrame = mark_placeholder(Instance.new("Frame"))
	mainFrame.Name = "MainFrame"
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = HorseStatusBillboardConfig.BackgroundColor
	mainFrame.BackgroundTransparency = HorseStatusBillboardConfig.BackgroundTransparency
	mainFrame.BorderSizePixel = 0
	mainFrame.Position = UDim2.fromScale(0.5, 0.5)
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.Parent = billboardGui

	local corner = mark_placeholder(Instance.new("UICorner"))
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = mainFrame

	local stroke = mark_placeholder(Instance.new("UIStroke"))
	stroke.Color = HorseStatusBillboardConfig.StrokeColor
	stroke.Transparency = HorseStatusBillboardConfig.StrokeTransparency
	stroke.Parent = mainFrame

	local padding = mark_placeholder(Instance.new("UIPadding"))
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 14)
	padding.PaddingRight = UDim.new(0, 14)
	padding.Parent = mainFrame

	local layout = mark_placeholder(Instance.new("UIListLayout"))
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = mainFrame

	local titleLabel = mark_placeholder(Instance.new("TextLabel"))
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = horseId
	titleLabel.TextColor3 = HorseStatusBillboardConfig.TitleColor
	titleLabel.TextSize = HorseStatusBillboardConfig.TitleTextSize
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.Parent = mainFrame

	local trustLabel = create_info_label(mainFrame, "TrustLabel")
	local bondLabel = create_info_label(mainFrame, "BondLabel")
	local qualityLabel = create_info_label(mainFrame, "QualityLabel")

	local statusLabels = {}

	for _, statusName: string in ipairs(HorseStatusService.StatusOrder) do
		statusLabels[statusName] = create_status_row(mainFrame, statusName)
	end

	return {
		gui = billboardGui,
		horseId = horseId,
		horseVisual = horseVisual,
		titleLabel = titleLabel,
		trustLabel = trustLabel,
		bondLabel = bondLabel,
		qualityLabel = qualityLabel,
		statusLabels = statusLabels,
	}
end

local function update_billboard(entry): ()
	local horse, resolvedHorseId = HorseStatusService.GetHorse(entry.horseId)
	local statuses = HorseStatusService.GetStatuses(entry.horseId)
	local displayData = nil

	if horse then
		entry.titleLabel.Text = horse.Nickname or horse.DisplayName or resolvedHorseId or entry.horseId
		displayData = HorseBondService.GetDisplayData(horse)
	else
		entry.titleLabel.Text = entry.horseId
	end

	if not displayData then
		entry.trustLabel.Text = "Confianca: --"
		entry.bondLabel.Text = "Nivel: --"
		entry.qualityLabel.Text = "Cuidado: --"
	else
		entry.trustLabel.Text = ("Confianca: %s  (%d/%d)"):format(
			displayData.TrustState,
			math.round(displayData.Friendship),
			math.round(displayData.MaxFriendship)
		)

		if displayData.XPToNextLevel > 0 then
			entry.bondLabel.Text = ("Nivel %d  XP %d/%d"):format(
				displayData.Level,
				math.floor(displayData.XP + 0.5),
				displayData.XPToNextLevel
			)
		else
			entry.bondLabel.Text = ("Nivel %d  XP MAX"):format(displayData.Level)
		end

		entry.qualityLabel.Text = ("Cuidado: %s  Streak %d"):format(
			displayData.CareQuality,
			displayData.CareStreak
		)
	end

	for _, statusName: string in ipairs(HorseStatusService.StatusOrder) do
		local label = entry.statusLabels[statusName]
		if label then
			local value = statuses and statuses[statusName] or nil
			label.Text = format_status_value(value)
		end
	end
end

local function sync_billboards(): ()
	if not HorseStatusBillboardConfig.Enabled then
		destroy_all_billboards()
		return
	end

	local visuals = get_horse_visuals()
	local activeVisuals: {[Instance]: boolean} = {}
	local visualsToDestroy = {}

	for _, horseVisual: Instance in visuals do
		if is_horse_mounted(horseVisual) then
			continue
		end

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
	if not HorseStatusBillboardConfig.Enabled then
		if next(activeBillboards) then
			destroy_all_billboards()
		end

		return
	end

	elapsedSinceRefresh += deltaTime

	if elapsedSinceRefresh < (HorseStatusBillboardConfig.RefreshInterval or 0.25) then
		return
	end

	elapsedSinceRefresh = 0
	sync_billboards()
end)

------------------//INIT
if HorseStatusBillboardConfig.Enabled then
	bind_plot(plotValue.Value)
else
	destroy_all_billboards()
end
