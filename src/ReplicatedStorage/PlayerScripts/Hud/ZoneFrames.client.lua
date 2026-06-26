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
	Display: Instance?,
	Parts: { BasePart },
	IsInside: boolean,
}

local rootTrove = Trove.new()
local interfaceTrove = nil
local boundUiRoot = nil
local boundZonesFolder = nil
local lastBindReason = ""

local function debug_log(message: string)
	print(("[ZoneFrames] %s"):format(message))
end

local function log_bind_reason(reason: string)
	if lastBindReason == reason then
		return
	end

	lastBindReason = reason
	debug_log(reason)
end

debug_log("Script iniciado")

local function is_display_instance(instance: Instance): boolean
	if instance:IsA("LayerCollector") then
		return true
	end

	return instance:IsA("Frame") or instance:IsA("CanvasGroup") or instance:IsA("ScrollingFrame")
end

local function get_display_visible(instance: Instance): boolean?
	if instance:IsA("LayerCollector") then
		return instance.Enabled
	end

	if instance:IsA("GuiObject") then
		return instance.Visible
	end

	return nil
end

local function set_display_visible(instance: Instance, isVisible: boolean)
	local currentValue = get_display_visible(instance)
	if currentValue == nil or currentValue == isVisible then
		return
	end

	if instance:IsA("LayerCollector") then
		instance.Enabled = isVisible
	elseif instance:IsA("GuiObject") then
		instance.Visible = isVisible
	end

	debug_log(("%s -> Open = %s"):format(instance:GetFullName(), tostring(isVisible)))
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
	local directUi = playerGui:FindFirstChild(UI_NAME)
	if directUi then
		return directUi
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant.Name == UI_NAME then
			return descendant
		end
	end

	return nil
end

local function find_main_container(uiRoot: Instance?): Instance?
	if not uiRoot then
		return nil
	end

	local directMain = uiRoot:FindFirstChild(MAIN_NAME)
	if directMain then
		return directMain
	end

	return uiRoot:FindFirstChild(MAIN_NAME, true)
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

local function gather_display_candidates(root: Instance, zoneName: string): { Instance }
	local zoneNameLower = string.lower(zoneName)
	local exactMatches = {}
	local partialMatches = {}

	for _, descendant in ipairs(root:GetDescendants()) do
		if is_display_instance(descendant) then
			local nameLower = string.lower(descendant.Name)

			if nameLower == zoneNameLower or nameLower == zoneNameLower .. "frame" or nameLower == zoneNameLower .. "gui" then
				exactMatches[#exactMatches + 1] = descendant
			elseif string.find(nameLower, zoneNameLower, 1, true) then
				partialMatches[#partialMatches + 1] = descendant
			end
		end
	end

	if #exactMatches > 0 then
		return exactMatches
	end

	return partialMatches
end

local function pick_best_display(candidates: { Instance }): Instance?
	local bestCandidate = nil
	local bestScore = -math.huge

	for _, candidate in ipairs(candidates) do
		local score = 0

		if candidate:IsA("LayerCollector") then
			score += 100
		end

		if candidate:IsA("Frame") or candidate:IsA("CanvasGroup") or candidate:IsA("ScrollingFrame") then
			score += 50
		end

		if candidate.Name == "Main" then
			score -= 1000
		end

		local descendantCount = #candidate:GetDescendants()
		score += math.min(descendantCount, 100)

		if score > bestScore then
			bestScore = score
			bestCandidate = candidate
		end
	end

	return bestCandidate
end

local function find_zone_display(uiRoot: Instance, mainContainer: Instance?, zoneName: string): Instance?
	local preferredScopes = {}

	if mainContainer and mainContainer ~= uiRoot then
		preferredScopes[#preferredScopes + 1] = mainContainer
	end

	preferredScopes[#preferredScopes + 1] = uiRoot

	for _, scope in ipairs(preferredScopes) do
		local candidates = gather_display_candidates(scope, zoneName)
		local bestCandidate = pick_best_display(candidates)

		if bestCandidate then
			return bestCandidate
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

local function build_zone_states(uiRoot: Instance, mainContainer: Instance?, zonesFolder: Instance): { ZoneState }
	local zoneStates = {}

	for _, child in ipairs(zonesFolder:GetChildren()) do
		local parts = collect_zone_parts(child)

		if #parts == 0 then
			debug_log(("Zona ignorada sem BasePart: %s"):format(child:GetFullName()))
			continue
		end

		local zoneName = child.Name
		local display = find_zone_display(uiRoot, mainContainer, zoneName)

		if display then
			debug_log(("Display encontrado para zona '%s': %s"):format(zoneName, display:GetFullName()))
			set_display_visible(display, false)
		else
			debug_log(("Display NAO encontrado para zona '%s' dentro de %s"):format(zoneName, uiRoot:GetFullName()))
		end

		zoneStates[#zoneStates + 1] = {
			Name = zoneName,
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

	local mainContainer = find_main_container(uiRoot)
	local zoneStates: { ZoneState } = {}
	local accumulator = 0

	local function refresh_zones()
		mainContainer = find_main_container(uiRoot)
		hide_all_displays(zoneStates)
		zoneStates = build_zone_states(uiRoot, mainContainer, zonesFolder)
		debug_log(("Zonas carregadas: %d"):format(#zoneStates))
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

				if zoneState.Display then
					set_display_visible(zoneState.Display, isInside)
				end

				if isInside then
					debug_log(("Player ENTROU na zona '%s'"):format(zoneState.Name))
				else
					debug_log(("Player SAIU da zona '%s'"):format(zoneState.Name))
				end
			end
		end
	end

	debug_log(("UI root encontrada: %s [%s]"):format(uiRoot:GetFullName(), uiRoot.ClassName))

	if mainContainer then
		debug_log(("Main encontrada: %s [%s]"):format(mainContainer:GetFullName(), mainContainer.ClassName))
	else
		debug_log("Main nao encontrada; a busca de displays vai usar toda a UI")
	end

	debug_log(("Zones encontrada: %s"):format(zonesFolder:GetFullName()))

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

		debug_log("UI root removida, desfazendo bind atual")
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

	trove:Add(uiRoot.DescendantAdded:Connect(function(instance)
		if is_display_instance(instance) or instance.Name == MAIN_NAME then
			debug_log(("Mudanca relevante na UI: %s"):format(instance:GetFullName()))
			refresh_zones()
			update_zones()
		end
	end))

	trove:Add(uiRoot.DescendantRemoving:Connect(function(instance)
		if is_display_instance(instance) or instance.Name == MAIN_NAME then
			debug_log(("Display removido da UI: %s"):format(instance:GetFullName()))
			refresh_zones()
			update_zones()
		end
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
		log_bind_reason("UI root ainda nao encontrada no PlayerGui")
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
	if instance.Name == UI_NAME or instance.Name == MAIN_NAME or instance:IsA("LayerCollector") then
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
