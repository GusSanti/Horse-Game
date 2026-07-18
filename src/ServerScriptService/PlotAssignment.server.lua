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
local HORSE_FOLDER_NAME = "HorseFolder"
local SLOT_PROMPT_PART_NAME = "Proximity"
local SLOT_PROMPT_ACTION_TEXT = "Buy"
local SLOT_PROMPT_HOLD_DURATION = 0

type PlotData = {
	instance: Instance,
	number: number,
}

------------------//VARIABLES
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local StableDictionary = require(Modules:WaitForChild("Dictionary"):WaitForChild("StableDictionary"))
local DataUtility = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))
local HorseService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseService"))
local Trove = require(Libraries:WaitForChild("Trove"))

local stablesFolder: Instance = workspace:WaitForChild(STABLES_FOLDER_NAME)
local assignedPlotByPlayer: {[Player]: PlotData} = {}
local plotOwnerByInstance: {[Instance]: Player} = {}
local playerTroves: {[Player]: any} = {}
local disable_plot_slot_prompts

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

	warn("No free plot found for " .. player.Name)
	clear_plot_metadata(player)

	return nil
end

local function release_plot(player: Player): ()
	local plotData = assignedPlotByPlayer[player]
	if plotData then
		HorseService.clear_plot_horses(plotData.instance)
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
	clear_plot_metadata(player)
end

local function cleanup_player(player: Player): ()
	local playerTrove = playerTroves[player]
	if not playerTrove then
		return
	end

	playerTrove:Destroy()
	playerTroves[player] = nil
end

local function sync_plot_horses(player: Player): ()
	local plotData = assignedPlotByPlayer[player] or assign_plot(player)
	if not plotData then
		return
	end

	HorseService.sync_plot_horses(player, plotData.instance)
end

local function get_owned_stalls_from_stable(stable): number
	local ownedStalls = tonumber(stable and stable.OwnedStalls) or StableDictionary.DefaultOwnedStalls
	return math.clamp(
		math.floor(ownedStalls),
		0,
		StableDictionary.MaxOwnedStalls or #StableDictionary.HorseSlotOrder
	)
end

local function get_slot_prompt(plot: Instance, slotName: string): ProximityPrompt?
	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	local slotFolder = horseFolder and horseFolder:FindFirstChild(slotName)
	local proximityPart = slotFolder and slotFolder:FindFirstChild(SLOT_PROMPT_PART_NAME)
	if not proximityPart then
		return nil
	end

	for _, child in ipairs(proximityPart:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			return child
		end
	end

	return nil
end

disable_plot_slot_prompts = function(plot: Instance): ()
	for _, slotName: string in ipairs(StableDictionary.HorseSlotOrder) do
		local prompt = get_slot_prompt(plot, slotName)
		if prompt then
			prompt.Enabled = false
		end
	end
end

local function refresh_plot_slot_prompts(player: Player): ()
	local plotData = assignedPlotByPlayer[player]
	if not plotData then
		return
	end

	local stable = DataUtility.server.get(player, "Stable")
	if not stable then
		disable_plot_slot_prompts(plotData.instance)
		return
	end

	local ownedStalls = get_owned_stalls_from_stable(stable)

	for slotIndex, slotName: string in ipairs(StableDictionary.HorseSlotOrder) do
		local prompt = get_slot_prompt(plotData.instance, slotName)
		if prompt then
			local slotPrice = StableDictionary.get_slot_purchase_price(slotName)
			local isStarterSlot = slotIndex == 1
			local isOwned = slotIndex <= ownedStalls
			local isNextLockedSlot = slotIndex == (ownedStalls + 1)
			local isPurchasable = (not isStarterSlot)
				and (not isOwned)
				and isNextLockedSlot
				and type(slotPrice) == "number"
				and slotPrice > 0

			prompt.Enabled = isPurchasable
			prompt.HoldDuration = SLOT_PROMPT_HOLD_DURATION
			prompt.ActionText = SLOT_PROMPT_ACTION_TEXT
			prompt.ObjectText = type(slotPrice) == "number"
				and ("Slot %d - %d Horseshoes"):format(slotIndex, slotPrice)
				or ("Slot %d"):format(slotIndex)
		end
	end
end

local function bind_plot_slot_prompts(player: Player, playerTrove, plot: Instance): ()
	for _, slotName: string in ipairs(StableDictionary.HorseSlotOrder) do
		local prompt = get_slot_prompt(plot, slotName)
		if prompt then
			playerTrove:Add(prompt.Triggered:Connect(function(triggeringPlayer: Player)
				if triggeringPlayer ~= player then
					return
				end

				HorseService.BuyStableSlot(player, slotName)
				refresh_plot_slot_prompts(player)
			end))
		end
	end

	refresh_plot_slot_prompts(player)
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
		bind_plot_slot_prompts(player, playerTrove, plotData.instance)
	end

	local horsesConnection = DataUtility.server.bind(player, "Horses", function()
		sync_plot_horses(player)
	end)

	if horsesConnection then
		playerTrove:Add(horsesConnection)
	end

	local stableConnection = DataUtility.server.bind(player, "Stable", function()
		sync_plot_horses(player)
		refresh_plot_slot_prompts(player)
	end)

	if stableConnection then
		playerTrove:Add(stableConnection)
	end

	sync_plot_horses(player)

	playerTrove:Connect(player.CharacterAdded, function(character: Model)
		on_character_added(player, character)
	end)

	local currentCharacter = player.Character
	if currentCharacter then
		on_character_added(player, currentCharacter)
	end
end

local function on_player_removing(player: Player): ()
	cleanup_player(player)
	release_plot(player)
end

------------------//INIT
for _, player: Player in Players:GetPlayers() do
	on_player_added(player)
end

Players.PlayerAdded:Connect(on_player_added)
Players.PlayerRemoving:Connect(on_player_removing)
