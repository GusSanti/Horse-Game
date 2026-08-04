local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Framework = require(Modules:WaitForChild("Framework"))
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local Network = require(Modules:WaitForChild("Network"))
local Trove = require(Libraries:WaitForChild("Trove"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))

local ZONES_FOLDER_NAME = "Zones"
local NPCS_FOLDER_NAME = "Npcs"
local UNLOCKED_AREAS_PATH = "Teleports.UnlockedAreas"
local ZONE_SCAN_INTERVAL = 0.2
local ZONE_VERTICAL_PADDING = 6
local TELEPORT_DISTANCE = 10
local TELEPORT_GROUND_PROBE_HEIGHT = 24
local TELEPORT_GROUND_PROBE_DISTANCE = 64
local MAX_GROUND_RISE_ABOVE_NPC = 1.5

local ZoneTeleportService = {
	Trove = nil,
	PlayerTroves = {},
	PlayerZoneStates = {},
	PendingAreaNotifications = {},
	ZonesFolder = nil,
	ZonesById = {},
	ZoneList = {},
	ScanElapsed = 0,
}

local function normalize_string(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	return trimmedValue ~= "" and trimmedValue or nil
end

local function find_zones_folder()
	return Workspace:FindFirstChild(ZONES_FOLDER_NAME) or Workspace:FindFirstChild(ZONES_FOLDER_NAME, true)
end

local function find_npcs_folder()
	return Workspace:FindFirstChild(NPCS_FOLDER_NAME) or Workspace:FindFirstChild(NPCS_FOLDER_NAME, true)
end

local function collect_zone_parts(container)
	if container:IsA("BasePart") then
		return { container }
	end

	local parts = {}
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

local function is_point_inside_zone(point, part)
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local halfSize = part.Size * 0.5
	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Z) <= halfSize.Z
		and math.abs(localPoint.Y) <= halfSize.Y + ZONE_VERTICAL_PADDING
end

local function find_named_descendant(root, name)
	if not root then
		return nil
	end

	local normalizedName = string.lower(name)
	if string.lower(root.Name) == normalizedName then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if string.lower(descendant.Name) == normalizedName then
			return descendant
		end
	end

	return nil
end

local function get_npc_root(npc)
	if not npc then
		return nil
	end
	if npc:IsA("BasePart") then
		return npc
	end

	local humanoidRoot = npc:FindFirstChild("HumanoidRootPart", true)
	if humanoidRoot and humanoidRoot:IsA("BasePart") then
		return humanoidRoot
	end
	if npc:IsA("Model") and npc.PrimaryPart then
		return npc.PrimaryPart
	end
	return npc:FindFirstChildWhichIsA("BasePart", true)
end

local function get_zone_display_name(zone)
	return normalize_string(zone.Container:GetAttribute("DisplayName")) or zone.Id
end

local function get_zone_npc_name(zone)
	return normalize_string(zone.Container:GetAttribute("TeleportNpc")) or zone.Id
end

local function get_character_root(player)
	local character = player.Character
	if not character or not character.Parent then
		return nil, nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return character, nil
	end

	return character, root
end

local function is_character_mounted(rootPart)
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant.Name == "HorseMountRiderWeld" and descendant:IsA("Weld") then
			if descendant.Part0 == rootPart or descendant.Part1 == rootPart then
				return true
			end
		end
	end

	return false
end

local function get_character_root_height(character, rootPart)
	local lowestY = math.huge
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local cframe = descendant.CFrame
			local halfHeight = descendant.Size.Y * 0.5
			local verticalExtent = math.abs(cframe.UpVector.Y) * halfHeight
			lowestY = math.min(lowestY, cframe.Position.Y - verticalExtent)
		end
	end

	if lowestY == math.huge then
		return 3
	end

	return math.max(rootPart.Position.Y - lowestY, 2)
end

local function resolve_destination_ground(horizontalPosition, expectedGroundY, ignoredInstances)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.IgnoreWater = false

	local ignored = table.clone(ignoredInstances)
	local origin = Vector3.new(horizontalPosition.X, expectedGroundY + TELEPORT_GROUND_PROBE_HEIGHT, horizontalPosition.Z)
	local direction = Vector3.new(0, -(TELEPORT_GROUND_PROBE_HEIGHT + TELEPORT_GROUND_PROBE_DISTANCE), 0)
	local maxGroundY = expectedGroundY + MAX_GROUND_RISE_ABOVE_NPC

	for _ = 1, 12 do
		raycastParams.FilterDescendantsInstances = ignored
		local result = Workspace:Raycast(origin, direction, raycastParams)
		if not result then
			return nil
		end
		if result.Position.Y <= maxGroundY then
			return result.Position.Y
		end
		if result.Instance == Workspace.Terrain then
			return nil
		end

		table.insert(ignored, result.Instance)
	end

	return nil
end

local function get_teleport_target(character, rootPart, npcRoot)
	local npcCFrame = npcRoot.CFrame
	local forward = Vector3.new(npcCFrame.LookVector.X, 0, npcCFrame.LookVector.Z)
	if forward.Magnitude < 0.001 then
		forward = Vector3.new(0, 0, 1)
	else
		forward = forward.Unit
	end

	local horizontalPosition = npcRoot.Position + (forward * TELEPORT_DISTANCE)
	local rootHeight = get_character_root_height(character, rootPart)
	local expectedGroundY = npcRoot.Position.Y - rootHeight
	local groundY = resolve_destination_ground(horizontalPosition, expectedGroundY, { character, npcRoot.Parent })
	local targetY = if groundY then groundY + rootHeight else npcRoot.Position.Y
	local targetPosition = Vector3.new(horizontalPosition.X, targetY, horizontalPosition.Z)

	-- The player appears in the NPC's line of sight and faces the NPC.
	return CFrame.lookAt(targetPosition, targetPosition - forward)
end

function ZoneTeleportService:_RefreshZones()
	local zonesFolder = find_zones_folder()
	self.ZonesFolder = zonesFolder
	table.clear(self.ZonesById)
	table.clear(self.ZoneList)

	if not zonesFolder then
		return
	end

	for _, child in ipairs(zonesFolder:GetChildren()) do
		local zoneId = normalize_string(child.Name)
		local parts = collect_zone_parts(child)
		if zoneId and #parts > 0 then
			local zone = {
				Id = zoneId,
				Container = child,
				Parts = parts,
			}
			self.ZonesById[zoneId] = zone
			table.insert(self.ZoneList, zone)
		end
	end
end

function ZoneTeleportService:_UnlockArea(player, zone)
	local unlockedAreas = DataUtility.server.get(player, UNLOCKED_AREAS_PATH)
	if type(unlockedAreas) ~= "table" then
		unlockedAreas = {}
	end
	if unlockedAreas[zone.Id] == true then
		return false
	end

	unlockedAreas[zone.Id] = true
	DataUtility.server.set(player, UNLOCKED_AREAS_PATH, unlockedAreas)
	return true
end

function ZoneTeleportService:_UpdatePlayerZones(player)
	local character, rootPart = get_character_root(player)
	if not character or not rootPart then
		self.PlayerZoneStates[player] = {}
		return
	end

	local previousStates = self.PlayerZoneStates[player] or {}
	local pendingNotifications = self.PendingAreaNotifications[player] or {}
	local nextStates = {}
	for _, zone in ipairs(self.ZoneList) do
		local isInside = false
		for _, part in ipairs(zone.Parts) do
			if part.Parent and is_point_inside_zone(rootPart.Position, part) then
				isInside = true
				break
			end
		end

		nextStates[zone.Id] = isInside
		if isInside and previousStates[zone.Id] ~= true then
			if self:_UnlockArea(player, zone) then
				pendingNotifications[zone.Id] = {
					AreaId = zone.Id,
					AreaName = get_zone_display_name(zone),
				}
			end
		elseif not isInside and previousStates[zone.Id] == true then
			local pendingNotification = pendingNotifications[zone.Id]
			if pendingNotification then
				pendingNotifications[zone.Id] = nil
				Network.Events.AreaUnlocked:Fire(player, pendingNotification)
			end
		end
	end

	self.PlayerZoneStates[player] = nextStates
	self.PendingAreaNotifications[player] = pendingNotifications
end

function ZoneTeleportService:_TeleportPlayer(player, areaId)
	areaId = normalize_string(areaId)
	if not areaId then
		return { Success = false, Code = "AreaRequired" }
	end

	local unlockedAreas = DataUtility.server.get(player, UNLOCKED_AREAS_PATH)
	if type(unlockedAreas) ~= "table" or unlockedAreas[areaId] ~= true then
		return { Success = false, Code = "AreaLocked" }
	end

	local zone = self.ZonesById[areaId]
	if not zone or not zone.Container.Parent then
		self:_RefreshZones()
		zone = self.ZonesById[areaId]
	end
	if not zone then
		return { Success = false, Code = "AreaUnavailable" }
	end

	local character, rootPart = get_character_root(player)
	if not character or not rootPart then
		return { Success = false, Code = "CharacterUnavailable" }
	end
	if is_character_mounted(rootPart) then
		return { Success = false, Code = "Mounted" }
	end

	local npc = find_named_descendant(find_npcs_folder(), get_zone_npc_name(zone))
	local npcRoot = get_npc_root(npc)
	if not npcRoot then
		return { Success = false, Code = "NpcUnavailable" }
	end

	character:PivotTo(get_teleport_target(character, rootPart, npcRoot))
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero

	return {
		Success = true,
		Code = "Teleported",
		AreaId = zone.Id,
		AreaName = get_zone_display_name(zone),
	}
end

function ZoneTeleportService:_TrackPlayer(player)
	if self.PlayerTroves[player] then
		return
	end

	local playerTrove = Trove.new()
	self.PlayerTroves[player] = playerTrove
	self.PlayerZoneStates[player] = {}
	self.PendingAreaNotifications[player] = {}
	playerTrove:Connect(player.CharacterAdded, function()
		self.PlayerZoneStates[player] = {}
		self.PendingAreaNotifications[player] = {}
	end)
end

function ZoneTeleportService:_UntrackPlayer(player)
	local playerTrove = self.PlayerTroves[player]
	if playerTrove then
		playerTrove:Destroy()
		self.PlayerTroves[player] = nil
	end
	self.PlayerZoneStates[player] = nil
	self.PendingAreaNotifications[player] = nil
end

function ZoneTeleportService.Init()
	if ZoneTeleportService.Trove then
		return
	end

	ZoneTeleportService.Trove = Trove.new()
	ZoneTeleportService:_RefreshZones()
	Network.Functions.TeleportToArea:Respond(function(player, areaId)
		return ZoneTeleportService:_TeleportPlayer(player, areaId)
	end, ZoneTeleportService.Trove)

	ZoneTeleportService.Trove:Connect(Framework.RuntimeEvents.PlayerAdded, function(player)
		ZoneTeleportService:_TrackPlayer(player)
	end)
	ZoneTeleportService.Trove:Connect(Framework.RuntimeEvents.PlayerRemoving, function(player)
		ZoneTeleportService:_UntrackPlayer(player)
	end)
	ZoneTeleportService.Trove:Connect(Workspace.DescendantAdded, function(instance)
		if instance.Name == ZONES_FOLDER_NAME
			or (ZoneTeleportService.ZonesFolder and instance:IsDescendantOf(ZoneTeleportService.ZonesFolder))
		then
			ZoneTeleportService:_RefreshZones()
		end
	end)
	ZoneTeleportService.Trove:Connect(Workspace.DescendantRemoving, function(instance)
		if instance == ZoneTeleportService.ZonesFolder
			or (ZoneTeleportService.ZonesFolder and instance:IsDescendantOf(ZoneTeleportService.ZonesFolder))
		then
			task.defer(function()
				if ZoneTeleportService.Trove then
					ZoneTeleportService:_RefreshZones()
				end
			end)
		end
	end)
	ZoneTeleportService.Trove:Connect(RunService.Heartbeat, function(deltaTime)
		ZoneTeleportService.ScanElapsed += deltaTime
		if ZoneTeleportService.ScanElapsed < ZONE_SCAN_INTERVAL then
			return
		end
		ZoneTeleportService.ScanElapsed %= ZONE_SCAN_INTERVAL

		for player in pairs(ZoneTeleportService.PlayerTroves) do
			if player.Parent == Players then
				ZoneTeleportService:_UpdatePlayerZones(player)
			end
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		ZoneTeleportService:_TrackPlayer(player)
	end
end

function ZoneTeleportService.Destroy()
	for player in pairs(table.clone(ZoneTeleportService.PlayerTroves)) do
		ZoneTeleportService:_UntrackPlayer(player)
	end
	if ZoneTeleportService.Trove then
		ZoneTeleportService.Trove:Destroy()
		ZoneTeleportService.Trove = nil
	end
	table.clear(ZoneTeleportService.ZonesById)
	table.clear(ZoneTeleportService.ZoneList)
	ZoneTeleportService.ZonesFolder = nil
	ZoneTeleportService.ScanElapsed = 0
end

return ZoneTeleportService
