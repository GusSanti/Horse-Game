--!strict

type MountState = { [string]: any }
type Payload = { [string]: any }

local InputState = {}

local VALID_GAIT_MODES: { [string]: boolean } = table.freeze({
	Idle = true,
	Gait = true,
	Trot = true,
	Gallop = true,
	Backward = true,
	Rear = true,
})

local function IsFiniteNumber(Value: any): boolean
	return type(Value) == "number"
		and Value == Value
		and Value ~= math.huge
		and Value ~= -math.huge
end

function InputState.Apply(
	MountStateValue: MountState,
	PayloadValue: Payload,
	BeginJump: (MountState, any) -> (),
	EndJump: (MountState) -> ()
): boolean
	local Sequence: any = PayloadValue.Sequence
	if not IsFiniteNumber(Sequence) or Sequence < 1 or Sequence % 1 ~= 0 then
		return false
	end
	if Sequence <= (MountStateValue.LastProcessedInputSequence or 0) then
		return false
	end
	MountStateValue.LastProcessedInputSequence = Sequence

	if IsFiniteNumber(PayloadValue.MoveX) then
		MountStateValue.InputX = math.clamp(PayloadValue.MoveX, -1, 1)
	end
	if IsFiniteNumber(PayloadValue.MoveZ) then
		MountStateValue.InputZ = math.clamp(PayloadValue.MoveZ, -1, 1)
	end
	if type(PayloadValue.Sprinting) == "boolean" then
		MountStateValue.Sprinting = PayloadValue.Sprinting
	end
	if IsFiniteNumber(PayloadValue.CameraYaw) then
		MountStateValue.CameraYaw = math.atan2(math.sin(PayloadValue.CameraYaw), math.cos(PayloadValue.CameraYaw))
	end
	if type(PayloadValue.GaitMode) == "string" and VALID_GAIT_MODES[PayloadValue.GaitMode] then
		MountStateValue.ClientGaitMode = PayloadValue.GaitMode
	end
	if PayloadValue.RearRequested == true then
		MountStateValue.RearRequestedAt = os.clock()
	end
	if PayloadValue.JumpLanded == true then
		EndJump(MountStateValue)
	end
	if PayloadValue.JumpRequested == true then
		BeginJump(MountStateValue, PayloadValue.JumpChargeAlpha)
	end
	return true
end

return table.freeze(InputState)
