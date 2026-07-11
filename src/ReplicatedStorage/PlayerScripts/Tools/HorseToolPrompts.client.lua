------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

------------------//CONSTANTS
local localPlayer: Player = Players.LocalPlayer
local modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local clientModules: Folder = modules:WaitForChild("Client")
local dictionary: Folder = modules:WaitForChild("Dictionary")
local gameModules: Folder = modules:WaitForChild("Game")
local gameData: Folder = modules:WaitForChild("GameData")
local hudModules: Folder = clientModules:WaitForChild("Hud")
local toolModules: Folder = gameModules:WaitForChild("Tools")
local clientFolder: Folder = toolModules:WaitForChild("Client")

local HorseInteractionUi = require(hudModules:WaitForChild("HorseInteractionUi"))
local ToolItemCatalog = require(gameData:WaitForChild("ToolItemCatalog"))
local toolDictionary = require(dictionary:WaitForChild("ToolDictionary"))
local toolRegistry = require(toolModules:WaitForChild("Registry"))

local VISUAL_HORSE_ATTRIBUTE: string = toolDictionary.VisualHorseAttribute
local HORSE_ID_ATTRIBUTE: string = toolDictionary.HorseIdAttribute
local PLOT_VALUE_NAME: string = toolDictionary.PlotValueName
local HORSE_FOLDER_NAME: string = toolDictionary.HorseFolderName
local REMOTE_FOLDER_NAME: string = toolDictionary.ToolRemotesFolderName
local USE_HORSE_TOOL_REMOTE_NAME: string = toolDictionary.UseHorseToolRemoteName
local IGNORE_REFRESH_ATTRIBUTE: string = toolDictionary.IgnoreRefreshAttribute

------------------//VARIABLES
local remotesFolder: Folder = ReplicatedStorage:WaitForChild(REMOTE_FOLDER_NAME)
local useHorseToolRemote: RemoteFunction = remotesFolder:WaitForChild(USE_HORSE_TOOL_REMOTE_NAME)
local plotValue: ObjectValue = localPlayer:WaitForChild(PLOT_VALUE_NAME)

local characterConnections: {RBXScriptConnection} = {}
local plotConnections: {RBXScriptConnection} = {}
local activePrompts: {ProximityPrompt} = {}
local cachedHandlers: {[string]: any} = {}
local refreshQueued: boolean = false
local activePromptToken: number = 0
local clientInteractionActive: boolean = false
local activeTimedSession = nil
local queue_refresh

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

local function should_ignore_descendant(descendant: Instance): boolean
	if descendant:IsA("ProximityPrompt") then
		return true
	end

	local current = descendant
	while current do
		if current:GetAttribute(IGNORE_REFRESH_ATTRIBUTE) == true then
			return true
		end

		current = current.Parent
	end

	return false
end

local function get_client_handler(definition): any
	local clientHandlerName = definition.clientHandlerName
	if type(clientHandlerName) ~= "string" or clientHandlerName == "" then
		return nil
	end

	if cachedHandlers[clientHandlerName] then
		return cachedHandlers[clientHandlerName]
	end

	local handlerModule = clientFolder:FindFirstChild(clientHandlerName)
	if not handlerModule or not handlerModule:IsA("ModuleScript") then
		return nil
	end

	local handler = require(handlerModule)
	cachedHandlers[clientHandlerName] = handler

	return handler
end

local function finish_client_interaction(shouldRefreshPrompts: boolean): ()
	clientInteractionActive = false
	HorseInteractionUi.HideDialogue()

	if shouldRefreshPrompts ~= false then
		queue_refresh()
	end
end

local function begin_client_interaction(): ()
	clientInteractionActive = true
end

local function invoke_server_use(tool: Tool?, itemId: string, horseId: string): (boolean, string?)
	local success, reason = useHorseToolRemote:InvokeServer(tool, itemId, horseId)

	print(("[HorseToolPrompts] InvokeServer tool=%s itemId=%s horseId=%s success=%s reason=%s"):format(
		tool and tool.Name or "nil",
		tostring(itemId),
		tostring(horseId),
		tostring(success),
		tostring(reason)
	))

	return success, reason
end

local function build_item_preview(definition, tool: Tool?, itemId: string): any
	local itemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
	if itemDefinition then
		return itemDefinition
	end

	itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
	if itemDefinition then
		return itemDefinition
	end

	return {
		ItemId = itemId,
		DisplayName = tool and tool.Name or itemId,
		PromptActionText = (definition.prompt and definition.prompt.actionText) or "Use",
		Description = "This item helps with horse care.",
	}
end

local function get_interaction_duration(definition, itemDefinition): number
	if type(definition.interactionDuration) == "number" and definition.interactionDuration > 0 then
		return definition.interactionDuration
	end

	local itemId = definition.id
	local toolCategory = nil

	if type(itemDefinition) == "table" then
		itemId = itemDefinition.ItemId or itemId
		toolCategory = itemDefinition.ToolCategory
	end

	if itemId == "soap" then
		return 0
	end

	if itemId == "horse_brush" then
		return 1.5
	end

	if toolCategory == "Food" or toolCategory == "Water" then
		return 1.2
	end

	if toolCategory == "Medicine" then
		return 1.35
	end

	return math.max((definition.prompt and definition.prompt.holdDuration) or 0.2, 1)
end

local function anchor_character_root(session): ()
	local character = localPlayer.Character
	if not character then
		return
	end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	session.rootPart = rootPart
	session.savedRootAnchored = rootPart.Anchored
	rootPart.Anchored = true
end

local function restore_character_root(session): ()
	local rootPart = session.rootPart
	if rootPart and rootPart.Parent then
		rootPart.Anchored = session.savedRootAnchored == true
	end
end

local function finish_timed_session(session, shouldRefreshPrompts: boolean): ()
	if activeTimedSession ~= session or session.closed then
		return
	end

	session.closed = true
	activeTimedSession = nil

	disconnect_all(session.connections)
	restore_character_root(session)
	HorseInteractionUi.HideTask()
	finish_client_interaction(shouldRefreshPrompts)
end

local function cancel_timed_session(session, shouldRefreshPrompts: boolean): ()
	if session.finishing then
		return
	end

	finish_timed_session(session, shouldRefreshPrompts)
end

local function complete_timed_session(session): ()
	if session.finishing or session.closed then
		return
	end

	session.finishing = true

	HorseInteractionUi.UpdateTask({
		text = session.taskText,
		progress = 1,
		timerText = "0.0s",
	})

	pcall(function()
		session.invokeServerUse()
	end)

	task.delay(0.1, function()
		finish_timed_session(session, true)
	end)
end

local function start_timed_interaction(context): boolean
	if activeTimedSession then
		return false
	end

	local actionDuration = math.max(context.actionDuration or 1, 0.05)
	local session = {
		tool = context.tool,
		horseVisual = context.horseVisual,
		invokeServerUse = context.invokeServerUse,
		taskText = context.taskText,
		actionDuration = actionDuration,
		startedAt = os.clock(),
		finishing = false,
		closed = false,
		connections = {},
	}

	activeTimedSession = session

	anchor_character_root(session)

	HorseInteractionUi.ShowTask({
		text = session.taskText,
		progress = 0,
		timerText = ("%.1fs"):format(actionDuration),
	})

	session.connections[#session.connections + 1] = localPlayer.CharacterRemoving:Connect(function()
		cancel_timed_session(session, false)
	end)

	session.connections[#session.connections + 1] = context.tool.AncestryChanged:Connect(function()
		if session.finishing then
			return
		end

		if not context.tool:IsDescendantOf(localPlayer.Character or game) then
			cancel_timed_session(session, false)
		end
	end)

	session.connections[#session.connections + 1] = context.horseVisual.AncestryChanged:Connect(function()
		if session.finishing then
			return
		end

		if not context.horseVisual:IsDescendantOf(workspace) then
			cancel_timed_session(session, true)
		end
	end)

	session.connections[#session.connections + 1] = RunService.RenderStepped:Connect(function()
		if activeTimedSession ~= session or session.closed then
			return
		end

		local elapsedTime = os.clock() - session.startedAt
		local progressAlpha = math.clamp(elapsedTime / actionDuration, 0, 1)
		local remainingTime = math.max(0, actionDuration - elapsedTime)

		HorseInteractionUi.UpdateTask({
			text = session.taskText,
			progress = progressAlpha,
			timerText = ("%.1fs"):format(remainingTime),
		})

		if elapsedTime >= actionDuration then
			complete_timed_session(session)
		end
	end)

	return true
end

local function start_tool_interaction(context): ()
	local clientHandler = context.clientHandler

	if clientHandler and type(clientHandler.start) == "function" then
		local started = false
		local startSuccess, startResult = pcall(function()
			return clientHandler.start({
				player = localPlayer,
				tool = context.tool,
				itemId = context.itemId,
				horseId = context.horseId,
				horseVisual = context.horseVisual,
				promptParent = context.promptParent,
				beginInteraction = begin_client_interaction,
				invokeServerUse = context.invokeServerUse,
				finishInteraction = finish_client_interaction,
				actionDuration = context.actionDuration,
				taskText = context.taskText,
				showTask = HorseInteractionUi.ShowTask,
				updateTask = HorseInteractionUi.UpdateTask,
				hideTask = HorseInteractionUi.HideTask,
			})
		end)

		if startSuccess then
			started = startResult == true
		end

		if not started then
			finish_client_interaction(true)
		end

		return
	end

	if not start_timed_interaction(context) then
		finish_client_interaction(true)
	end
end

local function begin_dialog_interaction(context): ()
	begin_client_interaction()
	destroy_active_prompts()

	local dialogShown = HorseInteractionUi.ShowDialogue({
		title = HorseInteractionUi.BuildDialogueTitle(context.itemDefinition),
		details = HorseInteractionUi.BuildDialogueText(context.itemDefinition),
		acceptText = context.itemDefinition.PromptActionText
			or (context.definition.prompt and context.definition.prompt.actionText)
			or "Use",
		denyText = "Cancel",
		onAccept = function()
			local currentTool = get_equipped_tool()
			if currentTool ~= context.tool then
				finish_client_interaction(true)
				return
			end

			start_tool_interaction(context)
		end,
		onDeny = function()
			finish_client_interaction(true)
		end,
	})

	if not dialogShown then
		start_tool_interaction(context)
	end
end

function queue_refresh(): ()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(function()
		refreshQueued = false

		if clientInteractionActive then
			return
		end

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
				prompt.ActionText = promptConfig.actionText or "Use"
				prompt.ObjectText = promptConfig.objectText or "Horse"
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = promptConfig.maxActivationDistance or 10
				prompt.RequiresLineOfSight = promptConfig.requiresLineOfSight == true
				prompt.Style = Enum.ProximityPromptStyle.Default
				prompt.Parent = promptParent

				local clientHandler = get_client_handler(definition)
				local itemDefinition = build_item_preview(definition, equippedTool, itemId)
				local actionDuration = get_interaction_duration(definition, itemDefinition)
				local taskText = HorseInteractionUi.BuildActionLabel(itemDefinition, promptConfig.actionText)

				prompt.Triggered:Connect(function()
					if promptToken ~= activePromptToken then
						return
					end

					local currentTool = get_equipped_tool()
					if currentTool ~= equippedTool then
						return
					end

					begin_dialog_interaction({
						clientHandler = clientHandler,
						definition = definition,
						itemDefinition = itemDefinition,
						tool = equippedTool,
						itemId = itemId,
						horseId = horseId,
						horseVisual = horseVisual,
						promptParent = promptParent,
						actionDuration = actionDuration,
						taskText = taskText,
						invokeServerUse = function()
							return invoke_server_use(equippedTool, itemId, horseId)
						end,
					})
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

localPlayer.CharacterAdded:Connect(bind_character)
localPlayer.CharacterRemoving:Connect(function()
	disconnect_all(characterConnections)
	clientInteractionActive = false
	HorseInteractionUi.HideDialogue()
	HorseInteractionUi.HideTask()
	queue_refresh()
end)

------------------//INIT
if localPlayer.Character then
	bind_character(localPlayer.Character)
end

bind_plot(plotValue.Value)
