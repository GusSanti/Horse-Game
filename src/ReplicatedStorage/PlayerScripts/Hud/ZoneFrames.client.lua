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

local DEFAULT_PROXIMITY_DISTANCE = 6
local UPDATE_INTERVAL = 0.1

type FrameMap = { [string]: GuiObject }
type ZoneMap = { [BasePart]: true }

local rootTrove = Trove.new()
local interfaceTrove = nil

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

local function get_zone_distance(zone: BasePart): number
	for _, attributeName in { "ProximityDistance", "OpenDistance", "Radius" } do
		local attributeValue = zone:GetAttribute(attributeName)

		if typeof(attributeValue) == "number" then
			return math.max(attributeValue, 0)
		end
	end

	return DEFAULT_PROXIMITY_DISTANCE
end

local function is_point_near_zone(point: Vector3, zone: BasePart): boolean
	-- Uses the part bounds plus a small padding so both Parts and MeshParts behave consistently.
	local padding = get_zone_distance(zone)
	local localPoint = zone.CFrame:PointToObjectSpace(point)
	local halfSize = zone.Size * 0.5

	local deltaX = math.max(math.abs(localPoint.X) - halfSize.X, 0)
	local deltaY = math.max(math.abs(localPoint.Y) - halfSize.Y, 0)
	local deltaZ = math.max(math.abs(localPoint.Z) - halfSize.Z, 0)

	return (deltaX * deltaX) + (deltaY * deltaY) + (deltaZ * deltaZ) <= (padding * padding)
end

local function set_frame_visible(frame: GuiObject, isVisible: boolean)
	if frame.Visible == isVisible then
		return
	end

	frame.Visible = isVisible
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

	local managedFramesByName: FrameMap = {}
	local trackedZones: ZoneMap = {}
	local accumulator = 0

	local function update_visibility()
		local characterRoot = get_character_root()
		local activeFrameNames: { [string]: boolean } = {}

		if characterRoot then
			for zone in pairs(trackedZones) do
				local matchingFrame = managedFramesByName[zone.Name]

				if matchingFrame and zone:IsDescendantOf(zonesFolder) and is_point_near_zone(characterRoot.Position, zone) then
					activeFrameNames[zone.Name] = true
				end
			end
		end

		for frameName, frame in pairs(managedFramesByName) do
			set_frame_visible(frame, activeFrameNames[frameName] == true)
		end
	end

	local function refresh_bindings()
		local previousFrames = managedFramesByName
		local nextFrames: FrameMap = {}
		local nextZones: ZoneMap = {}
		local zoneNames: { [string]: boolean } = {}

		for _, descendant in ipairs(zonesFolder:GetDescendants()) do
			if descendant:IsA("BasePart") then
				nextZones[descendant] = true
				zoneNames[descendant.Name] = true
			end
		end

		for _, child in ipairs(main:GetChildren()) do
			if child:IsA("GuiObject") and zoneNames[child.Name] then
				nextFrames[child.Name] = child
			end
		end

		trackedZones = nextZones
		managedFramesByName = nextFrames

		for _, frame in pairs(previousFrames) do
			if managedFramesByName[frame.Name] ~= frame then
				set_frame_visible(frame, false)
			end
		end

		update_visibility()
	end

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

	trove:Add(zonesFolder.DescendantAdded:Connect(function(instance)
		if instance:IsA("BasePart") then
			refresh_bindings()
		end
	end))

	trove:Add(zonesFolder.DescendantRemoving:Connect(function(instance)
		if instance:IsA("BasePart") then
			refresh_bindings()
		end
	end))

	trove:Add(main.ChildAdded:Connect(function(child)
		if child:IsA("GuiObject") then
			refresh_bindings()
		end
	end))

	trove:Add(main.ChildRemoved:Connect(function(child)
		if child:IsA("GuiObject") then
			refresh_bindings()
		end
	end))

	trove:Add(RunService.Heartbeat:Connect(function(deltaTime)
		accumulator += deltaTime

		if accumulator < UPDATE_INTERVAL then
			return
		end

		accumulator = 0
		update_visibility()
	end))

	refresh_bindings()
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
