local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local FRESH_BUCKET_ITEM_ID = "fresh_bucket"
local FILL_WATER_TANK_FUNCTION_NAME = "FillStableWaterTank"
local PLOT_VALUE_NAME = "Plot"
local HORSE_WATER_FOLDER_NAME = "HorseWater"
local WATER_TANK_MODEL_NAME = "TankHorseWater"
local WATER_PART_NAME = "Water"
local WATER_TANK_FILLED_FIELD = "WaterTankFilled"
local PROMPT_NAME = "FillStableWaterTankPrompt"
local OUTLINE_NAME = "StableWaterTankPlacementOutline"
local OUTLINE_COLOR = Color3.fromRGB(98, 175, 255)
local PROMPT_HOLD_DURATION = 3

local plotValue: ObjectValue = localPlayer:WaitForChild(PLOT_VALUE_NAME)
local activePrompts = {}
local activeOutlines = {}
local characterConnections = {}
local plotConnections = {}
local refreshQueued = false
local requestInFlight = false
local localTankFilledOverride = false
local queue_refresh

local function disconnect_all(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function destroy_prompts()
	for _, prompt in ipairs(activePrompts) do
		prompt:Destroy()
	end

	table.clear(activePrompts)

	for _, outline in ipairs(activeOutlines) do
		outline:Destroy()
	end

	table.clear(activeOutlines)
end

local function get_equipped_fresh_bucket_tool(): Tool?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local itemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(child)
			if itemDefinition and itemDefinition.ItemId == FRESH_BUCKET_ITEM_ID then
				return child
			end
		end
	end

	return nil
end

local function is_water_tank_filled(): boolean
	local stable = DataUtility.client.get("Stable")
	if type(stable) == "table" and stable[WATER_TANK_FILLED_FIELD] == false then
		localTankFilledOverride = false
	end

	return localTankFilledOverride or (type(stable) == "table" and stable[WATER_TANK_FILLED_FIELD] == true)
end

local function find_water_tank_model(plot: Instance?): Instance?
	local horseWaterFolder = plot and plot:FindFirstChild(HORSE_WATER_FOLDER_NAME)
	if not horseWaterFolder then
		return nil
	end

	return horseWaterFolder:FindFirstChild(WATER_TANK_MODEL_NAME)
		or horseWaterFolder:FindFirstChild(WATER_TANK_MODEL_NAME, true)
end

local function find_water_part(model: Instance?): BasePart?
	if not model then
		return nil
	end

	local waterPart = model:FindFirstChild(WATER_PART_NAME, true)
	return if waterPart and waterPart:IsA("BasePart") then waterPart else nil
end

local function find_prompt_parent(model: Instance?): BasePart?
	if not model then
		return nil
	end

	if model:IsA("BasePart") and model.Name ~= WATER_PART_NAME then
		return model
	end

	if model:IsA("Model") and model.PrimaryPart and model.PrimaryPart.Name ~= WATER_PART_NAME then
		return model.PrimaryPart
	end

	for _, child in ipairs(model:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= WATER_PART_NAME then
			return child
		end
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name ~= WATER_PART_NAME then
			return descendant
		end
	end

	return find_water_part(model)
end

local function create_placement_outlines(model: Instance?)
	if not model then
		return
	end

	local function add_outline(part: BasePart)
		if part.Name == WATER_PART_NAME then
			return
		end

		local selectionBox = Instance.new("SelectionBox")
		selectionBox.Name = OUTLINE_NAME
		selectionBox.Adornee = part
		selectionBox.Color3 = OUTLINE_COLOR
		selectionBox.SurfaceColor3 = OUTLINE_COLOR
		selectionBox.SurfaceTransparency = 1
		selectionBox.LineThickness = 0.035
		selectionBox.Parent = part
		activeOutlines[#activeOutlines + 1] = selectionBox
	end

	if model:IsA("BasePart") then
		add_outline(model)
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			add_outline(descendant)
		end
	end
end

local function request_fill_water_tank(tool: Tool): boolean
	if requestInFlight then
		return false
	end

	requestInFlight = true
	local callSucceeded, success = pcall(function()
		return Net.Function[FILL_WATER_TANK_FUNCTION_NAME]:Call(tool)
	end)
	requestInFlight = false

	return callSucceeded and success == true
end

function queue_refresh()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		destroy_prompts()

		local plot = plotValue.Value
		local tool = get_equipped_fresh_bucket_tool()
		if not plot or not tool or is_water_tank_filled() then
			return
		end

		local waterTankModel = find_water_tank_model(plot)
		local promptParent = find_prompt_parent(waterTankModel)
		if not promptParent then
			return
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.ActionText = "Place"
		prompt.ObjectText = "Water Tank"
		prompt.HoldDuration = PROMPT_HOLD_DURATION
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Custom
		prompt.Parent = promptParent
		create_placement_outlines(waterTankModel)

		prompt.Triggered:Connect(function()
			local currentTool = get_equipped_fresh_bucket_tool()
			if currentTool ~= tool then
				queue_refresh()
				return
			end

			prompt.Enabled = false
			local filled = request_fill_water_tank(tool)
			if filled then
				localTankFilledOverride = true
				SoundUtility.PlayGameSFX("Watering")
			elseif prompt.Parent then
				prompt.Enabled = true
			end

			queue_refresh()
		end)

		activePrompts[#activePrompts + 1] = prompt
	end)
end

local function bind_character(character: Model)
	disconnect_all(characterConnections)

	characterConnections[#characterConnections + 1] = character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	characterConnections[#characterConnections + 1] = character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	queue_refresh()
end

local function bind_plot(plot: Instance?)
	disconnect_all(plotConnections)

	if not plot then
		queue_refresh()
		return
	end

	plotConnections[#plotConnections + 1] = plot.DescendantAdded:Connect(function(descendant)
		if descendant.Name == HORSE_WATER_FOLDER_NAME
			or descendant.Name == WATER_TANK_MODEL_NAME
			or descendant.Name == WATER_PART_NAME
		then
			queue_refresh()
		end
	end)

	plotConnections[#plotConnections + 1] = plot.DescendantRemoving:Connect(function(descendant)
		if descendant.Name == PROMPT_NAME then
			return
		end

		if descendant.Name == HORSE_WATER_FOLDER_NAME
			or descendant.Name == WATER_TANK_MODEL_NAME
			or descendant.Name == WATER_PART_NAME
		then
			queue_refresh()
		end
	end)

	queue_refresh()
end

DataUtility.client.ensure_remotes()

plotValue:GetPropertyChangedSignal("Value"):Connect(function()
	localTankFilledOverride = false
	bind_plot(plotValue.Value)
end)

DataUtility.client.bind("Stable", function(stable)
	localTankFilledOverride = type(stable) == "table" and stable[WATER_TANK_FILLED_FIELD] == true
	queue_refresh()
end)

localPlayer.CharacterAdded:Connect(bind_character)
localPlayer.CharacterRemoving:Connect(function()
	disconnect_all(characterConnections)
	destroy_prompts()
	queue_refresh()
end)

if localPlayer.Character then
	bind_character(localPlayer.Character)
end

bind_plot(plotValue.Value)
queue_refresh()

script:SetAttribute("RuntimeReady", true)
