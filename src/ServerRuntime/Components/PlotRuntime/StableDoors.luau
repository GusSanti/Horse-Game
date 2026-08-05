--!strict

local TweenService: TweenService = game:GetService("TweenService")

local HORSE_FOLDER_NAME: string = "HorseFolder"
local MAIN_DOOR_NAME: string = "MainDoor"
local DOOR_NAME: string = "Door"
local PIVOT_NAME: string = "Pivot"
local OPEN_ANGLE_ATTRIBUTE: string = "OpenAngleDegrees"
local OPEN_POSITION_ATTRIBUTE: string = "OpenPosition"
local OPEN_ATTRIBUTE: string = "StableDoorOpen"
local ANIMATION_DURATION: number = 0.7

-- Negative Y rotation is clockwise when the hinge is viewed from above.
local LEVEL_CONFIGS: {[number]: any} = {
	[1] = {
		Slots = {
			Slot1 = { Angle = -90 },
			Slot2 = { Angle = 90 },
		},
	},
	[2] = {
		Slots = {
			Slot1 = { Position = Vector3.new(459.834, -24.636, 672.816) },
			Slot2 = { Position = Vector3.new(445.051, -24.636, 672.816) },
		},
		Main = {
			Door = { Angle = -90 },
		},
	},
	[3] = {
		Slots = {
			Slot1 = { Angle = -90 },
			Slot2 = { Angle = -90 },
			Slot3 = { Angle = -90 },
		},
		Main = {
			Door1 = { Angle = -90 },
			Door2 = { Angle = 90 },
		},
	},
	[4] = {
		Slots = {
			Slot1 = { Angle = -90 },
			Slot2 = { Angle = -90 },
			Slot3 = { Angle = -90 },
		},
	},
}

type DoorState = {
	Instance: Instance,
	ClosedCFrame: CFrame,
	OpenCFrame: CFrame,
	IsOpen: boolean,
	Tween: Tween?,
	Value: CFrameValue?,
	ValueConnection: RBXScriptConnection?,
	CompletedConnection: RBXScriptConnection?,
}

type PlotState = {
	Level: number,
	Slots: {[string]: DoorState},
	Main: {DoorState},
}

local StableDoors = {}
StableDoors.__index = StableDoors

local function get_instance_cframe(instance: Instance): CFrame?
	if instance:IsA("Model") then
		return instance:GetPivot()
	end
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	return nil
end

local function pivot_instance(instance: Instance, cframe: CFrame): ()
	if instance:IsA("Model") then
		instance:PivotTo(cframe)
	elseif instance:IsA("BasePart") then
		instance.CFrame = cframe
	end
end

local function stop_animation(state: DoorState): ()
	local tween: Tween? = state.Tween
	state.Tween = nil
	if tween then
		tween:Cancel()
	end
	if state.ValueConnection then
		state.ValueConnection:Disconnect()
		state.ValueConnection = nil
	end
	if state.CompletedConnection then
		state.CompletedConnection:Disconnect()
		state.CompletedConnection = nil
	end
	if state.Value then
		state.Value:Destroy()
		state.Value = nil
	end
end

local function resolve_open_cframe(door: Instance, definition: any, closedCFrame: CFrame): CFrame?
	local attributePosition: any = door:GetAttribute(OPEN_POSITION_ATTRIBUTE)
	local targetPosition: any = if typeof(attributePosition) == "Vector3" then attributePosition else definition.Position
	if typeof(targetPosition) == "Vector3" then
		return CFrame.new(targetPosition) * closedCFrame.Rotation
	end

	local attributeAngle: any = door:GetAttribute(OPEN_ANGLE_ATTRIBUTE)
	local angle: number? = if typeof(attributeAngle) == "number" then attributeAngle else definition.Angle
	if type(angle) ~= "number" then
		return nil
	end

	local pivot: Instance? = door:FindFirstChild(PIVOT_NAME, true)
	if not pivot or not pivot:IsA("BasePart") then
		warn(("[StableDoors] %s requires a BasePart named %s"):format(door:GetFullName(), PIVOT_NAME))
		return nil
	end

	return pivot.CFrame
		* CFrame.Angles(0, math.rad(angle), 0)
		* pivot.CFrame:Inverse()
		* closedCFrame
end

local function create_door_state(door: Instance?, definition: any): DoorState?
	if not door or (not door:IsA("Model") and not door:IsA("BasePart")) then
		return nil
	end

	local closedCFrame: CFrame? = get_instance_cframe(door)
	if not closedCFrame then
		return nil
	end
	local openCFrame: CFrame? = resolve_open_cframe(door, definition, closedCFrame)
	if not openCFrame then
		return nil
	end

	door:SetAttribute(OPEN_ATTRIBUTE, false)
	return {
		Instance = door,
		ClosedCFrame = closedCFrame,
		OpenCFrame = openCFrame,
		IsOpen = false,
		Tween = nil,
		Value = nil,
		ValueConnection = nil,
		CompletedConnection = nil,
	}
end

local function set_door_open(state: DoorState, isOpen: boolean, animate: boolean): ()
	local door: Instance = state.Instance
	if not door.Parent then
		stop_animation(state)
		return
	end

	local targetCFrame: CFrame = if isOpen then state.OpenCFrame else state.ClosedCFrame
	if state.IsOpen == isOpen then
		if not state.Tween and not animate then
			pivot_instance(door, targetCFrame)
		end
		return
	end

	stop_animation(state)
	state.IsOpen = isOpen
	door:SetAttribute(OPEN_ATTRIBUTE, isOpen)

	if not animate then
		pivot_instance(door, targetCFrame)
		return
	end

	local currentCFrame: CFrame? = get_instance_cframe(door)
	if not currentCFrame then
		return
	end

	local value: CFrameValue = Instance.new("CFrameValue")
	value.Value = currentCFrame
	state.Value = value
	state.ValueConnection = value:GetPropertyChangedSignal("Value"):Connect(function()
		if door.Parent then
			pivot_instance(door, value.Value)
		end
	end)

	local tween: Tween = TweenService:Create(
		value,
		TweenInfo.new(ANIMATION_DURATION, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
		{ Value = targetCFrame }
	)
	state.Tween = tween
	state.CompletedConnection = tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
		if state.Tween ~= tween then
			return
		end
		state.Tween = nil
		if playbackState == Enum.PlaybackState.Completed and door.Parent then
			pivot_instance(door, targetCFrame)
		end
		stop_animation(state)
	end)
	tween:Play()
end

local function destroy_plot_state(plotState: PlotState): ()
	for _slotName: string, state: DoorState in plotState.Slots do
		stop_animation(state)
	end
	for _index: number, state: DoorState in plotState.Main do
		stop_animation(state)
	end
end

function StableDoors.new(): any
	return setmetatable({
		_Plots = {} :: {[Instance]: PlotState},
	}, StableDoors)
end

function StableDoors:Bind(plot: Instance, level: number): ()
	self:Forget(plot)

	local config: any = LEVEL_CONFIGS[level]
	if not config then
		return
	end

	local plotState: PlotState = {
		Level = level,
		Slots = {},
		Main = {},
	}
	local horseFolder: Instance? = plot:FindFirstChild(HORSE_FOLDER_NAME)
	for slotName: string, definition: any in config.Slots do
		local slot: Instance? = if horseFolder then horseFolder:FindFirstChild(slotName) else nil
		local door: Instance? = if slot then slot:FindFirstChild(DOOR_NAME) else nil
		local state: DoorState? = create_door_state(door, definition)
		if state then
			plotState.Slots[slotName] = state
		end
	end

	local mainDoor: Instance? = plot:FindFirstChild(MAIN_DOOR_NAME)
	if mainDoor and config.Main then
		for doorName: string, definition: any in config.Main do
			local state: DoorState? = create_door_state(mainDoor:FindFirstChild(doorName), definition)
			if state then
				table.insert(plotState.Main, state)
			end
		end
	end

	self._Plots[plot] = plotState
end

function StableDoors:Sync(plot: Instance, level: number, openSlots: {[string]: boolean}, animate: boolean?): ()
	local plotState: PlotState? = self._Plots[plot]
	if not plotState or plotState.Level ~= level then
		self:Bind(plot, level)
		plotState = self._Plots[plot]
	end
	if not plotState then
		return
	end

	local hasOpenHorse: boolean = false
	for _slotName: string, isOpen: boolean in openSlots do
		hasOpenHorse = hasOpenHorse or isOpen
	end
	for slotName: string, state: DoorState in plotState.Slots do
		local isOpen: boolean = openSlots[slotName] == true
		set_door_open(state, isOpen, animate == true)
	end
	for _index: number, state: DoorState in plotState.Main do
		set_door_open(state, hasOpenHorse, animate == true)
	end
end

function StableDoors:Forget(plot: Instance): ()
	local plotState: PlotState? = self._Plots[plot]
	if plotState then
		destroy_plot_state(plotState)
		self._Plots[plot] = nil
	end
end

function StableDoors:Destroy(): ()
	for plot: Instance, plotState: PlotState in self._Plots do
		destroy_plot_state(plotState)
		self._Plots[plot] = nil
	end
end

return StableDoors
