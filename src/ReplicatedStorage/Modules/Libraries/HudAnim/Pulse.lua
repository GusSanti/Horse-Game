------------------//SERVICES
local RunService = game:GetService("RunService")

------------------//VARIABLES
local Pulse = {}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS
function Pulse.start(inst, state, utils)
	if state.pulseConn then state.pulseConn:Disconnect() end
	local amp = inst:GetAttribute("pulse_amp") or 0.03
	local period = inst:GetAttribute("pulse_period") or 1.2
	local rotAmp = inst:GetAttribute("pulse_rot_deg") or 1
	local t0 = os.clock()
	state.pulseConn = RunService.Heartbeat:Connect(function()
		if not inst.Parent then return end
		local dt = os.clock() - t0
		local s = 1 + math.sin((dt/period) * math.pi * 2) * amp
		local r = state.origRot + math.sin((dt/period) * math.pi * 2) * rotAmp
		inst.Size = utils.scale_udim2(state.origSize, s)
		inst.Rotation = r
	end)
end

function Pulse.stop(inst, state)
	if state.pulseConn then
		state.pulseConn:Disconnect()
		state.pulseConn = nil
	end
end

------------------//INIT
return Pulse
