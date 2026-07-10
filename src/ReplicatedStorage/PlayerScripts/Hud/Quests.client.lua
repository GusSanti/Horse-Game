local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Services = Modules:WaitForChild("Services")
local Utility = Modules:WaitForChild("Utility")

local QuestCatalog = require(GameData:WaitForChild("QuestCatalog"))
local Trove = require(Libraries:WaitForChild("Trove"))
local QuestClient = require(Services:WaitForChild("QuestClient"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainFrameFR", "MainframeFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local QUEST_ROOT_NAMES = { "Quests", "Quest" }
local QUESTS_BACKGROUND_NAMES = { "QuestsBG" }
local LIST_CONTAINER_NAMES = { "ListScrollingFrame", "ScrollingFrame", "ScrollFrame", "Scroll" }
local QUEST_TEMPLATE_NAMES = { "QuestBG" }
local QUEST_NAME_NAMES = { "QuestNameTX", "QuestName" }
local DETAIL_NAMES = { "DetailTX", "DetailsTX", "DescriptionTX" }
local BAR_NAMES = { "BarBG" }
local INSIDE_BAR_NAMES = { "InsideBar", "InsideBarBG" }
local TASK_PROGRESS_NAMES = { "TaskProgressTX", "ProgressTX" }
local REWARD_BUTTON_NAMES = { "RewardBT", "RewardBG" }
local REWARD_ITEM_NAME_NAMES = { "ItemNameTX", "ItemName" }
local REWARD_STATUS_NAMES = { "RewardsTX", "rewardsTX" }
local ITEM_IMAGE_NAMES = { "ItemImage", "ImageItem", "ImageLabel", "Icon" }
local VIEWPORT_FRAME_NAMES = { "ViewportFrame", "ViewPortFrame", "Viewport" }
local HORSESHOE_REFERENCE_NAMES = { "HorseshoeBG" }

local currentUi = nil
local currentTemplateSource = nil
local renderQueued = false
local claimRequestInFlight = false
local optimisticallyClaimedQuestId = nil
local orderedQuestIds = nil

local queue_render
local try_bind_ui

local function normalize_key(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	local normalizedValue = string.lower(trimmedValue)
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function matches_alias(instance, aliases)
	local normalizedName = normalize_key(instance.Name)
	if not normalizedName then
		return false
	end

	for _, alias in ipairs(aliases or {}) do
		if normalize_key(alias) == normalizedName then
			return true
		end
	end

	return false
end

local function find_named_instance(root, aliases, className, recursive)
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if matches_alias(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	if recursive == false then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if matches_alias(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function find_text_label(root, aliases, recursive)
	local instance = find_named_instance(root, aliases, "TextLabel", recursive)
	if instance then
		return instance
	end

	return nil
end

local function find_gui_button(root, aliases, recursive)
	local instance = find_named_instance(root, aliases, "GuiButton", recursive)
	if instance then
		return instance
	end

	return nil
end

local function find_gui_object(root, aliases, recursive)
	local instance = find_named_instance(root, aliases, "GuiObject", recursive)
	if instance then
		return instance
	end

	return nil
end

local function find_viewport_frame(root)
	if not root then
		return nil
	end

	if root:IsA("ViewportFrame") then
		return root
	end

	local instance = find_named_instance(root, VIEWPORT_FRAME_NAMES, "ViewportFrame", true)
	if instance then
		return instance
	end

	return nil
end

local function build_ordered_quest_ids()
	if orderedQuestIds then
		return orderedQuestIds
	end

	local ordered = {}
	local seen = {}

	for _, questId in ipairs(QuestCatalog.GetDailyQuestIds() or {}) do
		if not seen[questId] and QuestCatalog.GetDefinition(questId) then
			seen[questId] = true
			ordered[#ordered + 1] = questId
		end
	end

	local remaining = {}

	for questId, definition in pairs(QuestCatalog.Definitions or {}) do
		if definition and not seen[questId] then
			remaining[#remaining + 1] = questId
		end
	end

	table.sort(remaining)

	for _, questId in ipairs(remaining) do
		ordered[#ordered + 1] = questId
	end

	orderedQuestIds = ordered
	return orderedQuestIds
end

local function strip_scripts(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function make_template_source(template)
	local source = template:Clone()
	source.Visible = true
	strip_scripts(source)

	template.Visible = false
	template.Parent = nil

	return source
end

local function set_button_enabled(button, isEnabled)
	if not button then
		return
	end

	button.Active = isEnabled
	button.Selectable = isEnabled

	if button:IsA("TextButton") or button:IsA("ImageButton") then
		button.AutoButtonColor = isEnabled
	end
end

local function find_main_ui_root()
	local mainUi = find_named_instance(playerGui, MAIN_UI_NAMES, nil, true)
	if mainUi then
		return mainUi
	end

	return nil
end

local function find_mainframe_root()
	local mainUi = find_main_ui_root()
	if not mainUi then
		return nil
	end

	local mainframe = find_named_instance(mainUi, MAINFRAME_NAMES, nil, true)
	if mainframe then
		return mainframe
	end

	return nil
end

local function find_frames_container()
	local mainframe = find_mainframe_root()
	if not mainframe then
		return nil
	end

	local framesContainer = find_named_instance(mainframe, FRAMES_CONTAINER_NAMES, nil, true)
	if framesContainer then
		return framesContainer
	end

	return nil
end

local function find_quests_root()
	local framesContainer = find_frames_container()
	if not framesContainer then
		return nil
	end

	local questsRoot = find_named_instance(framesContainer, QUEST_ROOT_NAMES, nil, true)
	if questsRoot then
		return questsRoot
	end

	return nil
end

local function clear_viewport(viewportFrame)
	if not viewportFrame then
		return
	end

	for _, child in ipairs(viewportFrame:GetChildren()) do
		child:Destroy()
	end

	viewportFrame.CurrentCamera = nil
end

local function clear_item_image_container(itemImage, preservedViewport)
	if not itemImage then
		return
	end

	for _, child in ipairs(itemImage:GetChildren()) do
		if child == preservedViewport then
			continue
		end

		if child:IsA("UIAspectRatioConstraint")
			or child:IsA("UICorner")
			or child:IsA("UIStroke")
			or child:IsA("UIPadding")
			or child:IsA("UIListLayout")
			or child:IsA("UISizeConstraint")
			or child:IsA("UITextSizeConstraint")
		then
			continue
		end

		child:Destroy()
	end
end

local function clone_viewport_contents(sourceViewport, targetViewport)
	if not sourceViewport or not targetViewport then
		return false
	end

	clear_viewport(targetViewport)

	local clonedCamera = nil

	for _, child in ipairs(sourceViewport:GetChildren()) do
		local clone = child:Clone()
		clone.Parent = targetViewport

		if clone:IsA("Camera") then
			clonedCamera = clone
		end
	end

	targetViewport.BackgroundTransparency = sourceViewport.BackgroundTransparency
	targetViewport.Ambient = sourceViewport.Ambient
	targetViewport.LightColor = sourceViewport.LightColor
	targetViewport.LightDirection = sourceViewport.LightDirection
	targetViewport.ImageColor3 = sourceViewport.ImageColor3
	targetViewport.CurrentCamera = clonedCamera

	return true
end

local function populate_reward_image(itemImage, referenceRoot, rewardDisplay)
	if not itemImage or not referenceRoot or not rewardDisplay then
		return
	end

	if rewardDisplay.IconKey ~= "Horseshoe" then
		return
	end

	-- HorseshoeBG acts as the visual source template for every Horseshoe reward card.
	local sourceReference = find_named_instance(referenceRoot, HORSESHOE_REFERENCE_NAMES, nil, true)
	if not sourceReference then
		return
	end

	local targetViewport = find_viewport_frame(itemImage)
	local sourceViewport = find_viewport_frame(sourceReference)

	if targetViewport then
		targetViewport.Visible = true
	end

	if sourceViewport and targetViewport and clone_viewport_contents(sourceViewport, targetViewport) then
		if targetViewport ~= itemImage then
			clear_item_image_container(itemImage, targetViewport)
		end

		return
	end

	if targetViewport == itemImage then
		return
	end

	clear_item_image_container(itemImage, targetViewport)

	if targetViewport then
		targetViewport.Visible = false
	end

	local rewardVisual = sourceReference:Clone()
	rewardVisual.Name = "RewardVisual"
	strip_scripts(rewardVisual)

	if rewardVisual:IsA("GuiObject") then
		rewardVisual.AnchorPoint = Vector2.zero
		rewardVisual.Position = UDim2.fromScale(0, 0)
		rewardVisual.Size = UDim2.fromScale(1, 1)
		rewardVisual.Visible = true
	end

	rewardVisual.Parent = itemImage
end

local function format_progress_text(progressRatio)
	local percent = math.floor(math.clamp(progressRatio, 0, 1) * 100 + 0.5)
	return ("%d%%"):format(percent)
end

local function get_visible_quest_entries()
	local entries = {}
	local dailyQuestState = QuestClient.GetDailyQuestState() or {}
	local activeQuestId = type(dailyQuestState.QuestId) == "string" and dailyQuestState.QuestId or ""

	for _, questId in ipairs(build_ordered_quest_ids()) do
		local questDefinition = QuestCatalog.GetDefinition(questId)
		if not questDefinition then
			continue
		end

		local objective = questDefinition.Objective or {}
		local isActive = activeQuestId ~= "" and activeQuestId == questId
		local isClaimed = isActive
			and (dailyQuestState.Claimed == true or optimisticallyClaimedQuestId == questId)

		if isClaimed then
			continue
		end

		local questState = {
			QuestId = questId,
			Goal = objective.Target or 0,
			Progress = 0,
			Completed = false,
			Claimed = false,
		}

		if isActive then
			questState.Goal = dailyQuestState.Goal or questState.Goal
			questState.Progress = dailyQuestState.Progress or 0
			questState.Completed = dailyQuestState.Completed == true
			questState.Claimed = dailyQuestState.Claimed == true
		end

		entries[#entries + 1] = {
			Key = ("Quest_%s"):format(questId),
			QuestId = questId,
			Definition = questDefinition,
			State = questState,
			IsActive = isActive,
		}
	end

	return entries
end

local function update_canvas_size()
	if not currentUi or not currentUi.ListContainer or not currentUi.ListContainer:IsA("ScrollingFrame") then
		return
	end

	local scrollingFrame = currentUi.ListContainer
	local layout = scrollingFrame:FindFirstChildOfClass("UIListLayout")
	if not layout then
		layout = scrollingFrame:FindFirstChildWhichIsA("UIListLayout", true)
	end

	if layout then
		scrollingFrame.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
	end
end

local function configure_card(card, questEntry, referenceRoot)
	local questDefinition = questEntry.Definition
	local questState = questEntry.State
	local rewardDisplay = QuestCatalog.GetRewardDisplayData(questDefinition)
	local progress = math.max(0, tonumber(questState.Progress) or 0)
	local goal = math.max(0, tonumber(questState.Goal or (questDefinition.Objective and questDefinition.Objective.Target)) or 0)
	local progressRatio = if goal > 0 then math.clamp(progress / goal, 0, 1) else 0

	local questNameLabel = find_text_label(card, QUEST_NAME_NAMES, true)
	local detailLabel = find_text_label(card, DETAIL_NAMES, true)
	local barRoot = find_gui_object(card, BAR_NAMES, true)
	local insideBar = find_gui_object(barRoot, INSIDE_BAR_NAMES, true)
	local taskProgressLabel = find_text_label(card, TASK_PROGRESS_NAMES, true)
	local rewardButton = find_gui_button(card, REWARD_BUTTON_NAMES, true)
	local rewardRoot = rewardButton or find_gui_object(card, REWARD_BUTTON_NAMES, true) or card
	local rewardItemNameLabel = find_text_label(rewardRoot, REWARD_ITEM_NAME_NAMES, true)
	local rewardStatusLabel = find_text_label(rewardRoot, REWARD_STATUS_NAMES, true)
	local itemImage = find_gui_object(rewardRoot, ITEM_IMAGE_NAMES, true)

	card.Name = questEntry.Key
	card.Visible = true

	if questNameLabel then
		questNameLabel.Text = questDefinition.DisplayName or questEntry.QuestId
	end

	if detailLabel then
		detailLabel.Text = questDefinition.Description or "No quest details configured."
	end

	if insideBar then
		local currentSize = insideBar.Size
		insideBar.Size = UDim2.new(progressRatio, 0, currentSize.Y.Scale, currentSize.Y.Offset)
	end

	if taskProgressLabel then
		taskProgressLabel.Text = format_progress_text(progressRatio)
	end

	if rewardItemNameLabel then
		rewardItemNameLabel.Text = rewardDisplay.Text
	end

	if rewardStatusLabel then
		rewardStatusLabel.Text = questState.Completed and "Clear" or "rewards"
	end

	if itemImage then
		populate_reward_image(itemImage, referenceRoot, rewardDisplay)
	end

	if rewardButton then
		set_button_enabled(rewardButton, questEntry.IsActive and questState.Completed and not claimRequestInFlight)
		cardTrove:Add(rewardButton.Activated:Connect(function()
			if claimRequestInFlight or not questEntry.IsActive or not questState.Completed then
				return
			end

			claimRequestInFlight = true
			queue_render()

			local success, response = pcall(function()
				return QuestClient.ClaimDailyQuestReward()
			end)

			claimRequestInFlight = false

			if success and type(response) == "table" and response.Success == true then
				optimisticallyClaimedQuestId = questEntry.QuestId
			else
				optimisticallyClaimedQuestId = nil
			end

			queue_render()
		end))
	end
end

local function render_quests()
	if not currentUi or not currentTemplateSource then
		return
	end

	cardTrove:Clean()

	if currentUi.ListContainer:IsA("ScrollingFrame") then
		currentUi.ListContainer.CanvasPosition = Vector2.zero
	end

	for layoutOrder, questEntry in ipairs(get_visible_quest_entries()) do
		local card = currentTemplateSource:Clone()
		card.LayoutOrder = layoutOrder
		card.Parent = currentUi.ListContainer
		cardTrove:Add(card)

		configure_card(card, questEntry, currentUi.ReferenceRoot)
	end

	update_canvas_size()
	task.defer(update_canvas_size)
end

queue_render = function()
	if renderQueued then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		render_quests()
	end)
end

local function get_quest_ui(questsRoot)
	local contentRoot = find_gui_object(questsRoot, QUESTS_BACKGROUND_NAMES, true) or questsRoot
	local listContainer = find_gui_object(contentRoot, LIST_CONTAINER_NAMES, true)
	local template = listContainer and find_gui_object(listContainer, QUEST_TEMPLATE_NAMES, false)

	if not template and listContainer then
		template = find_gui_object(listContainer, QUEST_TEMPLATE_NAMES, true)
	end

	if not listContainer or not template then
		return nil
	end

	return {
		Root = questsRoot,
		ListContainer = listContainer,
		Template = template,
		ReferenceRoot = questsRoot,
	}
end

local function find_quest_ui()
	local questsRoot = find_quests_root()
	if not questsRoot then
		return nil
	end

	return get_quest_ui(questsRoot)
end

local function destroy_ui_binding()
	cardTrove:Clean()
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = nil
	currentTemplateSource = nil
	claimRequestInFlight = false
end

local function bind_ui(ui)
	if currentUi and currentUi.Root == ui.Root and currentTemplateSource and currentUi.Root.Parent then
		return
	end

	destroy_ui_binding()

	currentUi = ui
	currentTemplateSource = make_template_source(ui.Template)

	local horseshoeReference = find_gui_object(ui.ReferenceRoot, HORSESHOE_REFERENCE_NAMES, true)
	if horseshoeReference then
		horseshoeReference.Visible = false
	end

	uiTrove:Add(currentTemplateSource)
	uiTrove:Add(QuestClient.BindDailyQuestChanged(function()
		local dailyQuestState = QuestClient.GetDailyQuestState()
		if not dailyQuestState
			or dailyQuestState.Claimed
			or dailyQuestState.QuestId ~= optimisticallyClaimedQuestId
		then
			optimisticallyClaimedQuestId = nil
		end

		queue_render()
	end))

	uiTrove:Connect(ui.Root.AncestryChanged, function(_, parent)
		if parent then
			return
		end

		if currentUi and currentUi.Root == ui.Root then
			destroy_ui_binding()
			task.defer(try_bind_ui)
		end
	end)

	queue_render()
end

local function is_quest_ui_related(instance)
	return matches_alias(instance, MAIN_UI_NAMES)
		or matches_alias(instance, MAINFRAME_NAMES)
		or matches_alias(instance, FRAMES_CONTAINER_NAMES)
		or matches_alias(instance, QUEST_ROOT_NAMES)
		or matches_alias(instance, QUESTS_BACKGROUND_NAMES)
		or matches_alias(instance, LIST_CONTAINER_NAMES)
		or matches_alias(instance, QUEST_TEMPLATE_NAMES)
		or matches_alias(instance, HORSESHOE_REFERENCE_NAMES)
		or matches_alias(instance, REWARD_BUTTON_NAMES)
		or matches_alias(instance, ITEM_IMAGE_NAMES)
		or matches_alias(instance, VIEWPORT_FRAME_NAMES)
end

try_bind_ui = function()
	if currentUi and currentUi.Root and currentUi.Root.Parent and currentTemplateSource then
		return
	end

	local ui = find_quest_ui()
	if not ui then
		destroy_ui_binding()
		return
	end

	bind_ui(ui)
end

DataUtility.client.ensure_remotes()

rootTrove:Connect(playerGui.DescendantAdded, function(instance)
	if is_quest_ui_related(instance) or instance:IsA("LayerCollector") then
		try_bind_ui()
	end
end)

rootTrove:Connect(playerGui.DescendantRemoving, function(instance)
	if currentUi and (instance == currentUi.Root or instance:IsDescendantOf(currentUi.Root)) then
		task.defer(try_bind_ui)
	elseif is_quest_ui_related(instance) then
		task.defer(try_bind_ui)
	end
end)

try_bind_ui()