------------------//SERVICES
local StarterGui: StarterGui = game:GetService("StarterGui")

------------------//CONSTANTS
local MAX_ATTEMPTS = 10

------------------//VARIABLES

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
for _ = 1, MAX_ATTEMPTS do
	local success = pcall(function()
		StarterGui:SetCore("ResetButtonCallback", false)
	end)

	if success then
		break
	end

	task.wait(1)
end
