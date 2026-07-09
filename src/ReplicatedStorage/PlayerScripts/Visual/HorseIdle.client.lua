------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")

------------------//CONSTANTS
local REFRESH_INTERVAL = 1

------------------//VARIABLES
local localPlayer: Player = Players.LocalPlayer
local modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local dictionary: Folder = modules:WaitForChild("Dictionary")
local gameData: Folder = modules:WaitForChild("GameData")

local ToolDictionary = require(dictionary:WaitForChild("ToolDictionary"))
local HorseMountConfig = require(gameData:WaitForChild("HorseMountConfig"))

local PLOT_VALUE_NAME: string = ToolDictionary.PlotValueName
local HORSE_FOLDER_NAME: string = ToolDictionary.HorseFolderName
local VISUAL_HORSE_ATTRIBUTE: string = ToolDictionary.VisualHorseAttribute
local MOUNTED_USER_ID_ATTRIBUTE: string = ToolDictionary.MountedUserIdAttribute
local IGNORE_REFRESH_ATTRIBUTE: string = ToolDictionary.IgnoreRefreshAttribute

local plotValue: ObjectValue = localPlayer:WaitForChild(PLOT_VALUE_NAME)

local plotConnections: {RBXScriptConnection} = {}
local activeAnimations: {[Instance]: any} = {}
local elapsedSinceRefresh = 0
local refreshQueued = false

------------------//FUNCTIONS
local function disconnect_all(connections: {RBXScriptConnection}): ()
	for _, connection: RBXScriptConnection in connections do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function mark_local_instance(instance: Instance): Instance
	instance:SetAttribute(IGNORE_REFRESH_ATTRIBUTE, true)
	return instance
end

local function is_horse_mounted(horseVisual: Instance): boolean
	local mountedUserId = horseVisual:GetAttribute(MOUNTED_USER_ID_ATTRIBUTE)
	return type(mountedUserId) == "number" and mountedUserId > 0
end

local function ensure_animator(controller: Instance?): Animator?
	if not controller then
		return nil
	end

	local animator = controller:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	if controller:IsA("Humanoid") or controller:IsA("AnimationController") then
		animator = mark_local_instance(Instance.new("Animator"))
		animator.Parent = controller
		return animator
	end

	return nil
end

local function get_model_animator(model: Instance?): Animator?
	if not model or not model:IsA("Model") then
		return nil
	end

	local animationController = model:FindFirstChildOfClass("AnimationController")
	if not animationController then
		animationController = model:FindFirstChildWhichIsA("AnimationController", true)
	end

	if animationController then
		return ensure_animator(animationController)
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = model:FindFirstChildWhichIsA("Humanoid", true)
	end

	if humanoid then
		return ensure_animator(humanoid)
	end

	animationController = mark_local_instance(Instance.new("AnimationController"))
	animationController.Name = "HorseStableIdleAnimationController"
	animationController.Parent = model
	return ensure_animator(animationController)
end

local function stop_idle_animation(entry, fadeTime: number?): ()
	if not entry then
		return
	end

	if entry.track then
		pcall(function()
			entry.track:Stop(fadeTime or HorseMountConfig.AnimationFadeTime or 0.12)
		end)
	end
end

local function destroy_idle_animation(horseVisual: Instance): ()
	local entry = activeAnimations[horseVisual]
	if not entry then
		return
	end

	disconnect_all(entry.connections)
	stop_idle_animation(entry, 0)

	if entry.animation then
		entry.animation:Destroy()
	end

	activeAnimations[horseVisual] = nil
end

local function destroy_all_idle_animations(): ()
	local visualsToDestroy = {}

	for horseVisual in activeAnimations do
		visualsToDestroy[#visualsToDestroy + 1] = horseVisual
	end

	for _, horseVisual in visualsToDestroy do
		destroy_idle_animation(horseVisual)
	end
end

local function should_ignore_descendant(descendant: Instance): boolean
	local current = descendant

	while current do
		if current:GetAttribute(IGNORE_REFRESH_ATTRIBUTE) == true then
			return true
		end

		current = current.Parent
	end

	return false
end

local function get_horse_visuals(): {Instance}
	local plot = plotValue.Value
	if not plot then
		return {}
	end

	local horseFolder = plot:FindFirstChild(HORSE_FOLDER_NAME)
	if not horseFolder then
		return {}
	end

	local visuals = {}

	for _, slotFolder: Instance in horseFolder:GetChildren() do
		for _, child: Instance in slotFolder:GetChildren() do
			if child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true then
				visuals[#visuals + 1] = child
			end
		end
	end

	return visuals
end

local function ensure_idle_track(entry): AnimationTrack?
	if entry.track then
		return entry.track
	end

	local horseVisual = entry.horseVisual
	if not horseVisual or not horseVisual.Parent or not horseVisual:IsA("Model") then
		return nil
	end

	local animator = get_model_animator(horseVisual)
	local animationId = HorseMountConfig.HorseIdleAnimationId
	if not animator or type(animationId) ~= "string" or animationId == "" then
		return nil
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not track then
		animation:Destroy()
		return nil
	end

	pcall(function()
		track.Priority = Enum.AnimationPriority.Idle
	end)

	pcall(function()
		track.Looped = true
	end)

	entry.animation = animation
	entry.track = track
	return track
end

local function play_idle_animation(entry): ()
	local track = ensure_idle_track(entry)
	if not track then
		return
	end

	local isPlaying = false
	pcall(function()
		isPlaying = track.IsPlaying
	end)

	if not isPlaying then
		pcall(function()
			track:Play(HorseMountConfig.AnimationFadeTime or 0.12, 1, 1)
		end)
	end

	pcall(function()
		track:AdjustWeight(1, HorseMountConfig.HorseAnimationBlendTime or HorseMountConfig.AnimationFadeTime or 0.12)
	end)

	pcall(function()
		track:AdjustSpeed(1)
	end)
end

local function sync_horse_idle_animation(horseVisual: Instance): ()
	local entry = activeAnimations[horseVisual]
	if not entry then
		entry = {
			horseVisual = horseVisual,
			connections = {},
		}

		activeAnimations[horseVisual] = entry
		entry.connections[#entry.connections + 1] = horseVisual:GetAttributeChangedSignal(MOUNTED_USER_ID_ATTRIBUTE):Connect(function()
			sync_horse_idle_animation(horseVisual)
		end)
	end

	if not horseVisual.Parent or horseVisual:GetAttribute(VISUAL_HORSE_ATTRIBUTE) ~= true then
		destroy_idle_animation(horseVisual)
		return
	end

	if not horseVisual:IsA("Model") or is_horse_mounted(horseVisual) then
		stop_idle_animation(entry)
		return
	end

	play_idle_animation(entry)
end

local function sync_idle_animations(): ()
	local visuals = get_horse_visuals()
	local activeVisuals: {[Instance]: boolean} = {}
	local visualsToDestroy = {}

	for _, horseVisual: Instance in visuals do
		activeVisuals[horseVisual] = true
		sync_horse_idle_animation(horseVisual)
	end

	for horseVisual in activeAnimations do
		if not activeVisuals[horseVisual] or not horseVisual.Parent then
			visualsToDestroy[#visualsToDestroy + 1] = horseVisual
		end
	end

	for _, horseVisual in visualsToDestroy do
		destroy_idle_animation(horseVisual)
	end
end

local function queue_refresh(): ()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(function()
		refreshQueued = false
		sync_idle_animations()
	end)
end

local function bind_plot(plot: Instance?): ()
	disconnect_all(plotConnections)

	if not plot then
		destroy_all_idle_animations()
		return
	end

	plotConnections[#plotConnections + 1] = plot.DescendantAdded:Connect(function(descendant: Instance)
		if should_ignore_descendant(descendant) then
			return
		end

		queue_refresh()
	end)

	plotConnections[#plotConnections + 1] = plot.DescendantRemoving:Connect(function(descendant: Instance)
		if should_ignore_descendant(descendant) then
			return
		end

		queue_refresh()
	end)

	queue_refresh()
end

------------------//MAIN FUNCTIONS
plotValue:GetPropertyChangedSignal("Value"):Connect(function()
	bind_plot(plotValue.Value)
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	elapsedSinceRefresh += deltaTime

	if elapsedSinceRefresh < REFRESH_INTERVAL then
		return
	end

	elapsedSinceRefresh = 0
	sync_idle_animations()
end)

------------------//INIT
bind_plot(plotValue.Value)
