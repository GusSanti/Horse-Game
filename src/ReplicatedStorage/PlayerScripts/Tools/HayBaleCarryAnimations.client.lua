local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local HAY_BALE_ITEM_ID = "hay_bale"
local HAY_BALE_IDLE_ANIMATION_ID = "rbxassetid://81093189868077"
local HAY_BALE_WALK_ANIMATION_ID = "rbxassetid://97799701710783"
local HAY_BALE_ANIMATION_FADE_SECONDS = 0.15
local HAY_BALE_WALK_SPEED_REFERENCE = 14
local HAY_BALE_MOVE_DIRECTION_THRESHOLD = 0.05
local HAY_BALE_DEFAULT_GRIP = CFrame.new()
local HAY_BALE_EXTRA_GRIP_OFFSET = CFrame.new()

local toolConnections: { [Tool]: { RBXScriptConnection } } = {}
local characterConnections: { RBXScriptConnection } = {}
local activeSession = nil

local function disconnect_all(connections)
	for _, connection in ipairs(connections) do
		connection:Disconnect()
	end

	table.clear(connections)
end

local function is_hay_bale_tool(tool: Instance?): boolean
	if not tool or not tool:IsA("Tool") then
		return false
	end

	local itemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
	if itemDefinition and itemDefinition.ItemId == HAY_BALE_ITEM_ID then
		return true
	end

	return string.lower(tool.Name) == "haybaletool"
end

local function ensure_animator(humanoid: Humanoid): Animator?
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		return animator
	end

	animator = Instance.new("Animator")
	animator.Parent = humanoid
	return animator
end

local function load_animation_track(animator: Animator, animationId: string, looped: boolean): (AnimationTrack?, Animation?)
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	pcall(function()
		ContentProvider:PreloadAsync({ animation })
	end)

	local success, track = pcall(function()
		return animator:LoadAnimation(animation)
	end)

	if not success or not track then
		animation:Destroy()
		return nil, nil
	end

	pcall(function()
		track.Priority = Enum.AnimationPriority.Action
	end)

	pcall(function()
		track.Looped = looped
	end)

	return track, animation
end

local function stop_track(track: AnimationTrack?)
	if not track then
		return
	end

	pcall(function()
		track:Stop(HAY_BALE_ANIMATION_FADE_SECONDS)
	end)
end

local function play_track(track: AnimationTrack?, speed: number?)
	if not track then
		return
	end

	pcall(function()
		if not track.IsPlaying then
			track:Play(HAY_BALE_ANIMATION_FADE_SECONDS, 1, speed or 1)
		else
			track:AdjustSpeed(speed or 1)
		end
	end)
end

local function find_right_hand(character: Model?): BasePart?
	if not character then
		return nil
	end

	for _, partName in ipairs({ "RightHand", "Right Arm", "RightLowerArm", "RightUpperArm" }) do
		local part = character:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			return part
		end
	end

	local descendant = character:FindFirstChild("RightHand", true)
	return if descendant and descendant:IsA("BasePart") then descendant else nil
end

local function find_visual_handle(root: Instance): BasePart?
	local directHandle = root:FindFirstChild("Handle")
	if directHandle and directHandle:IsA("BasePart") then
		return directHandle
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.Name == "Handle" then
			return descendant
		end
	end

	if root:IsA("BasePart") then
		return root
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

local function has_character_attachment(character: Model, tool: Tool, handle: BasePart): boolean
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Weld") or descendant:IsA("Motor6D") or descendant:IsA("WeldConstraint") then
			local otherPart = nil
			if descendant.Part0 == handle then
				otherPart = descendant.Part1
			elseif descendant.Part1 == handle then
				otherPart = descendant.Part0
			end

			if otherPart
				and otherPart:IsDescendantOf(character)
				and not otherPart:IsDescendantOf(tool)
			then
				return true
			end
		end
	end

	return false
end

local function strip_visual_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function hide_tool_visual(session)
	if session.ToolVisualHidden then
		return
	end

	session.HiddenVisuals = {}
	session.ToolVisualHidden = true

	for _, descendant in ipairs(session.Tool:GetDescendants()) do
		if descendant:IsA("BasePart") then
			session.HiddenVisuals[#session.HiddenVisuals + 1] = {
				Instance = descendant,
				Property = "LocalTransparencyModifier",
				Value = descendant.LocalTransparencyModifier,
			}
			descendant.LocalTransparencyModifier = 1
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			session.HiddenVisuals[#session.HiddenVisuals + 1] = {
				Instance = descendant,
				Property = "Transparency",
				Value = descendant.Transparency,
			}
			descendant.Transparency = 1
		end
	end
end

local function restore_tool_visual(session)
	for _, entry in ipairs(session.HiddenVisuals or {}) do
		if entry.Instance and entry.Instance.Parent then
			pcall(function()
				entry.Instance[entry.Property] = entry.Value
			end)
		end
	end

	session.HiddenVisuals = nil
	session.ToolVisualHidden = false
end

local function clone_tool_visual(tool: Tool): (Model?, { [BasePart]: CFrame }?)
	local cloneSucceeded, toolClone = pcall(function()
		return tool:Clone()
	end)
	if not cloneSucceeded or not toolClone then
		return nil, nil
	end

	strip_visual_scripts(toolClone)

	local visualModel = Instance.new("Model")
	visualModel.Name = "HayBaleCarryVisual"

	for _, child in ipairs(toolClone:GetChildren()) do
		child.Parent = visualModel
	end

	toolClone:Destroy()

	local handle = find_visual_handle(visualModel)
	if not handle then
		visualModel:Destroy()
		return nil, nil
	end

	visualModel.PrimaryPart = handle
	local partOffsets = {}

	for _, descendant in ipairs(visualModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			partOffsets[descendant] = handle.CFrame:ToObjectSpace(descendant.CFrame)
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true
			descendant.LocalTransparencyModifier = 0

			if descendant ~= handle then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = handle
				weld.Part1 = descendant
				weld.Parent = descendant
			end
		elseif descendant:IsA("Decal") or descendant:IsA("Texture") then
			descendant.Transparency = 0
		end
	end

	return visualModel, partOffsets
end

local function get_tool_grip(tool: Tool): CFrame
	if tool.Grip ~= CFrame.new() then
		return tool.Grip * HAY_BALE_EXTRA_GRIP_OFFSET
	end

	return HAY_BALE_DEFAULT_GRIP * HAY_BALE_EXTRA_GRIP_OFFSET
end

local function ensure_carry_visual(session)
	local handle = find_visual_handle(session.Tool)
	if handle and has_character_attachment(session.Character, session.Tool, handle) then
		return
	end

	local rightHand = find_right_hand(session.Character)
	if not rightHand then
		return
	end

	local visualModel, partOffsets = clone_tool_visual(session.Tool)
	if not visualModel or not visualModel.PrimaryPart then
		return
	end

	session.CarryVisual = visualModel
	hide_tool_visual(session)

	visualModel.Parent = session.Character
	local targetHandleCFrame = rightHand.CFrame * get_tool_grip(session.Tool)
	for part, offset in pairs(partOffsets or {}) do
		if part and part.Parent then
			part.CFrame = targetHandleCFrame * offset
		end
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "HayBaleCarryVisualWeld"
	weld.Part0 = rightHand
	weld.Part1 = visualModel.PrimaryPart
	weld.Parent = visualModel.PrimaryPart
end

local function destroy_carry_visual(session)
	if session.CarryVisual then
		session.CarryVisual:Destroy()
		session.CarryVisual = nil
	end
end

local function set_session_mode(session, mode: string)
	if session.Mode == mode then
		return
	end

	session.Mode = mode

	if mode == "Walk" then
		stop_track(session.IdleTrack)
		play_track(session.WalkTrack, 1)
	else
		stop_track(session.WalkTrack)
		play_track(session.IdleTrack, 1)
	end
end

local function update_session_mode(session)
	if activeSession ~= session or session.Closed then
		return
	end

	local humanoid = session.Humanoid
	local rootPart = session.RootPart
	if not humanoid or not humanoid.Parent or humanoid.Health <= 0 then
		return
	end

	local horizontalSpeed = 0
	if rootPart and rootPart.Parent then
		local velocity = rootPart.AssemblyLinearVelocity
		horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	end

	local moving = humanoid.MoveDirection.Magnitude > HAY_BALE_MOVE_DIRECTION_THRESHOLD or horizontalSpeed > 0.5
	if moving then
		set_session_mode(session, "Walk")
		local playbackSpeed = math.clamp(horizontalSpeed / HAY_BALE_WALK_SPEED_REFERENCE, 0.75, 1.25)
		play_track(session.WalkTrack, playbackSpeed)
	else
		set_session_mode(session, "Idle")
	end
end

local function stop_session(session)
	if activeSession ~= session or session.Closed then
		return
	end

	session.Closed = true
	activeSession = nil

	disconnect_all(session.Connections)
	stop_track(session.IdleTrack)
	stop_track(session.WalkTrack)
	destroy_carry_visual(session)
	restore_tool_visual(session)

	for _, animation in ipairs(session.Animations) do
		animation:Destroy()
	end
end

local function start_session(tool: Tool)
	if activeSession and activeSession.Tool == tool then
		return
	end

	if activeSession then
		stop_session(activeSession)
	end

	local character = localPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not character or not humanoid or humanoid.Health <= 0 then
		return
	end

	local animator = ensure_animator(humanoid)
	if not animator then
		return
	end

	local idleTrack, idleAnimation = load_animation_track(animator, HAY_BALE_IDLE_ANIMATION_ID, true)
	local walkTrack, walkAnimation = load_animation_track(animator, HAY_BALE_WALK_ANIMATION_ID, true)
	if not idleTrack and not walkTrack then
		if idleAnimation then
			idleAnimation:Destroy()
		end
		if walkAnimation then
			walkAnimation:Destroy()
		end
		return
	end

	local session = {
		Tool = tool,
		Character = character,
		Humanoid = humanoid,
		RootPart = rootPart,
		IdleTrack = idleTrack,
		WalkTrack = walkTrack,
		Animations = {},
		Connections = {},
		HiddenVisuals = nil,
		ToolVisualHidden = false,
		CarryVisual = nil,
		Mode = nil,
		Closed = false,
	}

	if idleAnimation then
		session.Animations[#session.Animations + 1] = idleAnimation
	end
	if walkAnimation then
		session.Animations[#session.Animations + 1] = walkAnimation
	end

	activeSession = session
	ensure_carry_visual(session)
	set_session_mode(session, "Idle")

	session.Connections[#session.Connections + 1] = tool.Unequipped:Connect(function()
		stop_session(session)
	end)

	session.Connections[#session.Connections + 1] = tool.AncestryChanged:Connect(function()
		if not tool:IsDescendantOf(character) then
			stop_session(session)
		end
	end)

	session.Connections[#session.Connections + 1] = humanoid.Died:Connect(function()
		stop_session(session)
	end)

	session.Connections[#session.Connections + 1] = RunService.RenderStepped:Connect(function()
		update_session_mode(session)
	end)
end

local function watch_tool(tool: Tool)
	if toolConnections[tool] then
		return
	end

	local connections = {}
	toolConnections[tool] = connections

	connections[#connections + 1] = tool.Equipped:Connect(function()
		if is_hay_bale_tool(tool) then
			start_session(tool)
		end
	end)

	connections[#connections + 1] = tool.Unequipped:Connect(function()
		if activeSession and activeSession.Tool == tool then
			stop_session(activeSession)
		end
	end)

	connections[#connections + 1] = tool.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		if activeSession and activeSession.Tool == tool then
			stop_session(activeSession)
		end

		disconnect_all(connections)
		toolConnections[tool] = nil
	end)
end

local function watch_tool_container(container: Instance)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			watch_tool(child)
		end
	end

	characterConnections[#characterConnections + 1] = container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			watch_tool(child)
		end
	end)
end

local function bind_character(character: Model)
	disconnect_all(characterConnections)

	watch_tool_container(character)
	watch_tool_container(localPlayer:WaitForChild("Backpack"))

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") and is_hay_bale_tool(child) then
			start_session(child)
		end
	end

	characterConnections[#characterConnections + 1] = localPlayer.CharacterRemoving:Connect(function(removingCharacter)
		if removingCharacter == character and activeSession then
			stop_session(activeSession)
		end
	end)
end

localPlayer.CharacterAdded:Connect(bind_character)

if localPlayer.Character then
	bind_character(localPlayer.Character)
end
