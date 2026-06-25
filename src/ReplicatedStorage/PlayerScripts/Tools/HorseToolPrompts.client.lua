------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------//CONSTANTS
local localPlayer: Player = Players.LocalPlayer
local modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local dictionary: Folder = modules:WaitForChild("Dictionary")
local gameModules: Folder = modules:WaitForChild("Game")

local toolDictionary = require(dictionary:WaitForChild("ToolDictionary"))
local toolRegistry = require(gameModules:WaitForChild("Tools"):WaitForChild("Registry"))

local VISUAL_HORSE_ATTRIBUTE: string = toolDictionary.VisualHorseAttribute
local HORSE_ID_ATTRIBUTE: string = toolDictionary.HorseIdAttribute
local PLOT_VALUE_NAME: string = toolDictionary.PlotValueName
local HORSE_FOLDER_NAME: string = toolDictionary.HorseFolderName
local REMOTE_FOLDER_NAME: string = toolDictionary.ToolRemotesFolderName
local USE_HORSE_TOOL_REMOTE_NAME: string = toolDictionary.UseHorseToolRemoteName

------------------//VARIABLES
local remotesFolder: Folder = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME)
local useHorseToolRemote: RemoteFunction = remotesFolder:WaitForChild(USE_HORSE_TOOL_REMOTE_NAME)
local plotValue: ObjectValue = localPlayer:WaitForChild(PLOT_VALUE_NAME)

local characterConnections: {RBXScriptConnection} = {}
local plotConnections: {RBXScriptConnection} = {}
local activePrompts: {ProximityPrompt} = {}
local refreshQueued: boolean = false
local activePromptToken: number = 0

------------------//FUNCTIONS
local function disconnect_all(connections: {RBXScriptConnection}): ()
	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function destroy_active_prompts(): ()
	for _, prompt: ProximityPrompt in activePrompts do
		prompt:Destroy()
	end

	table.clear(activePrompts)
	activePromptToken += 1
end

local function get_equipped_tool(): Tool?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	for _, child: Instance in character:GetChildren() do
		if child:IsA("Tool") then
			return child
		end
	end

	return nil
end

local function find_prompt_parent(instance: Instance): BasePart?
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

local function queue_refresh(): ()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(function()
		refreshQueued = false

		destroy_active_prompts()

		local equippedTool = get_equipped_tool()
		local definition, itemId = toolRegistry.resolve_definition_from_tool(equippedTool)
		if not equippedTool or not definition or not itemId then
			return
		end

		local promptConfig = definition.prompt or {}
		local promptToken = activePromptToken

		for _, horseVisual: Instance in get_horse_visuals() do
			local promptParent = find_prompt_parent(horseVisual)
			local horseId = horseVisual:GetAttribute(HORSE_ID_ATTRIBUTE)

			if promptParent and type(horseId) == "string" and horseId ~= "" then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = ("%sPrompt"):format(itemId)
				prompt.ActionText = promptConfig.actionText or "Usar"
				prompt.ObjectText = promptConfig.objectText or "Cavalo"
				prompt.HoldDuration = promptConfig.holdDuration or 0
				prompt.MaxActivationDistance = promptConfig.maxActivationDistance or 10
				prompt.RequiresLineOfSight = promptConfig.requiresLineOfSight == true
				prompt.Style = Enum.ProximityPromptStyle.Default
				prompt.Parent = promptParent

				prompt.Triggered:Connect(function()
					if promptToken ~= activePromptToken then
						return
					end

					local currentTool = get_equipped_tool()
					if currentTool ~= equippedTool then
						return
					end

					local success = useHorseToolRemote:InvokeServer(currentTool, itemId, horseId)
					if success then
						if definition.consumeOnUse == false then
							queue_refresh()
						else
							destroy_active_prompts()
						end
					end
				end)

				activePrompts[#activePrompts + 1] = prompt
			end
		end
	end)
end

local function bind_character(character: Model): ()
	disconnect_all(characterConnections)

	characterConnections[#characterConnections + 1] = character.ChildAdded:Connect(function(child: Instance)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	characterConnections[#characterConnections + 1] = character.ChildRemoved:Connect(function(child: Instance)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	queue_refresh()
end

local function bind_plot(plot: Instance?): ()
	disconnect_all(plotConnections)

	if not plot then
		queue_refresh()
		return
	end

	plotConnections[#plotConnections + 1] = plot.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("ProximityPrompt") then
			return
		end

		queue_refresh()
	end)

	plotConnections[#plotConnections + 1] = plot.DescendantRemoving:Connect(function(descendant: Instance)
		if descendant:IsA("ProximityPrompt") then
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

localPlayer.CharacterAdded:Connect(bind_character)
localPlayer.CharacterRemoving:Connect(function()
	disconnect_all(characterConnections)
	queue_refresh()
end)

------------------//INIT
if localPlayer.Character then
	bind_character(localPlayer.Character)
end

bind_plot(plotValue.Value)
