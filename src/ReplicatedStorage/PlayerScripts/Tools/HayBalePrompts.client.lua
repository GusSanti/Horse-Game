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

local HAY_BALE_ITEM_ID = "hay_bale"
local PLACE_HAY_BALE_FUNCTION_NAME = "PlaceStableHayBale"
local PLOT_VALUE_NAME = "Plot"
local HAY_BALE_FOLDER_NAME = "HayBaleFolder"
local HAY_BALE_BUNDLE_NAME = "HaybaleBundle"
local HAY_BALE_MODEL_PREFIX = "Haybale"
local HAY_BALES_PLACED_FIELD = "HayBalesPlaced"
local PROMPT_NAME = "PlaceStableHayBalePrompt"
local OUTLINE_NAME = "StableHayBalePlacementOutline"
local OUTLINE_COLOR = Color3.fromRGB(0, 170, 255)
local PROMPT_HOLD_DURATION = 3
local MAX_HAY_BALES = 3

local plotValue: ObjectValue = localPlayer:WaitForChild(PLOT_VALUE_NAME)
local activePrompts = {}
local activeOutlines = {}
local characterConnections = {}
local plotConnections = {}
local refreshQueued = false
local requestInFlight = false
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

local function get_equipped_hay_bale_tool(): Tool?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local itemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(child)
			if itemDefinition and itemDefinition.ItemId == HAY_BALE_ITEM_ID then
				return child
			end
		end
	end

	return nil
end

local function get_hay_bales_placed(): number
	local stable = DataUtility.client.get("Stable")
	local placedCount = type(stable) == "table" and tonumber(stable[HAY_BALES_PLACED_FIELD]) or 0
	return math.clamp(math.floor(placedCount or 0), 0, MAX_HAY_BALES)
end

local function get_hay_bale_bundle(plot: Instance?): Instance?
	local hayBaleFolder = plot and plot:FindFirstChild(HAY_BALE_FOLDER_NAME)
	return hayBaleFolder and hayBaleFolder:FindFirstChild(HAY_BALE_BUNDLE_NAME) or nil
end

local function find_hay_bale_model(plot: Instance?, slotIndex: number): Instance?
	local bundle = get_hay_bale_bundle(plot)
	if not bundle then
		return nil
	end

	local modelName = ("%s%d"):format(HAY_BALE_MODEL_PREFIX, slotIndex)
	return bundle:FindFirstChild(modelName) or bundle:FindFirstChild(modelName, true)
end

local function find_prompt_parent(model: Instance?): BasePart?
	if not model then
		return nil
	end

	if model:IsA("BasePart") then
		return model
	end

	if model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function create_placement_outlines(model: Instance?)
	if not model then
		return
	end

	local function add_outline(part: BasePart)
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

local function request_place_hay_bale(tool: Tool, slotIndex: number): boolean
	if requestInFlight then
		return false
	end

	requestInFlight = true
	local callSucceeded, success = pcall(function()
		return Net.Function[PLACE_HAY_BALE_FUNCTION_NAME]:Call(tool, slotIndex)
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
		local tool = get_equipped_hay_bale_tool()
		local placedCount = get_hay_bales_placed()
		local nextSlotIndex = placedCount + 1

		if not plot or not tool or nextSlotIndex > MAX_HAY_BALES then
			return
		end

		local hayBaleModel = find_hay_bale_model(plot, nextSlotIndex)
		local promptParent = find_prompt_parent(hayBaleModel)
		if not promptParent then
			return
		end

		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.ActionText = "Place"
		prompt.ObjectText = ("Hay Bale %d/%d"):format(nextSlotIndex, MAX_HAY_BALES)
		prompt.HoldDuration = PROMPT_HOLD_DURATION
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Style = Enum.ProximityPromptStyle.Default
		prompt.Parent = promptParent
		create_placement_outlines(hayBaleModel)

		prompt.Triggered:Connect(function()
			local currentTool = get_equipped_hay_bale_tool()
			if currentTool ~= tool then
				queue_refresh()
				return
			end

			prompt.Enabled = false
			local placed = request_place_hay_bale(tool, nextSlotIndex)
			if placed then
				SoundUtility.PlayGameSFX("Dig")
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
		if descendant.Name == HAY_BALE_FOLDER_NAME
			or descendant.Name == HAY_BALE_BUNDLE_NAME
			or string.sub(descendant.Name, 1, #HAY_BALE_MODEL_PREFIX) == HAY_BALE_MODEL_PREFIX
		then
			queue_refresh()
		end
	end)

	plotConnections[#plotConnections + 1] = plot.DescendantRemoving:Connect(function(descendant)
		if descendant.Name == PROMPT_NAME then
			return
		end

		if descendant.Name == HAY_BALE_FOLDER_NAME
			or descendant.Name == HAY_BALE_BUNDLE_NAME
			or string.sub(descendant.Name, 1, #HAY_BALE_MODEL_PREFIX) == HAY_BALE_MODEL_PREFIX
		then
			queue_refresh()
		end
	end)

	queue_refresh()
end

DataUtility.client.ensure_remotes()

plotValue:GetPropertyChangedSignal("Value"):Connect(function()
	bind_plot(plotValue.Value)
end)

DataUtility.client.bind("Stable", queue_refresh)

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
