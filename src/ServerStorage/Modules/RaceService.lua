local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local Net = require(Libraries:WaitForChild("Net"))
local RaceConfig = require(GameData:WaitForChild("RaceConfig"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseService"))
local InventoryService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("InventoryServer"))
local QuestService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("QuestService"))
local RaceStateEvent = Net.Event.RaceState
local RaceActionFunction = Net.Function.RaceAction

local RaceService = {}

local initialized = false
local activeRound = nil
local hasWarnedAboutTrack = false

local HORSE_COLORS = {
	american_paint_horse = {
		Body = Color3.fromRGB(172, 131, 102),
		Mane = Color3.fromRGB(84, 58, 43),
	},
	andalusian = {
		Body = Color3.fromRGB(180, 184, 191),
		Mane = Color3.fromRGB(104, 108, 116),
	},
	friesian = {
		Body = Color3.fromRGB(42, 44, 50),
		Mane = Color3.fromRGB(15, 16, 20),
	},
	lipizzaner = {
		Body = Color3.fromRGB(225, 227, 232),
		Mane = Color3.fromRGB(169, 172, 180),
	},
	quarter_horse = {
		Body = Color3.fromRGB(154, 107, 76),
		Mane = Color3.fromRGB(80, 49, 34),
	},
	american_saddlebred = {
		Body = Color3.fromRGB(126, 80, 57),
		Mane = Color3.fromRGB(44, 28, 19),
	},
	starter_meadow_bay = {
		Body = Color3.fromRGB(142, 101, 70),
		Mane = Color3.fromRGB(57, 37, 25),
	},
	starter_dusty_chestnut = {
		Body = Color3.fromRGB(167, 95, 54),
		Mane = Color3.fromRGB(87, 43, 22),
	},
	starter_moon_gray = {
		Body = Color3.fromRGB(170, 176, 184),
		Mane = Color3.fromRGB(98, 103, 109),
	},
	starter_midnight_black = {
		Body = Color3.fromRGB(43, 45, 52),
		Mane = Color3.fromRGB(17, 18, 22),
	},
	default = {
		Body = Color3.fromRGB(124, 93, 72),
		Mane = Color3.fromRGB(56, 39, 29),
	},
}

local function extract_rotation(cframe)
	return CFrame.fromMatrix(Vector3.zero, cframe.XVector, cframe.YVector, cframe.ZVector)
end

local function round_to_tenths(value)
	return math.floor(value * 10 + 0.5) / 10
end

local function make_round_id()
	return ("race_%d_%d"):format(os.time(), math.random(1000, 9999))
end

local function get_track_assets()
	local raceFolder = Workspace:FindFirstChild("Race")
	if not raceFolder then
		return nil, "RaceFolderMissing"
	end

	local positionsFolder = raceFolder:FindFirstChild("Positions")
	if not positionsFolder then
		return nil, "PositionsFolderMissing"
	end

	local cameraReference = raceFolder:FindFirstChild("Camera")
	if not cameraReference or (not cameraReference:IsA("BasePart") and not cameraReference:IsA("Camera")) then
		return nil, "CameraMissing"
	end

	local horsesFolder = raceFolder:FindFirstChild("Horses")
	if not horsesFolder then
		horsesFolder = Instance.new("Folder")
		horsesFolder.Name = "Horses"
		horsesFolder.Parent = raceFolder
	end

	local slots = {}
	for _, child in ipairs(positionsFolder:GetChildren()) do
		if child:IsA("BasePart") then
			slots[#slots + 1] = child
		end
	end

	table.sort(slots, function(a, b)
		local aValue = tonumber(a.Name)
		local bValue = tonumber(b.Name)

		if aValue and bValue then
			return aValue < bValue
		end

		return a.Name < b.Name
	end)

	if #slots == 0 then
		return nil, "NoSlotsFound"
	end

	return {
		RaceFolder = raceFolder,
		HorsesFolder = horsesFolder,
		Slots = slots,
		CameraCFrame = cameraReference.CFrame,
	}, nil
end

local function warn_missing_track(reason)
	if hasWarnedAboutTrack then
		return
	end

	hasWarnedAboutTrack = true
	warn(("[RaceService] race disabled until the track exists in workspace.Race (%s)"):format(reason))
end

local function get_live_participants(round)
	local live = {}

	for _, participant in ipairs(round.Participants) do
		if participant.IsRemoved ~= true then
			live[#live + 1] = participant
		end
	end

	return live
end

local function get_ranked_participants(round)
	local live = get_live_participants(round)

	table.sort(live, function(a, b)
		if a.Progress == b.Progress then
			return a.JoinedAt < b.JoinedAt
		end

		return a.Progress > b.Progress
	end)

	return live
end

local function get_round_participant(round, player)
	if not round then
		return nil
	end

	return round.ParticipantsByUserId[player.UserId]
end

local function build_entries_payload(round)
	local ranked = get_ranked_participants(round)
	local entries = {}

	for index, participant in ipairs(ranked) do
		entries[#entries + 1] = {
			UserId = participant.Player.UserId,
			PlayerName = participant.Player.Name,
			HorseId = participant.HorseId,
			HorseName = participant.HorseSummary.Name,
			CatalogId = participant.HorseSummary.CatalogId,
			PlaceholderModelKey = participant.HorseSummary.PlaceholderModelKey,
			SlotIndex = participant.SlotIndex,
			Progress = participant.Progress,
			Distance = RaceConfig.RaceDistance,
			VisualSpeed = participant.SegmentTargetSpeed or participant.BaseSpeed,
			SegmentIndex = math.floor((participant.SegmentStartProgress or 0) / RaceConfig.SegmentLength),
			Rank = index,
		}
	end

	return entries
end

local function get_placement_reward(placement)
	local configuredReward = RaceConfig.PlacementRewards and RaceConfig.PlacementRewards[placement]
		or RaceConfig.ParticipationReward
	local items = {}

	for _, itemReward in ipairs(configuredReward and configuredReward.Items or {}) do
		local amount = math.max(0, math.floor(tonumber(itemReward.Amount) or 0))
		if amount > 0 and ToolItemCatalog.GetItemDefinition(itemReward.ItemId) then
			items[#items + 1] = {
				ItemId = itemReward.ItemId,
				Amount = amount,
			}
		end
	end

	return {
		Horseshoes = math.max(0, math.floor(tonumber(configuredReward and configuredReward.Horseshoes) or 0)),
		Items = items,
	}
end

local function grant_placement_reward(participant, reward)
	local horseshoes = reward.Horseshoes or 0
	if horseshoes > 0 then
		local currentHorseshoes = DataUtility.server.get(participant.Player, "Currencies.Horseshoes") or 0
		DataUtility.server.set(participant.Player, "Currencies.Horseshoes", currentHorseshoes + horseshoes)
	end

	for _, itemReward in ipairs(reward.Items or {}) do
		InventoryService.AddItemCount(participant.Player, itemReward.ItemId, itemReward.Amount)
	end
end

local function broadcast_state(payload)
	RaceStateEvent:FireAll(payload)
end

local function broadcast_queue_update(round)
	broadcast_state({
		Kind = "QueueUpdated",
		RoundId = round.Id,
		ParticipantCount = #get_live_participants(round),
		MaxParticipants = round.MaxParticipants,
		SecondsRemaining = math.max(0, round.InviteEndsAt - os.clock()),
		CameraCFrame = round.Assets.CameraCFrame,
		Entries = build_entries_payload(round),
	})
end

local function broadcast_race_status(round)
	broadcast_state({
		Kind = "RaceStatus",
		RoundId = round.Id,
		ParticipantCount = #get_live_participants(round),
		Distance = RaceConfig.RaceDistance,
		Entries = build_entries_payload(round),
	})
end

local function create_part(parent, name, size, color, cframe)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CFrame = cframe
	part.Parent = parent
	return part
end

local function create_intro_tag(adornee, player)
	if not adornee or (not adornee:IsA("BasePart") and not adornee:IsA("Attachment")) then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RaceTag"
	billboard.Size = UDim2.fromOffset(144, 46)
	billboard.StudsOffset = Vector3.new(0, 6.7, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 220
	billboard.Adornee = adornee

	local holder = Instance.new("Frame")
	holder.Name = "Holder"
	holder.BackgroundColor3 = Color3.fromRGB(37, 28, 20)
	holder.BackgroundTransparency = 0.08
	holder.BorderSizePixel = 0
	holder.Size = UDim2.fromScale(1, 1)
	holder.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = holder

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1
	stroke.Color = Color3.fromRGB(234, 190, 115)
	stroke.Transparency = 0.2
	stroke.Parent = holder

	local portrait = Instance.new("ImageLabel")
	portrait.Name = "PlayerPortrait"
	portrait.BackgroundColor3 = Color3.fromRGB(91, 68, 48)
	portrait.BorderSizePixel = 0
	portrait.Position = UDim2.fromOffset(4, 4)
	portrait.Size = UDim2.fromOffset(38, 38)
	portrait.Parent = holder

	local portraitCorner = Instance.new("UICorner")
	portraitCorner.CornerRadius = UDim.new(1, 0)
	portraitCorner.Parent = portrait

	local playerLabel = Instance.new("TextLabel")
	playerLabel.Name = "ItemNameTX"
	playerLabel.BackgroundTransparency = 1
	playerLabel.Size = UDim2.new(1, -52, 1, 0)
	playerLabel.Position = UDim2.fromOffset(48, 0)
	playerLabel.Font = Enum.Font.GothamBold
	playerLabel.TextSize = 13
	playerLabel.TextColor3 = Color3.fromRGB(255, 244, 226)
	playerLabel.TextTruncate = Enum.TextTruncate.AtEnd
	playerLabel.TextXAlignment = Enum.TextXAlignment.Left
	playerLabel.Text = player and player.Name or "Player"
	playerLabel.Parent = holder

	billboard.Parent = Workspace.Terrain
	if player then
		task.spawn(function()
			local success, image = pcall(function()
				return Players:GetUserThumbnailAsync(player.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if success and billboard.Parent then
				portrait.Image = image
			end
		end)
	end

	return billboard
end

local function find_template_model(modelKey, raceFolder)
	if modelKey == "" then
		return nil
	end

	local candidates = {}
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if assetsFolder then
		local assetHorses = assetsFolder:FindFirstChild("Horses")
		if assetHorses then
			candidates[#candidates + 1] = assetHorses
		end
		candidates[#candidates + 1] = assetsFolder
	end

	local replicatedHorses = ReplicatedStorage:FindFirstChild("HorseModels")
	if replicatedHorses then
		candidates[#candidates + 1] = replicatedHorses
	end

	local serverHorses = ServerStorage:FindFirstChild("HorseModels")
	if serverHorses then
		candidates[#candidates + 1] = serverHorses
	end

	local templatesFolder = raceFolder:FindFirstChild("Templates")
	if templatesFolder then
		candidates[#candidates + 1] = templatesFolder
	end

	for _, folder in ipairs(candidates) do
		local candidate = folder:FindFirstChild(modelKey)
		if candidate and candidate:IsA("Model") then
			return candidate
		end
	end

	return nil
end

local function build_fallback_horse_model(horseSummary)
	local palette = HORSE_COLORS[horseSummary.CatalogId] or HORSE_COLORS.default
	local model = Instance.new("Model")
	model.Name = ("%s_RaceModel"):format(horseSummary.HorseId or horseSummary.Id)

	local root = create_part(model, "Root", Vector3.new(2.6, 3.4, 7.2), palette.Body, CFrame.new(0, 3.4, 0))
	root.Transparency = 1

	create_part(model, "Body", Vector3.new(2.4, 2.5, 6.8), palette.Body, CFrame.new(0, 3.6, 0))
	create_part(model, "Chest", Vector3.new(2.2, 2.2, 2.1), palette.Body, CFrame.new(0, 3.45, -2.15))
	create_part(model, "Neck", Vector3.new(1.3, 2.3, 1.2), palette.Body, CFrame.new(0, 4.35, -3.35) * CFrame.Angles(math.rad(-24), 0, 0))
	create_part(model, "Head", Vector3.new(1.25, 1.25, 2.1), palette.Body, CFrame.new(0, 5.05, -4.35) * CFrame.Angles(math.rad(-12), 0, 0))
	create_part(model, "Mane", Vector3.new(0.6, 2.7, 0.8), palette.Mane, CFrame.new(0, 4.55, -3.2) * CFrame.Angles(math.rad(-18), 0, 0))
	create_part(model, "Tail", Vector3.new(0.65, 2.5, 0.85), palette.Mane, CFrame.new(0, 4.05, 3.35) * CFrame.Angles(math.rad(32), 0, 0))

	local legOffsets = {
		Vector3.new(-0.7, 1.6, -2.2),
		Vector3.new(0.7, 1.6, -2.2),
		Vector3.new(-0.7, 1.6, 2.1),
		Vector3.new(0.7, 1.6, 2.1),
	}

	for index, offset in ipairs(legOffsets) do
		create_part(model, ("Leg_%d"):format(index), Vector3.new(0.55, 3.1, 0.55), palette.Mane, CFrame.new(offset))
	end

	model.PrimaryPart = root
	return model
end

local function prepare_model(model)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
		end
	end
end

local function capture_part_offsets(model)
	local pivot = model:GetPivot()
	local offsets = {}

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			offsets[descendant] = pivot:ToObjectSpace(descendant.CFrame)
		end
	end

	return offsets
end

local function build_pivot_from_progress(participant, progress)
	local startPosition = participant.StartPivot.Position
	return CFrame.new(
		startPosition.X,
		startPosition.Y,
		startPosition.Z - progress
	) * participant.StartRotation
end

local function clear_participant_tweens(participant)
	local activeTweens = participant.ActiveTweens
	if not activeTweens then
		return
	end

	for _, tween in ipairs(activeTweens) do
		tween:Cancel()
	end

	participant.ActiveTweens = {}
end

local function destroy_intro_tag(participant)
	if participant.IntroTag and participant.IntroTag.Parent then
		participant.IntroTag:Destroy()
	end

	participant.IntroTag = nil
end

local function play_segment_tweens(participant)
	clear_participant_tweens(participant)

	local segmentDistance = math.max(0.001, participant.SegmentEndProgress - participant.SegmentStartProgress)
	local averageSpeed = math.max(0.1, (participant.SegmentStartSpeed + participant.SegmentTargetSpeed) * 0.5)
	local duration = math.max(0.05, segmentDistance / averageSpeed)

	participant.SegmentDuration = duration
	participant.SegmentStartedAt = os.clock()
end

local function get_aligned_slot_pivot(model, slot)
	local pivot = model:GetPivot()
	local boxCFrame, boxSize = model:GetBoundingBox()
	local boxOffset = pivot:ToObjectSpace(boxCFrame)
	local slotPosition = slot.Position + Vector3.new(0, slot.Size.Y * 0.5 + boxSize.Y * 0.5, 0)
	local desiredBoxCFrame = CFrame.new(slotPosition) * extract_rotation(slot.CFrame)
	return desiredBoxCFrame * boxOffset:Inverse()
end

local function create_race_model(round, horseSummary)
	local template = find_template_model(horseSummary.PlaceholderModelKey or "", round.Assets.RaceFolder)
	local model

	if template then
		model = template:Clone()
		model.Name = ("%s_RaceModel"):format(horseSummary.Id)
	else
		model = build_fallback_horse_model(horseSummary)
	end

	prepare_model(model)
	return model
end

local function compute_base_speed(horseSummary)
	local baseSpeed = RaceConfig.BaseSpeed
	baseSpeed += ((horseSummary.RaceAffinity or 0.5) - 0.5) * RaceConfig.AffinityScale
	baseSpeed += ((horseSummary.SprintSpeed or 24) - 24) * RaceConfig.SprintScale
	baseSpeed += ((horseSummary.Acceleration or 0.8) - 0.8) * RaceConfig.AccelerationScale
	baseSpeed += ((horseSummary.Stamina or 100) - 100) * RaceConfig.StaminaScale
	return math.clamp(baseSpeed, RaceConfig.MinSpeed + 0.25, RaceConfig.MaxSpeed - 0.25)
end

local function get_race_condition_segment_bonus(participant)
	local conditionPercent = math.clamp(tonumber(participant.RaceConditionPercent) or 50, 0, 100)
	local minimumPercent = math.clamp(tonumber(RaceConfig.RaceConditionMinimumPercent) or 50, 0, 99)
	local conditionAlpha = math.clamp((conditionPercent - minimumPercent) / (100 - minimumPercent), 0, 1)
	local minimumChance = math.clamp(tonumber(RaceConfig.RaceConditionFastChanceAtMinimum) or 0, 0, 1)
	local maximumChance = math.clamp(tonumber(RaceConfig.RaceConditionFastChanceAtMaximum) or minimumChance, minimumChance, 1)
	local fastSegmentChance = minimumChance + ((maximumChance - minimumChance) * conditionAlpha)

	if math.random() <= fastSegmentChance then
		return math.max(0, tonumber(RaceConfig.RaceConditionFastSegmentBonus) or 0)
	end

	return 0
end

local function compute_target_speed(round, participant)
	local ranked = get_ranked_participants(round)
	local rank = #ranked
	local leaderProgress = ranked[1] and ranked[1].Progress or participant.Progress

	for index, entry in ipairs(ranked) do
		if entry == participant then
			rank = index
			break
		end
	end

	local total = math.max(1, #ranked)
	local midpoint = (total + 1) * 0.5
	local rankBias = (rank - midpoint) * RaceConfig.RankBiasStep
	local catchupBonus = math.clamp((leaderProgress - participant.Progress) * RaceConfig.CatchupBonusPerStud, 0, RaceConfig.MaxCatchupBonus)
	local randomSwing = (math.random() * 2 - 1) * RaceConfig.SegmentVariance
	local finishKick = (RaceConfig.RaceDistance - participant.Progress) <= 40 and RaceConfig.FinishKick or 0
	local conditionBonus = get_race_condition_segment_bonus(participant)

	return math.clamp(
		participant.BaseSpeed + rankBias + catchupBonus + randomSwing + finishKick + conditionBonus,
		RaceConfig.MinSpeed,
		RaceConfig.MaxSpeed
	)
end

local function advance_segment(round, participant)
	participant.SegmentStartProgress = participant.SegmentEndProgress
	participant.SegmentEndProgress = math.min(RaceConfig.RaceDistance, participant.SegmentStartProgress + RaceConfig.SegmentLength)
	participant.SegmentStartSpeed = participant.SegmentTargetSpeed
	participant.SegmentTargetSpeed = compute_target_speed(round, participant)
	play_segment_tweens(participant)
end

local function destroy_participant_model(participant)
	clear_participant_tweens(participant)
	destroy_intro_tag(participant)

	if participant.Model then
		participant.Model:Destroy()
		participant.Model = nil
	end
end

local function remove_participant(round, player)
	local participant = get_round_participant(round, player)
	if not participant then
		return false
	end

	participant.IsRemoved = true
	round.ParticipantsByUserId[player.UserId] = nil
	round.UsedSlotNames[participant.Slot.Name] = nil
	destroy_participant_model(participant)

	for index, entry in ipairs(round.Participants) do
		if entry == participant then
			table.remove(round.Participants, index)
			break
		end
	end

	return true
end

local function cleanup_round(round, reason)
	if round.Connection then
		round.Connection:Disconnect()
		round.Connection = nil
	end

	for _, participant in ipairs(round.Participants) do
		destroy_participant_model(participant)
	end

	round.Participants = {}
	round.ParticipantsByUserId = {}
	round.UsedSlotNames = {}

	if activeRound == round then
		activeRound = nil
	end

	broadcast_state({
		Kind = "Reset",
		RoundId = round.Id,
		Reason = reason or "Reset",
	})
end

local function get_available_slot(round)
	for index, slot in ipairs(round.Assets.Slots) do
		if not round.UsedSlotNames[slot.Name] then
			return slot, index
		end
	end

	return nil, nil
end

local function create_participant(round, player, horseSummary)
	local slot, slotIndex = get_available_slot(round)
	if not slot then
		return nil, "NoSlotAvailable"
	end

	local model = create_race_model(round, horseSummary)
	local slotPivot = get_aligned_slot_pivot(model, slot)
	model:PivotTo(slotPivot)

	local participant = {
		Player = player,
		JoinedAt = os.clock(),
		HorseId = horseSummary.Id,
		HorseSummary = horseSummary,
		Model = model,
		Slot = slot,
		SlotIndex = slotIndex,
		StartPivot = slotPivot,
		StartRotation = extract_rotation(slotPivot),
		Progress = 0,
		BaseSpeed = compute_base_speed(horseSummary),
		RaceConditionPercent = horseSummary.RaceConditionPercent,
		SegmentStartProgress = 0,
		SegmentEndProgress = math.min(RaceConfig.SegmentLength, RaceConfig.RaceDistance),
		SegmentStartSpeed = 0,
		SegmentTargetSpeed = 0,
		SegmentDuration = 0,
		SegmentStartedAt = 0,
		PartOffsets = capture_part_offsets(model),
		ActiveTweens = {},
		IntroTag = create_intro_tag(slot, player),
		IsRemoved = false,
	}

	participant.SegmentStartSpeed = participant.BaseSpeed * 0.88
	participant.SegmentTargetSpeed = math.clamp(participant.BaseSpeed + 1.1, RaceConfig.MinSpeed, RaceConfig.MaxSpeed)

	round.UsedSlotNames[slot.Name] = true
	return participant, nil
end

local function finish_round(round, winnerParticipant)
	if activeRound ~= round or round.State ~= "Racing" then
		return
	end

	round.State = "Finished"

	if round.Connection then
		round.Connection:Disconnect()
		round.Connection = nil
	end

	local finishTimeMs = math.floor((os.clock() - round.RaceStartedAt) * 1000 + 0.5)
	local rankedParticipants = get_ranked_participants(round)
	local rankedParticipantCount = #rankedParticipants
	local rewardsByUserId = {}
	for placement, participant in ipairs(rankedParticipants) do
		local reward = get_placement_reward(placement)
		grant_placement_reward(participant, reward)
		rewardsByUserId[participant.Player.UserId] = reward
		HorseService.RecordRacePlacement(participant.Player, participant.HorseId, placement, rankedParticipantCount, reward.Horseshoes)

		local completedArenaRuns = (DataUtility.server.get(participant.Player, "Arena.RunsCompleted") or 0) + 1
		DataUtility.server.set(participant.Player, "Arena.RunsCompleted", completedArenaRuns)
		QuestService.IncrementStat(participant.Player, "Stats.TotalArenaRuns", 1)

		if participant == winnerParticipant then
			HorseService.RecordRaceWin(participant.Player, participant.HorseId, finishTimeMs, reward.Horseshoes)
		end
	end

	local resultEntries = build_entries_payload(round)
	for _, entry in ipairs(resultEntries) do
		entry.Reward = rewardsByUserId[entry.UserId]
	end
	local winnerReward = rewardsByUserId[winnerParticipant.Player.UserId] or get_placement_reward(1)

	broadcast_state({
		Kind = "Result",
		RoundId = round.Id,
		Duration = RaceConfig.ResultDuration,
		Winner = {
			UserId = winnerParticipant.Player.UserId,
			PlayerName = winnerParticipant.Player.Name,
			HorseId = winnerParticipant.HorseId,
			HorseName = winnerParticipant.HorseSummary.Name,
			SlotIndex = winnerParticipant.SlotIndex,
			FinishTimeMs = finishTimeMs,
			Reward = winnerReward.Horseshoes,
			Items = winnerReward.Items,
		},
		Entries = resultEntries,
		RewardsByUserId = rewardsByUserId,
	})

	task.delay(RaceConfig.ResultDuration, function()
		if activeRound == round then
			cleanup_round(round, "Completed")
		end
	end)
end

local function begin_race(round)
	if activeRound ~= round or round.State ~= "Invite" then
		return
	end

	if #round.Participants == 0 then
		cleanup_round(round, "NoParticipants")
		return
	end

	round.State = "Racing"
	round.RaceStartedAt = os.clock()
	round.LastStatusAt = 0

	for _, participant in ipairs(round.Participants) do
		local playedArenaRuns = (DataUtility.server.get(participant.Player, "Arena.RunsPlayed") or 0) + 1
		DataUtility.server.set(participant.Player, "Arena.RunsPlayed", playedArenaRuns)
		HorseService.RecordRaceEntry(participant.Player, participant.HorseId)
		participant.Progress = 0
		participant.SegmentStartProgress = 0
		participant.SegmentEndProgress = math.min(RaceConfig.SegmentLength, RaceConfig.RaceDistance)
		participant.SegmentStartSpeed = participant.BaseSpeed * 0.88
		participant.SegmentTargetSpeed = compute_target_speed(round, participant)
		play_segment_tweens(participant)

		task.delay(RaceConfig.IntroTagDuration, function()
			destroy_intro_tag(participant)
		end)
	end

	broadcast_state({
		Kind = "RaceStarted",
		RoundId = round.Id,
		CameraCFrame = round.Assets.CameraCFrame,
		CameraSpeed = RaceConfig.CameraSpeed,
		Distance = RaceConfig.RaceDistance,
		Entries = build_entries_payload(round),
	})

	round.Connection = RunService.Heartbeat:Connect(function()
		if activeRound ~= round or round.State ~= "Racing" then
			return
		end

		if #round.Participants == 0 then
			cleanup_round(round, "NoParticipants")
			return
		end

		for _, participant in ipairs(round.Participants) do
			if participant.IsRemoved ~= true then
				local segmentDuration = math.max(0.001, participant.SegmentDuration or 0.001)
				local segmentAlpha = math.clamp(
					(os.clock() - (participant.SegmentStartedAt or os.clock())) / segmentDuration,
					0,
					1
				)

				participant.Progress = participant.SegmentStartProgress
					+ ((participant.SegmentEndProgress - participant.SegmentStartProgress) * segmentAlpha)

				while segmentAlpha >= 1
					and participant.SegmentEndProgress < RaceConfig.RaceDistance do
					advance_segment(round, participant)

					segmentDuration = math.max(0.001, participant.SegmentDuration or 0.001)
					segmentAlpha = math.clamp(
						(os.clock() - (participant.SegmentStartedAt or os.clock())) / segmentDuration,
						0,
						1
					)
					participant.Progress = participant.SegmentStartProgress
						+ ((participant.SegmentEndProgress - participant.SegmentStartProgress) * segmentAlpha)
				end

				if participant.Progress >= RaceConfig.RaceDistance then
					finish_round(round, participant)
					return
				end
			end
		end

		if os.clock() - round.LastStatusAt >= RaceConfig.StatusBroadcastInterval then
			round.LastStatusAt = os.clock()
			broadcast_race_status(round)
		end
	end)
end

local function open_invite_round()
	if activeRound then
		return
	end

	local assets, errorCode = get_track_assets()
	if not assets then
		warn_missing_track(errorCode)
		return
	end

	hasWarnedAboutTrack = false

	local maxParticipants = math.min(RaceConfig.MaxParticipants, #assets.Slots)
	local round = {
		Id = make_round_id(),
		State = "Invite",
		Assets = assets,
		MaxParticipants = maxParticipants,
		InviteEndsAt = os.clock() + RaceConfig.InviteDuration,
		Participants = {},
		ParticipantsByUserId = {},
		UsedSlotNames = {},
		LastStatusAt = 0,
	}

	activeRound = round

	for _, player in ipairs(Players:GetPlayers()) do
		RaceService.SyncPlayer(player)
	end

	task.delay(RaceConfig.InviteDuration, function()
		if activeRound == round and round.State == "Invite" then
			begin_race(round)
		end
	end)
end

local function invitation_loop()
	task.wait(RaceConfig.InitialInviteDelay)

	while true do
		if not activeRound then
			open_invite_round()
		end

		task.wait(RaceConfig.InviteInterval)

		while activeRound do
			task.wait(1)
		end
	end
end

function RaceService.SyncPlayer(player)
	local round = activeRound
	if not round or round.State ~= "Invite" then
		return
	end

	local horseOptions = HorseService.GetOwnedHorseSummaries(player)
	if #horseOptions == 0 then
		return
	end

	RaceStateEvent:Fire(player, {
		Kind = "InviteOpened",
		RoundId = round.Id,
		SecondsRemaining = math.max(0, round.InviteEndsAt - os.clock()),
		MaxParticipants = round.MaxParticipants,
		ParticipantCount = #get_live_participants(round),
		CameraCFrame = round.Assets.CameraCFrame,
		HorseOptions = horseOptions,
	})

	local participant = get_round_participant(round, player)
	if participant then
		RaceStateEvent:Fire(player, {
			Kind = "QueueUpdated",
			RoundId = round.Id,
			ParticipantCount = #get_live_participants(round),
			MaxParticipants = round.MaxParticipants,
			SecondsRemaining = math.max(0, round.InviteEndsAt - os.clock()),
			CameraCFrame = round.Assets.CameraCFrame,
			Entries = build_entries_payload(round),
		})
	end
end

function RaceService.HandleAction(player, payload)
	if type(payload) ~= "table" then
		return {
			Success = false,
			Code = "InvalidPayload",
		}
	end

	local round = activeRound
	if not round then
		return {
			Success = false,
			Code = "NoActiveRound",
		}
	end

	if payload.Action == "Leave" then
		if round.State ~= "Invite" then
			return {
				Success = false,
				Code = "RaceAlreadyStarted",
			}
		end

		local removed = remove_participant(round, player)
		if removed then
			broadcast_queue_update(round)
		end

		return {
			Success = removed,
			Code = removed and "LeftQueue" or "NotQueued",
			RoundId = round.Id,
		}
	end

	if payload.Action ~= "Join" then
		return {
			Success = false,
			Code = "UnknownAction",
		}
	end

	if round.State ~= "Invite" then
		return {
			Success = false,
			Code = "InviteClosed",
		}
	end

	if payload.RoundId ~= round.Id then
		return {
			Success = false,
			Code = "RoundMismatch",
		}
	end

	if os.clock() >= round.InviteEndsAt then
		return {
			Success = false,
			Code = "InviteExpired",
		}
	end

	local existingParticipant = get_round_participant(round, player)
	if existingParticipant then
		return {
			Success = true,
			Code = "AlreadyJoined",
			RoundId = round.Id,
			SlotIndex = existingParticipant.SlotIndex,
			CameraCFrame = round.Assets.CameraCFrame,
			SecondsRemaining = math.max(0, round.InviteEndsAt - os.clock()),
			ParticipantCount = #get_live_participants(round),
		}
	end

	if #round.Participants >= round.MaxParticipants then
		return {
			Success = false,
			Code = "RaceFull",
		}
	end

	local horseOptions = HorseService.GetOwnedHorseSummaries(player)
	if #horseOptions == 0 then
		return {
			Success = false,
			Code = "NoHorseOwned",
		}
	end

	local selectedHorseId = payload.HorseId
	if (selectedHorseId == nil or selectedHorseId == "") and #horseOptions == 1 then
		selectedHorseId = horseOptions[1].Id
	end

	if not selectedHorseId or selectedHorseId == "" then
		return {
			Success = false,
			Code = "HorseSelectionRequired",
			HorseOptions = horseOptions,
		}
	end

	local selectedHorseSummary = nil
	for _, horseSummary in ipairs(horseOptions) do
		if horseSummary.Id == selectedHorseId then
			selectedHorseSummary = horseSummary
			break
		end
	end

	if not selectedHorseSummary then
		return {
			Success = false,
			Code = "HorseNotOwned",
		}
	end

	local raceReadiness, readinessError = HorseService.GetRaceReadiness(player, selectedHorseId)
	if not raceReadiness then
		return {
			Success = false,
			Code = readinessError or "HorseStatusUnavailable",
		}
	end

	if raceReadiness.CanRace ~= true then
		return {
			Success = false,
			Code = "HorseNeedsTooLow",
			HorseId = selectedHorseId,
			HorseOptions = HorseService.GetOwnedHorseSummaries(player),
			BlockedStatus = raceReadiness.BlockedStatus,
			BlockedStatusDisplay = raceReadiness.BlockedStatusDisplay,
			BlockedPercent = raceReadiness.BlockedPercent,
			MinimumPercent = raceReadiness.MinimumPercent,
		}
	end

	selectedHorseSummary.PlayerName = player.Name

	local participant, createError = create_participant(round, player, selectedHorseSummary)
	if not participant then
		return {
			Success = false,
			Code = createError or "JoinFailed",
		}
	end

	round.Participants[#round.Participants + 1] = participant
	round.ParticipantsByUserId[player.UserId] = participant

	broadcast_queue_update(round)

	return {
		Success = true,
		Code = "Joined",
		RoundId = round.Id,
		SlotIndex = participant.SlotIndex,
		Horse = selectedHorseSummary,
		CameraCFrame = round.Assets.CameraCFrame,
		SecondsRemaining = math.max(0, round.InviteEndsAt - os.clock()),
		ParticipantCount = #get_live_participants(round),
	}
end

function RaceService.Init()
	if initialized then
		return
	end

	RaceActionFunction:Respond(function(player, payload)
		return RaceService.HandleAction(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player)
		local round = activeRound
		if not round then
			return
		end

		local removed = remove_participant(round, player)
		if not removed then
			return
		end

		if round.State == "Invite" then
			broadcast_queue_update(round)
			return
		end

		if (round.State == "Racing" or round.State == "Finished") and #round.Participants == 0 then
			cleanup_round(round, "NoParticipants")
		else
			broadcast_race_status(round)
		end
	end)

	task.spawn(invitation_loop)
	initialized = true
end

return RaceService
