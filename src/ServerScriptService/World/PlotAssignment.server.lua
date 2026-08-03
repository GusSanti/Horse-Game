------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

------------------//CONSTANTS
local STABLES_FOLDER_NAME = "Stables"
local STABLE_PLOT_NAME = "Stable"
local STABLE_PLOT_NAME_PREFIX = "Stable"
local PLAYER_SPAWN_NAME = "PlayerSpawn"
local PLOT_VALUE_NAME = "Plot"
local PLOT_NUMBER_ATTRIBUTE = "PlotNumber"
local PLOT_NUMBER_LOWER_ATTRIBUTE = "plotnumber"
local OWNER_USER_ID_ATTRIBUTE = "OwnerUserId"
local OWNER_NAME_ATTRIBUTE = "OwnerName"
local STABLE_LEVEL_ATTRIBUTE = "StableLevel"
local HAS_HAY_BALE_FOLDER_ATTRIBUTE = "HasHayBaleFolder"
local HAS_HORSE_WATER_ATTRIBUTE = "HasHorseWater"
local HORSE_FOLDER_NAME = "HorseFolder"
local HAY_BALE_FOLDER_NAME = "HayBaleFolder"
local HORSE_WATER_FOLDER_NAME = "HorseWater"
local SLOT_PROMPT_PART_NAME = "Proximity"
local SLOT_PROMPT_NAME = "BuyStableSlotPrompt"
local SLOT_PROMPT_ACTION_TEXT = "Buy"
local SLOT_PROMPT_HOLD_DURATION = 0
local SLOT_PROMPT_MAX_ACTIVATION_DISTANCE = 10
local TELEPORT_TO_STABLE_EVENT_NAME = "TeleportToStable"

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
local HorseRoamingConfig = require(Modules:WaitForChild("GameData"):WaitForChild("Horse"):WaitForChild("HorseRoamingConfig"))
local DataUtility = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))
local HorseRoamingService = require(HorseModules:WaitForChild("HorseRoamingService"))
local HorseService = require(HorseModules:WaitForChild("HorseService"))
local Trove = require(Libraries:WaitForChild("Trove"))
local Net = require(Libraries:WaitForChild("Net"))

local stablesFolder: Instance = workspace:WaitForChild(STABLES_FOLDER_NAME)
local assignedPlotByPlayer: {[Player]: PlotData} = {}
local plotOwnerByInstance: {[Instance]: Player} = {}
local playerTroves: {[Player]: any} = {}
local plotTroves: {[Player]: any} = {}
local activeLevelByPlayer: {[Player]: number} = {}
local changingLevelByPlayer: {[Player]: boolean} = {}
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
	player:SetAttribute(STABLE_LEVEL_ATTRIBUTE, nil)
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

local function get_level_from_template_name(templateName: string): number?
	local levelText = string.match(string.lower(templateName), "^%s*level%s*(%d+)%s*$")
	return levelText and tonumber(levelText) or nil
end

local function ensure_horse_folder_layout(plot: Instance): Instance?
	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	local directSlots: {Instance} = {}

	for _, slotName: string in StableDictionary.HorseSlotOrder do
		local directSlot = plot:FindFirstChild(slotName)
		if directSlot then
			directSlots[#directSlots + 1] = directSlot
		end
	end

	if not horseFolder and #directSlots > 0 then
		horseFolder = Instance.new("Folder")
		horseFolder.Name = HORSE_FOLDER_NAME
		horseFolder.Parent = plot
	end

	if horseFolder then
		for _, directSlot in directSlots do
			directSlot.Parent = horseFolder
		end
	end

	return horseFolder
end

local function get_ordered_plots(): {PlotData}
	local plots: {PlotData} = {}

	for _, plot: Instance in stablesFolder:GetChildren() do
		local isLevelTemplate = get_level_from_template_name(plot.Name) ~= nil
		local plotNumber = if isLevelTemplate then nil else get_plot_number(plot)
		local playerSpawn = if isLevelTemplate then nil else get_player_spawn(plot)

		if plotNumber and playerSpawn then
			table.insert(plots, {
				instance = plot,
				number = plotNumber,
			})
		end
	end

	-- In the level-based layout, Workspace.Stables contains the LevelX templates
	-- and the physical plots live in Workspace as Stable, Stable2, Stable3, etc.
	-- Numbered children of Stables remain supported for older maps.
	if #plots == 0 then
		local stableContainer = workspace:FindFirstChild(STABLE_PLOT_NAME)
		if stableContainer and not get_player_spawn(stableContainer) then
			for _, plot: Instance in stableContainer:GetChildren() do
				local plotNumber = get_plot_number(plot)
				local playerSpawn = get_player_spawn(plot)
				if plotNumber and playerSpawn then
					table.insert(plots, {
						instance = plot,
						number = plotNumber,
					})
				end
			end
		end
	end

	if #plots == 0 then
		for _, plot: Instance in workspace:GetChildren() do
			local stableSuffix = string.match(plot.Name, "^" .. STABLE_PLOT_NAME_PREFIX .. "(%d*)$")
			local playerSpawn = get_player_spawn(plot)
			if stableSuffix ~= nil and playerSpawn then
				local fallbackNumber = if plot.Name == STABLE_PLOT_NAME
					then 1
					else tonumber(stableSuffix)
				local plotNumber = get_plot_number(plot) or fallbackNumber
				if plotNumber then
					table.insert(plots, {
						instance = plot,
						number = plotNumber,
					})
				end
			end
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
	local plotTrove = plotTroves[player]
	if plotTrove then
		plotTrove:Destroy()
		plotTroves[player] = nil
	end

	local playerTrove = playerTroves[player]
	if not playerTrove then
		return
	end

	playerTrove:Destroy()
	playerTroves[player] = nil
end

local function get_plot_template_from_level(levelTemplate: Instance, plotNumber: number): Instance?
	-- Also support a single plot model directly named LevelX.
	if get_player_spawn(levelTemplate) then
		return levelTemplate
	end

	for _, candidate: Instance in levelTemplate:GetChildren() do
		if get_plot_number(candidate) == plotNumber and get_player_spawn(candidate) then
			return candidate
		end
	end

	return nil
end

local function get_level_plot_template(level: number, plotNumber: number): Instance?
	local visitedLevelTemplates: {[Instance]: boolean} = {}

	local function test_level_template(levelTemplate: Instance): Instance?
		if visitedLevelTemplates[levelTemplate]
			or get_level_from_template_name(levelTemplate.Name) ~= level
		then
			return nil
		end
		visitedLevelTemplates[levelTemplate] = true
		return get_plot_template_from_level(levelTemplate, plotNumber)
	end

	for _, child in stablesFolder:GetChildren() do
		local plotTemplate = test_level_template(child)
		if plotTemplate then
			return plotTemplate
		end
	end

	-- Roblox permits duplicate/nested Stables folders. Search every LevelX and
	-- select the numbered sub-plot that matches the player's assigned plot.
	for _, root: Instance in { workspace, ServerStorage, ReplicatedStorage } do
		for _, descendant in root:GetDescendants() do
			local plotTemplate = test_level_template(descendant)
			if plotTemplate then
				return plotTemplate
			end
		end
	end

	return nil
end

local function align_level_clone_to_spawn(levelClone: Instance, targetSpawn: BasePart): (boolean, string)
	local levelSpawn = get_player_spawn(levelClone)
	if not levelSpawn then
		return false, PLAYER_SPAWN_NAME .. "Missing"
	end

	local offset = targetSpawn.CFrame * levelSpawn.CFrame:Inverse()
	if levelClone:IsA("Model") then
		levelClone:PivotTo(offset * levelClone:GetPivot())
	else
		if levelClone:IsA("BasePart") then
			levelClone.CFrame = offset * levelClone.CFrame
		end

		for _, descendant in levelClone:GetDescendants() do
			if descendant:IsA("BasePart") then
				descendant.CFrame = offset * descendant.CFrame
			end
		end
	end

	return true, "Aligned"
end

local function replace_plot_contents(plot: Instance, template: Instance): (boolean, string)
	local targetSpawn = get_player_spawn(plot)
	if not targetSpawn then
		return false, "TargetPlayerSpawnMissing"
	end

	local cloneSucceeded, levelClone = pcall(function()
		return template:Clone()
	end)
	if not cloneSucceeded or not levelClone then
		return false, "TemplateCloneFailed"
	end

	local aligned, alignReason = align_level_clone_to_spawn(levelClone, targetSpawn)
	if not aligned then
		levelClone:Destroy()
		return false, alignReason
	end

	local clonedSpawn = get_player_spawn(levelClone)
	for _, child in plot:GetChildren() do
		if child ~= targetSpawn then
			child:Destroy()
		end
	end

	for _, child in levelClone:GetChildren() do
		if child ~= clonedSpawn then
			child.Parent = plot
		end
	end

	levelClone:Destroy()
	return true, "Replaced"
end

local function sync_plot_horses(player: Player): ()
	local plotData = assignedPlotByPlayer[player] or assign_plot(player)
	if not plotData then
		return
	end

	HorseService.SyncPlotHorses(player, plotData.instance)
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
	if proximityPart:IsA("ProximityPrompt") then
		return proximityPart
	end

	for _, child in ipairs(proximityPart:GetChildren()) do
		if child:IsA("ProximityPrompt") then
			return child
		end
	end

	if not proximityPart:IsA("BasePart") and not proximityPart:IsA("Attachment") then
		return nil
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = SLOT_PROMPT_NAME
	prompt.HoldDuration = SLOT_PROMPT_HOLD_DURATION
	prompt.MaxActivationDistance = SLOT_PROMPT_MAX_ACTIVATION_DISTANCE
	prompt.RequiresLineOfSight = false
	prompt.Parent = proximityPart

	return prompt
end

local function get_slot_folder(plot: Instance, slotName: string): Instance?
	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	return horseFolder and horseFolder:FindFirstChild(slotName) or nil
end

local function ensure_free_horse_part(slotFolder: Instance): BasePart?
	local existing = slotFolder:FindFirstChild(HorseRoamingConfig.FreeHorsePartName)
	if existing then
		if existing:IsA("BasePart") then
			return existing
		end

		warn(("%s precisa ser uma BasePart em %s"):format(
			HorseRoamingConfig.FreeHorsePartName,
			slotFolder:GetFullName()
		))
		return nil
	end

	local referencePart = slotFolder:FindFirstChild(SLOT_PROMPT_PART_NAME)
	if not referencePart or not referencePart:IsA("BasePart") then
		referencePart = slotFolder:FindFirstChild("HorsePosition")
	end
	if not referencePart or not referencePart:IsA("BasePart") then
		return nil
	end

	local freeHorsePart = Instance.new("Part")
	freeHorsePart.Name = HorseRoamingConfig.FreeHorsePartName
	freeHorsePart.Size = referencePart.Size
	freeHorsePart.CFrame = referencePart.CFrame
	freeHorsePart.Transparency = 1
	freeHorsePart.Anchored = true
	freeHorsePart.CanCollide = false
	freeHorsePart.CanQuery = false
	freeHorsePart.CanTouch = false
	freeHorsePart.CastShadow = false
	freeHorsePart.Parent = slotFolder
	return freeHorsePart
end

local function get_free_horse_prompt(plot: Instance, slotName: string): ProximityPrompt?
	local slotFolder = get_slot_folder(plot, slotName)
	local freeHorsePart = slotFolder and slotFolder:FindFirstChild(HorseRoamingConfig.FreeHorsePartName)
	if not freeHorsePart then
		return nil
	end

	local prompt = freeHorsePart:FindFirstChild(HorseRoamingConfig.FreePromptName)
	return if prompt and prompt:IsA("ProximityPrompt") then prompt else nil
end

local function ensure_free_horse_prompt(plot: Instance, slotName: string): ProximityPrompt?
	local slotFolder = get_slot_folder(plot, slotName)
	if not slotFolder then
		return nil
	end

	local freeHorsePart = ensure_free_horse_part(slotFolder)
	if not freeHorsePart then
		return nil
	end

	local prompt = freeHorsePart:FindFirstChild(HorseRoamingConfig.FreePromptName)
	if prompt and not prompt:IsA("ProximityPrompt") then
		warn(("%s precisa ser um ProximityPrompt em %s"):format(
			HorseRoamingConfig.FreePromptName,
			freeHorsePart:GetFullName()
		))
		return nil
	end

	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = HorseRoamingConfig.FreePromptName
		prompt.Parent = freeHorsePart
	end

	prompt.HoldDuration = HorseRoamingConfig.FreePromptHoldDuration
	prompt.MaxActivationDistance = HorseRoamingConfig.FreePromptMaxActivationDistance
	prompt.KeyboardKeyCode = HorseRoamingConfig.FreePromptKeyboardKeyCode
	prompt.RequiresLineOfSight = false
	return prompt
end

disable_plot_slot_prompts = function(plot: Instance): ()
	for _, slotName: string in ipairs(StableDictionary.HorseSlotOrder) do
		local prompt = get_slot_prompt(plot, slotName)
		if prompt then
			prompt.Enabled = false
		end

		local freeHorsePrompt = get_free_horse_prompt(plot, slotName)
		if freeHorsePrompt then
			freeHorsePrompt.Enabled = false
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

local function refresh_free_horse_prompts(player: Player): ()
	local plotData = assignedPlotByPlayer[player]
	if not plotData then
		return
	end

	local stable = DataUtility.server.get(player, "Stable")
	local horseSlots = type(stable) == "table" and stable.HorseSlots or nil
	local ownedStalls = get_owned_stalls_from_stable(stable)

	for slotIndex, slotName: string in ipairs(StableDictionary.HorseSlotOrder) do
		local prompt = get_free_horse_prompt(plotData.instance, slotName)
		if prompt then
			local horseId = type(horseSlots) == "table" and horseSlots[slotName] or nil
			local hasAssignedHorse = slotIndex <= ownedStalls
				and type(horseId) == "string"
				and horseId ~= ""
			local isFree = hasAssignedHorse and HorseRoamingService.IsHorseFree(player, horseId)

			prompt.Enabled = hasAssignedHorse
			prompt.ActionText = if isFree
				then HorseRoamingConfig.ReturnPromptActionText
				else HorseRoamingConfig.FreePromptActionText
			prompt.ObjectText = HorseRoamingConfig.FreePromptObjectText
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
				refresh_free_horse_prompts(player)
			end))
		end

		local freeHorsePrompt = ensure_free_horse_prompt(plot, slotName)
		if freeHorsePrompt then
			playerTrove:Add(freeHorsePrompt.Triggered:Connect(function(triggeringPlayer: Player)
				if triggeringPlayer ~= player then
					return
				end

				local stable = DataUtility.server.get(player, "Stable")
				local horseSlots = type(stable) == "table" and stable.HorseSlots or nil
				local horseId = type(horseSlots) == "table" and horseSlots[slotName] or nil
				if type(horseId) ~= "string" or horseId == "" then
					refresh_free_horse_prompts(player)
					return
				end

				local isFree = HorseRoamingService.ToggleHorseFree(player, horseId)
				if not isFree then
					HorseService.SyncPlotHorses(player, plot)
				end
				refresh_free_horse_prompts(player)
			end))
		end
	end

	refresh_plot_slot_prompts(player)
	refresh_free_horse_prompts(player)
end

local function rebind_plot_slot_prompts(player: Player, plot: Instance): ()
	local previousTrove = plotTroves[player]
	if previousTrove then
		previousTrove:Destroy()
	end

	local plotTrove = Trove.new()
	plotTroves[player] = plotTrove
	bind_plot_slot_prompts(player, plotTrove, plot)
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
		warn(("[PlotAssignment] Falha ao aplicar %s para %s: %s"):format(
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
		warn(("[PlotAssignment] %s nao conseguiu usar !level%s: %s"):format(
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

	playerTrove:Connect(player.CharacterAdded, function(character: Model)
		on_character_added(player, character)
	end)
	playerTrove:Connect(player.Chatted, function(message: string)
		task.spawn(handle_chat_command, player, message)
	end)

	task.spawn(restore_saved_plot_level, player)

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

Net.Event[TELEPORT_TO_STABLE_EVENT_NAME]:Connect(teleport_player_to_plot)

Players.PlayerAdded:Connect(on_player_added)
Players.PlayerRemoving:Connect(on_player_removing)
