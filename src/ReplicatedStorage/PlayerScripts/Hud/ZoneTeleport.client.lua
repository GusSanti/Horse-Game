local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HudAnim = require(Libraries:WaitForChild("HudAnim"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))
local Notifications = require(Modules:WaitForChild("Client"):WaitForChild("Hud"):WaitForChild("Notifications"))

local MAIN_UI_NAMES = { "MainUI" }
local MAINFRAME_NAMES = { "MainframeFR", "MainFrameFR" }
local FRAMES_CONTAINER_NAMES = { "Frames" }
local TELEPORT_ROOT_NAMES = { "Teleport" }
local LEFT_BUTTON_FRAME_NAMES = { "LeftbuttonFR", "LeftbuttonFr" }
local TELEPORT_BUTTON_NAMES = { "teleportBt", "TeleportBT" }
local LIST_NAMES = { "ListScrollingFrame" }
local TEMPLATE_NAMES = { "TemplateButton" }
local AREA_LABEL_NAMES = { "SellTX", "AreaNameTX", "NameTX", "Name" }
local AREA_SHADOW_LABEL_NAMES = { "SellShadowTX", "AreaNameShadowTX", "NameShadowTX" }

local GENERATED_ATTRIBUTE = "ZoneTeleportEntry"
local TELEPORT_DATA_PATH = "Teleports"
local UNLOCKED_AREAS_PATH = "Teleports.UnlockedAreas"
local AREA_UNLOCKED_EVENT_NAME = "AreaUnlocked"
local UNLOCK_NOTIFICATION_ID = "ZoneTeleportUnlocked"

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local rootTrove = Trove.new()
local uiTrove = Trove.new()
local cardTrove = Trove.new()

local currentUi = nil
local templateSource = nil
local renderQueued = false
local teleportRequestInFlight = false

local function normalize_key(value)
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	return normalizedValue ~= "" and normalizedValue or nil
end

local function matches_alias(instance, aliases)
	local instanceName = normalize_key(instance.Name)
	if not instanceName then
		return false
	end

	for _, alias in ipairs(aliases) do
		if instanceName == normalize_key(alias) then
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

local function find_gui_object(root, aliases, recursive)
	return find_named_instance(root, aliases, "GuiObject", recursive)
end

local function find_main_ui()
	return find_named_instance(playerGui, MAIN_UI_NAMES, nil, true)
end

local function find_frames_container()
	local mainUi = find_main_ui()
	local mainframe = find_named_instance(mainUi, MAINFRAME_NAMES, nil, true)
	return find_named_instance(mainframe, FRAMES_CONTAINER_NAMES, nil, true)
end

local function find_teleport_button()
	local mainUi = find_main_ui()
	local leftButtons = find_named_instance(mainUi, LEFT_BUTTON_FRAME_NAMES, nil, true)
	return find_named_instance(leftButtons or mainUi, TELEPORT_BUTTON_NAMES, "GuiButton", true)
end

local function find_zone_container(areaId)
	local zones = Workspace:FindFirstChild("Zones") or Workspace:FindFirstChild("Zones", true)
	if not zones then
		return nil
	end

	return zones:FindFirstChild(areaId)
end

local function get_area_name(areaId)
	local zone = find_zone_container(areaId)
	local displayName = zone and zone:GetAttribute("DisplayName")
	if type(displayName) == "string" and displayName ~= "" then
		return displayName
	end

	return areaId
end

local function set_text(root, aliases, text)
	local updatedCount = 0
	local function set_if_matching(instance)
		if not matches_alias(instance, aliases) then
			return
		end
		if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
			instance.Text = text
			updatedCount += 1
		end
	end

	set_if_matching(root)
	for _, descendant in ipairs(root:GetDescendants()) do
		set_if_matching(descendant)
	end

	return updatedCount
end

local function update_canvas_size()
	if not currentUi or not currentUi.List:IsA("ScrollingFrame") then
		return
	end

	local layout = currentUi.List:FindFirstChildOfClass("UIListLayout")
		or currentUi.List:FindFirstChildOfClass("UIGridLayout")
	if layout then
		currentUi.List.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y)
	end
end

local function clear_generated_cards()
	cardTrove:Clean()
	if not currentUi then
		return
	end

	for _, child in ipairs(currentUi.List:GetChildren()) do
		if child:GetAttribute(GENERATED_ATTRIBUTE) == true then
			child:Destroy()
		end
	end
end

local function get_unlocked_areas()
	local teleports = DataUtility.client.get(TELEPORT_DATA_PATH)
	local unlockedAreas = type(teleports) == "table" and teleports.UnlockedAreas or nil
	local areas = {}
	if type(unlockedAreas) ~= "table" then
		return areas
	end

	for areaId, isUnlocked in pairs(unlockedAreas) do
		if type(areaId) == "string" and isUnlocked == true then
			table.insert(areas, {
				Id = areaId,
				Name = get_area_name(areaId),
			})
		end
	end

	table.sort(areas, function(left, right)
		return string.lower(left.Name) < string.lower(right.Name)
	end)
	return areas
end

local function show_teleport_error(code)
	local detailsByCode = {
		Mounted = "Desmonte do cavalo antes de se teleportar.",
		NpcUnavailable = "Esta área ainda não possui um NPC de destino configurado.",
		AreaUnavailable = "Esta área não está disponível neste servidor.",
		CharacterUnavailable = "Seu personagem ainda não está pronto.",
	}

	Notifications.ShowDialogue({
		id = "ZoneTeleportError",
		title = "Não foi possível teleportar",
		details = detailsByCode[code] or "Tente novamente em instantes.",
		acceptText = "Ok",
		denyText = "Fechar",
	})
end

local function close_teleport_ui()
	if currentUi and currentUi.Root and currentUi.Root.Parent then
		HudAnim.set_visible(currentUi.Root, false, true)
	end
end

local function request_teleport(areaId)
	if teleportRequestInFlight then
		return
	end

	teleportRequestInFlight = true
	task.spawn(function()
		local success, response = pcall(function()
			return Net.Function.TeleportToArea:Call(areaId)
		end)
		teleportRequestInFlight = false

		if success and type(response) == "table" and response.Success == true then
			close_teleport_ui()
			return
		end

		show_teleport_error(type(response) == "table" and response.Code or nil)
	end)
end

local function render_areas()
	if not currentUi or not templateSource or not currentUi.Root.Parent then
		return
	end

	clear_generated_cards()
	local areas = get_unlocked_areas()
	for layoutOrder, area in ipairs(areas) do
		local card = templateSource:Clone()
		card.Name = "Teleport_" .. area.Id
		card.LayoutOrder = layoutOrder
		card.Visible = true
		card:SetAttribute(GENERATED_ATTRIBUTE, true)
		set_text(card, AREA_LABEL_NAMES, area.Name)
		set_text(card, AREA_SHADOW_LABEL_NAMES, area.Name)

		local button = if card:IsA("GuiButton") then card else card:FindFirstChildWhichIsA("GuiButton", true)
		if button then
			button:SetAttribute("IgnoreAutoFrameButton", true)
		end

		card.Parent = currentUi.List
		cardTrove:Add(card)
		if button then
			cardTrove:Connect(button.Activated, function()
				request_teleport(area.Id)
			end)
		end
	end

	update_canvas_size()
	task.defer(update_canvas_size)
end

local function queue_render()
	if renderQueued then
		return
	end

	renderQueued = true
	task.defer(function()
		renderQueued = false
		render_areas()
	end)
end

local function open_teleport_ui()
	if not currentUi or not currentUi.Root.Parent then
		return
	end

	queue_render()
	HudAnim.set_visible(currentUi.Root, true, true)
end

local function destroy_ui_binding()
	clear_generated_cards()
	uiTrove:Destroy()
	uiTrove = Trove.new()
	currentUi = nil
	templateSource = nil
	teleportRequestInFlight = false
end

local function try_bind_ui()
	local frames = find_frames_container()
	local root = find_gui_object(frames, TELEPORT_ROOT_NAMES, true)
	if not root then
		destroy_ui_binding()
		return
	end
	if currentUi and currentUi.Root == root and templateSource and root.Parent then
		return
	end

	local list = find_gui_object(root, LIST_NAMES, true)
	local template = find_gui_object(list, TEMPLATE_NAMES, true)
	if not list or not template then
		destroy_ui_binding()
		return
	end

	destroy_ui_binding()
	currentUi = {
		Root = root,
		List = list,
		Template = template,
	}
	template.Visible = false
	pcall(function()
		local layout = list:FindFirstChildOfClass("UIListLayout") or list:FindFirstChildOfClass("UIGridLayout")
		if layout then
			layout.IgnoreInvisibleGuiObjects = true
		end
	end)
	templateSource = template:Clone()
	templateSource.Visible = true
	uiTrove:Add(templateSource)

	local teleportButton = find_teleport_button()
	if teleportButton then
		teleportButton:SetAttribute("IgnoreAutoFrameButton", true)
		uiTrove:Connect(teleportButton.Activated, open_teleport_ui)
	end
	uiTrove:Connect(root.AncestryChanged, function(_, parent)
		if not parent and currentUi and currentUi.Root == root then
			destroy_ui_binding()
			task.defer(try_bind_ui)
		end
	end)
	uiTrove:Connect(list:GetPropertyChangedSignal("AbsoluteSize"), function()
		task.defer(update_canvas_size)
	end)

	queue_render()
end

DataUtility.client.ensure_remotes()
rootTrove:Add(DataUtility.client.bind(UNLOCKED_AREAS_PATH, queue_render))
Net.Event[AREA_UNLOCKED_EVENT_NAME]:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	local areaName = type(payload.AreaName) == "string" and payload.AreaName or payload.AreaId
	if type(areaName) ~= "string" or areaName == "" then
		return
	end

	queue_render()
	Notifications.ShowDialogue({
		id = UNLOCK_NOTIFICATION_ID,
		title = "Nova área desbloqueada!",
		details = ("Você descobriu %s. Ela já está disponível em Teleportes."):format(areaName),
		acceptText = "Ver teleporte",
		denyText = "Continuar",
		onAccept = open_teleport_ui,
	})
end, rootTrove)

rootTrove:Connect(playerGui.DescendantAdded, function(instance)
	if matches_alias(instance, TELEPORT_ROOT_NAMES)
		or matches_alias(instance, TEMPLATE_NAMES)
		or matches_alias(instance, TELEPORT_BUTTON_NAMES)
	then
		task.defer(try_bind_ui)
	end
end)
rootTrove:Connect(Workspace.DescendantAdded, function(instance)
	if instance.Name == "Zones" or find_zone_container(instance.Name) == instance then
		queue_render()
	end
end)

try_bind_ui()
script:SetAttribute("RuntimeReady", true)
