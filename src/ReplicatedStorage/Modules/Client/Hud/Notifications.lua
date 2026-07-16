local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

local Notifications = {}

local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"
local DIALOGUE_FRAME_NAMES = { "DialogueFR" }
local CONFIRMATION_FRAME_NAMES = { "ConfirmationFR" }
local TASKS_FRAME_NAMES = { "TasksFR" }
local FEEDING_FRAME_NAMES = { "FeedingFR", "LoadingFR" }
local TITLE_NAMES = { "DialogueNameTX" }
local TITLE_SHADOW_NAMES = { "DialogueNameShadowTX" }
local DETAILS_NAMES = { "DetailsTX" }
local ACCEPT_BUTTON_NAMES = { "Accept" }
local DENY_BUTTON_NAMES = { "Deny" }

local activeNotificationId = nil
local buttonConnections = {}

local function normalize_key(value: string?): string?
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	return normalizedValue ~= "" and normalizedValue or nil
end

local function matches_alias(instance: Instance, aliases: {string}): boolean
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

local function find_named_instance(root: Instance?, aliases: {string}, className: string?): Instance?
	if not root then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if matches_alias(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

local function get_mainframe(): Instance?
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	local mainUi = playerGui:FindFirstChild(MAIN_UI_NAME) or playerGui:FindFirstChild(MAIN_UI_NAME, true)
	if not mainUi then
		return nil
	end

	return mainUi:FindFirstChild(MAINFRAME_NAME) or mainUi:FindFirstChild(MAINFRAME_NAME, true)
end

local function get_dialogue_references()
	local mainframe = get_mainframe()
	local dialogue = find_named_instance(mainframe, DIALOGUE_FRAME_NAMES, "GuiObject")
	if not dialogue then
		return nil
	end

	return {
		Dialogue = dialogue :: GuiObject,
		Title = find_named_instance(dialogue, TITLE_NAMES, "TextLabel") :: TextLabel?,
		TitleShadow = find_named_instance(dialogue, TITLE_SHADOW_NAMES, "TextLabel") :: TextLabel?,
		Details = find_named_instance(dialogue, DETAILS_NAMES, "TextLabel") :: TextLabel?,
		AcceptButton = find_named_instance(dialogue, ACCEPT_BUTTON_NAMES, "GuiButton") :: GuiButton?,
		DenyButton = find_named_instance(dialogue, DENY_BUTTON_NAMES, "GuiButton") :: GuiButton?,
	}
end

local function disconnect_buttons(): ()
	for _, connection in ipairs(buttonConnections) do
		connection:Disconnect()
	end

	table.clear(buttonConnections)
end

local function hide_confirmation_root(): ()
	local confirmation = find_named_instance(get_mainframe(), CONFIRMATION_FRAME_NAMES, "GuiObject")
	if confirmation then
		(confirmation :: GuiObject).Visible = false
	end
end

local function hide_task_panels(): ()
	local mainframe = get_mainframe()
	local tasks = find_named_instance(mainframe, TASKS_FRAME_NAMES, "GuiObject")
	local feeding = find_named_instance(tasks or mainframe, FEEDING_FRAME_NAMES, "GuiObject")

	if feeding then
		(feeding :: GuiObject).Visible = false
	end

	if tasks then
		(tasks :: GuiObject).Visible = false
	end
end

local function set_text_pair(primary: TextLabel?, shadow: TextLabel?, value: string?): ()
	if type(value) ~= "string" then
		return
	end

	if primary then
		primary.Text = value
	end

	if shadow then
		shadow.Text = value
	end
end

local function set_button_text(button: GuiButton?, value: string?): ()
	if not button or type(value) ~= "string" or value == "" then
		return
	end

	if button:IsA("TextButton") then
		button.Text = value
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("TextLabel") then
			descendant.Text = value
		end
	end
end

function Notifications.ShowDialogue(config): boolean
	config = config or {}

	local refs = get_dialogue_references()
	if not refs or not refs.AcceptButton or not refs.DenyButton then
		return false
	end

	disconnect_buttons()
	hide_confirmation_root()
	if config.hideTasks == true then
		hide_task_panels()
	end

	activeNotificationId = config.id
	refs.Dialogue.Visible = true
	set_text_pair(refs.Title, refs.TitleShadow, config.title or "Notification")
	set_text_pair(refs.Details, nil, config.details or "")
	set_button_text(refs.AcceptButton, config.acceptText)
	set_button_text(refs.DenyButton, config.denyText)

	buttonConnections[#buttonConnections + 1] = refs.AcceptButton.MouseButton1Click:Connect(function()
		Notifications.HideDialogue(config.id)
		if type(config.onAccept) == "function" then
			config.onAccept()
		end
	end)

	buttonConnections[#buttonConnections + 1] = refs.DenyButton.MouseButton1Click:Connect(function()
		Notifications.HideDialogue(config.id)
		if type(config.onDeny) == "function" then
			config.onDeny()
		end
	end)

	return true
end

function Notifications.UpdateDialogue(id, config): boolean
	if activeNotificationId ~= id then
		return false
	end

	local refs = get_dialogue_references()
	if not refs or not refs.Dialogue.Visible then
		return false
	end

	config = config or {}
	set_text_pair(refs.Title, refs.TitleShadow, config.title)
	set_text_pair(refs.Details, nil, config.details)
	set_button_text(refs.AcceptButton, config.acceptText)
	set_button_text(refs.DenyButton, config.denyText)
	return true
end

function Notifications.IsDialogueActive(id): boolean
	return activeNotificationId == id
end

function Notifications.HideDialogue(id): boolean
	if id ~= nil and activeNotificationId ~= id then
		return false
	end

	local refs = get_dialogue_references()
	disconnect_buttons()
	hide_confirmation_root()

	if refs then
		refs.Dialogue.Visible = false
	end

	activeNotificationId = nil
	return refs ~= nil
end

return Notifications
