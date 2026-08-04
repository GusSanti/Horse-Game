local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")
local GameModules = Modules:WaitForChild("Game")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local Network = require(Modules:WaitForChild("Network"))
local QuestService = require(script.Parent.Parent:WaitForChild("Quest"):WaitForChild("QuestService"))
local StableCleaningConfig = require(GameData:WaitForChild("Horse"):WaitForChild("StableCleaningConfig"))
local StableDictionary = require(Dictionary:WaitForChild("StableDictionary"))
local ToolRegistry = require(GameModules:WaitForChild("Tools"):WaitForChild("Registry"))
local HorseCareService = require(script.Parent:WaitForChild("HorseCareService"))

local StableCleaningService = {}

local random = Random.new()
local initialized = false
local activeRequestByPlayer = {}
local lastPlotByPlayer = {}

local GENERATED_VISUAL_ATTRIBUTE = "GeneratedStableDirtVisual"
local HORSE_ID_ATTRIBUTE = "HorseId"
local HORSE_POSITION_NAME = "HorsePosition"
local DIRT_GROUND_RAY_DISTANCE = 100
local DIRT_GROUND_MIN_HORIZONTAL_AREA = 16
local DIRT_GROUND_MAX_RAYCAST_HITS = 32

local function get_spawn_settings()
	if RunService:IsStudio() then
		return {
			InitialDelay = StableCleaningConfig.StudioInitialSpawnDelaySeconds,
			Interval = StableCleaningConfig.StudioSpawnIntervalSeconds,
			Jitter = StableCleaningConfig.StudioSpawnJitterSeconds,
			Tick = StableCleaningConfig.StudioServiceTickSeconds,
		}
	end

	return {
		InitialDelay = StableCleaningConfig.InitialSpawnDelaySeconds,
		Interval = StableCleaningConfig.SpawnIntervalSeconds,
		Jitter = StableCleaningConfig.SpawnJitterSeconds,
		Tick = StableCleaningConfig.ServiceTickSeconds,
	}
end

local function get_next_spawn_at(now: number, settings): number
	local jitter = random:NextNumber(-settings.Jitter, settings.Jitter)
	return now + math.max(5, settings.Interval + jitter)
end

local function normalize_stable_care(horse, now: number, settings): boolean
	local changed = false

	if type(horse.StableCare) ~= "table" then
		horse.StableCare = {}
		changed = true
	end

	local stableCare = horse.StableCare
	if type(stableCare.Dirt) ~= "table" then
		stableCare.Dirt = {}
		changed = true
	end

	if type(stableCare.NextDirtId) ~= "number" or stableCare.NextDirtId < 1 then
		stableCare.NextDirtId = 1
		changed = true
	end

	if type(stableCare.NextDirtAt) ~= "number" or stableCare.NextDirtAt <= 0 then
		stableCare.NextDirtAt = now + settings.InitialDelay
		changed = true
	elseif RunService:IsStudio() and stableCare.NextDirtAt > now + settings.Interval then
		stableCare.NextDirtAt = now + settings.InitialDelay
		changed = true
	end

	if type(stableCare.LastStableCleanedAt) ~= "number" then
		stableCare.LastStableCleanedAt = 0
		changed = true
	end

	local normalizedDirt = {}
	for _, dirtRecord in ipairs(stableCare.Dirt) do
		if type(dirtRecord) == "table"
			and type(dirtRecord.Id) == "string"
			and dirtRecord.Id ~= ""
			and StableCleaningConfig.GetDirtDefinition(dirtRecord.TypeId)
		then
			dirtRecord.OffsetX = tonumber(dirtRecord.OffsetX) or 0
			dirtRecord.OffsetZ = tonumber(dirtRecord.OffsetZ) or 0
			dirtRecord.Rotation = tonumber(dirtRecord.Rotation) or 0
			dirtRecord.SpawnedAt = tonumber(dirtRecord.SpawnedAt) or now
			normalizedDirt[#normalizedDirt + 1] = dirtRecord
		else
			changed = true
		end
	end

	while #normalizedDirt > StableCleaningConfig.MaxDirtPerHorse do
		table.remove(normalizedDirt)
		changed = true
	end

	if #normalizedDirt ~= #stableCare.Dirt then
		stableCare.Dirt = normalizedDirt
	end

	return changed
end

local function choose_dirt_type(): string
	local totalWeight = 0

	for _, dirtTypeId in ipairs(StableCleaningConfig.DirtOrder) do
		local definition = StableCleaningConfig.GetDirtDefinition(dirtTypeId)
		totalWeight += math.max(0, definition and definition.Weight or 0)
	end

	local roll = random:NextNumber(0, math.max(totalWeight, 1))
	local cursor = 0

	for _, dirtTypeId in ipairs(StableCleaningConfig.DirtOrder) do
		local definition = StableCleaningConfig.GetDirtDefinition(dirtTypeId)
		cursor += math.max(0, definition and definition.Weight or 0)
		if roll <= cursor then
			return dirtTypeId
		end
	end

	return StableCleaningConfig.DirtOrder[1]
end

local function choose_dirt_offset(existingDirt): (number, number)
	local selectedX = 0
	local selectedZ = 0

	for _ = 1, 10 do
		local angle = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(2.2, 3.8)
		local offsetX = math.cos(angle) * radius
		local offsetZ = math.sin(angle) * radius
		local isClear = true

		for _, dirtRecord in ipairs(existingDirt) do
			local deltaX = offsetX - (tonumber(dirtRecord.OffsetX) or 0)
			local deltaZ = offsetZ - (tonumber(dirtRecord.OffsetZ) or 0)
			if (deltaX * deltaX) + (deltaZ * deltaZ) < 1.7 * 1.7 then
				isClear = false
				break
			end
		end

		selectedX = offsetX
		selectedZ = offsetZ
		if isClear then
			break
		end
	end

	return selectedX, selectedZ
end

local function add_dirt_record(horse, now: number)
	local stableCare = horse.StableCare
	local offsetX, offsetZ = choose_dirt_offset(stableCare.Dirt)
	local dirtId = ("dirt_%d"):format(stableCare.NextDirtId)

	stableCare.NextDirtId += 1
	stableCare.Dirt[#stableCare.Dirt + 1] = {
		Id = dirtId,
		TypeId = choose_dirt_type(),
		OffsetX = math.floor((offsetX * 100) + 0.5) / 100,
		OffsetZ = math.floor((offsetZ * 100) + 0.5) / 100,
		Rotation = random:NextInteger(0, 359),
		SpawnedAt = now,
	}
end

local function get_assigned_horse_ids(stable): {[string]: boolean}
	local assignedHorseIds = {}
	local horseSlots = type(stable) == "table" and stable.HorseSlots or {}

	for _, slotName in ipairs(StableDictionary.HorseSlotOrder) do
		local horseId = horseSlots[slotName]
		if type(horseId) == "string" and horseId ~= "" then
			assignedHorseIds[horseId] = true
		end
	end

	return assignedHorseIds
end

local function process_spawns(player: Player, now: number): boolean
	local horses = DataUtility.server.get(player, "Horses")
	local stable = DataUtility.server.get(player, "Stable")
	if type(horses) ~= "table" or type(horses.Owned) ~= "table" or type(stable) ~= "table" then
		return false
	end

	local settings = get_spawn_settings()
	local assignedHorseIds = get_assigned_horse_ids(stable)
	local changed = false

	for horseId, horse in pairs(horses.Owned) do
		changed = normalize_stable_care(horse, now, settings) or changed

		local stableCare = horse.StableCare
		if assignedHorseIds[horseId]
			and #stableCare.Dirt < StableCleaningConfig.MaxDirtPerHorse
			and now >= stableCare.NextDirtAt
		then
			-- Commit the previous interval while the old dirt set is still active.
			HorseCareService.RefreshHorse(horse, now)
			add_dirt_record(horse, now)
			stableCare.NextDirtAt = get_next_spawn_at(now, settings)
			changed = true
		elseif now >= stableCare.NextDirtAt then
			stableCare.NextDirtAt = get_next_spawn_at(now, settings)
			changed = true
		end
	end

	if changed then
		DataUtility.server.set(player, "Horses", horses)
	end

	return changed
end

local function get_dirt_template(templateName: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local stableCleaningAssets = assets and assets:FindFirstChild("StableCleaning")
	local dirtAssets = stableCleaningAssets and stableCleaningAssets:FindFirstChild("Dirt")
	return dirtAssets and dirtAssets:FindFirstChild(templateName) or nil
end

local function make_fallback_dirt(definition): Model
	local model = Instance.new("Model")
	model.Name = definition.TemplateName

	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanTouch = false
	root.CanQuery = false
	root.Parent = model
	model.PrimaryPart = root

	local visual = Instance.new("Part")
	visual.Name = "FallbackVisual"
	visual.Size = Vector3.new(1.8, 0.18, 1.45)
	visual.Position = Vector3.new(0, 0.12, 0)
	visual.Anchored = true
	visual.CanCollide = false
	visual.CanTouch = false
	visual.CanQuery = false
	visual.Material = Enum.Material.SmoothPlastic
	visual.Shape = Enum.PartType.Ball
	visual.Color = if definition.Id == "loose_hay"
		then Color3.fromRGB(205, 165, 72)
		else Color3.fromRGB(91, 61, 41)
	visual.Parent = model

	return model
end

local function get_visual_adornee(visual: Instance): BasePart?
	if visual:IsA("BasePart") then
		return visual
	end

	if visual:IsA("Model") and visual.PrimaryPart then
		return visual.PrimaryPart
	end

	return visual:FindFirstChildWhichIsA("BasePart", true)
end

local function add_dirt_billboard(visual: Instance, definition)
	local adornee = get_visual_adornee(visual)
	if not adornee then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DirtInfoBillboard"
	billboard:SetAttribute("CompactDirtBillboard", true)
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = StableCleaningConfig.DirtBillboardMaxDistance
	billboard.Size = UDim2.fromOffset(230, 54)
	billboard.StudsOffsetWorldSpace = StableCleaningConfig.DirtBillboardStudsOffset
	billboard.Parent = visual

	local label = Instance.new("TextLabel")
	label.Name = "Info"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.RichText = true
	label.Text = (
		'<font color="#FFD773">%s</font>\n'
		.. '<font color="#FF8A7A">%s</font>\n'
		.. '<font color="#84FFA9">%s @ Noob</font>'
	):format(
		definition.DisplayName,
		StableCleaningConfig.GetCompactPenaltySummary(definition.Id),
		StableCleaningConfig.GetRequiredToolDisplayName(definition.Id)
	)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 12
	label.TextStrokeColor3 = Color3.fromRGB(20, 13, 10)
	label.TextStrokeTransparency = 0.35
	label.TextWrapped = true
	label.Parent = billboard
end

local function sync_dirt_billboard(visual: Instance, definition, shouldShow: boolean)
	local billboard = visual:FindFirstChild("DirtInfoBillboard")
	if not shouldShow and billboard then
		billboard:Destroy()
	elseif shouldShow and (
		not billboard
		or billboard:GetAttribute("CompactDirtBillboard") ~= true
	) then
		if billboard then
			billboard:Destroy()
		end
		add_dirt_billboard(visual, definition)
	end
end

local function create_dirt_visual(horseId: string, dirtRecord): Instance
	local definition = StableCleaningConfig.GetDirtDefinition(dirtRecord.TypeId)
	local template = definition and get_dirt_template(definition.TemplateName)
	local visual = if template then template:Clone() else make_fallback_dirt(definition)

	visual.Name = dirtRecord.Id
	visual:SetAttribute(GENERATED_VISUAL_ATTRIBUTE, true)
	visual:SetAttribute(StableCleaningConfig.DirtAttribute, true)
	visual:SetAttribute(StableCleaningConfig.DirtIdAttribute, dirtRecord.Id)
	visual:SetAttribute(StableCleaningConfig.DirtTypeAttribute, dirtRecord.TypeId)
	visual:SetAttribute(StableCleaningConfig.RequiredToolAttribute, definition.RequiredToolId)
	visual:SetAttribute(HORSE_ID_ATTRIBUTE, horseId)
	visual:SetAttribute("StableDirtPenaltyText", StableCleaningConfig.GetPenaltySummary(definition.Id))
	visual:SetAttribute("StableDirtToolDisplayName", StableCleaningConfig.GetRequiredToolDisplayName(definition.Id))

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end

	return visual
end

local function ensure_dirt_folder(slotFolder: Instance): Folder
	local dirtFolder = slotFolder:FindFirstChild(StableCleaningConfig.DirtFolderName)
	if dirtFolder and dirtFolder:IsA("Folder") then
		return dirtFolder
	end

	if dirtFolder then
		dirtFolder:Destroy()
	end

	dirtFolder = Instance.new("Folder")
	dirtFolder.Name = StableCleaningConfig.DirtFolderName
	dirtFolder:SetAttribute("IgnoreToolPromptRefresh", true)
	dirtFolder.Parent = slotFolder
	return dirtFolder
end

local function is_dirt_ground_surface(raycastResult: RaycastResult): boolean
	if raycastResult.Normal.Y < 0.75 then
		return false
	end

	local hitInstance = raycastResult.Instance
	if hitInstance:IsA("Terrain") then
		return true
	end

	if not hitInstance:IsA("BasePart") then
		return false
	end

	return (hitInstance.Size.X * hitInstance.Size.Z) >= DIRT_GROUND_MIN_HORIZONTAL_AREA
end

local function get_dirt_ground_surface(
	horsePosition: BasePart,
	visual: Instance,
	horizontalPosition: Vector3
): (Vector3, Vector3)
	local slotFolder = horsePosition.Parent
	local ignoredInstances: {Instance} = if slotFolder then { slotFolder } else { horsePosition, visual }

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignoredInstances
	raycastParams.RespectCanCollide = true

	local rayHeight = math.max(horsePosition.Size.Y * 0.5, 2) + 0.05
	local rayOrigin = horizontalPosition + Vector3.new(0, rayHeight, 0)
	local rayDirection = Vector3.new(0, -DIRT_GROUND_RAY_DISTANCE, 0)

	for _ = 1, DIRT_GROUND_MAX_RAYCAST_HITS do
		local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if not rayResult then
			break
		end

		if is_dirt_ground_surface(rayResult) then
			return rayResult.Position, rayResult.Normal.Unit
		end

		-- Ignore small props and continue until the actual stable floor is found.
		ignoredInstances[#ignoredInstances + 1] = rayResult.Instance
		raycastParams.FilterDescendantsInstances = ignoredInstances
	end

	local fallbackPosition = horizontalPosition
		- (horsePosition.CFrame.UpVector * (horsePosition.Size.Y * 0.5))
	return fallbackPosition, horsePosition.CFrame.UpVector
end

local function get_part_lowest_surface_distance(
	part: BasePart,
	surfacePosition: Vector3,
	surfaceNormal: Vector3
): number
	local halfSize = part.Size * 0.5
	local lowestDistance = math.huge

	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local cornerPosition = part.CFrame:PointToWorldSpace(Vector3.new(
					halfSize.X * xSign,
					halfSize.Y * ySign,
					halfSize.Z * zSign
				))
				local distance = (cornerPosition - surfacePosition):Dot(surfaceNormal)
				lowestDistance = math.min(lowestDistance, distance)
			end
		end
	end

	return lowestDistance
end

local function get_visual_lowest_surface_distance(
	visual: Instance,
	surfacePosition: Vector3,
	surfaceNormal: Vector3
): number?
	local lowestDistance = math.huge
	local foundVisiblePart = false

	local function include_part(part: BasePart)
		if part.Transparency >= 1 then
			return
		end

		foundVisiblePart = true
		lowestDistance = math.min(
			lowestDistance,
			get_part_lowest_surface_distance(part, surfacePosition, surfaceNormal)
		)
	end

	if visual:IsA("BasePart") then
		include_part(visual)
	end

	for _, descendant in ipairs(visual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			include_part(descendant)
		end
	end

	return if foundVisiblePart then lowestDistance else nil
end

local function position_dirt_visual(visual: Instance, horsePosition: BasePart, dirtRecord)
	if not visual:IsA("Model") and not visual:IsA("BasePart") then
		return
	end

	local localOffset = Vector3.new(dirtRecord.OffsetX, 0, dirtRecord.OffsetZ)
	local horizontalPosition = horsePosition.CFrame:PointToWorldSpace(localOffset)
	local surfacePosition, surfaceNormal = get_dirt_ground_surface(horsePosition, visual, horizontalPosition)

	local surfaceForward = horsePosition.CFrame.LookVector
		- (surfaceNormal * horsePosition.CFrame.LookVector:Dot(surfaceNormal))
	if surfaceForward.Magnitude < 0.001 then
		surfaceForward = horsePosition.CFrame.RightVector
			- (surfaceNormal * horsePosition.CFrame.RightVector:Dot(surfaceNormal))
	end
	surfaceForward = surfaceForward.Unit

	local targetCFrame = CFrame.lookAt(
		surfacePosition,
		surfacePosition + surfaceForward,
		surfaceNormal
	) * CFrame.Angles(0, math.rad(dirtRecord.Rotation), 0)
	visual:PivotTo(targetCFrame)

	-- Templates do not necessarily share the same pivot height. Move the visible
	-- geometry, rather than the invisible root, so its lowest point touches ground.
	local lowestDistance = get_visual_lowest_surface_distance(visual, surfacePosition, surfaceNormal)
	if lowestDistance then
		visual:PivotTo(visual:GetPivot() - (surfaceNormal * lowestDistance))
	end
end

local function sync_slot_visuals(slotFolder: Instance, horse)
	local dirtFolder = ensure_dirt_folder(slotFolder)
	local horsePosition = slotFolder:FindFirstChild(HORSE_POSITION_NAME)

	if not horse or not horsePosition or not horsePosition:IsA("BasePart") then
		dirtFolder:ClearAllChildren()
		return
	end

	local expectedById = {}
	local billboardDirtIdByType = {}
	for _, dirtRecord in ipairs(horse.StableCare and horse.StableCare.Dirt or {}) do
		expectedById[dirtRecord.Id] = dirtRecord
		if not billboardDirtIdByType[dirtRecord.TypeId] then
			billboardDirtIdByType[dirtRecord.TypeId] = dirtRecord.Id
		end
	end

	for _, child in ipairs(dirtFolder:GetChildren()) do
		if not expectedById[child.Name] then
			child:Destroy()
		end
	end

	for dirtId, dirtRecord in pairs(expectedById) do
		local visual = dirtFolder:FindFirstChild(dirtId)
		if not visual
			or visual:GetAttribute(StableCleaningConfig.DirtTypeAttribute) ~= dirtRecord.TypeId
		then
			if visual then
				visual:Destroy()
			end
			visual = create_dirt_visual(horse.Id, dirtRecord)
			visual.Parent = dirtFolder
		end

		local definition = StableCleaningConfig.GetDirtDefinition(dirtRecord.TypeId)
		sync_dirt_billboard(
			visual,
			definition,
			billboardDirtIdByType[dirtRecord.TypeId] == dirtId
		)
		position_dirt_visual(visual, horsePosition, dirtRecord)
	end
end

function StableCleaningService.SyncPlayerVisuals(player: Player)
	local plotValue = player:FindFirstChild("Plot")
	local plot = plotValue and plotValue:IsA("ObjectValue") and plotValue.Value or nil
	if not plot then
		return
	end

	lastPlotByPlayer[player] = plot

	local horseFolder = plot:FindFirstChild("HorseFolder")
	local horses = DataUtility.server.get(player, "Horses")
	local stable = DataUtility.server.get(player, "Stable")
	if not horseFolder or type(horses) ~= "table" or type(stable) ~= "table" then
		return
	end

	local ownedHorses = horses.Owned or {}
	local horseSlots = stable.HorseSlots or {}

	for _, slotName in ipairs(StableDictionary.HorseSlotOrder) do
		local slotFolder = horseFolder:FindFirstChild(slotName)
		if slotFolder then
			local horseId = horseSlots[slotName]
			sync_slot_visuals(slotFolder, ownedHorses[horseId])
		end
	end
end

local function clear_plot_visuals(plot: Instance?)
	local horseFolder = plot and plot:FindFirstChild("HorseFolder")
	if not horseFolder then
		return
	end

	for _, slotFolder in ipairs(horseFolder:GetChildren()) do
		local dirtFolder = slotFolder:FindFirstChild(StableCleaningConfig.DirtFolderName)
		if dirtFolder then
			dirtFolder:Destroy()
		end
	end
end

local function find_dirt_visual(plot: Instance, horseId: string, dirtId: string): Instance?
	for _, descendant in ipairs(plot:GetDescendants()) do
		if descendant:GetAttribute(StableCleaningConfig.DirtAttribute) == true
			and descendant:GetAttribute(HORSE_ID_ATTRIBUTE) == horseId
			and descendant:GetAttribute(StableCleaningConfig.DirtIdAttribute) == dirtId
		then
			return descendant
		end
	end

	return nil
end

local function is_player_close_enough(player: Player, dirtVisual: Instance): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return false
	end

	local dirtPosition
	if dirtVisual:IsA("Model") or dirtVisual:IsA("BasePart") then
		dirtPosition = dirtVisual:GetPivot().Position
	else
		return false
	end

	return (rootPart.Position - dirtPosition).Magnitude <= StableCleaningConfig.MaxCleanDistance + 2
end

local function find_dirt_record(dirtRecords, dirtId: string)
	for index, dirtRecord in ipairs(dirtRecords) do
		if dirtRecord.Id == dirtId then
			return dirtRecord, index
		end
	end

	return nil, nil
end

local function clean_dirt(player: Player, tool: Instance?, horseId: string, dirtId: string): (boolean, string)
	if activeRequestByPlayer[player] then
		return false, "Busy"
	end

	if not tool or not tool:IsA("Tool") or tool.Parent ~= player.Character then
		return false, "ToolNotEquipped"
	end

	if type(horseId) ~= "string" or horseId == "" or type(dirtId) ~= "string" or dirtId == "" then
		return false, "InvalidTarget"
	end

	local toolDefinition, toolItemId = ToolRegistry.resolve_definition_from_tool(tool)
	if not toolDefinition or toolDefinition.target ~= StableCleaningConfig.TargetType or not toolItemId then
		return false, "InvalidCleaningTool"
	end

	local horses = DataUtility.server.get(player, "Horses")
	local horse = horses and horses.Owned and horses.Owned[horseId]
	if not horse then
		return false, "HorseNotOwned"
	end

	local settings = get_spawn_settings()
	normalize_stable_care(horse, os.time(), settings)
	local dirtRecord, dirtIndex = find_dirt_record(horse.StableCare.Dirt, dirtId)
	local dirtDefinition = dirtRecord and StableCleaningConfig.GetDirtDefinition(dirtRecord.TypeId)
	if not dirtDefinition or dirtDefinition.RequiredToolId ~= toolItemId then
		return false, "WrongCleaningTool"
	end

	local plotValue = player:FindFirstChild("Plot")
	local plot = plotValue and plotValue:IsA("ObjectValue") and plotValue.Value or nil
	local dirtVisual = plot and find_dirt_visual(plot, horseId, dirtId) or nil
	if not plot or not dirtVisual or not is_player_close_enough(player, dirtVisual) then
		return false, "TooFar"
	end

	activeRequestByPlayer[player] = true
	local succeeded, response = pcall(function()
		local now = os.time()

		-- Apply the dirt penalty up to this exact moment, then remove it.
		HorseCareService.RefreshHorse(horse, now)
		table.remove(horse.StableCare.Dirt, dirtIndex)
		horse.StableCare.LastStableCleanedAt = now

		horse.Needs.Values.Cleanliness = math.clamp(
			(horse.Needs.Values.Cleanliness or 0) + StableCleaningConfig.CleanlinessRestorePerDirt,
			0,
			horse.Needs.Max.Cleanliness or 100
		)

		horse.State.LastCareAt = now
		horse.State.LastCleanedAt = now
		horse.State.Mood = "Helpful"
		horse.Stats.CareActions = (horse.Stats.CareActions or 0) + 1

		local allClean = #horse.StableCare.Dirt == 0
		if allClean then
			horse.Needs.Values.Happiness = math.clamp(
				(horse.Needs.Values.Happiness or 0) + StableCleaningConfig.AllCleanHappinessBonus,
				0,
				horse.Needs.Max.Happiness or 100
			)
			horse.State.Mood = "Comfortable"
		end

		QuestService.EnsureDailyQuest(player)
		DataUtility.server.set(player, "Horses", horses)

		local stats = DataUtility.server.get(player, "Stats")
		if stats then
			stats.TotalCareActions = (stats.TotalCareActions or 0) + 1
			stats.TotalCleanActions = (stats.TotalCleanActions or 0) + 1
			stats.TotalStableCleanActions = (stats.TotalStableCleanActions or 0) + 1
			DataUtility.server.set(player, "Stats", stats)
		end

		QuestService.RefreshDailyQuestProgress(player)
		StableCleaningService.SyncPlayerVisuals(player)

		return allClean and "StallClean" or "DirtCleaned"
	end)
	activeRequestByPlayer[player] = nil

	if not succeeded then
		warn(("[StableCleaning] failed for %s: %s"):format(player.Name, tostring(response)))
		return false, "CleanFailed"
	end

	return true, response
end

function StableCleaningService.PlayerReady(player: Player)
	process_spawns(player, os.time())
	StableCleaningService.SyncPlayerVisuals(player)
end

function StableCleaningService.Init()
	if initialized then
		return
	end

	initialized = true
	Network.Horse.CleanStableDirt:Respond(clean_dirt)

	Players.PlayerRemoving:Connect(function(player)
		activeRequestByPlayer[player] = nil
		clear_plot_visuals(lastPlotByPlayer[player])
		lastPlotByPlayer[player] = nil
	end)

	task.spawn(function()
		while initialized do
			local now = os.time()
			for _, player in ipairs(Players:GetPlayers()) do
				process_spawns(player, now)
				StableCleaningService.SyncPlayerVisuals(player)
			end
			task.wait(get_spawn_settings().Tick)
		end
	end)
end

return StableCleaningService
