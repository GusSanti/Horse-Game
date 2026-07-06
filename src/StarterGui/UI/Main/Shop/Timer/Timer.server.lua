local textLabel = script.Parent

local function formatTime(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d", minutes, secs)
end

while true do
	textLabel.Text = formatTime(10)
	for timer = 9, 0, -1 do
		wait(1)
		textLabel.Text = formatTime(timer)
	end
end

