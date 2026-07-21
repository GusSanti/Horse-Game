local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Services = Modules:WaitForChild("Services")
local Utility = Modules:WaitForChild("Utility")

local Trove = require(Libraries:WaitForChild("Trove"))
local StableDictionary = require(Dictionary:WaitForChild("StableDictionary"))
local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local HorseStatusBillboardConfig = require(GameData:WaitForChild("HorseStatusBillboardConfig"))
local HorseBondService = require(Services:WaitForChild("HorseBondService"))
local HorseStatusService = require(Services:WaitForChild("HorseStatusService"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local Net = require(Libraries:WaitForChild("Net"))

local localPlayer: Player = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()

local REFRESH_INTERVAL: number = HorseStatusBillboardConfig.RefreshInterval or 0.25
local RENDER_BATCH_SIZE = 1

local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"
local FRAMES_CONTAINER_NAME = "Frames"
local STABLE_FRAME_NAME = "Stable"
local STABLE_CONTENT_NAME = "StableFR"
local LIST_CONTAINER_NAMES = { "ListScrollingFrame" }
local TEMPLATE_NAMES = { "HorseTemplate" }
local STATS_NAMES = { "StatsFR" }
local STAT_TEMPLATE_NAMES = { "StatFR" }
local HORSE_NAME_NAMES = { "HorseNameTX" }
local HORSE_DETAILS_NAMES = { "DetailsTX" }
local HORSE_IMAGE_NAMES = { "HorseImage" }
local SELECTED_FRAME_NAMES = { "SelectedFR" }
local SELECTED_TEXT_NAMES = { "SelectedTX" }
local STAT_NAME_NAMES = { "StatsTX" }
local STAT_INFO_NAMES = { "StatAmountTX" }
local BAR_NAMES = { "BarBG" }
local INSIDE_BAR_NAMES = { "InsideBarBG" }
local BAR_FILL_SIZE_NAMES = {
	InsideBarBG = true,
}

local STATUS_DISPLAY_NAMES = {
	Trust = "Trust",
	Level = "Level",
	Care = "Care",
	Happiness = "Happiness",
	Hunger = "Hunger",
	Thirst = "Thirst",
	Cleanliness = "Cleanliness",
	Health = "Health",
}

type StableUi = {
	Root: Instance,
	ListContainer: GuiObject,
	Template: GuiObject,
	TemplateSource: GuiObject?,
}

type StableHorseEntry = {
	SlotIndex: number,
	SlotName: string,
	HorseId: string,
}

type CardStatRow = {
	NameLabel: TextLabel?,
	InfoLabel: TextLabel?,
	BarFill: GuiObject?,
}

type HorseCard = {
	SlotName: string,
	HorseId: string,
	Card: GuiObject,
	NameLabel: TextLabel?,
	DetailsLabel: TextLabel?,
	SelectedFrame: GuiObject?,
	SelectedLabel: TextLabel?,
	ImageObject: GuiObject?,
	StatRows: {[string]: CardStatRow},
}

local currentUi: StableUi? = nil
local activeCards: {HorseCard} = {}
local refreshAccumulator = 0
local renderQueued = false
local renderGeneration = 0
local stableRenderDirty = false
local mountRequestInFlight = false

local function normalize_key(value: string?): string?
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

local function matches_alias(instance: Instance, aliases: {string}): boolean
	local normalizedName = normalize_key(instance.Name)
	if not normalizedName then
		return false
	end

	for _, alias: string in ipairs(aliases) do
		if normalize_key(alias) == normalizedName then
			return true
		end
	end

	return false
end

local function find_named_instance(root: Instance?, aliases: {string}, className: string?, recursive: boolean?): Instance?
	if not root then
		return nil
	end

	for _, child: Instance in ipairs(root:GetChildren()) do
		if matches_alias(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	if recursive == false then
		return nil
	end

	for _, descendant: Instance in ipairs(root:GetDescendants()) do
		if matches_alias(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function find_text_label(root: Instance?, aliases: {string}): TextLabel?
	local instance = find_named_instance(root, aliases, "TextLabel")
	if instance then
		return instance :: TextLabel
	end

	return nil
end

local function find_gui_object(root: Instance?, aliases: {string}, recursive: boolean?): GuiObject?
	local instance = find_named_instance(root, aliases, "GuiObject", recursive)
	if instance then
		return instance :: GuiObject
	end

	return nil
end

local function find_horse_mount_button(card: GuiObject, horseImage: GuiObject?): GuiButton?
	if horseImage and horseImage:IsA("GuiButton") then
		return horseImage
	end

	if card:IsA("GuiButton") then
		return card
	end

	return nil
end

local function mount_horse_from_stable(horseId: string): ()
	if mountRequestInFlight or horseId == "" then
		return
	end

	mountRequestInFlight = true

	task.spawn(function()
		pcall(function()
			Net.Function.HorseMountAction:Call({
				Action = "Mount",
				HorseId = horseId,
			})
		end)

		mountRequestInFlight = false
	end)
end

local function find_frame(root: Instance?, aliases: {string}, recursive: boolean?): Frame?
	local instance = find_named_instance(root, aliases, "Frame", recursive)
	if instance then
		return instance :: Frame
	end

	return nil
end

local function clear_viewport_descendants(root: Instance?): ()
	if not root then
		return
	end

	for _, descendant: Instance in ipairs(root:GetDescendants()) do
		if descendant:IsA("ViewportFrame") then
			descendant:Destroy()
		end
	end
end

local function set_horse_image(imageObject: GuiObject?, horse): ()
	if not imageObject then
		return
	end

	clear_viewport_descendants(imageObject)

	local definition = type(horse) == "table" and HorseCatalog.GetDefinition(horse.CatalogId) or nil
	local imageId = definition and definition.Image or ""

	if imageObject:IsA("ImageLabel") or imageObject:IsA("ImageButton") then
		imageObject.Image = type(imageId) == "string" and imageId or ""
		imageObject.ImageColor3 = Color3.fromRGB(255, 255, 255)
		imageObject.ImageTransparency = imageObject.Image ~= "" and 0 or 1
	end
end

local function find_main_ui_root(): Instance?
	local mainUi = playerGui:FindFirstChild(MAIN_UI_NAME)
	if not mainUi then
		mainUi = playerGui:FindFirstChild(MAIN_UI_NAME, true)
	end

	if not mainUi then
		return nil
	end

	return mainUi
end

local function find_mainframe_root(): Instance?
	local mainUi = find_main_ui_root()
	if not mainUi then
		return nil
	end

	local mainframe = mainUi:FindFirstChild(MAINFRAME_NAME)
	if not mainframe then
		mainframe = mainUi:FindFirstChild(MAINFRAME_NAME, true)
	end

	if not mainframe then
		return nil
	end

	return mainframe
end

local function find_main_frames_container(): Instance?
	local mainframe = find_mainframe_root()
	if not mainframe then
		return nil
	end

	local framesContainer = mainframe:FindFirstChild(FRAMES_CONTAINER_NAME)
	if framesContainer then
		return framesContainer
	end

	return mainframe:FindFirstChild(FRAMES_CONTAINER_NAME, true)
end

local function find_stable_root_instance(): Instance?
	local framesContainer = find_main_frames_container()
	if not framesContainer then
		return nil
	end

	local stableRoot = framesContainer:FindFirstChild(STABLE_FRAME_NAME)
	if stableRoot then
		return stableRoot
	end

	return framesContainer:FindFirstChild(STABLE_FRAME_NAME, true)
end

local function close_stable_ui(): ()
	local root = currentUi and currentUi.Root or find_stable_root_instance()
	if root and root:IsA("GuiObject") then
		root.Visible = false
		return
	end

	if root and root:IsA("LayerCollector") then
		root.Enabled = false
		return
	end

	local contentRoot = root and find_named_instance(root, { STABLE_CONTENT_NAME }, nil, true)
	if contentRoot and contentRoot:IsA("GuiObject") then
		contentRoot.Visible = false
	elseif contentRoot and contentRoot:IsA("LayerCollector") then
		contentRoot.Enabled = false
	end
end

local function is_ui_visible(instance: Instance?): boolean
	local current = instance

	while current do
		if current:IsA("GuiObject") and current.Visible ~= true then
			return false
		end

		if current:IsA("LayerCollector") and current.Enabled ~= true then
			return false
		end

		current = current.Parent
	end

	return true
end

local function strip_local_scripts(root: Instance): ()
	for _, descendant: Instance in ipairs(root:GetDescendants()) do
		if descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function build_relative_path(root: Instance, target: Instance): {string}
	local segments = {}
	local current = target

	while current and current ~= root do
		table.insert(segments, 1, current.Name)
		current = current.Parent
	end

	return segments
end

local function find_direct_child_by_name(parent: Instance, childName: string): Instance?
	for _, child: Instance in ipairs(parent:GetChildren()) do
		if child.Name == childName then
			return child
		end
	end

	return nil
end

local function find_by_relative_path(root: Instance, pathSegments: {string}): Instance?
	local current = root

	for _, segment: string in ipairs(pathSegments) do
		local nextNode = find_direct_child_by_name(current, segment)
		if not nextNode then
			return nil
		end

		current = nextNode
	end

	return current
end

local function restore_original_gui_metrics(sourceRoot: Instance, targetRoot: Instance, ignoredSizeNames: {[string]: boolean}?): ()
	local function restore_pair(sourceInstance: Instance, targetInstance: Instance): ()
		if sourceInstance:IsA("GuiObject") and targetInstance:IsA("GuiObject") then
			targetInstance.AutomaticSize = sourceInstance.AutomaticSize

			if not (ignoredSizeNames and ignoredSizeNames[targetInstance.Name]) then
				targetInstance.Size = sourceInstance.Size
			end
		end
	end

	restore_pair(sourceRoot, targetRoot)

	for _, sourceDescendant: Instance in ipairs(sourceRoot:GetDescendants()) do
		local targetDescendant = find_by_relative_path(targetRoot, build_relative_path(sourceRoot, sourceDescendant))
		if targetDescendant then
			restore_pair(sourceDescendant, targetDescendant)
		end
	end
end

local function make_template_source(template: GuiObject): GuiObject
	local source = template:Clone()
	source.Visible = true
	strip_local_scripts(source)
	clear_viewport_descendants(source)

	template.Visible = false

	return source
end

local function get_status_display_name(statusName: string): string
	return STATUS_DISPLAY_NAMES[statusName] or statusName
end

local function clamp_ratio(currentValue: number, maxValue: number): number
	if maxValue <= 0 then
		return 0
	end

	return math.clamp(currentValue / maxValue, 0, 1)
end

local function round_number(value: number?): number
	if type(value) ~= "number" then
		return 0
	end

	return math.floor(value + 0.5)
end

local function get_stable_horses(): {StableHorseEntry}
	local stable = DataUtility.client.get("Stable")
	local horses = DataUtility.client.get("Horses")
	local horseEntries: {StableHorseEntry} = {}

	if type(stable) ~= "table" or type(horses) ~= "table" then
		return horseEntries
	end

	local horseSlots = stable.HorseSlots
	local ownedHorses = horses.Owned

	if type(horseSlots) ~= "table" or type(ownedHorses) ~= "table" then
		return horseEntries
	end

	local ownedStalls = math.clamp(
		math.floor(tonumber(stable.OwnedStalls) or StableDictionary.DefaultOwnedStalls),
		0,
		StableDictionary.MaxOwnedStalls or #StableDictionary.HorseSlotOrder
	)

	for slotIndex, slotName: string in ipairs(StableDictionary.HorseSlotOrder) do
		if slotIndex > ownedStalls then
			break
		end

		local horseId = horseSlots[slotName]
		if type(horseId) == "string" and horseId ~= "" and ownedHorses[horseId] then
			horseEntries[#horseEntries + 1] = {
				SlotIndex = slotIndex,
				SlotName = slotName,
				HorseId = horseId,
			}
		end
	end

	return horseEntries
end

local function cards_match_stable_entries(stableHorseEntries: {StableHorseEntry}): boolean
	if #activeCards ~= #stableHorseEntries then
		return false
	end

	for index, stableHorseEntry: StableHorseEntry in ipairs(stableHorseEntries) do
		local activeCard = activeCards[index]
		if not activeCard then
			return false
		end

		if activeCard.HorseId ~= stableHorseEntry.HorseId or activeCard.SlotName ~= stableHorseEntry.SlotName then
			return false
		end
	end

	return true
end

local function get_owned_horse(horseId: string): any?
	local horses = DataUtility.client.get("Horses")
	local ownedHorses = type(horses) == "table" and horses.Owned or nil

	if type(ownedHorses) ~= "table" then
		return nil
	end

	return ownedHorses[horseId]
end

local function get_equipped_horse_id(): string
	local horses = DataUtility.client.get("Horses")
	local equippedHorseId = type(horses) == "table" and horses.EquippedHorseId or nil

	if type(equippedHorseId) ~= "string" then
		return ""
	end

	return equippedHorseId
end

local function is_horse_equipped(horseId: string): boolean
	return horseId ~= "" and get_equipped_horse_id() == horseId
end

local function get_horse_display_name(horseId: string, horse): string
	if type(horse) == "table" then
		local nickname = horse.Nickname
		if type(nickname) == "string" and nickname ~= "" then
			return nickname
		end

		local displayName = horse.DisplayName
		if type(displayName) == "string" and displayName ~= "" then
			return displayName
		end

		local definition = HorseCatalog.GetDefinition(horse.CatalogId)
		if definition and type(definition.DisplayName) == "string" and definition.DisplayName ~= "" then
			return definition.DisplayName
		end
	end

	return horseId
end

local function build_horse_details_text(horseId: string, horse): string
	local definition = nil
	if type(horse) == "table" then
		definition = HorseCatalog.GetDefinition(horse.CatalogId)
	end

	if not definition then
		definition = HorseCatalog.GetDefinition("Default")
	end

	local rarity = definition and definition.Rarity or nil
	local tier = definition and definition.Tier or nil

	if type(rarity) == "string" and rarity ~= "" and type(tier) == "string" and tier ~= "" then
		return ("%s | %s"):format(rarity, tier)
	end

	if type(rarity) == "string" and rarity ~= "" then
		return rarity
	end

	if type(tier) == "string" and tier ~= "" then
		return tier
	end

	if type(horse) == "table" and type(horse.CatalogId) == "string" and horse.CatalogId ~= "" then
		return horse.CatalogId
	end

	return horseId
end

local function update_canvas_size(): ()
	local ui = currentUi
	if not ui then
		return
	end

	if not ui.ListContainer:IsA("ScrollingFrame") then
		return
	end

	local scrollingFrame = ui.ListContainer :: ScrollingFrame
	local layout = scrollingFrame:FindFirstChildOfClass("UIListLayout") :: UIListLayout?
	if not layout then
		layout = scrollingFrame:FindFirstChildWhichIsA("UIListLayout", true) :: UIListLayout?
	end

	if layout then
		scrollingFrame.CanvasSize = UDim2.fromOffset(
			layout.AbsoluteContentSize.X,
			layout.AbsoluteContentSize.Y
		)
	end
end

local function format_percent(alpha: number): string
	return ("%d%%"):format(math.max(0, round_number(math.clamp(alpha, 0, 1) * 100)))
end

local function build_placeholder_descriptors(): {{Key: string, Label: string, Info: string, Alpha: number}}
	local descriptors = {
		{
			Key = "Trust",
			Label = get_status_display_name("Trust"),
			Info = format_percent(0),
			Alpha = 0,
		},
		{
			Key = "Level",
			Label = get_status_display_name("Level"),
			Info = format_percent(0),
			Alpha = 0,
		},
		{
			Key = "Care",
			Label = get_status_display_name("Care"),
			Info = format_percent(0),
			Alpha = 0,
		},
	}

	for _, statusName: string in ipairs(HorseStatusService.StatusOrder) do
		descriptors[#descriptors + 1] = {
			Key = statusName,
			Label = get_status_display_name(statusName),
			Info = format_percent(0),
			Alpha = 0,
		}
	end

	return descriptors
end

local function build_status_descriptors(horse): {{Key: string, Label: string, Info: string, Alpha: number}}
	if type(horse) ~= "table" then
		return build_placeholder_descriptors()
	end

	local descriptors = {}
	local statuses = HorseStatusService.GetStatuses(horse) or {}
	local displayData = HorseBondService.GetDisplayData(horse)
	local needs = type(horse) == "table" and horse.Needs or {}
	local maxValues = type(needs) == "table" and needs.Max or {}

	local trustAlpha = 0
	local levelAlpha = 0

	if displayData then
		trustAlpha = clamp_ratio(
			tonumber(displayData.Friendship) or 0,
			math.max(1, tonumber(displayData.MaxFriendship) or 100)
		)

		levelAlpha = math.clamp(tonumber(displayData.ProgressAlpha) or 0, 0, 1)
	end

	local careTotalRatio = 0
	local careCount = 0
	for _, statusName: string in ipairs(HorseStatusService.StatusOrder) do
		local maxValue = math.max(1, tonumber(maxValues[statusName]) or 100)
		local currentValue = tonumber(statuses[statusName]) or 0
		careTotalRatio += clamp_ratio(currentValue, maxValue)
		careCount += 1
	end

	local careAlpha = if careCount > 0 then math.clamp(careTotalRatio / careCount, 0, 1) else 0

	descriptors[#descriptors + 1] = {
		Key = "Trust",
		Label = get_status_display_name("Trust"),
		Info = format_percent(trustAlpha),
		Alpha = trustAlpha,
	}

	descriptors[#descriptors + 1] = {
		Key = "Level",
		Label = get_status_display_name("Level"),
		Info = format_percent(levelAlpha),
		Alpha = levelAlpha,
	}

	descriptors[#descriptors + 1] = {
		Key = "Care",
		Label = get_status_display_name("Care"),
		Info = format_percent(careAlpha),
		Alpha = careAlpha,
	}

	for _, statusName: string in ipairs(HorseStatusService.StatusOrder) do
		local maxValue = math.max(1, tonumber(maxValues[statusName]) or 100)
		local currentValue = math.max(0, tonumber(statuses[statusName]) or 0)
		local ratio = clamp_ratio(currentValue, maxValue)
		local percent = math.max(0, round_number((currentValue / maxValue) * 100))

		descriptors[#descriptors + 1] = {
			Key = statusName,
			Label = get_status_display_name(statusName),
			Info = ("%d%%"):format(percent),
			Alpha = ratio,
		}
	end

	return descriptors
end

local function update_card_stats(cardEntry: HorseCard): ()
	local horse = get_owned_horse(cardEntry.HorseId)
	if not horse then
		return
	end

	if cardEntry.NameLabel then
		cardEntry.NameLabel.Text = get_horse_display_name(cardEntry.HorseId, horse)
	end

	if cardEntry.DetailsLabel then
		cardEntry.DetailsLabel.Text = build_horse_details_text(cardEntry.HorseId, horse)
	end

	set_horse_image(cardEntry.ImageObject, horse)

	if cardEntry.SelectedFrame then
		cardEntry.SelectedFrame.Visible = is_horse_equipped(cardEntry.HorseId)
	end

	if cardEntry.SelectedLabel and cardEntry.SelectedLabel.Text == "" then
		cardEntry.SelectedLabel.Text = "Selected"
	end

	for _, descriptor in ipairs(build_status_descriptors(horse)) do
		local row = cardEntry.StatRows[descriptor.Key]
		if not row then
			continue
		end

		if row.NameLabel then
			row.NameLabel.Text = descriptor.Label
		end

		if row.InfoLabel then
			row.InfoLabel.Text = descriptor.Info
		end

		if row.BarFill then
			local currentSize = row.BarFill.Size
			row.BarFill.Size = UDim2.new(
				math.clamp(descriptor.Alpha, 0, 1),
				0,
				currentSize.Y.Scale,
				currentSize.Y.Offset
			)
		end
	end
end

local function configure_card(card: GuiObject, templateSource: GuiObject, stableHorseEntry: StableHorseEntry): HorseCard
	local horse = get_owned_horse(stableHorseEntry.HorseId)
	local nameLabel = find_text_label(card, HORSE_NAME_NAMES)
	local detailsLabel = find_text_label(card, HORSE_DETAILS_NAMES)
	local horseImage = find_gui_object(card, HORSE_IMAGE_NAMES, true)
	local mountButton = find_horse_mount_button(card, horseImage)
	local selectedFrame = find_gui_object(card, SELECTED_FRAME_NAMES, true)
	local selectedLabel = find_text_label(selectedFrame, SELECTED_TEXT_NAMES)
	local statsContainer = find_gui_object(card, STATS_NAMES, true)
	local statTemplate = find_gui_object(statsContainer, STAT_TEMPLATE_NAMES, true)
	local statRows: {[string]: CardStatRow} = {}

	card.Name = stableHorseEntry.HorseId
	card.Visible = true
	card.LayoutOrder = stableHorseEntry.SlotIndex
	restore_original_gui_metrics(templateSource, card, BAR_FILL_SIZE_NAMES)

	if nameLabel then
		nameLabel.Text = get_horse_display_name(stableHorseEntry.HorseId, horse)
	end

	if detailsLabel then
		detailsLabel.Text = build_horse_details_text(stableHorseEntry.HorseId, horse)
	end

	if selectedFrame then
		selectedFrame.Visible = is_horse_equipped(stableHorseEntry.HorseId)
	end

	if selectedLabel and selectedLabel.Text == "" then
		selectedLabel.Text = "Selected"
	end

	set_horse_image(horseImage, horse)

	if mountButton then
		cardTrove:Connect(mountButton.Activated, function()
			mount_horse_from_stable(stableHorseEntry.HorseId)
		end)
	end

	if statsContainer and statTemplate then
		statTemplate.Visible = false

		for index, descriptor in ipairs(build_status_descriptors(horse)) do
			local row = statTemplate:Clone() :: GuiObject
			row.Name = descriptor.Key
			row.Visible = true
			row.LayoutOrder = index
			row.Parent = statsContainer
			restore_original_gui_metrics(statTemplate, row, BAR_FILL_SIZE_NAMES)

			statRows[descriptor.Key] = {
				NameLabel = find_text_label(row, STAT_NAME_NAMES),
				InfoLabel = find_text_label(row, STAT_INFO_NAMES),
				BarFill = find_gui_object(find_gui_object(row, BAR_NAMES, true), INSIDE_BAR_NAMES, true),
			}
		end
	end

	restore_original_gui_metrics(templateSource, card, BAR_FILL_SIZE_NAMES)

	return {
		SlotName = stableHorseEntry.SlotName,
		HorseId = stableHorseEntry.HorseId,
		Card = card,
		NameLabel = nameLabel,
		DetailsLabel = detailsLabel,
		SelectedFrame = selectedFrame,
		SelectedLabel = selectedLabel,
		ImageObject = horseImage,
		StatRows = statRows,
	}
end

local function refresh_cards(): ()
	for _, cardEntry: HorseCard in ipairs(activeCards) do
		update_card_stats(cardEntry)
	end
end

local function render_stable(): ()
	local ui = currentUi
	if not ui or not ui.TemplateSource then
		return
	end

	if not is_ui_visible(ui.Root) then
		stableRenderDirty = true
		return
	end

	stableRenderDirty = false
	renderGeneration += 1

	local generation = renderGeneration
	local stableHorseEntries = get_stable_horses()

	local templateSource = ui.TemplateSource

	cardTrove:Clean()
	table.clear(activeCards)
	if ui.ListContainer:IsA("ScrollingFrame") then
		local scrollingFrame = ui.ListContainer :: ScrollingFrame
		scrollingFrame.CanvasPosition = Vector2.zero
	end

	local nextEntryIndex = 1

	local function render_batch(): ()
		if generation ~= renderGeneration then
			return
		end

		local currentBoundUi = currentUi
		if not currentBoundUi or currentBoundUi.Root ~= ui.Root or not currentBoundUi.TemplateSource then
			return
		end

		if not is_ui_visible(ui.Root) then
			stableRenderDirty = true
			return
		end

		local batchEnd = math.min(#stableHorseEntries, nextEntryIndex + RENDER_BATCH_SIZE - 1)
		for entryIndex = nextEntryIndex, batchEnd do
			local stableHorseEntry = stableHorseEntries[entryIndex]
			local card = templateSource:Clone()
			card.Parent = ui.ListContainer
			cardTrove:Add(card)

			local cardEntry = configure_card(card, templateSource, stableHorseEntry)
			activeCards[#activeCards + 1] = cardEntry
		end

		nextEntryIndex = batchEnd + 1
		refresh_cards()
		update_canvas_size()

		if nextEntryIndex <= #stableHorseEntries then
			task.spawn(function()
			RunService.Heartbeat:Wait()
			render_batch()
		end)
			return
		end

		task.defer(function()
			if generation ~= renderGeneration then
				return
			end

			update_canvas_size()
		end)
	end

	render_batch()
end

local function queue_render(): ()
	local ui = currentUi
	if not ui or not ui.TemplateSource then
		return
	end

	stableRenderDirty = true
	if not is_ui_visible(ui.Root) or renderQueued then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		if stableRenderDirty then
			render_stable()
		end
	end)
end

local function refresh_or_render_stable(): ()
	local ui = currentUi
	if not ui or not ui.TemplateSource then
		return
	end

	stableRenderDirty = true
	if not is_ui_visible(ui.Root) then
		return
	end

	local stableHorseEntries = get_stable_horses()
	if cards_match_stable_entries(stableHorseEntries) then
		stableRenderDirty = false
		refresh_cards()
		update_canvas_size()
		return
	end

	queue_render()
end

local function get_stable_ui(root: Instance): StableUi?
	local contentRoot = find_named_instance(root, { STABLE_CONTENT_NAME }, nil, true) or root
	local listContainer = find_gui_object(contentRoot, LIST_CONTAINER_NAMES, true)
	local template = listContainer and find_gui_object(listContainer, TEMPLATE_NAMES, false)
	if not template and listContainer then
		template = find_gui_object(listContainer, TEMPLATE_NAMES, true)
	end

	if not listContainer or not template then
		return nil
	end

	local statsContainer = find_gui_object(template, STATS_NAMES, true)
	local statTemplate = statsContainer and find_gui_object(statsContainer, STAT_TEMPLATE_NAMES, true)
	local horseName = find_text_label(template, HORSE_NAME_NAMES)
	local horseImage = find_gui_object(template, HORSE_IMAGE_NAMES, true)

	if not statsContainer or not statTemplate or not horseName or not horseImage then
		return nil
	end

	return {
		Root = root,
		ListContainer = listContainer,
		Template = template,
	}
end

local function find_stable_ui(): StableUi?
	local stableRoot = find_stable_root_instance()
	if not stableRoot then
		return nil
	end

	return get_stable_ui(stableRoot)
end

local function destroy_ui_binding(): ()
	renderGeneration += 1
	renderQueued = false
	stableRenderDirty = false
	cardTrove:Clean()
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = nil
	table.clear(activeCards)
end

local function bind_ui(ui: StableUi): ()
	local existingUi = currentUi
	if existingUi and existingUi.Root == ui.Root then
		return
	end

	destroy_ui_binding()

	local templateSource = make_template_source(ui.Template)
	ui.TemplateSource = templateSource
	currentUi = ui
	uiTrove:Add(templateSource)

	uiTrove:Add(DataUtility.client.bind("Stable", refresh_or_render_stable))
	uiTrove:Add(DataUtility.client.bind("Horses", refresh_or_render_stable))
	uiTrove:Add(DataUtility.client.bind("Horses.Owned", refresh_or_render_stable))

	uiTrove:Connect(ui.Root.AncestryChanged, function(_, parent)
		if parent then
			return
		end

		local boundUi = currentUi
		if boundUi and boundUi.Root == ui.Root then
			destroy_ui_binding()
			task.defer(function()
				local reboundUi = find_stable_ui()
				if reboundUi then
					bind_ui(reboundUi)
				end
			end)
		end
	end)

	queue_render()
end

local function is_stable_ui_related(instance: Instance): boolean
	return instance.Name == STABLE_FRAME_NAME
		or instance.Name == STABLE_CONTENT_NAME
		or matches_alias(instance, TEMPLATE_NAMES)
		or matches_alias(instance, STAT_TEMPLATE_NAMES)
		or matches_alias(instance, HORSE_IMAGE_NAMES)
		or matches_alias(instance, HORSE_NAME_NAMES)
		or instance.Name == FRAMES_CONTAINER_NAME
		or instance.Name == MAINFRAME_NAME
		or instance.Name == MAIN_UI_NAME
end

local function try_bind_ui(): ()
	local ui = find_stable_ui()
	if not ui then
		destroy_ui_binding()
		return
	end

	bind_ui(ui)
end

DataUtility.client.ensure_remotes()

rootTrove:Connect(Net.Event.HorseMountState, function(payload)
	if type(payload) == "table" and payload.Kind == "Mounting" then
		close_stable_ui()
	end
end)

rootTrove:Connect(playerGui.DescendantAdded, function(instance: Instance)
	if is_stable_ui_related(instance) or instance:IsA("LayerCollector") then
		try_bind_ui()
	end
end)

rootTrove:Connect(playerGui.DescendantRemoving, function(instance: Instance)
	local ui = currentUi
	if ui and (instance == ui.Root or instance:IsDescendantOf(ui.Root)) then
		task.defer(try_bind_ui)
	elseif is_stable_ui_related(instance) then
		task.defer(try_bind_ui)
	end
end)

rootTrove:Add(DataUtility.client.bind("Horses.Owned", refresh_or_render_stable))

rootTrove:Connect(RunService.Heartbeat, function(deltaTime: number)
	local ui = currentUi
	if ui and stableRenderDirty and is_ui_visible(ui.Root) and not renderQueued then
		refresh_or_render_stable()
	end

	if not ui or #activeCards == 0 then
		return
	end

	refreshAccumulator += deltaTime
	if refreshAccumulator < REFRESH_INTERVAL then
		return
	end

	refreshAccumulator = 0
	refresh_cards()
end)

try_bind_ui()
