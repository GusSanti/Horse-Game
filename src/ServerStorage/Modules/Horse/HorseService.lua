------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace: Workspace = game:GetService("Workspace")

------------------//CONSTANTS
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Dictionary = Modules:WaitForChild("Dictionary")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local HORSE_FOLDER_NAME = "HorseFolder"
local HORSE_POSITION_NAME = "HorsePosition"
local PRIMARY_HORSE_SLOT_NAME = "Slot1"
local VISUAL_HORSE_ATTRIBUTE = "IsStableVisualHorse"
local HORSE_ID_ATTRIBUTE = "HorseId"
local HORSE_CATALOG_ID_ATTRIBUTE = "HorseCatalogId"
local HORSE_VISUAL_MODEL_NAME_ATTRIBUTE = "HorseVisualModelName"
local MOUNTED_USER_ID_ATTRIBUTE = "MountedUserId"
local ROAMING_HORSE_ATTRIBUTE = "IsHorseRoaming"
local ROAMING_BEHAVIOR_ATTRIBUTE = "HorseRoamingBehavior"
local SERVER_ANIMATIONS_READY_ATTRIBUTE = "HorseServerAnimationsReady"
local STATUS_UPDATE_INTERVAL_SECONDS = 60
local STABLE_GROUND_RAY_DISTANCE = 100
local STABLE_GROUND_MIN_HORIZONTAL_AREA = 16
local STABLE_GROUND_MAX_RAYCAST_HITS = 32
local PLAYER_COLLISION_GROUP = "Players"
local HORSE_COLLISION_GROUP = "Horses"

------------------//VARIABLES
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseCatalog = require(GameData:WaitForChild("Horse"):WaitForChild("HorseCatalog"))
local HorseMountConfig = require(GameData:WaitForChild("Horse"):WaitForChild("HorseMountConfig"))
local NatureCatalog = require(GameData:WaitForChild("Horse"):WaitForChild("NatureCatalog"))
local HorseBondService = require(Utility:WaitForChild("Horse"):WaitForChild("HorseBondService"))
local HorseEquipmentUtility = require(Utility:WaitForChild("Horse"):WaitForChild("HorseEquipmentUtility"))
local HorseStatusService = require(Utility:WaitForChild("Horse"):WaitForChild("HorseStatusService"))
local StableDictionary = require(Dictionary:WaitForChild("StableDictionary"))
local SoundUtility = require(Utility:WaitForChild("SoundUtility"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))
local HorseCareService = require(script.Parent:WaitForChild("HorseCareService"))
local HorseSaddleVisualService = require(script.Parent:WaitForChild("HorseSaddleVisualService"))

local HorseService = {}
local statusDecayLoopStarted = false
local collisionServiceInitialized = false
local registeredCollisionVisuals = setmetatable({}, { __mode = "k" })
local stableAnimationStates = setmetatable({}, { __mode = "k" })
local collisionPlayerConnections = {}
local is_visual_horse_mounted: (Instance) -> boolean
local RACE_MIN_STATUS_PERCENT = 50
local STATUS_DISPLAY_NAMES = {
	Happiness = "Felicidade",
	Hunger = "Hunger",
	Thirst = "Thirst",
	Cleanliness = "Cleanliness",
	Health = "Health",
}

------------------//FUNCTIONS
local function set_part_collision_group(part: BasePart, groupName: string): ()
	pcall(function()
		part.CollisionGroup = groupName
	end)
end

local function apply_collision_group(root: Instance, groupName: string): ()
	if root:IsA("BasePart") then
		set_part_collision_group(root, groupName)
	end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then
			set_part_collision_group(descendant, groupName)
		end
	end
end

local function bind_collision_character(player: Player, character: Model): ()
	local record = collisionPlayerConnections[player]
	if not record then
		return
	end

	if record.CharacterConnection then
		record.CharacterConnection:Disconnect()
	end

	apply_collision_group(character, PLAYER_COLLISION_GROUP)
	record.CharacterConnection = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			set_part_collision_group(descendant, PLAYER_COLLISION_GROUP)
		end
	end)
end

local function bind_collision_player(player: Player): ()
	if collisionPlayerConnections[player] then
		return
	end

	local record = {}
	collisionPlayerConnections[player] = record
	record.CharacterAdded = player.CharacterAdded:Connect(function(character)
		bind_collision_character(player, character)
	end)

	if player.Character then
		bind_collision_character(player, player.Character)
	end
end

local function ensure_horse_animator(visual: Instance): Animator?
	if not visual:IsA("Model") then
		return nil
	end

	local existingAnimator = visual:FindFirstChildWhichIsA("Animator", true)
	if existingAnimator then
		return existingAnimator
	end

	local controller = visual:FindFirstChildOfClass("AnimationController")
		or visual:FindFirstChildWhichIsA("AnimationController", true)
		or visual:FindFirstChildOfClass("Humanoid")
		or visual:FindFirstChildWhichIsA("Humanoid", true)

	if not controller then
		controller = Instance.new("AnimationController")
		controller.Name = "HorseAnimationController"
		controller.Parent = visual
	end

	local animator = controller:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = controller
	end

	return animator
end

local function stop_stable_animation_track(track: AnimationTrack?): ()
	if not track then
		return
	end

	pcall(function()
		track:Stop(HorseMountConfig.HorseAnimationBlendTime or 0.24)
	end)
end

local function destroy_stable_animation_state(visual: Instance): ()
	local state = stableAnimationStates[visual]
	if not state then
		return
	end

	stableAnimationStates[visual] = nil
	for _, connection in state.Connections do
		connection:Disconnect()
	end
	for _, track in state.Tracks do
		stop_stable_animation_track(track)
		track:Destroy()
	end
	stop_stable_animation_track(state.BrushTrack)
	if state.BrushTrack then
		state.BrushTrack:Destroy()
	end
	stop_stable_animation_track(state.FeedTrack)
	if state.FeedTrack then
		state.FeedTrack:Destroy()
	end
	for _, animation in state.Animations do
		animation:Destroy()
	end
end

local function load_stable_animation_track(animator: Animator, animationId: string): (AnimationTrack?, Animation?)
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local success, trackOrError = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not trackOrError then
		warn(("[HorseService] nao foi possivel carregar a animacao %s: %s"):format(
			animationId,
			tostring(trackOrError)
		))
		animation:Destroy()
		return nil, nil
	end

	local track = trackOrError :: AnimationTrack
	track.Priority = Enum.AnimationPriority.Idle
	track.Looped = true
	return track, animation
end

local function sync_stable_animation(visual: Instance): ()
	local state = stableAnimationStates[visual]
	if not state then
		return
	end
	if state.BrushActive or state.FeedActive then
		return
	end

	local mountedUserId = visual:GetAttribute(MOUNTED_USER_ID_ATTRIBUTE)
	local mode = if type(mountedUserId) == "number" and mountedUserId > 0
		then nil
		elseif visual:GetAttribute(ROAMING_HORSE_ATTRIBUTE) == true
			and visual:GetAttribute(ROAMING_BEHAVIOR_ATTRIBUTE) == "Walking"
		then "Walk"
		else "Idle"

	if state.Mode == mode then
		local currentTrack = mode and state.Tracks[mode] or nil
		if not currentTrack or currentTrack.IsPlaying then
			return
		end
	end

	for trackMode, track in state.Tracks do
		if trackMode == mode then
			if not track.IsPlaying then
				track:Play(HorseMountConfig.AnimationFadeTime or 0.12, 1, 1)
			end
			track:AdjustWeight(1, HorseMountConfig.HorseAnimationBlendTime or 0.24)
			track:AdjustSpeed(1)
		else
			stop_stable_animation_track(track)
		end
	end

	state.Mode = mode
end

local function register_stable_animations(visual: Instance, animator: Animator?): ()
	if visual:GetAttribute(VISUAL_HORSE_ATTRIBUTE) ~= true or stableAnimationStates[visual] then
		return
	end
	if not animator then
		warn(("[HorseService] cavalo %s nao possui Animator valido"):format(visual:GetFullName()))
		return
	end

	local idleTrack, idleAnimation = load_stable_animation_track(animator, HorseMountConfig.HorseIdleAnimationId)
	local walkTrack, walkAnimation = load_stable_animation_track(animator, HorseMountConfig.HorseWalkAnimationId)
	if not idleTrack or not walkTrack then
		for _, track in { idleTrack, walkTrack } do
			if track then
				track:Destroy()
			end
		end
		for _, animation in { idleAnimation, walkAnimation } do
			if animation then
				animation:Destroy()
			end
		end
		visual:SetAttribute(SERVER_ANIMATIONS_READY_ATTRIBUTE, false)
		return
	end
	local brushTrack, brushAnimation = load_stable_animation_track(animator, HorseMountConfig.HorseBrushAnimationId)
	if brushTrack then
		brushTrack.Priority = Enum.AnimationPriority.Action
		brushTrack.Looped = true
	end
	local feedTrack, feedAnimation = load_stable_animation_track(animator, HorseMountConfig.HorseFeedAnimationId)
	if feedTrack then
		feedTrack.Priority = Enum.AnimationPriority.Action
		feedTrack.Looped = true
	end

	local state = {
		Mode = nil,
		Tracks = { Idle = idleTrack, Walk = walkTrack },
		BrushTrack = brushTrack,
		BrushActive = false,
		FeedTrack = feedTrack,
		FeedActive = false,
		Animations = { idleAnimation, walkAnimation, brushAnimation, feedAnimation },
		Connections = {},
	}
	stableAnimationStates[visual] = state
	for _, attributeName in {
		MOUNTED_USER_ID_ATTRIBUTE,
		ROAMING_HORSE_ATTRIBUTE,
		ROAMING_BEHAVIOR_ATTRIBUTE,
	} do
		state.Connections[#state.Connections + 1] = visual:GetAttributeChangedSignal(attributeName):Connect(function()
			sync_stable_animation(visual)
		end)
	end
	state.Connections[#state.Connections + 1] = visual.AncestryChanged:Connect(function(_, parent)
		if not parent then
			destroy_stable_animation_state(visual)
		end
	end)

	visual:SetAttribute(SERVER_ANIMATIONS_READY_ATTRIBUTE, true)
	sync_stable_animation(visual)
end

function HorseService.RegisterHorseVisual(visual: Instance?): ()
	if not visual then
		return
	end

	local animator = ensure_horse_animator(visual)
	register_stable_animations(visual, animator)
	if registeredCollisionVisuals[visual] then
		return
	end

	apply_collision_group(visual, HORSE_COLLISION_GROUP)
	registeredCollisionVisuals[visual] = visual.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			set_part_collision_group(descendant, HORSE_COLLISION_GROUP)
		end
	end)
end

local function get_player_horse_visual(player: Player, horseId: string): Instance?
	local plotValue = player:FindFirstChild("Plot")
	if not plotValue or not plotValue:IsA("ObjectValue") or not plotValue.Value then
		return nil
	end

	local horseFolder = plotValue.Value:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return nil
	end

	for _, visual: Instance in horseFolder:GetDescendants() do
		if visual:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true
			and visual:GetAttribute(HORSE_ID_ATTRIBUTE) == horseId
		then
			return visual
		end
	end

	return nil
end

function HorseService.PlayBrushAnimation(player: Player, horseId: string): (boolean, string)
	local visual = get_player_horse_visual(player, horseId)
	if not visual then
		return false, "HorseVisualMissing"
	end
	if is_visual_horse_mounted(visual) then
		return false, "HorseMounted"
	end

	local state = stableAnimationStates[visual]
	local brushTrack = state and state.BrushTrack
	if not brushTrack then
		return false, "BrushAnimationMissing"
	end

	state.FeedActive = false
	stop_stable_animation_track(state.FeedTrack)
	state.BrushActive = true
	for _, track in state.Tracks do
		stop_stable_animation_track(track)
	end
	pcall(function()
		brushTrack:Stop(0)
		brushTrack:Play(HorseMountConfig.AnimationFadeTime or 0.12, 1, 1)
	end)

	return true, "BrushAnimationPlaying"
end

function HorseService.StopBrushAnimation(player: Player, horseId: string): ()
	local visual = get_player_horse_visual(player, horseId)
	local state = visual and stableAnimationStates[visual] or nil
	if not state or not state.BrushActive then
		return
	end

	state.BrushActive = false
	stop_stable_animation_track(state.BrushTrack)
	state.Mode = nil
	sync_stable_animation(visual)
end

function HorseService.PlayFeedAnimation(player: Player, horseId: string): (boolean, string)
	local visual = get_player_horse_visual(player, horseId)
	if not visual then
		return false, "HorseVisualMissing"
	end
	if is_visual_horse_mounted(visual) then
		return false, "HorseMounted"
	end

	local state = stableAnimationStates[visual]
	local feedTrack = state and state.FeedTrack
	if not feedTrack then
		return false, "FeedAnimationMissing"
	end

	state.BrushActive = false
	stop_stable_animation_track(state.BrushTrack)
	state.FeedActive = true
	for _, track in state.Tracks do
		stop_stable_animation_track(track)
	end
	pcall(function()
		feedTrack:Stop(0)
		feedTrack:Play(HorseMountConfig.AnimationFadeTime or 0.12, 1, 1)
	end)

	return true, "FeedAnimationPlaying"
end

function HorseService.StopFeedAnimation(player: Player, horseId: string): ()
	local visual = get_player_horse_visual(player, horseId)
	local state = visual and stableAnimationStates[visual] or nil
	if not state or not state.FeedActive then
		return
	end

	state.FeedActive = false
	stop_stable_animation_track(state.FeedTrack)
	state.Mode = nil
	sync_stable_animation(visual)
end

function HorseService.Init(): ()
	if collisionServiceInitialized then
		return
	end
	collisionServiceInitialized = true

	for _, player in Players:GetPlayers() do
		bind_collision_player(player)
	end

	Players.PlayerAdded:Connect(bind_collision_player)
	Players.PlayerRemoving:Connect(function(player)
		local record = collisionPlayerConnections[player]
		collisionPlayerConnections[player] = nil
		if record then
			for _, connection in record do
				connection:Disconnect()
			end
		end
	end)
end

local function get_display_name(horse)
	local nickname = horse.Nickname or ""
	if nickname ~= "" then
		return nickname
	end

	return horse.DisplayName or horse.CatalogId or horse.Id
end

local function create_horse_record(definition, instanceId: number, ownerUserId: number, options)
	local obtainedAt = options.ObtainedAt or os.time()
	local natureId = options.NatureId or NatureCatalog.RollNatureId()

	return {
		Id = ("horse_%d"):format(instanceId),
		InstanceId = instanceId,
		CatalogId = definition.CatalogId,
		DisplayName = definition.DisplayName,
		Nickname = options.Nickname or definition.ShortName or definition.DisplayName,
		VisualModelName = definition.PlaceholderModelKey,
		Tier = definition.Tier,
		Rarity = definition.Rarity,
		LaunchGroup = definition.LaunchGroup,
		PlaceholderModelKey = definition.PlaceholderModelKey,
		Description = definition.Description,
		Nature = NatureCatalog.BuildRecord(natureId, options.NatureSource or options.Source or "HorseCreation", obtainedAt),
		OwnerUserId = ownerUserId,
		Acquisition = {
			Source = options.Source or "Unknown",
			ObtainedAt = obtainedAt,
			IsStarterGrant = options.IsStarterGrant == true,
		},
		Bond = {
			Level = 1,
			XP = 0,
			TotalXP = 0,
			MaxLevel = definition.Bonding.MaxBondLevel,
			Friendship = definition.Bonding.StartingFriendship,
			MaxFriendship = definition.Bonding.MaxFriendship,
			CareBonus = TableUtility.DeepCopy(definition.Bonding.CareBonus),
			LastProgressAt = obtainedAt,
			AccruedCareSeconds = 0,
			CareStreak = 0,
			BestCareStreak = 0,
			SuccessfulCareWindows = 0,
			LastQualifiedAt = 0,
			TrustState = "Wary",
		},
		Needs = {
			Values = TableUtility.DeepCopy(definition.Needs.Starting),
			Max = TableUtility.DeepCopy(definition.Needs.Max),
			DecayPerHour = TableUtility.DeepCopy(definition.Needs.DecayPerHour),
			Modifiers = {},
			LastUpdatedAt = obtainedAt,
		},
		Movement = TableUtility.DeepCopy(definition.Movement),
		Temperament = TableUtility.DeepCopy(definition.Temperament),
		Dependencies = TableUtility.DeepCopy(definition.Dependencies),
		State = {
			Mood = "Curious",
			Energy = 100,
			IsDirty = false,
			IsSaddled = false,
			LastCareAt = 0,
			LastFedAt = 0,
			LastWateredAt = 0,
			LastMedicatedAt = 0,
			LastGroomedAt = 0,
			LastCleanedAt = 0,
		},
		StableCare = {
			Dirt = {},
			NextDirtId = 1,
			NextDirtAt = 0,
			LastStableCleanedAt = 0,
		},
		Equipment = {
			SaddleItemId = "",
			BridleItemId = "",
			SaddlePadItemId = "",
			AccessoryItemIds = {},
		},
		Stats = {
			CareActions = 0,
			RacesEntered = 0,
			RacesWon = 0,
			BestRaceTimeMs = 0,
		},
	}
end

local function get_status_display_name(statusName: string?): string
	if type(statusName) ~= "string" or statusName == "" then
		return "Status"
	end

	return STATUS_DISPLAY_NAMES[statusName] or statusName
end

local function evaluate_race_readiness(horse, now: number?)
	local statuses = HorseStatusService.GetComputedStatuses(horse, now)
	local needs = horse and horse.Needs or {}
	local maxValues = needs and needs.Max or {}
	local lowestStatus = nil
	local lowestPercent = 100
	local blockedStatus = nil
	local blockedPercent = 100
	local totalPercent = 0
	local statusCount = 0

	for _, statusName: string in ipairs(HorseStatusService.StatusOrder) do
		local maxValue = math.max(1, tonumber(maxValues[statusName]) or 100)
		local currentValue = math.clamp(tonumber(statuses and statuses[statusName]) or 0, 0, maxValue)
		local percent = math.floor(((currentValue / maxValue) * 100) + 0.5)
		totalPercent += percent
		statusCount += 1

		if not lowestStatus or percent < lowestPercent then
			lowestStatus = statusName
			lowestPercent = percent
		end

		if percent < RACE_MIN_STATUS_PERCENT and (not blockedStatus or percent < blockedPercent) then
			blockedStatus = statusName
			blockedPercent = percent
		end
	end

	return {
		CanRace = blockedStatus == nil,
		MinimumPercent = RACE_MIN_STATUS_PERCENT,
		LowestStatus = lowestStatus,
		LowestStatusDisplay = get_status_display_name(lowestStatus),
		LowestPercent = lowestPercent,
		BlockedStatus = blockedStatus,
		BlockedStatusDisplay = get_status_display_name(blockedStatus),
		BlockedPercent = blockedPercent,
		AveragePercent = statusCount > 0 and math.floor((totalPercent / statusCount) + 0.5) or 100,
	}
end

local function get_first_owned_horse_id(horses): string?
	local orderedIds = horses.OrderedIds or {}
	local ownedHorses = horses.Owned or {}

	for _, horseId: string in orderedIds do
		if ownedHorses[horseId] then
			return horseId
		end
	end

	for horseId in ownedHorses do
		return horseId
	end

	return nil
end

local function get_owned_horse_ids_in_order(horses): {string}
	local orderedHorseIds: {string} = {}
	local addedHorseIds: {[string]: boolean} = {}
	local orderedIds = horses.OrderedIds or {}
	local ownedHorses = horses.Owned or {}

	for _, horseId: string in orderedIds do
		if ownedHorses[horseId] and not addedHorseIds[horseId] then
			addedHorseIds[horseId] = true
			orderedHorseIds[#orderedHorseIds + 1] = horseId
		end
	end

	for horseId in ownedHorses do
		if not addedHorseIds[horseId] then
			addedHorseIds[horseId] = true
			orderedHorseIds[#orderedHorseIds + 1] = horseId
		end
	end

	return orderedHorseIds
end

local function get_owned_horses_state(player: Player)
	local horses = DataUtility.server.get(player, "Horses")
	if not horses then
		return nil, nil
	end

	return horses, horses.Owned or {}
end

local function get_owned_stalls(stable): number
	local maxOwnedStalls = StableDictionary.MaxOwnedStalls or #StableDictionary.HorseSlotOrder
	local ownedStalls = stable.OwnedStalls

	if type(ownedStalls) ~= "number" then
		return StableDictionary.DefaultOwnedStalls
	end

	return math.clamp(math.floor(ownedStalls), 0, maxOwnedStalls)
end

local function get_slot_purchase_price(slotName: string): number?
	if StableDictionary.get_slot_purchase_price then
		return StableDictionary.get_slot_purchase_price(slotName)
	end

	return StableDictionary.SlotPurchasePrices and StableDictionary.SlotPurchasePrices[slotName] or nil
end

local function get_next_purchasable_slot_name(ownedStalls: number): string?
	local nextIndex = ownedStalls + 1
	return StableDictionary.HorseSlotOrder[nextIndex]
end

local function is_valid_slot_name(slotName: string): boolean
	for _, currentSlotName: string in StableDictionary.HorseSlotOrder do
		if currentSlotName == slotName then
			return true
		end
	end

	return false
end

local function get_slot_index(slotName: string): number?
	for slotIndex, currentSlotName: string in StableDictionary.HorseSlotOrder do
		if currentSlotName == slotName then
			return slotIndex
		end
	end

	return nil
end

local function get_first_empty_slot_name(horseSlots: {[string]: string}, ownedStalls: number): string?
	for slotIndex, slotName: string in StableDictionary.HorseSlotOrder do
		if slotIndex > ownedStalls then
			break
		end

		if horseSlots[slotName] == "" then
			return slotName
		end
	end

	return nil
end

local function ensure_stable_state(stable, horses): boolean
	local changed = false

	if type(stable.HorseSlots) ~= "table" then
		stable.HorseSlots = StableDictionary.get_default_horse_slots()
		changed = true
	end

	local ownedStalls = get_owned_stalls(stable)
	if stable.OwnedStalls ~= ownedStalls then
		stable.OwnedStalls = ownedStalls
		changed = true
	end

	local horseSlots = stable.HorseSlots
	local ownedHorses = horses.Owned or {}
	local assignedHorseIds: {[string]: boolean} = {}

	for _, slotName: string in StableDictionary.HorseSlotOrder do
		if type(horseSlots[slotName]) ~= "string" then
			horseSlots[slotName] = ""
			changed = true
		end
	end

	for slotIndex, slotName: string in StableDictionary.HorseSlotOrder do
		local horseId = horseSlots[slotName]

		if slotIndex > ownedStalls then
			if horseId ~= "" then
				horseSlots[slotName] = ""
				changed = true
			end
		elseif horseId ~= "" then
			if not ownedHorses[horseId] or assignedHorseIds[horseId] then
				horseSlots[slotName] = ""
				changed = true
			else
				assignedHorseIds[horseId] = true
			end
		end
	end

	local orderedHorseIds = get_owned_horse_ids_in_order(horses)
	local equippedHorseId = horses.EquippedHorseId or ""

	if equippedHorseId ~= "" and ownedHorses[equippedHorseId] then
		local prioritizedHorseIds = { equippedHorseId }

		for _, horseId: string in orderedHorseIds do
			if horseId ~= equippedHorseId then
				prioritizedHorseIds[#prioritizedHorseIds + 1] = horseId
			end
		end

		orderedHorseIds = prioritizedHorseIds
	end

	for _, horseId: string in orderedHorseIds do
		if not assignedHorseIds[horseId] then
			local emptySlotName = get_first_empty_slot_name(horseSlots, ownedStalls)
			if not emptySlotName then
				break
			end

			horseSlots[emptySlotName] = horseId
			assignedHorseIds[horseId] = true
			changed = true
		end
	end

	return changed
end

local function save_stable(player: Player, stable): ()
	DataUtility.server.set(player, "Stable", stable)
end

local function save_owned_horses(player: Player, horses): ()
	DataUtility.server.set(player, "Horses.Owned", horses.Owned)
end

local function refresh_owned_horse_statuses(player: Player, horses, horseId: string?): (boolean, string)
	if not horses or type(horses.Owned) ~= "table" then
		return false, "DataUnavailable"
	end

	local now = os.time()
	local changed = false
	local totalBondXP = 0

	local function refresh_horse(horse): ()
		local natureChanged = NatureCatalog.NormalizeHorseNature(horse, now)
		local horseChanged = HorseCareService.RefreshHorse(horse, now)
		local bondChanged, xpGained = HorseBondService.ApplyPassiveProgress(horse, now)

		changed = changed or natureChanged or horseChanged or bondChanged
		totalBondXP += xpGained or 0
	end

	if horseId and horseId ~= "" then
		local horse = horses.Owned[horseId]
		if not horse then
			return false, "HorseNotOwned"
		end

		refresh_horse(horse)
	else
		for _, horse in horses.Owned do
			refresh_horse(horse)
		end
	end

	if changed then
		save_owned_horses(player, horses)

		if totalBondXP > 0 then
			local currentBondPoints = DataUtility.server.get(player, "Stats.TotalBondPointsEarned") or 0
			DataUtility.server.set(player, "Stats.TotalBondPointsEarned", currentBondPoints + totalBondXP)
		end

		return true, "Updated"
	end

	return true, "Unchanged"
end

local function get_horse_assets_folder(): Instance?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		return nil
	end

	return assetsFolder:FindFirstChild("Horses")
end

local function get_horse_visual_model_name(horse): string
	if type(horse.VisualModelName) == "string" and horse.VisualModelName ~= "" then
		return horse.VisualModelName
	end

	if type(horse.PlaceholderModelKey) == "string" and horse.PlaceholderModelKey ~= "" then
		return horse.PlaceholderModelKey
	end

	if type(horse.CatalogId) == "string" and horse.CatalogId ~= "" then
		return horse.CatalogId
	end

	if type(horse.DisplayName) == "string" and horse.DisplayName ~= "" then
		return horse.DisplayName
	end

	return ""
end

local function find_horse_visual_source(horse): Instance?
	local horsesFolder = get_horse_assets_folder()
	if not horsesFolder then
		return nil
	end

	local modelName = get_horse_visual_model_name(horse)
	if modelName ~= "" then
		local model = horsesFolder:FindFirstChild(modelName)
		if model then
			return model
		end
	end

	local catalogId = horse.CatalogId
	if type(catalogId) == "string" and catalogId ~= "" then
		local catalogModel = horsesFolder:FindFirstChild(catalogId)
		if catalogModel then
			return catalogModel
		end

		local definition = HorseCatalog.GetDefinition(catalogId)
		if definition then
			local placeholderModel = horsesFolder:FindFirstChild(definition.PlaceholderModelKey)
			if placeholderModel then
				return placeholderModel
			end
		end
	end

	return nil
end

local function get_base_part_lowest_y(basePart: BasePart): number
	local cframe = basePart.CFrame
	local halfSizeX = cframe.RightVector * (basePart.Size.X * 0.5)
	local halfSizeY = cframe.UpVector * (basePart.Size.Y * 0.5)
	local halfSizeZ = cframe.LookVector * (basePart.Size.Z * 0.5)
	local lowestY = math.huge

	for xSign = -1, 1, 2 do
		for ySign = -1, 1, 2 do
			for zSign = -1, 1, 2 do
				local cornerPosition = cframe.Position + (halfSizeX * xSign) + (halfSizeY * ySign) + (halfSizeZ * zSign)
				lowestY = math.min(lowestY, cornerPosition.Y)
			end
		end
	end

	return lowestY
end

local function get_instance_lowest_y(instance: Instance): number?
	if instance:IsA("BasePart") then
		return get_base_part_lowest_y(instance)
	end

	local lowestY = math.huge
	local foundBasePart = false

	for _, descendant: Instance in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			foundBasePart = true
			lowestY = math.min(lowestY, get_base_part_lowest_y(descendant))
		end
	end

	if not foundBasePart then
		return nil
	end

	return lowestY
end

local function get_visible_instance_lowest_y(instance: Instance): number?
	local lowestHoofBoneY = math.huge
	local foundHoofBone = false

	for _, descendant: Instance in instance:GetDescendants() do
		if descendant:IsA("Bone") then
			local boneName = string.lower(descendant.Name)
			local isHoofBone = string.find(boneName, "hoof", 1, true)
				or string.find(boneName, "foot", 1, true)
				or boneName == "leg_1"
				or boneName == "leg_2"
				or boneName == "leg_3"
				or boneName == "leg_4"

			if isHoofBone then
				foundHoofBone = true
				lowestHoofBoneY = math.min(lowestHoofBoneY, descendant.WorldPosition.Y)
			end
		end
	end

	-- Skinned meshes do not update their BasePart bounds when their root Bone
	-- moves. Hoof Bones therefore reflect the visible feet more accurately.
	if foundHoofBone then
		return lowestHoofBoneY
	end

	if instance:IsA("BasePart") then
		if instance.Transparency < 1 then
			return get_base_part_lowest_y(instance)
		end

		return nil
	end

	local lowestY = math.huge
	local foundVisibleBasePart = false

	for _, descendant: Instance in instance:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Transparency < 1 then
			foundVisibleBasePart = true
			lowestY = math.min(lowestY, get_base_part_lowest_y(descendant))
		end
	end

	if not foundVisibleBasePart then
		return nil
	end

	return lowestY
end

is_visual_horse_mounted = function(visualHorse: Instance): boolean
	return (tonumber(visualHorse:GetAttribute(MOUNTED_USER_ID_ATTRIBUTE)) or 0) > 0
end

local function clear_visual_horse_from_slot(slotFolder: Instance, force: boolean?): ()
	for _, child: Instance in slotFolder:GetChildren() do
		if child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true
			and (force == true or not is_visual_horse_mounted(child))
		then
			child:Destroy()
		end
	end
end

local function get_visual_horses_in_slot(slotFolder: Instance): {Instance}
	local visualHorses = {}

	for _, child: Instance in slotFolder:GetChildren() do
		if child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true then
			visualHorses[#visualHorses + 1] = child
		end
	end

	return visualHorses
end

local function apply_visual_horse_metadata(visualHorse: Instance, horse): ()
	visualHorse.Name = horse.Id
	visualHorse:SetAttribute(VISUAL_HORSE_ATTRIBUTE, true)
	visualHorse:SetAttribute(HORSE_ID_ATTRIBUTE, horse.Id)
	visualHorse:SetAttribute(HORSE_CATALOG_ID_ATTRIBUTE, horse.CatalogId)
	visualHorse:SetAttribute(HORSE_VISUAL_MODEL_NAME_ATTRIBUTE, get_horse_visual_model_name(horse))
	HorseService.RegisterHorseVisual(visualHorse)
end

local function has_matching_visual_horse_identity(visualHorse: Instance, horse): boolean
	if visualHorse:GetAttribute(VISUAL_HORSE_ATTRIBUTE) ~= true then
		return false
	end

	if visualHorse:GetAttribute(HORSE_ID_ATTRIBUTE) ~= horse.Id then
		return false
	end

	if visualHorse:GetAttribute(HORSE_CATALOG_ID_ATTRIBUTE) ~= horse.CatalogId then
		return false
	end

	return true
end

local function is_visual_horse_current(visualHorse: Instance, horse): boolean
	if not has_matching_visual_horse_identity(visualHorse, horse) then
		return false
	end

	local currentModelName = visualHorse:GetAttribute(HORSE_VISUAL_MODEL_NAME_ATTRIBUTE)
	if type(currentModelName) ~= "string" or currentModelName == "" then
		return true
	end

	return visualHorse:GetAttribute(HORSE_VISUAL_MODEL_NAME_ATTRIBUTE) == get_horse_visual_model_name(horse)
end

local function get_horse_position(slotFolder: Instance): BasePart?
	local horsePosition = slotFolder:FindFirstChild(HORSE_POSITION_NAME)
	if not horsePosition or not horsePosition:IsA("BasePart") then
		return nil
	end

	-- HorsePosition is only a placement marker. Keeping it non-collidable avoids
	-- the stable horse being supported by the marker instead of the stable floor.
	horsePosition.Transparency = 1
	horsePosition.CanCollide = false
	horsePosition.CanTouch = false
	horsePosition.CanQuery = false

	return horsePosition
end

local function is_stable_ground_surface(raycastResult: RaycastResult): boolean
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

	return (hitInstance.Size.X * hitInstance.Size.Z) >= STABLE_GROUND_MIN_HORIZONTAL_AREA
end

local function get_stable_ground_y(horsePosition: BasePart, visualHorse: Instance): number
	local slotFolder = horsePosition.Parent
	local ignoredInstances: {Instance} = if slotFolder then { slotFolder } else { horsePosition, visualHorse }

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = ignoredInstances
	raycastParams.RespectCanCollide = true

	local rayOrigin = horsePosition.Position + Vector3.new(0, (horsePosition.Size.Y * 0.5) + 0.05, 0)
	local rayDirection = Vector3.new(0, -STABLE_GROUND_RAY_DISTANCE, 0)

	for _ = 1, STABLE_GROUND_MAX_RAYCAST_HITS do
		local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
		if not rayResult then
			break
		end

		if is_stable_ground_surface(rayResult) then
			return rayResult.Position.Y
		end

		-- Small loose objects are not floor. Ignore them and continue searching
		-- downwards until a broad horizontal surface is found.
		ignoredInstances[#ignoredInstances + 1] = rayResult.Instance
		raycastParams.FilterDescendantsInstances = ignoredInstances
	end

	return get_base_part_lowest_y(horsePosition)
end

local function get_visual_base_parts(visualHorse: Instance): {BasePart}
	local baseParts = {}
	if visualHorse:IsA("BasePart") then
		baseParts[#baseParts + 1] = visualHorse
	end

	for _, descendant: Instance in visualHorse:GetDescendants() do
		if descendant:IsA("BasePart") then
			baseParts[#baseParts + 1] = descendant
		end
	end

	return baseParts
end

local function get_stable_physics_root(visualHorse: Instance, baseParts: {BasePart}): BasePart?
	if visualHorse:IsA("BasePart") then
		return visualHorse
	end

	if visualHorse:IsA("Model") then
		local primaryPart = visualHorse.PrimaryPart
		if primaryPart and primaryPart:IsDescendantOf(visualHorse) then
			return primaryPart
		end
	end

	for _, rootName in { "HorseRoot", "RootPart" } do
		local rootPart = visualHorse:FindFirstChild(rootName, true)
		if rootPart and rootPart:IsA("BasePart") then
			return rootPart
		end
	end

	return baseParts[1]
end

local function stop_visual_physics(baseParts: {BasePart}): ()
	for _, basePart in baseParts do
		if basePart.Parent then
			basePart.AssemblyLinearVelocity = Vector3.zero
			basePart.AssemblyAngularVelocity = Vector3.zero
		end
	end
end

local function stabilize_visual_horse_in_stable(visualHorse: Instance): ()
	-- Keep one root in every physical assembly anchored. Anchoring every part
	-- would stop Motor6D-driven idle animations, while anchoring only the root
	-- prevents gravity/network ownership from making the visual shake.
	local baseParts = get_visual_base_parts(visualHorse)
	local rootPart = get_stable_physics_root(visualHorse, baseParts)
	if not rootPart then
		return
	end

	rootPart.Anchored = true
	local rootAssemblyParts: {[BasePart]: boolean} = { [rootPart] = true }
	for _, connectedPart in rootPart:GetConnectedParts(true) do
		rootAssemblyParts[connectedPart] = true
	end

	for _, basePart in baseParts do
		if not rootAssemblyParts[basePart] then
			local hasAnchoredPart = basePart.Anchored
			for _, connectedPart in basePart:GetConnectedParts(true) do
				if connectedPart.Anchored then
					hasAnchoredPart = true
					break
				end
			end

			if not hasAnchoredPart then
				basePart.Anchored = true
			end
		end
	end

	stop_visual_physics(baseParts)
end

local function position_visual_horse(visualHorse: Instance, horsePosition: BasePart): ()
	visualHorse:PivotTo(horsePosition.CFrame)

	-- Invisible roots and hitboxes can extend below the hooves. Aligning from
	-- visible geometry makes the visible feet touch the stable floor.
	local horseLowestY = get_visible_instance_lowest_y(visualHorse) or get_instance_lowest_y(visualHorse)
	if not horseLowestY then
		return
	end

	local currentPivot = visualHorse:GetPivot()
	local groundY = get_stable_ground_y(horsePosition, visualHorse)
	local heightOffset = groundY - horseLowestY

	visualHorse:PivotTo(currentPivot + Vector3.new(0, heightOffset, 0))
end

function HorseService.PositionVisualHorseInStable(visualHorse: Instance, horsePosition: BasePart): ()
	-- This helper is also used when a free horse returns to its stall, so both
	-- creation and return paths place its visible hooves on the stable floor.
	horsePosition.Transparency = 1
	horsePosition.CanCollide = false
	horsePosition.CanTouch = false
	horsePosition.CanQuery = false
	stabilize_visual_horse_in_stable(visualHorse)
	position_visual_horse(visualHorse, horsePosition)
	stabilize_visual_horse_in_stable(visualHorse)
end

function HorseService.StabilizeVisualHorseInStable(visualHorse: Instance): ()
	stabilize_visual_horse_in_stable(visualHorse)
end

local function create_visual_horse_in_slot(slotFolder: Instance, horse): (Instance?, string)
	clear_visual_horse_from_slot(slotFolder)

	local horsePosition = get_horse_position(slotFolder)
	if not horsePosition then
		return nil, "HorsePositionMissing"
	end

	local horseModel = find_horse_visual_source(horse)
	if not horseModel then
		return nil, "HorseModelMissing"
	end

	local visualHorse = horseModel:Clone()
	visualHorse.Parent = slotFolder
	-- Animator:LoadAnimation requires the rig to be inside Workspace. Parent the
	-- clone before metadata registers its collision and animation controllers.
	apply_visual_horse_metadata(visualHorse, horse)

	if visualHorse:IsA("Model") or visualHorse:IsA("BasePart") then
		HorseService.PositionVisualHorseInStable(visualHorse, horsePosition)
		HorseSaddleVisualService.Sync(visualHorse, horse)
		HorseService.StabilizeVisualHorseInStable(visualHorse)

		return visualHorse, "Created"
	end

	visualHorse:Destroy()
	return nil, "InvalidHorseModelType"
end

local function sync_visual_horse_in_slot(slotFolder: Instance, horse): ()
	local horsePosition = get_horse_position(slotFolder)
	local visualHorses = get_visual_horses_in_slot(slotFolder)

	-- Status decay writes the Horses profile every minute. That write also
	-- refreshes stable visuals, so mounted horses must be left entirely alone.
	for _, visualHorse in ipairs(visualHorses) do
		if is_visual_horse_mounted(visualHorse) then
			return
		end
	end

	if not horse then
		clear_visual_horse_from_slot(slotFolder)
		return
	end

	if #visualHorses == 1 and is_visual_horse_current(visualHorses[1], horse) then
		apply_visual_horse_metadata(visualHorses[1], horse)
		if horsePosition then
			HorseService.PositionVisualHorseInStable(visualHorses[1], horsePosition)
		end
		HorseSaddleVisualService.Sync(visualHorses[1], horse)
		HorseService.StabilizeVisualHorseInStable(visualHorses[1])
		return
	end

	create_visual_horse_in_slot(slotFolder, horse)
end

local function find_active_visual_outside_slot(horseFolder: Instance, slotFolder: Instance, horseId: string): Instance?
	for _, descendant in horseFolder:GetDescendants() do
		if descendant:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true
			and descendant:GetAttribute(HORSE_ID_ATTRIBUTE) == horseId
			and not descendant:IsDescendantOf(slotFolder)
			and (
				descendant:GetAttribute(ROAMING_HORSE_ATTRIBUTE) == true
				or is_visual_horse_mounted(descendant)
			)
		then
			return descendant
		end
	end

	return nil
end

local function build_horse_summary(horse, equippedHorseId, now: number?)
	local movement, naturePerformance, saddleDefinition = HorseEquipmentUtility.GetEffectiveMovement(horse)
	local nature = NatureCatalog.GetHorseNatureDefinition(horse)
	local natureRecord = type(horse.Nature) == "table" and horse.Nature or {}
	local stats = horse.Stats or {}
	local readiness = evaluate_race_readiness(horse, now)

	return {
		Id = horse.Id,
		CatalogId = horse.CatalogId,
		Name = get_display_name(horse),
		DisplayName = horse.DisplayName or horse.CatalogId or horse.Id,
		Nickname = horse.Nickname or "",
		PlaceholderModelKey = horse.PlaceholderModelKey or "",
		NatureId = nature and nature.Id or "",
		Nature = nature and NatureCatalog.BuildRecord(
			nature.Id,
			natureRecord.Source or "Generated",
			natureRecord.RolledAt or now
		) or nil,
		NaturePerformance = naturePerformance,
		RaceAffinity = movement.RaceAffinity or 0.5,
		SprintSpeed = movement.SprintSpeed or 24,
		Acceleration = movement.Acceleration or 0.8,
		Stamina = movement.Stamina or 100,
		RacesEntered = stats.RacesEntered or 0,
		RacesWon = stats.RacesWon or 0,
		BestRaceTimeMs = stats.BestRaceTimeMs or 0,
		IsEquipped = horse.Id == equippedHorseId,
		CanRace = readiness.CanRace,
		RaceMinPercent = readiness.MinimumPercent,
		RaceConditionPercent = readiness.AveragePercent,
		RaceLowestStatus = readiness.LowestStatus,
		RaceLowestStatusDisplay = readiness.LowestStatusDisplay,
		RaceLowestPercent = readiness.LowestPercent,
		RaceBlockedStatus = readiness.BlockedStatus,
		RaceBlockedStatusDisplay = readiness.BlockedStatusDisplay,
		RaceBlockedPercent = readiness.BlockedPercent,
		SaddleItemId = saddleDefinition and saddleDefinition.ItemId or "",
		SaddleDisplayName = saddleDefinition and saddleDefinition.DisplayName or "",
		SaddleSprintBonus = saddleDefinition
			and saddleDefinition.SaddleBonuses
			and saddleDefinition.SaddleBonuses.SprintSpeedAdd
			or 0,
	}
end

local function build_horse_reveal_payload(horse)
	if type(horse) ~= "table" then
		return nil
	end

	local definition = HorseCatalog.GetDefinition(horse.CatalogId) or HorseCatalog.GetDefinition("Default")
	if not definition then
		return nil
	end

	return {
		HorseId = horse.Id,
		CatalogId = definition.CatalogId,
		DisplayName = definition.DisplayName,
		Rarity = definition.Rarity,
		ModelKey = definition.PlaceholderModelKey,
		Nature = horse.Nature,
		Source = horse.Acquisition and horse.Acquisition.Source or "",
	}
end

local function find_starter_granted_horse(horses)
	if type(horses) ~= "table" or type(horses.Owned) ~= "table" then
		return nil
	end

	for _, horseId: string in ipairs(horses.OrderedIds or {}) do
		local horse = horses.Owned[horseId]
		if horse and horse.Acquisition and horse.Acquisition.Source == "StarterGrant" then
			return horse
		end
	end

	for _, horse in pairs(horses.Owned) do
		if horse and horse.Acquisition and horse.Acquisition.Source == "StarterGrant" then
			return horse
		end
	end

	return nil
end

local function compute_race_happiness_gain(placement: number, participantCount: number): number
	local clampedParticipantCount = math.max(1, math.floor(participantCount or 1))
	local clampedPlacement = math.clamp(math.floor(placement or clampedParticipantCount), 1, clampedParticipantCount)

	if clampedParticipantCount == 1 then
		return 2
	end

	local placementAlpha = 1 - ((clampedPlacement - 1) / (clampedParticipantCount - 1))
	return math.max(1, math.floor((1 + (placementAlpha * 3)) + 0.5))
end

local function add_happiness_to_horse(horse, happinessGain: number, moodText: string?): ()
	local safeGain = math.max(0, happinessGain or 0)
	if safeGain <= 0 then
		return
	end

	horse.Needs = horse.Needs or {}
	horse.Needs.Values = horse.Needs.Values or {}
	horse.Needs.Max = horse.Needs.Max or {}
	horse.State = horse.State or {}

	horse.Needs.Values.Happiness = math.clamp(
		(horse.Needs.Values.Happiness or 0) + safeGain,
		0,
		horse.Needs.Max.Happiness or 100
	)

	if type(moodText) == "string" and moodText ~= "" then
		horse.State.Mood = moodText
	end
end

------------------//MAIN FUNCTIONS
function HorseService.GetPlayerHorse(player: Player, horseId: string?): (any?, string)
	local horses = DataUtility.server.get(player, "Horses")
	if not horses or not horses.Owned then
		return nil, "DataUnavailable"
	end

	if horseId and horseId ~= "" then
		if not horses.Owned[horseId] then
			return nil, "HorseNotOwned"
		end

		local requestedHorse = horses.Owned[horseId]
		local now = os.time()
		local natureChanged = requestedHorse and NatureCatalog.NormalizeHorseNature(requestedHorse, now)
		if requestedHorse and (HorseCareService.RefreshHorse(requestedHorse, now) or natureChanged) then
			DataUtility.server.set(player, "Horses", horses)
		end

		return requestedHorse, horseId
	end

	local resolvedHorseId = horses.EquippedHorseId or ""
	if resolvedHorseId == "" or not horses.Owned[resolvedHorseId] then
		local firstHorseId = get_first_owned_horse_id(horses)
		if not firstHorseId then
			return nil, "HorseNotFound"
		end

		resolvedHorseId = firstHorseId
	end

	local horse = horses.Owned[resolvedHorseId]
	local now = os.time()
	local natureChanged = horse and NatureCatalog.NormalizeHorseNature(horse, now)
	if horse and (HorseCareService.RefreshHorse(horse, now) or natureChanged) then
		DataUtility.server.set(player, "Horses", horses)
	end

	return horse, resolvedHorseId
end

function HorseService.GetOwnedHorse(player, horseId)
	local _, owned = get_owned_horses_state(player)
	if not owned then
		return nil
	end

	return owned[horseId]
end

function HorseService.GetOwnedHorses(player)
	local horses, owned = get_owned_horses_state(player)
	if not horses or not owned then
		return {}
	end

	local ordered = {}
	local inserted = {}

	for _, horseId in ipairs(horses.OrderedIds or {}) do
		local horse = owned[horseId]
		if horse then
			ordered[#ordered + 1] = horse
			inserted[horseId] = true
		end
	end

	for horseId, horse in pairs(owned) do
		if not inserted[horseId] then
			ordered[#ordered + 1] = horse
		end
	end

	return ordered
end

function HorseService.GetOwnedHorseSummaries(player)
	local horses = DataUtility.server.get(player, "Horses")
	if not horses then
		return {}
	end

	local summaries = {}
	local now = os.time()
	local changed = false
	for _, horse in ipairs(HorseService.GetOwnedHorses(player)) do
		changed = NatureCatalog.NormalizeHorseNature(horse, now) or changed
		summaries[#summaries + 1] = build_horse_summary(horse, horses.EquippedHorseId, now)
	end
	if changed then
		DataUtility.server.set(player, "Horses", horses)
	end

	return summaries
end

function HorseService.GetRaceReadiness(player: Player, horseId: string)
	local horse, errorCode = HorseService.GetPlayerHorse(player, horseId)
	if not horse then
		return nil, errorCode or "HorseNotOwned"
	end

	return evaluate_race_readiness(horse, os.time()), nil
end

function HorseService.CreateHorseForPlayer(player: Player, catalogId: string, options): (any, string)
	options = options or {}

	local horses = DataUtility.server.get(player, "Horses")
	local collection = DataUtility.server.get(player, "Collection")
	local stats = DataUtility.server.get(player, "Stats")
	local stable = DataUtility.server.get(player, "Stable")

	if not horses or not collection or not stats or not stable then
		return nil, "DataUnavailable"
	end

	local definition = HorseCatalog.GetDefinition(catalogId)
	if not definition then
		return nil, "UnknownHorseCatalogId"
	end

	local stableChanged = ensure_stable_state(stable, horses)
	local ownedStalls = get_owned_stalls(stable)
	local emptySlotName = get_first_empty_slot_name(stable.HorseSlots, ownedStalls)

	if not emptySlotName then
		if stableChanged then
			save_stable(player, stable)
		end

		return nil, "NoStableSlotAvailable"
	end

	horses.NextHorseInstanceId = (horses.NextHorseInstanceId or 0) + 1

	local horse = create_horse_record(definition, horses.NextHorseInstanceId, player.UserId, options)
	local obtainedAt = horse.Acquisition.ObtainedAt
	HorseBondService.NormalizeBond(horse, obtainedAt)
	HorseStatusService.NormalizeHorse(horse, obtainedAt)

	horses.Owned[horse.Id] = horse
	TableUtility.InsertUnique(horses.OrderedIds, horse.Id)
	stable.HorseSlots[emptySlotName] = horse.Id

	if options.EquipOnGrant or horses.EquippedHorseId == "" then
		horses.EquippedHorseId = horse.Id
	end

	stableChanged = ensure_stable_state(stable, horses) or stableChanged

	TableUtility.InsertUnique(collection.DiscoveredHorseIds, catalogId)
	TableUtility.InsertUnique(collection.OwnedHorseCatalogIds, catalogId)

	stats.TotalHorsesOwned = #horses.OrderedIds

	DataUtility.server.set(player, "Horses", horses)

	if stableChanged then
		save_stable(player, stable)
	end

	DataUtility.server.set(player, "Collection", collection)
	DataUtility.server.set(player, "Stats.TotalHorsesOwned", stats.TotalHorsesOwned)

	return horse, "Created"
end

function HorseService.EnsureStarterHorse(player: Player): (any, string)
	local horses = DataUtility.server.get(player, "Horses")
	local progression = DataUtility.server.get(player, "Progression")
	local stable = DataUtility.server.get(player, "Stable")

	if not horses or not progression or not stable then
		return nil, "DataUnavailable"
	end

	local hasAnyHorse = next(horses.Owned or {}) ~= nil
	if hasAnyHorse and (horses.EquippedHorseId == "" or horses.Owned[horses.EquippedHorseId] == nil) then
		local firstHorseId = get_first_owned_horse_id(horses)
		if firstHorseId then
			horses.EquippedHorseId = firstHorseId
			DataUtility.server.set(player, "Horses", horses)
		end
	end

	if progression.FirstHorseGranted and hasAnyHorse then
		if progression.StarterRevealAcknowledged ~= true and type(progression.PendingHorseReveal) ~= "table" then
			local starterHorse = find_starter_granted_horse(horses)
			local revealPayload = build_horse_reveal_payload(starterHorse)
			if revealPayload then
				DataUtility.server.set(player, "Progression.PendingHorseReveal", revealPayload)
			end
		end

		local stableChanged = ensure_stable_state(stable, horses)
		if stableChanged then
			save_stable(player, stable)
		end

		if horses.EquippedHorseId == "" then
			horses = DataUtility.server.get(player, "Horses")
		end

		local currentHorse = HorseService.GetPlayerHorse(player)
		return currentHorse, "AlreadyGranted"
	end

	if not hasAnyHorse then
		local starterHorseId = HorseCatalog.RollRouletteHorseId()
		local starterHorse, starterError = HorseService.CreateHorseForPlayer(player, starterHorseId, {
			Source = "StarterGrant",
			IsStarterGrant = true,
			EquipOnGrant = true,
		})

		if not starterHorse then
			return nil, starterError or "StarterGrantFailed"
		end

		local revealPayload = build_horse_reveal_payload(starterHorse)
		if revealPayload then
			DataUtility.server.set(player, "Progression.PendingHorseReveal", revealPayload)
		end
	end

	progression.FirstHorseGranted = true
	DataUtility.server.set(player, "Progression", progression)

	local updatedHorses = DataUtility.server.get(player, "Horses")
	local updatedStable = DataUtility.server.get(player, "Stable")
	if updatedHorses and updatedStable and ensure_stable_state(updatedStable, updatedHorses) then
		save_stable(player, updatedStable)
	end

	local currentHorse = HorseService.GetPlayerHorse(player)
	if not currentHorse then
		return nil, "Granted"
	end

	return currentHorse, "Granted"
end

function HorseService.BuyStableSlot(player: Player, slotName: string): (boolean, string, number?)
	if not is_valid_slot_name(slotName) then
		return false, "InvalidSlot", nil
	end

	if slotName == PRIMARY_HORSE_SLOT_NAME then
		return false, "StarterSlotAlwaysOwned", nil
	end

	local slotPrice = get_slot_purchase_price(slotName)
	if type(slotPrice) ~= "number" or slotPrice <= 0 then
		return false, "SlotNotPurchasable", nil
	end

	local horses = DataUtility.server.get(player, "Horses")
	local stable = DataUtility.server.get(player, "Stable")
	if not horses or not stable then
		return false, "DataUnavailable", nil
	end

	local stableChanged = ensure_stable_state(stable, horses)
	local ownedStalls = get_owned_stalls(stable)
	local slotIndex = get_slot_index(slotName)
	local nextSlotName = get_next_purchasable_slot_name(ownedStalls)

	if stableChanged then
		save_stable(player, stable)
	end

	if not slotIndex then
		return false, "InvalidSlot", nil
	end

	if slotIndex <= ownedStalls then
		return false, "SlotAlreadyOwned", ownedStalls
	end

	if slotName ~= nextSlotName then
		return false, "PreviousSlotRequired", ownedStalls
	end

	local currentHorseshoes = DataUtility.server.get(player, "Currencies.Horseshoes") or 0
	if currentHorseshoes < slotPrice then
		return false, "NotEnoughHorseshoes", ownedStalls
	end

	stable.OwnedStalls = math.min(
		ownedStalls + 1,
		StableDictionary.MaxOwnedStalls or #StableDictionary.HorseSlotOrder
	)

	if ensure_stable_state(stable, horses) then
		-- ensure_stable_state may auto-fill newly unlocked slots with already owned horses.
	end

	DataUtility.server.set(player, "Currencies.Horseshoes", currentHorseshoes - slotPrice)
	save_stable(player, stable)
	SoundUtility.PlayGameSFXForPlayer(player, "MoneyGet")

	return true, slotName, stable.OwnedStalls
end

function HorseService.ClearPlotHorses(plot: Instance): (boolean, string)
	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return false, "HorseFolderMissing"
	end

	for _, slotFolder: Instance in horseFolder:GetChildren() do
		clear_visual_horse_from_slot(slotFolder, true)
	end

	return true, "Cleared"
end

function HorseService.SyncPlotHorses(player: Player, plot: Instance): (boolean, string)
	local horses = DataUtility.server.get(player, "Horses")
	local stable = DataUtility.server.get(player, "Stable")

	if not horses or not stable then
		return false, "DataUnavailable"
	end

	local stableChanged = ensure_stable_state(stable, horses)
	if stableChanged then
		save_stable(player, stable)
	end

	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return false, "HorseFolderMissing"
	end

	local ownedStalls = get_owned_stalls(stable)
	local horseSlots = stable.HorseSlots or {}
	local ownedHorses = horses.Owned or {}

	for slotIndex, slotName: string in StableDictionary.HorseSlotOrder do
		local slotFolder = horseFolder:FindFirstChild(slotName)
		if slotFolder then
			local horseId = slotIndex <= ownedStalls and horseSlots[slotName] or ""
			local horse = horseId ~= "" and ownedHorses[horseId] or nil

			-- A released (or temporarily mounted) horse lives in another container
			-- under HorseFolder. Do not recreate a duplicate in its stable slot when
			-- needs/status data is saved while that live visual is away.
			local activeVisual = horse and find_active_visual_outside_slot(horseFolder, slotFolder, horseId) or nil
			if horse and activeVisual then
				clear_visual_horse_from_slot(slotFolder)
				apply_visual_horse_metadata(activeVisual, horse)
				HorseSaddleVisualService.Sync(activeVisual, horse)
			else
				sync_visual_horse_in_slot(slotFolder, horse)
			end
		end
	end

	return true, "Synced"
end

function HorseService.RefreshHorseStatuses(player: Player, horseId: string?): (boolean, string)
	local horses = DataUtility.server.get(player, "Horses")
	return refresh_owned_horse_statuses(player, horses, horseId)
end

function HorseService.GetEffectiveMovement(horse)
	return HorseEquipmentUtility.GetEffectiveMovement(horse)
end

function HorseService.SetHorseNature(player: Player, horseId: string, natureId: string, source: string?)
	local horses = DataUtility.server.get(player, "Horses")
	local owned = horses and horses.Owned
	local horse = owned and owned[horseId]
	if not horse then
		return nil, "HorseNotOwned"
	end

	if not NatureCatalog.GetDefinition(natureId) then
		return nil, "UnknownNatureId"
	end

	NatureCatalog.SetHorseNature(horse, natureId, source or "NatureRoulette", os.time())
	DataUtility.server.set(player, "Horses", horses)
	return build_horse_summary(horse, horses.EquippedHorseId, os.time()), "NatureUpdated"
end

function HorseService.StartStatusDecayLoop(): ()
	if statusDecayLoopStarted then
		return
	end

	statusDecayLoopStarted = true

	task.spawn(function()
		while statusDecayLoopStarted do
			task.wait(STATUS_UPDATE_INTERVAL_SECONDS)

			for _, player: Player in Players:GetPlayers() do
				HorseService.RefreshHorseStatuses(player)
			end
		end
	end)
end

function HorseService.RecordRaceEntry(player, horseId)
	local horses, owned = get_owned_horses_state(player)
	if not horses or not owned or not owned[horseId] then
		return false, "HorseNotOwned"
	end

	local horse = owned[horseId]
	horse.Stats = horse.Stats or {}
	horse.Stats.RacesEntered = (horse.Stats.RacesEntered or 0) + 1
	owned[horseId] = horse
	horses.Owned = owned

	DataUtility.server.set(player, "Horses", horses)

	local totalRacesEntered = (DataUtility.server.get(player, "Stats.TotalRacesEntered") or 0) + 1
	DataUtility.server.set(player, "Stats.TotalRacesEntered", totalRacesEntered)

	local raceStats = DataUtility.server.get(player, "Race")
	if raceStats then
		raceStats.RacesEntered = (raceStats.RacesEntered or 0) + 1
		raceStats.LastRaceAt = os.time()
		DataUtility.server.set(player, "Race", raceStats)
	end

	return true, build_horse_summary(horse, horses.EquippedHorseId)
end

function HorseService.RecordRaceWin(player, horseId, finishTimeMs, rewardAmount)
	local horses, owned = get_owned_horses_state(player)
	if not horses or not owned or not owned[horseId] then
		return false, "HorseNotOwned"
	end

	local horse = owned[horseId]
	horse.Stats = horse.Stats or {}
	horse.Stats.RacesWon = (horse.Stats.RacesWon or 0) + 1

	local currentBestTime = horse.Stats.BestRaceTimeMs or 0
	if finishTimeMs and finishTimeMs > 0 and (currentBestTime <= 0 or finishTimeMs < currentBestTime) then
		horse.Stats.BestRaceTimeMs = finishTimeMs
	end

	owned[horseId] = horse
	horses.Owned = owned
	DataUtility.server.set(player, "Horses", horses)

	local totalRaceWins = (DataUtility.server.get(player, "Stats.TotalRaceWins") or 0) + 1
	DataUtility.server.set(player, "Stats.TotalRaceWins", totalRaceWins)

	local raceStats = DataUtility.server.get(player, "Race")
	if raceStats then
		raceStats.RacesWon = (raceStats.RacesWon or 0) + 1
		raceStats.LastRaceAt = os.time()

		local currentBestRaceTime = raceStats.BestRaceTimeMs or 0
		if finishTimeMs and finishTimeMs > 0 and (currentBestRaceTime <= 0 or finishTimeMs < currentBestRaceTime) then
			raceStats.BestRaceTimeMs = finishTimeMs
		end

		DataUtility.server.set(player, "Race", raceStats)
	end

	return true, build_horse_summary(horse, horses.EquippedHorseId)
end

function HorseService.RecordRacePlacement(player, horseId, placement, participantCount, rewardAmount)
	local horses, owned = get_owned_horses_state(player)
	if not horses or not owned or not owned[horseId] then
		return false, "HorseNotOwned"
	end

	local horse = owned[horseId]
	local now = os.time()
	HorseCareService.RefreshHorse(horse, now)

	add_happiness_to_horse(
		horse,
		compute_race_happiness_gain(placement, participantCount),
		placement == 1 and "Thrilled" or "Proud"
	)

	owned[horseId] = horse
	horses.Owned = owned
	DataUtility.server.set(player, "Horses", horses)

	local raceStats = DataUtility.server.get(player, "Race")
	if raceStats then
		raceStats.TotalRewardsEarned = (raceStats.TotalRewardsEarned or 0) + math.max(0, rewardAmount or 0)
		DataUtility.server.set(player, "Race", raceStats)
	end

	return true, build_horse_summary(horse, horses.EquippedHorseId, now)
end

------------------//INIT
return HorseService
