local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local GameModules = Modules:WaitForChild("Game")

local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))
local StableCleaningConfig = require(GameData:WaitForChild("Horse"):WaitForChild("StableCleaningConfig"))
local ToolRegistry = require(GameModules:WaitForChild("Tools"):WaitForChild("Registry"))

local gameplayRemotes = ReplicatedStorage:WaitForChild(NetworkConfig.GameplayFolderName)
local stableCleaningRemotes = gameplayRemotes:WaitForChild(StableCleaningConfig.RemoteFolderName)
local cleanDirtRemote = stableCleaningRemotes:WaitForChild(StableCleaningConfig.CleanRemoteName)
local plotValue = localPlayer:WaitForChild("Plot")

local activePrompts = {}
local connections = {}
local refreshQueued = false
local requestInFlight = false
local queue_refresh

local function disconnect_all()
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
end

local function get_equipped_cleaning_tool(): (Tool?, string?)
	local character = localPlayer.Character
	if not character then
		return nil, nil
	end

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			local definition, itemId = ToolRegistry.resolve_definition_from_tool(child)
			if definition and definition.target == StableCleaningConfig.TargetType then
				return child, itemId
			end
		end
	end

	return nil, nil
end

local function get_prompt_parent(dirtVisual: Instance): BasePart?
	if dirtVisual:IsA("Model") then
		return dirtVisual.PrimaryPart or dirtVisual:FindFirstChildWhichIsA("BasePart", true)
	end

	if dirtVisual:IsA("BasePart") then
		return dirtVisual
	end

	return nil
end

local function get_dirt_visuals(plot: Instance, toolItemId: string): {Instance}
	local visuals = {}

	for _, descendant in ipairs(plot:GetDescendants()) do
		if descendant:GetAttribute(StableCleaningConfig.DirtAttribute) == true
			and descendant:GetAttribute(StableCleaningConfig.RequiredToolAttribute) == toolItemId
		then
			visuals[#visuals + 1] = descendant
		end
	end

	return visuals
end

local function request_clean(tool: Tool, horseId: string, dirtId: string): boolean
	if requestInFlight then
		return false
	end

	requestInFlight = true
	local callSucceeded, wasCleaned = pcall(function()
		return cleanDirtRemote:InvokeServer(tool, horseId, dirtId)
	end)
	requestInFlight = false

	return callSucceeded and wasCleaned == true
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
		local tool, toolItemId = get_equipped_cleaning_tool()
		if not plot or not tool or not toolItemId then
			return
		end

		for _, dirtVisual in ipairs(get_dirt_visuals(plot, toolItemId)) do
			local promptParent = get_prompt_parent(dirtVisual)
			local dirtId = dirtVisual:GetAttribute(StableCleaningConfig.DirtIdAttribute)
			local dirtTypeId = dirtVisual:GetAttribute(StableCleaningConfig.DirtTypeAttribute)
			local horseId = dirtVisual:GetAttribute("HorseId")
			local dirtDefinition = StableCleaningConfig.GetDirtDefinition(dirtTypeId)

			if promptParent
				and dirtDefinition
				and type(dirtId) == "string"
				and dirtId ~= ""
				and type(horseId) == "string"
				and horseId ~= ""
			then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "StableCleaningPrompt"
				prompt.ActionText = dirtDefinition.ActionText
				prompt.ObjectText = ("%s  |  %s"):format(
					dirtDefinition.DisplayName,
					StableCleaningConfig.GetPenaltySummary(dirtTypeId)
				)
				prompt.HoldDuration = dirtDefinition.HoldDuration
				prompt.MaxActivationDistance = StableCleaningConfig.MaxCleanDistance
				prompt.RequiresLineOfSight = false
				prompt.Style = Enum.ProximityPromptStyle.Default
				prompt.Parent = promptParent

				prompt.Triggered:Connect(function()
					local currentTool, currentItemId = get_equipped_cleaning_tool()
					if currentTool ~= tool or currentItemId ~= toolItemId then
						queue_refresh()
						return
					end

					prompt.Enabled = false
					if not request_clean(tool, horseId, dirtId) and prompt.Parent then
						prompt.Enabled = true
					end
				end)

				activePrompts[#activePrompts + 1] = prompt
			end
		end
	end)
end

local function bind_character(character: Model)
	disconnect_all()

	connections[#connections + 1] = character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	connections[#connections + 1] = character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			queue_refresh()
		end
	end)

	queue_refresh()
end

plotValue:GetPropertyChangedSignal("Value"):Connect(queue_refresh)
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:GetAttribute(StableCleaningConfig.DirtAttribute) == true then
		queue_refresh()
	end
end)
workspace.DescendantRemoving:Connect(function(descendant)
	if descendant:GetAttribute(StableCleaningConfig.DirtAttribute) == true then
		queue_refresh()
	end
end)

localPlayer.CharacterAdded:Connect(bind_character)
localPlayer.CharacterRemoving:Connect(function()
	disconnect_all()
	destroy_prompts()
end)

if localPlayer.Character then
	bind_character(localPlayer.Character)
end

queue_refresh()
