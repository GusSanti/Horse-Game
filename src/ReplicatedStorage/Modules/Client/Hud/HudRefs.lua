local Players = game:GetService("Players")

local localPlayer = Players.LocalPlayer

local HudRefs = {}

HudRefs.MainUiName = "MainUI"
HudRefs.MainframeName = "MainframeFR"

function HudRefs.NormalizeKey(value: string?): string?
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

function HudRefs.MatchesAlias(instance: Instance, aliases: {string}): boolean
	local normalizedName = HudRefs.NormalizeKey(instance.Name)
	if not normalizedName then
		return false
	end

	for _, alias in ipairs(aliases) do
		if HudRefs.NormalizeKey(alias) == normalizedName then
			return true
		end
	end

	return false
end

function HudRefs.FindNamedInstance(root: Instance?, aliases: {string}, className: string?, recursive: boolean?): Instance?
	if not root then
		return nil
	end

	for _, child in ipairs(root:GetChildren()) do
		if HudRefs.MatchesAlias(child, aliases) and (not className or child:IsA(className)) then
			return child
		end
	end

	if recursive == false then
		return nil
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if HudRefs.MatchesAlias(descendant, aliases) and (not className or descendant:IsA(className)) then
			return descendant
		end
	end

	return nil
end

function HudRefs.FindTextLabel(root: Instance?, aliases: {string}): TextLabel?
	local instance = HudRefs.FindNamedInstance(root, aliases, "TextLabel")
	if instance then
		return instance :: TextLabel
	end

	return nil
end

function HudRefs.FindGuiObject(root: Instance?, aliases: {string}, recursive: boolean?): GuiObject?
	local instance = HudRefs.FindNamedInstance(root, aliases, "GuiObject", recursive)
	if instance then
		return instance :: GuiObject
	end

	return nil
end

function HudRefs.GetPlayerGui(): PlayerGui?
	return localPlayer:FindFirstChildOfClass("PlayerGui")
end

function HudRefs.GetMainframeRoot(): Instance?
	local playerGui = HudRefs.GetPlayerGui()
	if not playerGui then
		return nil
	end

	local mainUi = playerGui:FindFirstChild(HudRefs.MainUiName) or playerGui:FindFirstChild(HudRefs.MainUiName, true)
	if not mainUi then
		return nil
	end

	return mainUi:FindFirstChild(HudRefs.MainframeName) or mainUi:FindFirstChild(HudRefs.MainframeName, true)
end

function HudRefs.SetVisible(guiObject: GuiObject?, isVisible: boolean): ()
	if guiObject then
		guiObject.Visible = isVisible
	end
end

function HudRefs.SetTextPair(primary: TextLabel?, shadow: TextLabel?, text: string): ()
	if primary then
		primary.Text = text
	end

	if shadow then
		shadow.Text = text
	end
end

function HudRefs.IsDescendantOf(instance: Instance?, ancestor: Instance?): boolean
	if not instance or not ancestor then
		return false
	end

	return instance ~= ancestor and instance:IsDescendantOf(ancestor)
end

return HudRefs
