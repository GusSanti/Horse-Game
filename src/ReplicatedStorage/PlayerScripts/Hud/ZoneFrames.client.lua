local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")

local Trove = require(Libraries:WaitForChild("Trove"))

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local UI_NAME = "UI"
local MAIN_NAME = "Main"
local ZONES_FOLDER_NAME = "Zones"
local UPDATE_INTERVAL = 0.1
local VERTICAL_PADDING = 6

type ZoneState = {
	Name: string,
	Frame: GuiObject?,
	Parts: { BasePart },
	IsInside: boolean,
}

local rootTrove = Trove.new()
local interfaceTrove = nil
local boundUi = nil
local boundMain = nil
local boundZonesFolder = nil

local function debug_log(message: string)
	print(("[ZoneFrames] %s"):format(message))
end

debug_log("Script iniciado")

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

local function set_frame_visible(frame: GuiObject, isVisible: boolean)
	if frame.Visible == isVisible then
		return
	end

	frame.Visible = isVisible
	debug_log(("%s -> Visible = %s"):format(frame:GetFullName(), tostring(isVisible)))
end

local function find_screen_gui(): ScreenGui?
	local directUi = playerGui:FindFirstChild(UI_NAME)
	if directUi and directUi:IsA("ScreenGui") then
		return directUi
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("ScreenGui") and descendant.Name == UI_NAME then
			return descendant
		end
	end

	return nil
end

local function find_main_container(ui: ScreenGui?): GuiObject?
	if not ui then
		return nil
	end

	local directMain = ui:FindFirstChild(MAIN_NAME)
	if directMain and directMain:IsA("GuiObject") then
		return directMain
	end

	local recursiveMain = ui:FindFirstChild(MAIN_NAME, true)
	if recursiveMain and recursiveMain:IsA("GuiObject") then
		return recursiveMain
	end

	return nil
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

local function find_zone_frame(main: Instance, zoneName: string): GuiObject?
	local directMatch = main:FindFirstChild(zoneName)
	if directMatch and directMatch:IsA("GuiObject") then
		return directMatch
	end

	local recursiveMatch = main:FindFirstChild(zoneName, true)
	if recursiveMatch and recursiveMatch:IsA("GuiObject") then
		return recursiveMatch
	end

	local loweredZoneName = string.lower(zoneName)

	for _, descendant in ipairs(main:GetDescendants()) do
		if descendant:IsA("GuiObject") and string.lower(descendant.Name) == loweredZoneName then
			return descendant
		end
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

local function build_zone_states(main: Instance, zonesFolder: Instance): { ZoneState }
	local zoneStates = {}

	for _, child in ipairs(zonesFolder:GetChildren()) do
		local parts = collect_zone_parts(child)

		if #parts == 0 then
			debug_log(("Zona ignorada sem BasePart: %s"):format(child:GetFullName()))
			continue
		end

		local zoneName = child.Name
		local frame = find_zone_frame(main, zoneName)

		if frame then
			debug_log(("Frame encontrado para zona '%s': %s"):format(zoneName, frame:GetFullName()))
			set_frame_visible(frame, false)
		else
			debug_log(("Frame NAO encontrado para zona '%s' dentro de UI.Main"):format(zoneName))
		end

		zoneStates[#zoneStates + 1] = {
			Name = zoneName,
			Frame = frame,
			Parts = parts,
			IsInside = false,
		}
	end

	return zoneStates
end

local function hide_all_frames(zoneStates: { ZoneState })
	for _, zoneState in ipairs(zoneStates) do
		if zoneState.Frame then
			set_frame_visible(zoneState.Frame, false)
		end
	end
end

local function destroy_interface_binding()
	if interfaceTrove then
		interfaceTrove:Destroy()
		interfaceTrove = nil
	end

	boundUi = nil
	boundMain = nil
	boundZonesFolder = nil
end

local function bind_interface(ui: ScreenGui, main: GuiObject, zonesFolder: Instance)
	if interfaceTrove and boundUi == ui and boundMain == main and boundZonesFolder == zonesFolder then
		return
	end

	destroy_interface_binding()

	local trove = rootTrove:Extend()
	interfaceTrove = trove
	boundUi = ui
	boundMain = main
	boundZonesFolder = zonesFolder

	local zoneStates: { ZoneState } = {}
	local accumulator = 0

	local function refresh_zones()
		hide_all_frames(zoneStates)
		zoneStates = build_zone_states(main, zonesFolder)
		debug_log(("Zonas carregadas: %d"):format(#zoneStates))
	end

	local function update_zones()
		local characterRoot = get_character_root()
		if not characterRoot then
			hide_all_frames(zoneStates)

			for _, zoneState in ipairs(zoneStates) do
				zoneState.IsInside = false
			end

			return
		end

		for _, zoneState in ipairs(zoneStates) do
			local isInside = false

			for _, part in ipairs(zoneState.Parts) do
				if part.Parent and is_point_inside_zone(characterRoot.Position, part) then
					isInside = true
					break
				end
			end

			if isInside ~= zoneState.IsInside then
				zoneState.IsInside = isInside

				if zoneState.Frame then
					set_frame_visible(zoneState.Frame, isInside)
				end

				if isInside then
					debug_log(("Player ENTROU na zona '%s'"):format(zoneState.Name))
				else
					debug_log(("Player SAIU da zona '%s'"):format(zoneState.Name))
				end
			end
		end
	end

	debug_log(("UI encontrada: %s"):format(ui:GetFullName()))
	debug_log(("Main encontrada: %s"):format(main:GetFullName()))
	debug_log(("Zones encontrada: %s"):format(zonesFolder:GetFullName()))

	trove:Add(function()
		hide_all_frames(zoneStates)

		if interfaceTrove == trove then
			interfaceTrove = nil
		end
	end)

	trove:Add(ui.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		debug_log("UI removida, desfazendo bind atual")
		destroy_interface_binding()
	end))

	trove:Add(main.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		debug_log("Main removida, desfazendo bind atual")
		destroy_interface_binding()
	end))

	trove:Add(zonesFolder.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		debug_log("Pasta Zones removida, desfazendo bind atual")
		destroy_interface_binding()
	end))

	trove:Add(localPlayer.CharacterAdded:Connect(function()
		debug_log("CharacterAdded detectado, atualizando zonas")
		task.defer(update_zones)
	end))

	trove:Add(zonesFolder.ChildAdded:Connect(function(instance)
		debug_log(("Zona adicionada: %s"):format(instance:GetFullName()))
		refresh_zones()
		update_zones()
	end))

	trove:Add(zonesFolder.ChildRemoved:Connect(function()
		debug_log("Zona removida, recarregando mapeamento")
		refresh_zones()
		update_zones()
	end))

	trove:Add(zonesFolder.DescendantAdded:Connect(function(instance)
		if instance:IsA("BasePart") then
			debug_log(("Part adicionada em zonas: %s"):format(instance:GetFullName()))
			refresh_zones()
			update_zones()
		end
	end))

	trove:Add(zonesFolder.DescendantRemoving:Connect(function(instance)
		if instance:IsA("BasePart") then
			debug_log(("Part removida de zonas: %s"):format(instance:GetFullName()))
			refresh_zones()
			update_zones()
		end
	end))

	trove:Add(main.DescendantAdded:Connect(function(instance)
		if instance:IsA("GuiObject") then
			debug_log(("Gui adicionada em Main: %s"):format(instance:GetFullName()))
			refresh_zones()
			update_zones()
		end
	end))

	trove:Add(main.DescendantRemoving:Connect(function(instance)
		if instance:IsA("GuiObject") then
			debug_log(("Gui removida de Main: %s"):format(instance:GetFullName()))
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
	local ui = find_screen_gui()
	if not ui then
		return
	end

	local main = find_main_container(ui)
	if not main then
		debug_log(("UI encontrada sem Main ainda: %s"):format(ui:GetFullName()))
		return
	end

	local zonesFolder = find_zones_folder()
	if not zonesFolder then
		debug_log("Pasta Zones ainda nao encontrada no Workspace")
		return
	end

	bind_interface(ui, main, zonesFolder)
end

for _, descendant in ipairs(playerGui:GetDescendants()) do
	if descendant:IsA("ScreenGui") then
		try_bind_interface()
		break
	end
end

rootTrove:Add(playerGui.DescendantAdded:Connect(function(instance)
	if instance:IsA("ScreenGui") or instance.Name == MAIN_NAME then
		debug_log(("Mudanca detectada no PlayerGui: %s"):format(instance:GetFullName()))
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
		debug_log("Estrutura de zonas alterada, reavaliando bind")
		task.defer(try_bind_interface)
	end
end))

try_bind_interface()
