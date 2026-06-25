------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//CONSTANTS
local STABLES_FOLDER_NAME = "Stables"
local PLAYER_SPAWN_NAME = "PlayerSpawn"
local PLOT_VALUE_NAME = "Plot"
local PLOT_NUMBER_ATTRIBUTE = "PlotNumber"
local PLOT_NUMBER_LOWER_ATTRIBUTE = "plotnumber"
local OWNER_USER_ID_ATTRIBUTE = "OwnerUserId"
local OWNER_NAME_ATTRIBUTE = "OwnerName"

type PlotData = {
	instance: Instance,
	number: number,
}

------------------//VARIABLES
local Modules = ReplicatedStorage:WaitForChild("Modules")
local DataUtility = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))
local HorseService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseService"))

local stablesFolder: Instance = workspace:WaitForChild(STABLES_FOLDER_NAME)
local assignedPlotByPlayer: {[Player]: PlotData} = {}
local plotOwnerByInstance: {[Instance]: Player} = {}
local playerConnections: {[Player]: {any}} = {}

------------------//FUNCTIONS
local function set_plot_number_attributes(instance: Instance, plotNumber: number?): ()
	instance:SetAttribute(PLOT_NUMBER_ATTRIBUTE, plotNumber)
	instance:SetAttribute(PLOT_NUMBER_LOWER_ATTRIBUTE, plotNumber)
end

local function ensure_plot_value(player: Player): ObjectValue
	local plotValue = player:FindFirstChild(PLOT_VALUE_NAME)
	if plotValue and plotValue:IsA("ObjectValue") then
		return plotValue
	end

	if plotValue then
		plotValue:Destroy()
	end

	local newPlotValue = Instance.new("ObjectValue")
	newPlotValue.Name = PLOT_VALUE_NAME
	newPlotValue.Parent = player

	return newPlotValue
end

local function clear_plot_metadata(player: Player): ()
	local plotValue = player:FindFirstChild(PLOT_VALUE_NAME)
	if plotValue and plotValue:IsA("ObjectValue") then
		plotValue.Value = nil
	end

	set_plot_number_attributes(player, nil)
end

local function set_plot_metadata(player: Player, plot: Instance, plotNumber: number): ()
	local plotValue = ensure_plot_value(player)
	plotValue.Value = plot
	set_plot_number_attributes(player, plotNumber)
end

local function get_plot_number(plot: Instance): number?
	local plotNumber = tonumber(plot.Name)
	if plotNumber then
		return plotNumber
	end

	local mainAttribute = plot:GetAttribute(PLOT_NUMBER_ATTRIBUTE)
	if typeof(mainAttribute) == "number" then
		return mainAttribute
	end

	local lowerAttribute = plot:GetAttribute(PLOT_NUMBER_LOWER_ATTRIBUTE)
	if typeof(lowerAttribute) == "number" then
		return lowerAttribute
	end

	return nil
end

local function get_player_spawn(plot: Instance): BasePart?
	local playerSpawn = plot:FindFirstChild(PLAYER_SPAWN_NAME)
	if playerSpawn and playerSpawn:IsA("BasePart") then
		return playerSpawn
	end

	return nil
end

local function get_ordered_plots(): {PlotData}
	local plots: {PlotData} = {}

	for _, plot: Instance in stablesFolder:GetChildren() do
		local plotNumber = get_plot_number(plot)
		local playerSpawn = get_player_spawn(plot)

		if plotNumber and playerSpawn then
			table.insert(plots, {
				instance = plot,
				number = plotNumber,
			})
		end
	end

	table.sort(plots, function(a: PlotData, b: PlotData): boolean
		return a.number < b.number
	end)

	return plots
end

local function assign_plot(player: Player): PlotData?
	local currentPlot = assignedPlotByPlayer[player]
	if currentPlot and currentPlot.instance.Parent then
		set_plot_metadata(player, currentPlot.instance, currentPlot.number)
		return currentPlot
	end

	for _, plotData: PlotData in get_ordered_plots() do
		if not plotOwnerByInstance[plotData.instance] then
			assignedPlotByPlayer[player] = plotData
			plotOwnerByInstance[plotData.instance] = player

			plotData.instance:SetAttribute(OWNER_USER_ID_ATTRIBUTE, player.UserId)
			plotData.instance:SetAttribute(OWNER_NAME_ATTRIBUTE, player.Name)
			set_plot_metadata(player, plotData.instance, plotData.number)

			return plotData
		end
	end

	warn("Nenhuma plot livre encontrada para " .. player.Name)
	clear_plot_metadata(player)

	return nil
end

local function release_plot(player: Player): ()
	local plotData = assignedPlotByPlayer[player]
	if plotData then
		HorseService.clear_plot_horses(plotData.instance)

		if plotOwnerByInstance[plotData.instance] == player then
			plotOwnerByInstance[plotData.instance] = nil
		end

		if plotData.instance.Parent then
			plotData.instance:SetAttribute(OWNER_USER_ID_ATTRIBUTE, nil)
			plotData.instance:SetAttribute(OWNER_NAME_ATTRIBUTE, nil)
		end
	end

	assignedPlotByPlayer[player] = nil
	clear_plot_metadata(player)
end

local function disconnect_player_connections(player: Player): ()
	local connections = playerConnections[player]
	if not connections then
		return
	end

	for _, connection in connections do
		connection:Disconnect()
	end

	playerConnections[player] = nil
end

local function sync_plot_horses(player: Player): ()
	local plotData = assignedPlotByPlayer[player] or assign_plot(player)
	if not plotData then
		return
	end

	HorseService.sync_plot_horses(player, plotData.instance)
end

local function teleport_character_to_plot(player: Player, character: Model): ()
	local plotData = assignedPlotByPlayer[player] or assign_plot(player)
	if not plotData then
		return
	end

	local playerSpawn = get_player_spawn(plotData.instance)
	if not playerSpawn then
		warn("Plot " .. plotData.instance.Name .. " sem PlayerSpawn valido para " .. player.Name)
		return
	end

	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then
		warn("HumanoidRootPart nao encontrado para " .. player.Name)
		return
	end

	if not character.Parent or player.Parent ~= Players then
		return
	end

	set_plot_number_attributes(character, plotData.number)
	character:PivotTo(playerSpawn.CFrame * CFrame.new(0, 3, 0))
	sync_plot_horses(player)
end

------------------//MAIN FUNCTIONS
local function on_character_added(player: Player, character: Model): ()
	task.defer(teleport_character_to_plot, player, character)
end

local function on_player_added(player: Player): ()
	assign_plot(player)
	playerConnections[player] = {}

	local horsesConnection = DataUtility.server.bind(player, "Horses", function()
		sync_plot_horses(player)
	end)

	if horsesConnection then
		playerConnections[player][#playerConnections[player] + 1] = horsesConnection
	end

	local stableConnection = DataUtility.server.bind(player, "Stable", function()
		sync_plot_horses(player)
	end)

	if stableConnection then
		playerConnections[player][#playerConnections[player] + 1] = stableConnection
	end

	sync_plot_horses(player)

	player.CharacterAdded:Connect(function(character: Model)
		on_character_added(player, character)
	end)

	local currentCharacter = player.Character
	if currentCharacter then
		on_character_added(player, currentCharacter)
	end
end

local function on_player_removing(player: Player): ()
	disconnect_player_connections(player)
	release_plot(player)
end

------------------//INIT
for _, player: Player in Players:GetPlayers() do
	on_player_added(player)
end

Players.PlayerAdded:Connect(on_player_added)
Players.PlayerRemoving:Connect(on_player_removing)
