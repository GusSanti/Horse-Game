local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VISUAL_HORSE_ATTRIBUTE = "IsStableVisualHorse"
local HORSE_ID_ATTRIBUTE = "HorseId"
local PLOT_VALUE_NAME = "Plot"
local HORSE_FOLDER_NAME = "HorseFolder"
local REMOTE_FOLDER_NAME = "ToolRemotes"
local USE_HORSE_TOOL_REMOTE_NAME = "UseHorseTool"

local localPlayer = Players.LocalPlayer
local modules = ReplicatedStorage:WaitForChild("Modules")
local gameData = modules:WaitForChild("GameData")
local toolItems = gameData:WaitForChild("ToolItems")
local toolRegistry = require(toolItems:WaitForChild("Registry"))

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME)
local useHorseToolRemote = remotesFolder:WaitForChild(USE_HORSE_TOOL_REMOTE_NAME)
local plotValue = localPlayer:WaitForChild(PLOT_VALUE_NAME)

local characterConnections = {}
local plotConnections = {}
local activePrompts = {}
local refreshQueued = false
local activePromptToken = 0

local function disconnect_all(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function destroy_active_prompts()
	for _, prompt in ipairs(activePrompts) do
		prompt:Destroy()
	end

	table.clear(activePrompts)
	activePromptToken += 1
end

local function get_equipped_tool()
	local character = localPlayer.Character
	if not character then
		return nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			return child
		end
	end

	return nil
end

local function find_prompt_parent(instance)
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end

		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
	end

	return nil
end

local function get_horse_visuals()
	local plot = plotValue.Value
	if not plot then
		return {}
	end

	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return {}
	end

	local visuals = {}

	for _, slotFolder in ipairs(horseFolder:GetChildren()) do
		for _, child in ipairs(slotFolder:GetChildren()) do
			if child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true then
				visuals[#visuals + 1] = child
			end
		end
	end

	return visuals
end

local function queue_refresh()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(function()
		refreshQueued = false

		destroy_active_prompts()

		local equippedTool = get_equipped_tool()
		local definition, itemId = toolRegistry.ResolveDefinitionFromTool(equippedTool)
		if not equippedTool or not definition or not itemId then
			return
		end

		local promptConfig = definition.Prompt or {}
		local promptToken = activePromptToken

		for _, horseVisual in ipairs(get_horse_visuals()) do
			local promptParent = find_prompt_parent(horseVisual)
			local horseId = horseVisual:GetAttribute(HORSE_ID_ATTRIBUTE)

			if promptParent and type(horseId) == "string" and horseId ~= "" then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = ("%sPrompt"):format(itemId)
				prompt.ActionText = promptConfig.ActionText or "Usar"
				prompt.ObjectText = promptConfig.ObjectText or "Cavalo"
				prompt.HoldDuration = promptConfig.HoldDuration or 0
				prompt.MaxActivationDistance = promptConfig.MaxActivationDistance or 10
				prompt.RequiresLineOfSight = promptConfig.RequiresLineOfSight == true
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
						if definition.ConsumeOnUse == false then
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

local function bind_character(character)
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

local function bind_plot(plot)
	disconnect_all(plotConnections)

	if not plot then
		queue_refresh()
		return
	end

	plotConnections[#plotConnections + 1] = plot.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			return
		end

		queue_refresh()
	end)

	plotConnections[#plotConnections + 1] = plot.DescendantRemoving:Connect(function(descendant)
		if descendant:IsA("ProximityPrompt") then
			return
		end

		queue_refresh()
	end)

	queue_refresh()
end

plotValue:GetPropertyChangedSignal("Value"):Connect(function()
	bind_plot(plotValue.Value)
end)

localPlayer.CharacterAdded:Connect(bind_character)
localPlayer.CharacterRemoving:Connect(function()
	disconnect_all(characterConnections)
	queue_refresh()
end)

if localPlayer.Character then
	bind_character(localPlayer.Character)
end

bind_plot(plotValue.Value)
