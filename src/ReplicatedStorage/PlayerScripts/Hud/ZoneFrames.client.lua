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

type ZoneState = {
	Name: string,
	Frame: GuiObject?,
	Parts: { BasePart },
	IsInside: boolean,
}

local rootTrove = Trove.new()
local interfaceTrove = nil

local function debug_log(message: string)
	print(("[ZoneFrames] %s"):format(message))
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

local function is_point_inside_part(point: Vector3, part: BasePart): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5

	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Y) <= halfSize.Y
		and math.abs(localPoint.Z) <= halfSize.Z
end

local function set_frame_visible(frame: GuiObject, isVisible: boolean)
	if frame.Visible == isVisible then
		return
	end

	frame.Visible = isVisible
	debug_log(("%s -> Visible = %s"):format(frame:GetFullName(), tostring(isVisible)))
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

	return nil
end

local function collect_zone_parts(container: Instance): { BasePart }
	local parts = {}

	if container:IsA("BasePart") then
		table.insert(parts, container)
		return parts
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end

	return parts
end

local function build_zone_states(main: Instance, zonesFolder: Instance): { ZoneState }
	local zoneStates = {}

	for _, child in ipairs(zonesFolder:GetChildren()) do
		local parts = collect_zone_parts(child)

		if #parts == 0 then
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

		table.insert(zoneStates, {
			Name = zoneName,
			Frame = frame,
			Parts = parts,
			IsInside = false,
		})
	end

	return zoneStates
end

local function bind_interface(ui: ScreenGui)
	if interfaceTrove then
		interfaceTrove:Destroy()
		interfaceTrove = nil
	end

	local trove = rootTrove:Extend()
	interfaceTrove = trove

	local main = ui:WaitForChild(MAIN_NAME)
	local zonesFolder = Workspace:WaitForChild(ZONES_FOLDER_NAME)

	local zoneStates: { ZoneState } = {}
	local accumulator = 0

	local function refresh_zones()
		for _, zoneState in ipairs(zoneStates) do
			if zoneState.Frame then
				set_frame_visible(zoneState.Frame, false)
			end
		end

		zoneStates = build_zone_states(main, zonesFolder)
		debug_log(("Zonas carregadas: %d"):format(#zoneStates))
	end

	local function update_zones()
		local characterRoot = get_character_root()
		if not characterRoot then
			for _, zoneState in ipairs(zoneStates) do
				if zoneState.IsInside then
					zoneState.IsInside = false

					if zoneState.Frame then
						set_frame_visible(zoneState.Frame, false)
					end
				end
			end

			return
		end

		for _, zoneState in ipairs(zoneStates) do
			local isInside = false

			for _, part in ipairs(zoneState.Parts) do
				if part.Parent and is_point_inside_part(characterRoot.Position, part) then
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

	trove:Add(ui.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		trove:Destroy()
	end))

	trove:Add(function()
		if interfaceTrove == trove then
			interfaceTrove = nil
		end
	end)

	trove:Add(zonesFolder.ChildAdded:Connect(function()
		debug_log("Zona adicionada, recarregando mapeamento")
		refresh_zones()
	end))

	trove:Add(zonesFolder.ChildRemoved:Connect(function()
		debug_log("Zona removida, recarregando mapeamento")
		refresh_zones()
	end))

	trove:Add(zonesFolder.DescendantAdded:Connect(function(instance)
		if instance:IsA("BasePart") then
			debug_log(("Part adicionada em zonas: %s"):format(instance:GetFullName()))
			refresh_zones()
		end
	end))

	trove:Add(zonesFolder.DescendantRemoving:Connect(function(instance)
		if instance:IsA("BasePart") then
			debug_log(("Part removida de zonas: %s"):format(instance:GetFullName()))
			refresh_zones()
		end
	end))

	trove:Add(main.DescendantAdded:Connect(function(instance)
		if instance:IsA("GuiObject") then
			debug_log(("Gui adicionada em Main: %s"):format(instance:GetFullName()))
			refresh_zones()
		end
	end))

	trove:Add(main.DescendantRemoving:Connect(function(instance)
		if instance:IsA("GuiObject") then
			debug_log(("Gui removida de Main: %s"):format(instance:GetFullName()))
			refresh_zones()
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

local function try_bind_ui(instance: Instance)
	if not instance:IsA("ScreenGui") or instance.Name ~= UI_NAME then
		return
	end

	bind_interface(instance)
end

for _, child in ipairs(playerGui:GetChildren()) do
	try_bind_ui(child)
end

rootTrove:Add(playerGui.ChildAdded:Connect(try_bind_ui))
