------------------//VARIABLES
local Fade = {}

local MAX_FADE_RECORDS = 220

------------------//FUNCTIONS
local function push_record(records, instance, propertyName)
	if #records >= MAX_FADE_RECORDS then
		return
	end

	local success, value = pcall(function()
		return instance[propertyName]
	end)

	if not success or type(value) ~= "number" or value >= 1 then
		return
	end

	records[#records + 1] = {
		Instance = instance,
		Property = propertyName,
		Base = value,
	}
end

local function consider_instance(records, instance)
	if instance:IsA("CanvasGroup") then
		push_record(records, instance, "GroupTransparency")
		return true
	end

	if instance:IsA("GuiObject") then
		push_record(records, instance, "BackgroundTransparency")
	end

	if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
		push_record(records, instance, "TextTransparency")
		push_record(records, instance, "TextStrokeTransparency")
	end

	if instance:IsA("ImageLabel") or instance:IsA("ImageButton") or instance:IsA("ViewportFrame") then
		push_record(records, instance, "ImageTransparency")
	end

	if instance:IsA("UIStroke") then
		push_record(records, instance, "Transparency")
	end

	return false
end

------------------//MAIN FUNCTIONS
function Fade.collect(root)
	if not root or not root:IsA("GuiObject") then
		return {}
	end

	local records = {}
	if consider_instance(records, root) then
		return records
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		consider_instance(records, descendant)
	end

	return records
end

function Fade.set_hidden(records)
	for _, record in ipairs(records or {}) do
		local instance = record.Instance
		if instance and instance.Parent then
			pcall(function()
				instance[record.Property] = 1
			end)
		end
	end
end

function Fade.restore(records)
	for _, record in ipairs(records or {}) do
		local instance = record.Instance
		if instance and instance.Parent then
			pcall(function()
				instance[record.Property] = record.Base
			end)
		end
	end
end

------------------//INIT
return Fade
