--!strict

------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//CONSTANTS
local PLOT_VALUE_NAME = "Plot"
local PLOT_NUMBER_ATTRIBUTE = "PlotNumber"
local PLOT_NUMBER_LOWER_ATTRIBUTE = "plotnumber"
local OWNER_USER_ID_ATTRIBUTE = "OwnerUserId"
local OWNER_NAME_ATTRIBUTE = "OwnerName"
local STABLE_LEVEL_ATTRIBUTE = "StableLevel"
local HAS_HAY_BALE_FOLDER_ATTRIBUTE = "HasHayBaleFolder"
local HAS_HORSE_WATER_ATTRIBUTE = "HasHorseWater"
local HAY_BALE_FOLDER_NAME = "HayBaleFolder"
local HORSE_WATER_FOLDER_NAME = "HorseWater"

type PlotData = {
	instance: Instance,
	number: number,
}

------------------//VARIABLES
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local ServerModules = ServerStorage:WaitForChild("Modules")
local HorseModules = ServerModules:WaitForChild("Horse")
local StableDictionary = require(Modules:WaitForChild("Dictionary"):WaitForChild("StableDictionary"))
local DataUtility = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))
local Framework = require(Modules:WaitForChild("Framework"))
local Network = require(Modules:WaitForChild("Network"))
local HorseRoamingService = require(HorseModules:WaitForChild("HorseRoamingService"))
local HorseService = require(HorseModules:WaitForChild("HorseService"))
local Trove = require(Libraries:WaitForChild("Trove"))
local Layout = require(script.Layout)
local Prompts = require(script.Prompts)

local assignedPlotByPlayer: {[Player]: PlotData} = {}
local plotOwnerByInstance: {[Instance]: Player} = {}
local playerTroves: {[Player]: any} = {}
local activeLevelByPlayer: {[Player]: number} = {}
local changingLevelByPlayer: {[Player]: boolean} = {}
local promptRuntime: any = nil
local disable_plot_slot_prompts: (Instance) -> ()

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
	player:SetAttribute(STABLE_LEVEL_ATTRIBUTE, nil)
end

local function set_plot_metadata(player: Player, plot: Instance, plotNumber: number): ()
	local plotValue = ensure_plot_value(player)
	plotValue.Value = plot
	set_plot_number_attributes(player, plotNumber)
end

local get_player_spawn = Layout.GetPlayerSpawn
local ensure_horse_folder_layout = Layout.EnsureHorseFolder
local get_ordered_plots = Layout.GetOrderedPlots

local function assign_plot(player: Player): PlotData?
	local currentPlot = assignedPlotByPlayer[player]
	if currentPlot and currentPlot.instance.Parent then
		set_plot_metadata(player, currentPlot.instance, currentPlot.number)
		return currentPlot
	end

	for _, plotData: PlotData in get_ordered_plots() do
		if not plotOwnerByInstance[plotData.instance] then
			ensure_horse_folder_layout(plotData.instance)
			assignedPlotByPlayer[player] = plotData
			plotOwnerByInstance[plotData.instance] = player

			plotData.instance:SetAttribute(OWNER_USER_ID_ATTRIBUTE, player.UserId)
			plotData.instance:SetAttribute(OWNER_NAME_ATTRIBUTE, player.Name)
			set_plot_metadata(player, plotData.instance, plotData.number)

			return plotData
		end
	end

	warn("No free plot found for " .. player.Name)
	clear_plot_metadata(player)

	return nil
end

local function release_plot(player: Player): ()
	local plotData = assignedPlotByPlayer[player]
	if plotData then
		HorseService.ClearPlotHorses(plotData.instance)
		disable_plot_slot_prompts(plotData.instance)

		if plotOwnerByInstance[plotData.instance] == player then
			plotOwnerByInstance[plotData.instance] = nil
		end

		if plotData.instance.Parent then
			plotData.instance:SetAttribute(OWNER_USER_ID_ATTRIBUTE, nil)
			plotData.instance:SetAttribute(OWNER_NAME_ATTRIBUTE, nil)
		end
	end

	assignedPlotByPlayer[player] = nil
	activeLevelByPlayer[player] = nil
	changingLevelByPlayer[player] = nil
	clear_plot_metadata(player)
end

local function cleanup_player(player: Player): ()
	if promptRuntime then
		promptRuntime:CleanupPlayer(player)
	end

	local playerTrove = playerTroves[player]
	if not playerTrove then
		return
	end

	playerTrove:Destroy()
	playerTroves[player] = nil
end

local get_level_plot_template = Layout.GetLevelPlotTemplate
local replace_plot_contents = Layout.ReplacePlotContents

local function sync_plot_horses(player: Player): ()
	local plotData = assignedPlotByPlayer[player] or assign_plot(player)
	if not plotData then
		return
	end

	HorseService.SyncPlotHorses(player, plotData.instance)
end

promptRuntime = Prompts.new(assignedPlotByPlayer, sync_plot_horses)
disable_plot_slot_prompts = function(plot: Instance): ()
	promptRuntime:Disable(plot)
end
local function refresh_plot_slot_prompts(player: Player): ()
	promptRuntime:RefreshSlots(player)
end
local function refresh_free_horse_prompts(player: Player): ()
	promptRuntime:RefreshFree(player)
end
local function rebind_plot_slot_prompts(player: Player, plot: Instance): ()
	promptRuntime:Rebind(player, plot)
end

local function set_player_plot_level(player: Player, requestedLevel): (boolean, string)
	if player.Parent ~= Players then
		return false, "PlayerUnavailable"
	end

	if changingLevelByPlayer[player] then
		return false, "LevelChangeBusy"
	end

	local numericLevel = tonumber(requestedLevel)
	if not numericLevel or numericLevel % 1 ~= 0 then
		return false, "InvalidLevel"
	end

	local level = math.floor(numericLevel)
	if level < StableDictionary.DefaultLevel or level > StableDictionary.MaxLevel then
		return false, "InvalidLevel"
	end

	local plotData = assignedPlotByPlayer[player] or assign_plot(player)
	if not plotData then
		return false, "PlotMissing"
	end

	local template = get_level_plot_template(level, plotData.number)
	if not template then
		return false, "LevelPlotTemplateMissing"
	end

	local stable = DataUtility.server.get(player, "Stable")
	if player.Parent ~= Players then
		return false, "PlayerUnavailable"
	elseif type(stable) ~= "table" then
		return false, "StableDataMissing"
	end

	changingLevelByPlayer[player] = true
	HorseRoamingService.ReturnPlayerHorsesToStable(player)
	HorseService.ClearPlotHorses(plotData.instance)
	disable_plot_slot_prompts(plotData.instance)

	local replaced, replaceReason = replace_plot_contents(plotData.instance, template)
	if not replaced then
		changingLevelByPlayer[player] = nil
		rebind_plot_slot_prompts(player, plotData.instance)
		sync_plot_horses(player)
		warn(("[PlotRuntime] Failed to apply %s for %s: %s"):format(
			template.Name,
			player.Name,
			replaceReason
		))
		return false, replaceReason
	end

	ensure_horse_folder_layout(plotData.instance)
	activeLevelByPlayer[player] = level
	plotData.instance:SetAttribute(STABLE_LEVEL_ATTRIBUTE, level)
	plotData.instance:SetAttribute(
		HAS_HAY_BALE_FOLDER_ATTRIBUTE,
		plotData.instance:FindFirstChild(HAY_BALE_FOLDER_NAME) ~= nil
	)
	plotData.instance:SetAttribute(
		HAS_HORSE_WATER_ATTRIBUTE,
		plotData.instance:FindFirstChild(HORSE_WATER_FOLDER_NAME) ~= nil
	)
	player:SetAttribute(STABLE_LEVEL_ATTRIBUTE, level)
	rebind_plot_slot_prompts(player, plotData.instance)

	-- OwnedStalls and HorseSlots intentionally stay untouched: bought slots are
	-- player-wide and immediately become available in every level that contains
	-- their matching Slot folder.
	stable.Level = level
	DataUtility.server.set(player, "Stable", stable)
	sync_plot_horses(player)
	refresh_plot_slot_prompts(player)
	refresh_free_horse_prompts(player)
	changingLevelByPlayer[player] = nil

	return true, StableDictionary.get_level_template_name(level)
end

local function restore_saved_plot_level(player: Player): ()
	local stable = DataUtility.server.get(player, "Stable")
	if type(stable) ~= "table" or player.Parent ~= Players then
		return
	end

	local savedLevel = StableDictionary.get_normalized_level(stable.Level)
	local changed, reason = set_player_plot_level(player, savedLevel)
	if not changed and reason == "LevelPlotTemplateMissing" and savedLevel ~= StableDictionary.DefaultLevel then
		set_player_plot_level(player, StableDictionary.DefaultLevel)
	end
end

local function handle_chat_command(player: Player, message: string): ()
	local requestedLevel = string.match(string.lower(message), "^%s*!level(%d+)%s*$")
	if not requestedLevel then
		return
	end

	local changed, reason = set_player_plot_level(player, requestedLevel)
	if not changed then
		warn(("[PlotRuntime] %s could not use !level%s: %s"):format(
			player.Name,
			requestedLevel,
			reason
		))
	end
end

local function teleport_character_to_plot(player: Player, character: Model): ()
	local plotData = assignedPlotByPlayer[player] or assign_plot(player)
	if not plotData then
		return
	end

	local playerSpawn = get_player_spawn(plotData.instance)
	if not playerSpawn then
		warn("Plot " .. plotData.instance.Name .. " has no valid PlayerSpawn for " .. player.Name)
		return
	end

	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then
		warn("HumanoidRootPart not found for " .. player.Name)
		return
	end

	if not character.Parent or player.Parent ~= Players then
		return
	end

	set_plot_number_attributes(character, plotData.number)
	character:PivotTo(playerSpawn.CFrame * CFrame.new(0, 3, 0))
	sync_plot_horses(player)
end

local function teleport_player_to_plot(player: Player): ()
	local character = player.Character
	if not character then
		return
	end

	teleport_character_to_plot(player, character)
end

------------------//MAIN FUNCTIONS
local function on_character_added(player: Player, character: Model): ()
	task.defer(teleport_character_to_plot, player, character)
end

local function on_player_added(player: Player): ()
	cleanup_player(player)
	assign_plot(player)

	local playerTrove = Trove.new()
	playerTroves[player] = playerTrove

	local plotData = assignedPlotByPlayer[player]
	if plotData then
		rebind_plot_slot_prompts(player, plotData.instance)
	end

	local horsesConnection = DataUtility.server.bind(player, "Horses", function()
		sync_plot_horses(player)
		refresh_free_horse_prompts(player)
	end)

	if horsesConnection then
		playerTrove:Add(horsesConnection)
	end

	local stableConnection = DataUtility.server.bind(player, "Stable", function(stable)
		sync_plot_horses(player)
		refresh_plot_slot_prompts(player)
		refresh_free_horse_prompts(player)

		if type(stable) == "table" then
			local savedLevel = StableDictionary.get_normalized_level(stable.Level)
			if activeLevelByPlayer[player] ~= savedLevel and not changingLevelByPlayer[player] then
				task.defer(set_player_plot_level, player, savedLevel)
			end
		end
	end)

	if stableConnection then
		playerTrove:Add(stableConnection)
	end

	sync_plot_horses(player)

	playerTrove:Connect(player.Chatted, function(message: string)
		task.spawn(handle_chat_command, player, message)
	end)

	playerTrove:Add(task.spawn(restore_saved_plot_level, player))
end

local function on_player_removing(player: Player): ()
	cleanup_player(player)
	release_plot(player)
end

local PlotRuntime = {
	Name = "PlotRuntime",
	Trove = nil :: any,
}

function PlotRuntime:Init(): ()
	if self.Trove then
		return
	end

	self.Trove = Trove.new()
	Network.Events.TeleportToStable:Connect(teleport_player_to_plot, self.Trove)
	self.Trove:Connect(Framework.RuntimeEvents.PlayerAdded, on_player_added)
	self.Trove:Connect(Framework.RuntimeEvents.PlayerRemoving, on_player_removing)
	self.Trove:Connect(Framework.RuntimeEvents.CharacterAdded, on_character_added)
end

function PlotRuntime:Destroy(): ()
	if not self.Trove then
		return
	end

	for Player: Player in table.clone(playerTroves) do
		on_player_removing(Player)
	end
	promptRuntime:Destroy()
	self.Trove:Destroy()
	self.Trove = nil
	table.clear(assignedPlotByPlayer)
	table.clear(plotOwnerByInstance)
	table.clear(activeLevelByPlayer)
	table.clear(changingLevelByPlayer)
end

return PlotRuntime
