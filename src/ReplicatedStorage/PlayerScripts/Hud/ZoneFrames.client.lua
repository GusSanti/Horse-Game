local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")

local Trove = require(Libraries:WaitForChild("Trove"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local MAIN_UI_NAME = "MainUI"
local MAINFRAME_NAME = "MainframeFR"
local FRAMES_CONTAINER_NAME = "Frames"
local ZONES_FOLDER_NAME = "Zones"
local UPDATE_INTERVAL = 0.1
local VERTICAL_PADDING = 6

local ZONE_FRAME_ALIASES = {
	shop = "SeedShop",
	shopzone = "SeedShop",
	seedshop = "SeedShop",
	seedshopzone = "SeedShop",
	seedzone = "SeedShop",
}

type ZoneState = {
	Name: string,
	Display: GuiObject?,
	Parts: { BasePart },
	IsInside: boolean,
}

local rootTrove = Trove.new()
local interfaceTrove = nil
local boundUiRoot = nil
local boundZonesFolder = nil
local lastBindReason = ""

local function log_bind_reason(reason: string)
	if lastBindReason == reason then
		return
	end

	lastBindReason = reason
end

local function normalize_key(value): string?
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

local function get_character_root(): BasePart?
	local character = localPlayer.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function is_point_inside_zone(point: Vector3, part: BasePart): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5

	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Z) <= halfSize.Z
		and math.abs(localPoint.Y) <= halfSize.Y + VERTICAL_PADDING
end

local function find_ui_root(): Instance?
	local directUi = playerGui:FindFirstChild(MAIN_UI_NAME)
	if directUi then
		return directUi
	end

	return playerGui:FindFirstChild(MAIN_UI_NAME, true)
end

local function find_main_container(uiRoot: Instance?): Instance?
	if not uiRoot then
		return nil
	end

	local directMain = uiRoot:FindFirstChild(MAINFRAME_NAME)
	if directMain then
		return directMain
	end

	return uiRoot:FindFirstChild(MAINFRAME_NAME, true)
end

local function find_frames_container(mainContainer: Instance?): Instance?
	if not mainContainer then
		return nil
	end

	local directFrames = mainContainer:FindFirstChild(FRAMES_CONTAINER_NAME)
	if directFrames then
		return directFrames
	end

	return mainContainer:FindFirstChild(FRAMES_CONTAINER_NAME, true)
end

local function find_zones_folder(): Instance?
	local directZones = Workspace:FindFirstChild(ZONES_FOLDER_NAME)
	if directZones then
		return directZones
	end

	return Workspace:FindFirstChild(ZONES_FOLDER_NAME, true)
end

local function is_zone_related_instance(instance: Instance): boolean
	if instance.Name == ZONES_FOLDER_NAME then
		return true
	end

	local zonesFolder = find_zones_folder()
	return zonesFolder ~= nil and instance:IsDescendantOf(zonesFolder)
end

local function get_display_visible(instance: GuiObject): boolean
	return instance.Visible
end

local function set_display_visible(instance: GuiObject?, isVisible: boolean)
	if not instance or instance.Visible == isVisible then
		return
	end

	instance.Visible = isVisible
end

local function resolve_frame_name(zoneName: string): string?
	local normalizedName = normalize_key(zoneName)
	if not normalizedName then
		return zoneName
	end

	local alias = ZONE_FRAME_ALIASES[normalizedName]
	if alias then
		return alias
	end

	return zoneName
end

local function find_zone_display(framesContainer: Instance?, zoneName: string): GuiObject?
	if not framesContainer then
		return nil
	end

	local frameName = resolve_frame_name(zoneName)
	if not frameName then
		return nil
	end

	local directDisplay = framesContainer:FindFirstChild(frameName)
	if directDisplay and directDisplay:IsA("GuiObject") then
		return directDisplay :: GuiObject
	end

	local nestedDisplay = framesContainer:FindFirstChild(frameName, true)
	if nestedDisplay and nestedDisplay:IsA("GuiObject") then
		return nestedDisplay :: GuiObject
	end

	return nil
end

local function collect_zone_parts(container: Instance): { BasePart }
	local parts = {}

	if container:IsA("BasePart") then
		parts[#parts + 1] = container
		return parts
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			parts[#parts + 1] = descendant
		end
	end

	return parts
end

local function build_zone_states(framesContainer: Instance?, zonesFolder: Instance): { ZoneState }
	local zoneStates = {}

	for _, child in ipairs(zonesFolder:GetChildren()) do
		local parts = collect_zone_parts(child)
		if #parts == 0 then
			continue
		end

		local display = find_zone_display(framesContainer, child.Name)
		if display then
			set_display_visible(display, false)
		end

		zoneStates[#zoneStates + 1] = {
			Name = child.Name,
			Display = display,
			Parts = parts,
			IsInside = false,
		}
	end

	return zoneStates
end

local function hide_all_displays(zoneStates: { ZoneState })
	for _, zoneState in ipairs(zoneStates) do
		if zoneState.Display then
			set_display_visible(zoneState.Display, false)
		end
	end
end

local function show_target_frame(framesContainer: Instance?, target: GuiObject?)
	if not framesContainer or not target then
		return
	end

	for _, child in ipairs(framesContainer:GetChildren()) do
		if child:IsA("GuiObject") and child ~= target then
			child.Visible = false
		end
	end

	target.Visible = true
end

local function destroy_interface_binding()
	if interfaceTrove then
		interfaceTrove:Destroy()
		interfaceTrove = nil
	end

	boundUiRoot = nil
	boundZonesFolder = nil
end

local function bind_interface(uiRoot: Instance, zonesFolder: Instance)
	if interfaceTrove and boundUiRoot == uiRoot and boundZonesFolder == zonesFolder then
		return
	end

	destroy_interface_binding()
	lastBindReason = ""

	local trove = rootTrove:Extend()
	interfaceTrove = trove
	boundUiRoot = uiRoot
	boundZonesFolder = zonesFolder

	local framesContainer = find_frames_container(find_main_container(uiRoot))
	local zoneStates: { ZoneState } = {}
	local accumulator = 0

	local function refresh_zones()
		framesContainer = find_frames_container(find_main_container(uiRoot))
		hide_all_displays(zoneStates)
		zoneStates = build_zone_states(framesContainer, zonesFolder)
	end

	local function update_zones()
		local characterRoot = get_character_root()
		if not characterRoot then
			hide_all_displays(zoneStates)

			for _, zoneState in ipairs(zoneStates) do
				zoneState.IsInside = false
			end

			return
		end

		local enteredDisplay = nil

		for _, zoneState in ipairs(zoneStates) do
			local isInside = false

			for _, part in ipairs(zoneState.Parts) do
				if part.Parent and is_point_inside_zone(characterRoot.Position, part) then
					isInside = true
					break
				end
			end

			local wasInside = zoneState.IsInside
			zoneState.IsInside = isInside

			if isInside and not wasInside and zoneState.Display and not enteredDisplay then
				enteredDisplay = zoneState.Display
			elseif not isInside and wasInside and zoneState.Display then
				set_display_visible(zoneState.Display, false)
			end
		end

		if enteredDisplay then
			show_target_frame(framesContainer, enteredDisplay)
		end
	end

	trove:Add(function()
		hide_all_displays(zoneStates)

		if interfaceTrove == trove then
			interfaceTrove = nil
		end
	end)

	trove:Add(uiRoot.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		destroy_interface_binding()
	end))

	trove:Add(zonesFolder.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		destroy_interface_binding()
	end))

	trove:Add(localPlayer.CharacterAdded:Connect(function()
		task.defer(update_zones)
	end))

	trove:Add(uiRoot.DescendantAdded:Connect(function(instance)
		if instance:IsA("GuiObject") or instance.Name == MAINFRAME_NAME or instance.Name == FRAMES_CONTAINER_NAME then
			refresh_zones()
			update_zones()
		end
	end))

	trove:Add(uiRoot.DescendantRemoving:Connect(function(instance)
		if instance:IsA("GuiObject") or instance.Name == MAINFRAME_NAME or instance.Name == FRAMES_CONTAINER_NAME then
			refresh_zones()
			update_zones()
		end
	end))

	trove:Add(zonesFolder.ChildAdded:Connect(function()
		refresh_zones()
		update_zones()
	end))

	trove:Add(zonesFolder.ChildRemoved:Connect(function()
		refresh_zones()
		update_zones()
	end))

	trove:Add(zonesFolder.DescendantAdded:Connect(function(instance)
		if instance:IsA("BasePart") then
			refresh_zones()
			update_zones()
		end
	end))

	trove:Add(zonesFolder.DescendantRemoving:Connect(function(instance)
		if instance:IsA("BasePart") then
			refresh_zones()
			update_zones()
		end
	end))

	trove:Add(RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime

		if accumulator < UPDATE_INTERVAL then
			return
		end

		accumulator = 0
		update_zones()
	end))

	refresh_zones()
	update_zones()
end

local function try_bind_interface()
	local uiRoot = find_ui_root()
	if not uiRoot then
		log_bind_reason("MainUI ainda nao encontrada no PlayerGui")
		return
	end

	local zonesFolder = find_zones_folder()
	if not zonesFolder then
		log_bind_reason("Pasta Zones ainda nao encontrada no Workspace")
		return
	end

	bind_interface(uiRoot, zonesFolder)
end

for _, _ in ipairs(playerGui:GetDescendants()) do
	try_bind_interface()
	break
end

rootTrove:Add(playerGui.DescendantAdded:Connect(function(instance)
	if instance.Name == MAIN_UI_NAME or instance.Name == MAINFRAME_NAME or instance.Name == FRAMES_CONTAINER_NAME then
		try_bind_interface()
	end
end))

rootTrove:Add(Workspace.DescendantAdded:Connect(function(instance)
	if is_zone_related_instance(instance) then
		try_bind_interface()
	end
end))

rootTrove:Add(Workspace.DescendantRemoving:Connect(function(instance)
	if boundZonesFolder and (instance == boundZonesFolder or instance:IsDescendantOf(boundZonesFolder)) then
		task.defer(try_bind_interface)
	end
end))

try_bind_interface()
