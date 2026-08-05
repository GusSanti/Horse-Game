--!strict

local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Libraries: Folder = Modules:WaitForChild("Libraries") :: Folder
local Trove: any = require(Libraries:WaitForChild("Trove"))

local STABLE_SLOT_PROMPT_ATTRIBUTE: string = "StableSlotPrompt"
local STABLE_PROMPT_AVAILABLE_ATTRIBUTE: string = "StablePromptAvailable"
local PROMPT_OPEN_ATTRIBUTE: string = "PromptChoicesOpen"
local PLOT_VALUE_NAME: string = "Plot"

local LocalPlayer: Player = Players.LocalPlayer
local PlotValue: ObjectValue = LocalPlayer:WaitForChild(PLOT_VALUE_NAME) :: ObjectValue
local Scope: any = Trove.new()
local PlotScope: any = Trove.new()
local CharacterScope: any = Trove.new()
local trackedPrompts: { [ProximityPrompt]: boolean } = {}
local refreshQueued: boolean = false

local function get_root_part(): BasePart?
	local character: Model? = LocalPlayer.Character
	local rootPart: Instance? = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if rootPart and rootPart:IsA("BasePart") then rootPart else nil
end

local function get_prompt_position(prompt: ProximityPrompt): Vector3?
	local parent: Instance? = prompt.Parent
	if parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	end
	if parent and parent:IsA("BasePart") then
		return parent.Position
	end
	return nil
end

local function is_available(prompt: ProximityPrompt): boolean
	return prompt.Parent ~= nil
		and prompt:GetAttribute(STABLE_SLOT_PROMPT_ATTRIBUTE) == true
		and trackedPrompts[prompt] == true
end

local function apply_focus(): ()
	local rootPart: BasePart? = get_root_part()
	local closestPrompt: ProximityPrompt? = nil
	local closestDistance: number = math.huge
	local choicesOpen: boolean = false

	for prompt: ProximityPrompt in trackedPrompts do
		if prompt:GetAttribute(PROMPT_OPEN_ATTRIBUTE) == true then
			choicesOpen = true
			break
		end
	end

	if rootPart and not choicesOpen then
		for prompt: ProximityPrompt in trackedPrompts do
			if is_available(prompt) then
				local position: Vector3? = get_prompt_position(prompt)
				if position then
					local distance: number = (position - rootPart.Position).Magnitude
					if distance <= prompt.MaxActivationDistance and distance < closestDistance then
						closestPrompt = prompt
						closestDistance = distance
					end
				end
			end
		end
	end

	for prompt: ProximityPrompt in trackedPrompts do
		local shouldEnable: boolean = prompt == closestPrompt
		if prompt.Enabled ~= shouldEnable then
			prompt.Enabled = shouldEnable
		end
	end
end

local function queue_refresh(): ()
	if refreshQueued then
		return
	end

	refreshQueued = true
	task.defer(function(): ()
		refreshQueued = false
		apply_focus()
	end)
end

local function track_prompt(prompt: ProximityPrompt): ()
	if trackedPrompts[prompt] or prompt:GetAttribute(STABLE_SLOT_PROMPT_ATTRIBUTE) ~= true then
		return
	end

	trackedPrompts[prompt] = if prompt:GetAttribute(STABLE_PROMPT_AVAILABLE_ATTRIBUTE) == nil then prompt.Enabled else prompt:GetAttribute(STABLE_PROMPT_AVAILABLE_ATTRIBUTE) == true
	PlotScope:Connect(prompt:GetAttributeChangedSignal(STABLE_PROMPT_AVAILABLE_ATTRIBUTE), function(): ()
		trackedPrompts[prompt] = prompt:GetAttribute(STABLE_PROMPT_AVAILABLE_ATTRIBUTE) == true
		queue_refresh()
	end)
	PlotScope:Connect(prompt:GetAttributeChangedSignal(PROMPT_OPEN_ATTRIBUTE), queue_refresh)
	PlotScope:Connect(prompt.AncestryChanged, function(): ()
		if prompt.Parent then
			return
		end
		trackedPrompts[prompt] = nil
		queue_refresh()
	end)
	queue_refresh()
end

local function bind_plot(plot: Instance?): ()
	PlotScope:Destroy()
	PlotScope = Trove.new()
	table.clear(trackedPrompts)

	if not plot then
		return
	end

	for _, descendant: Instance in ipairs(plot:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			track_prompt(descendant)
		end
	end

	PlotScope:Connect(plot.DescendantAdded, function(descendant: Instance): ()
		if descendant:IsA("ProximityPrompt") then
			track_prompt(descendant)
		end
	end)
	PlotScope:Connect(plot.DescendantRemoving, function(descendant: Instance): ()
		if descendant:IsA("ProximityPrompt") then
			trackedPrompts[descendant] = nil
			queue_refresh()
		end
	end)
	queue_refresh()
end

Scope:Connect(PlotValue:GetPropertyChangedSignal("Value"), function(): ()
	bind_plot(PlotValue.Value)
end)
local function bind_character(character: Model?): ()
	CharacterScope:Destroy()
	CharacterScope = Trove.new()
	if not character then
		queue_refresh()
		return
	end

	local rootPart: BasePart? = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if rootPart then
		CharacterScope:Connect(rootPart:GetPropertyChangedSignal("CFrame"), queue_refresh)
	end
	queue_refresh()
end

Scope:Connect(LocalPlayer.CharacterAdded, bind_character)
Scope:Connect(LocalPlayer.CharacterRemoving, function(): ()
	bind_character(nil)
end)

bind_character(LocalPlayer.Character)

bind_plot(PlotValue.Value)

script.Destroying:Connect(function(): ()
	PlotScope:Destroy()
	CharacterScope:Destroy()
	Scope:Destroy()
end)

script:SetAttribute("RuntimeReady", true)
