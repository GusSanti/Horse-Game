--[[
====================================
        Realistic Footsteps
          Created by Ruben Roy
                  (DarkTwentyFive)
====================================

RbxCharacterSounds - DO NOT MODIFY THIS SCRIPT UNLESS YOU KNOW WHAT YOU'RE DOING

]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local FootstepsSoundGroup = game:GetService("SoundService"):WaitForChild("Footsteps")

local SOUND_DATA = {
	Climbing = {
		SoundId = "rbxasset://sounds/action_footsteps_plastic.mp3",
		Looped = true,
	},
	Died = {
		SoundId = "rbxasset://sounds/uuhhh.mp3",
	},
	FreeFalling = {
		SoundId = "rbxasset://sounds/action_falling.mp3",
		Looped = true,
	},
	GettingUp = {
		SoundId = "rbxasset://sounds/action_get_up.mp3",
	},
	Jumping = {
		SoundId = "rbxasset://sounds/action_jump.mp3",
	},
	Landing = {
		SoundId = "rbxasset://sounds/action_jump_land.mp3",
	},
	Running = {
		SoundId = '' ,
		Looped = true,
		Playing = true,
		Pitch = 1,
	},
	Splash = {
		SoundId = "rbxasset://sounds/impact_water.mp3",
	},
	Swimming = {
		SoundId = "rbxasset://sounds/action_swim.mp3",
		Looped = true,
		Pitch = 1.6,
	},
}

local function waitForFirst(...)
	local shunt = Instance.new("BindableEvent")
	local slots = {...}

	local function fire(...)
		for i = 1, #slots do
			slots[i]:Disconnect()
		end

		return shunt:Fire(...)
	end

	for i = 1, #slots do
		slots[i] = slots[i]:Connect(fire)
	end

	return shunt.Event:Wait()
end

local function map(x, inMin, inMax, outMin, outMax)
	return (x - inMin)*(outMax - outMin)/(inMax - inMin) + outMin
end

local function playSound(sound)
	sound.TimePosition = 0
	sound.Playing = true
end

local function fadeInSound(sound, targetVolume)
	sound.Volume = 0
	if not sound.Playing then
		sound.TimePosition = 0
		sound.Playing = true
	end
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Linear)
	local tween = TweenService:Create(sound, tweenInfo, {Volume = targetVolume or 0.65})
	tween:Play()
end

local function stopSound(sound)
	local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Linear)
	local tween = TweenService:Create(sound, tweenInfo, {Volume = 0})
	tween:Play()
	tween.Completed:Connect(function()
		if sound.Volume == 0 then
			sound.Playing = false
			sound.TimePosition = 0
		end
	end)
end

local function initializeSoundSystem(player, humanoid, rootPart)
	local sounds = {}

	for name, props in pairs(SOUND_DATA) do
		local existingSound = rootPart:FindFirstChild(name)
		if existingSound and existingSound:IsA("Sound") then
			existingSound:Destroy()
		end

		local sound = Instance.new("Sound")
		sound.Name = name

		sound.Archivable = false
		sound.EmitterSize = 5
		sound.MaxDistance = 150
		sound.Volume = 0.65

		for propName, propValue in pairs(props) do
			sound[propName] = propValue
		end

		sound.Parent = rootPart
		sounds[name] = sound
	end

	local playingLoopedSounds = {}

	local function stopPlayingLoopedSounds(except)
		for sound in pairs(playingLoopedSounds) do
			if sound ~= except then
				stopSound(sound)
				playingLoopedSounds[sound] = nil
			end
		end
	end

	local stateTransitions = {
		[Enum.HumanoidStateType.FallingDown] = function()
			stopPlayingLoopedSounds()
		end,

		[Enum.HumanoidStateType.GettingUp] = function()
			stopPlayingLoopedSounds()
			sounds.GettingUp.Volume = 0.65
			playSound(sounds.GettingUp)
		end,

		[Enum.HumanoidStateType.Jumping] = function()
			stopPlayingLoopedSounds()
			sounds.Jumping.Volume = 0.65
			playSound(sounds.Jumping)
		end,

		[Enum.HumanoidStateType.Swimming] = function()
			local verticalSpeed = math.abs(rootPart.Velocity.Y)
			if verticalSpeed > 0.1 then
				sounds.Splash.Volume = math.clamp(map(verticalSpeed, 100, 350, 0.28, 1), 0, 1)
				playSound(sounds.Splash)
			end
			stopPlayingLoopedSounds(sounds.Swimming)
			fadeInSound(sounds.Swimming, 0.65)
			playingLoopedSounds[sounds.Swimming] = true
		end,

		[Enum.HumanoidStateType.Freefall] = function()
			sounds.FreeFalling.Volume = 0
			stopPlayingLoopedSounds(sounds.FreeFalling)
			playingLoopedSounds[sounds.FreeFalling] = true
		end,

		[Enum.HumanoidStateType.Landed] = function()
			stopPlayingLoopedSounds()
			local verticalSpeed = math.abs(rootPart.Velocity.Y)
			if verticalSpeed > 75 then
				sounds.Landing.Volume = math.clamp(map(verticalSpeed, 50, 100, 0, 1), 0, 1)
				playSound(sounds.Landing)
			end
		end,

		[Enum.HumanoidStateType.Running] = function()
			stopPlayingLoopedSounds(sounds.Running)
			if not sounds.Running.Playing then
				sounds.Running.Volume = 0
				sounds.Running.Playing = true
			end
			playingLoopedSounds[sounds.Running] = true
		end,

		[Enum.HumanoidStateType.Climbing] = function()
			local sound = sounds.Climbing
			if math.abs(rootPart.Velocity.Y) > 0.1 then
				fadeInSound(sound, 0.65)
				stopPlayingLoopedSounds(sound)
			else
				stopPlayingLoopedSounds()
			end
			playingLoopedSounds[sound] = true
		end,

		[Enum.HumanoidStateType.Seated] = function()
			stopPlayingLoopedSounds()
		end,

		[Enum.HumanoidStateType.Dead] = function()
			stopPlayingLoopedSounds()
			sounds.Died.Volume = 0.65
			playSound(sounds.Died)
		end,
	}

	local loopedSoundUpdaters = {
		[sounds.Climbing] = function(dt, sound, vel)
			sound.Playing = vel.Magnitude > 0.1
		end,

		[sounds.FreeFalling] = function(dt, sound, vel)
			if vel.Magnitude > 75 then
				sound.Volume = math.clamp(sound.Volume + 0.9*dt, 0, 1)
			else
				sound.Volume = 0
			end
		end,

		[sounds.Running] = function(dt, sound, vel)
			local materialName = humanoid.FloorMaterial.Name
			local materialNode = FootstepsSoundGroup:FindFirstChild(materialName)

			if not materialNode then
				warn("Material não encontrado no Footsteps: " .. materialName .. " - Usando Plastic")
				materialNode = FootstepsSoundGroup:FindFirstChild("Plastic")
			end

			if materialNode then
				sound.SoundId = materialNode.SoundId
				sound.PlaybackSpeed = materialNode.PlaybackSpeed * (vel.Magnitude/20)

				local targetVolume = materialNode.Volume * (vel.Magnitude/12) * 1
				sound.Volume = sound.Volume + (targetVolume - sound.Volume) * math.min(dt * 15, 1)

				sound.EmitterSize = materialNode.Volume * (vel.Magnitude/12) * 50 * 1
			end
		end,
	}

	local stateRemap = {
		[Enum.HumanoidStateType.RunningNoPhysics] = Enum.HumanoidStateType.Running,
	}

	local activeState = stateRemap[humanoid:GetState()] or humanoid:GetState()

	local initialTransition = stateTransitions[activeState]
	if initialTransition then
		initialTransition()
	end

	local stateChangedConn = humanoid.StateChanged:Connect(function(_, state)
		state = stateRemap[state] or state

		if state ~= activeState then
			local transitionFunc = stateTransitions[state]

			if transitionFunc then
				transitionFunc()
			end

			activeState = state
		end
	end)

	local steppedConn = RunService.Stepped:Connect(function(_, worldDt)
		for sound in pairs(playingLoopedSounds) do
			local updater = loopedSoundUpdaters[sound]

			if updater then
				updater(worldDt, sound, rootPart.Velocity)
			end
		end
	end)

	local humanoidAncestryChangedConn
	local rootPartAncestryChangedConn
	local characterAddedConn

	local function terminate()
		stateChangedConn:Disconnect()
		steppedConn:Disconnect()
		humanoidAncestryChangedConn:Disconnect()
		rootPartAncestryChangedConn:Disconnect()
		characterAddedConn:Disconnect()
	end

	humanoidAncestryChangedConn = humanoid.AncestryChanged:Connect(function(_, parent)
		if not parent then
			terminate()
		end
	end)

	rootPartAncestryChangedConn = rootPart.AncestryChanged:Connect(function(_, parent)
		if not parent then
			terminate()
		end
	end)

	characterAddedConn = player.CharacterAdded:Connect(terminate)
end

local function playerAdded(player)
	local function characterAdded(character)
		if not character.Parent then
			waitForFirst(character.AncestryChanged, player.CharacterAdded)
		end

		if player.Character ~= character or not character.Parent then
			return
		end

		local humanoid = character:FindFirstChildOfClass("Humanoid")
		while character:IsDescendantOf(game) and not humanoid do
			waitForFirst(character.ChildAdded, character.AncestryChanged, player.CharacterAdded)
			humanoid = character:FindFirstChildOfClass("Humanoid")
		end

		if player.Character ~= character or not character:IsDescendantOf(game) then
			return
		end

		local rootPart = character:FindFirstChild("HumanoidRootPart")
		while character:IsDescendantOf(game) and not rootPart do
			waitForFirst(character.ChildAdded, character.AncestryChanged, humanoid.AncestryChanged, player.CharacterAdded)
			rootPart = character:FindFirstChild("HumanoidRootPart")
		end

		if rootPart and humanoid:IsDescendantOf(game) and character:IsDescendantOf(game) and player.Character == character then
			initializeSoundSystem(player, humanoid, rootPart)
		end
	end

	if player.Character then
		characterAdded(player.Character)
	end
	player.CharacterAdded:Connect(characterAdded)
end

Players.PlayerAdded:Connect(playerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	playerAdded(player)
end

repeat
	task.wait()
until game.Players.LocalPlayer.Character

local Character = game.Players.LocalPlayer.Character
local Head = Character:WaitForChild("HumanoidRootPart")
local RunningSound = Head:WaitForChild("Running")
local Humanoid = Character:WaitForChild("Humanoid")
local vel = 0

Humanoid.Changed:Connect(function(property)

end)

Humanoid.Running:connect(function(a)
	local materialName = Humanoid.FloorMaterial.Name
	local materialNode = FootstepsSoundGroup:FindFirstChild(materialName)

	if not materialNode then
		materialNode = FootstepsSoundGroup:FindFirstChild("Plastic")
	end

	if materialNode then
		RunningSound.PlaybackSpeed  = materialNode.PlaybackSpeed * (a/20) * (math.random(30,50)/40)
		RunningSound.EmitterSize    = materialNode.Volume * (a/12) * 50

		local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Linear)
		TweenService:Create(RunningSound, tweenInfo, {Volume = materialNode.Volume * (a/12)}):Play()
	end
	vel = a
end)