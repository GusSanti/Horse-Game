local Workspace = game:GetService("Workspace")

local NPCS_FOLDER_NAME = "Npcs"
local DEFAULT_FADE_TIME = 0.15

local NPC_IDLE_ANIMATIONS = {
    Chef = "122382477972816",
    Cowboy = "92691472480288",
    Doctor = "99194435491936",
    Farmer = "122382477972816",
    Noob = "92691472480288",
}

local R6_PART_NAMES = {
	"Head",
	"Torso",
	"HumanoidRootPart",
	"Left Arm",
	"Right Arm",
	"Left Leg",
	"Right Leg",
}

local tracksByNpc = {}
local animationsByNpc = {}
local ancestryConnectionsByNpc = {}

local function normalize_key(value)
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function normalize_animation_id(animationId)
	if type(animationId) == "number" then
		return ("rbxassetid://%d"):format(animationId)
	end

	if type(animationId) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(animationId, "^%s*(.-)%s*$", "%1")
	if trimmedValue == "" then
		return nil
	end

	if string.find(trimmedValue, "rbxassetid://", 1, true) == 1 then
		return trimmedValue
	end

	return "rbxassetid://" .. trimmedValue
end

local function get_idle_animation_id(npc)
	local npcKey = normalize_key(npc and npc.Name)
	if not npcKey then
		return nil
	end

	for npcName, animationId in pairs(NPC_IDLE_ANIMATIONS) do
		if normalize_key(npcName) == npcKey then
			return normalize_animation_id(animationId)
		end
	end

	return nil
end

local function find_r6_humanoid(npc)
	local humanoid = npc:FindFirstChildOfClass("Humanoid") or npc:FindFirstChildWhichIsA("Humanoid", true)
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then
		return nil
	end

	for _, partName in ipairs(R6_PART_NAMES) do
		local part = npc:FindFirstChild(partName)
		if not part or not part:IsA("BasePart") then
			return nil
		end
	end

	return humanoid
end

local function ensure_animator(humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function cleanup_npc(npc)
	local track = tracksByNpc[npc]
	if track then
		pcall(function()
			track:Stop(DEFAULT_FADE_TIME)
			track:Destroy()
		end)
		tracksByNpc[npc] = nil
	end

	local animation = animationsByNpc[npc]
	if animation then
		animation:Destroy()
		animationsByNpc[npc] = nil
	end

	local ancestryConnection = ancestryConnectionsByNpc[npc]
	if ancestryConnection then
		ancestryConnection:Disconnect()
		ancestryConnectionsByNpc[npc] = nil
	end
end

local function play_idle_animation(npc)
	if not npc or not npc:IsA("Model") or tracksByNpc[npc] then
		return
	end

	local animationId = get_idle_animation_id(npc)
	if not animationId then
		return
	end

	local humanoid = find_r6_humanoid(npc)
	if not humanoid then
		warn(("[NpcIdleAnimations] NPC '%s' is not a valid R6 dummy."):format(npc.Name))
		return
	end

	local animation = Instance.new("Animation")
	animation.Name = npc.Name .. "IdleAnimation"
	animation.AnimationId = animationId

	local success, track = pcall(function()
		return ensure_animator(humanoid):LoadAnimation(animation)
	end)

	if not success or not track then
		animation:Destroy()
		warn(("[NpcIdleAnimations] failed to load R6 idle animation for NPC '%s'."):format(npc.Name))
		return
	end

	track.Looped = true
	track.Priority = Enum.AnimationPriority.Idle
	track:Play(DEFAULT_FADE_TIME, 1, 1)

	tracksByNpc[npc] = track
	animationsByNpc[npc] = animation
	ancestryConnectionsByNpc[npc] = npc.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanup_npc(npc)
		end
	end)
end

local function configure_npcs(npcsFolder)
	for _, npc in ipairs(npcsFolder:GetChildren()) do
		play_idle_animation(npc)
	end
end

local npcsFolder = Workspace:WaitForChild(NPCS_FOLDER_NAME)
configure_npcs(npcsFolder)

npcsFolder.ChildAdded:Connect(function(child)
	task.defer(play_idle_animation, child)
end)

npcsFolder.ChildRemoved:Connect(cleanup_npc)
