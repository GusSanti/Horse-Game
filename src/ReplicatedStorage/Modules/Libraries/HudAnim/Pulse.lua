------------------//SERVICES
local RunService = game:GetService("RunService")

------------------//VARIABLES
local Pulse = {}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS
function Pulse.start(inst, state, utils)
	Pulse.stop(state)
	local amp = inst:GetAttribute("pulse_amp") or 0.03
	local period = inst:GetAttribute("pulse_period") or 1.2
	local rotAmp = inst:GetAttribute("pulse_rot_deg") or 1
	local hoverScale = state.Hovered and (inst:GetAttribute("hover_scale") or 0.04) or 0
	local baseScale = 1 + hoverScale
	local baseSize = state.BaseSize or state.origSize or inst.Size
	local baseRotation = state.BaseRotation or state.origRot or inst.Rotation
	local t0 = os.clock()
	state.pulseConn = RunService.Heartbeat:Connect(function()
		if not inst.Parent or not state.Hovered or state.Pressed then
			Pulse.stop(state)
			return
		end
		local dt = os.clock() - t0
		local wave = math.sin((dt/period) * math.pi * 2)
		local s = baseScale + wave * amp
		local r = baseRotation + wave * rotAmp
		inst.Size = utils.scale_udim2(baseSize, s)
		inst.Rotation = r
	end)
end

function Pulse.stop(state)
	if state.pulseConn then
		state.pulseConn:Disconnect()
		state.pulseConn = nil
	end
end

------------------//INIT
return Pulse
