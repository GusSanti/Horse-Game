------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace: Workspace = game:GetService("Workspace")

------------------//CONSTANTS
local localPlayer: Player = Players.LocalPlayer
local modules: Folder = ReplicatedStorage:WaitForChild("Modules")
local gameData: Folder = modules:WaitForChild("GameData")
local libraries: Folder = modules:WaitForChild("Libraries")

local BaseSignConfig = require(gameData:WaitForChild("Ui"):WaitForChild("BaseSignConfig"))
local Trove = require(libraries:WaitForChild("Trove"))

------------------//VARIABLES
local signTrove = Trove.new()
local signsByPlot: {[Instance]: any} = {}
local plotTroves: {[Instance]: any} = {}
local thumbnailByUserId: {[number]: string} = {}
local screenGui: ScreenGui? = nil
local signTemplate: Instance? = nil
local templateResolved: boolean = false

------------------//FUNCTIONS
local function get_screen_gui(): ScreenGui?
	if screenGui and screenGui.Parent then
		return screenGui
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	local createdGui = Instance.new("ScreenGui")
	createdGui.Name = BaseSignConfig.ScreenGuiName
	createdGui.ResetOnSpawn = false
	createdGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	createdGui:SetAttribute(BaseSignConfig.IgnoreAnimationAttribute, true)
	createdGui.Parent = playerGui

	screenGui = createdGui
	signTrove:Add(createdGui)

	return createdGui
end

local function resolve_sign_template(): Instance?
	if templateResolved then
		return signTemplate
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	local mainUi = playerGui:FindFirstChild(BaseSignConfig.TemplateMainUiName)
	local mainframe = mainUi and mainUi:FindFirstChild(BaseSignConfig.TemplateMainframeName, true)
	if not mainframe then
		return nil
	end

	local resolved: Instance? = mainframe
	for _, segmentName: string in BaseSignConfig.TemplatePath do
		resolved = resolved and resolved:FindFirstChild(segmentName, true)
	end

	templateResolved = true
	signTemplate = resolved

	if not resolved then
		warn("[BaseSigns] Missing authored sign template in MainUI")
	end

	return resolved
end

local function apply_portrait_thumbnail(portrait: ImageLabel, userId: number): ()
	local cachedThumbnail = thumbnailByUserId[userId]
	if cachedThumbnail then
		portrait.Image = cachedThumbnail
		return
	end

	task.spawn(function(): ()
		local success, thumbnail = pcall(function(): string
			return Players:GetUserThumbnailAsync(
				userId,
				BaseSignConfig.ThumbnailType,
				BaseSignConfig.ThumbnailSize
			)
		end)

		if not success or type(thumbnail) ~= "string" then
			return
		end

		thumbnailByUserId[userId] = thumbnail

		if portrait.Parent then
			portrait.Image = thumbnail
		end
	end)
end

local function build_sign(adornee: BasePart, userId: number, displayText: string): any?
	local template = resolve_sign_template()
	local parentGui = get_screen_gui()
	if not template or not parentGui then
		return nil
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = BaseSignConfig.BillboardName
	billboard.Adornee = adornee
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = BaseSignConfig.MaxDistance
	billboard.Size = BaseSignConfig.BillboardSize
	billboard.StudsOffset = BaseSignConfig.StudsOffset
	billboard.Parent = parentGui

	local root = template:Clone()
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.Visible = true
	root.Parent = billboard

	for _, discardName: string in BaseSignConfig.TemplateDiscardNames do
		local discarded = root:FindFirstChild(discardName, true)
		if discarded then
			discarded:Destroy()
		end
	end

	for _, descendant: Instance in root:GetDescendants() do
		if descendant:IsA("UIAspectRatioConstraint") then
			descendant:Destroy()
		end
	end

	local plaque = root:FindFirstChild(BaseSignConfig.TemplatePlaqueName, true)
	local textLabel = plaque and plaque:FindFirstChild(BaseSignConfig.TemplateTextName, true)
	local shadowLabel = plaque and plaque:FindFirstChild(BaseSignConfig.TemplateTextShadowName, true)
	local portrait = root:FindFirstChild(BaseSignConfig.TemplatePortraitName, true)

	if plaque and plaque:IsA("GuiObject") then
		plaque.AnchorPoint = Vector2.new(0.5, 0.5)
		plaque.Position = BaseSignConfig.PlaquePosition
		plaque.Size = BaseSignConfig.PlaqueSize
	end

	local textHolder = textLabel and textLabel.Parent
	if textHolder and textHolder:IsA("GuiObject") then
		textHolder.AnchorPoint = Vector2.new(0.5, 0.5)
		textHolder.Position = UDim2.fromScale(0.5, 0.5)
		textHolder.Size = UDim2.fromScale(1, 1)
	end

	local shadowOffset = BaseSignConfig.TextShadowOffset
	local shadowPosition = UDim2.fromScale(
		BaseSignConfig.TextPosition.X.Scale + shadowOffset.X,
		BaseSignConfig.TextPosition.Y.Scale + shadowOffset.Y
	)

	local labelLayouts = {
		{ Label = textLabel, Position = BaseSignConfig.TextPosition },
		{ Label = shadowLabel, Position = shadowPosition },
	}

	for _, layout in labelLayouts do
		local label = layout.Label
		if label and label:IsA("TextLabel") then
			label.Text = displayText
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Position = layout.Position
			label.Size = BaseSignConfig.TextSize
			label.TextXAlignment = Enum.TextXAlignment.Center
		end
	end

	if portrait and portrait:IsA("ImageLabel") then
		portrait.AnchorPoint = Vector2.new(0.5, 0.5)
		portrait.Position = BaseSignConfig.PortraitPosition
		portrait.Size = BaseSignConfig.PortraitSize
		portrait.ZIndex = 2

		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = portrait

		local corner = Instance.new("UICorner")
		corner.CornerRadius = BaseSignConfig.PortraitCornerRadius
		corner.Parent = portrait

		portrait.Image = ""
		apply_portrait_thumbnail(portrait, userId)
	end

	return {
		Billboard = billboard,
		TextLabel = textLabel,
		ShadowLabel = shadowLabel,
		Portrait = portrait,
		UserId = userId,
	}
end

local function destroy_sign(plot: Instance): ()
	local sign = signsByPlot[plot]
	if not sign then
		return
	end

	signsByPlot[plot] = nil
	if sign.Billboard.Parent then
		sign.Billboard:Destroy()
	end
end

local function resolve_display_text(userId: number, ownerName: string?): string
	if userId == localPlayer.UserId then
		return BaseSignConfig.OwnBaseText
	end

	if type(ownerName) == "string" and ownerName ~= "" then
		return ownerName
	end

	return "Base"
end

local function refresh_plot(plot: Instance): ()
	local userId = plot:GetAttribute(BaseSignConfig.OwnerUserIdAttribute)
	local adornee = plot:FindFirstChild(BaseSignConfig.PlayerSpawnName)

	if type(userId) ~= "number" or not adornee or not adornee:IsA("BasePart") then
		destroy_sign(plot)
		return
	end

	local displayText = resolve_display_text(userId, plot:GetAttribute(BaseSignConfig.OwnerNameAttribute))
	local sign = signsByPlot[plot]

	if sign and sign.Billboard.Parent then
		sign.Billboard.Adornee = adornee

		if sign.UserId ~= userId then
			sign.UserId = userId
			if sign.Portrait then
				apply_portrait_thumbnail(sign.Portrait, userId)
			end
		end

		if sign.TextLabel then
			sign.TextLabel.Text = displayText
		end

		if sign.ShadowLabel then
			sign.ShadowLabel.Text = displayText
		end

		return
	end

	destroy_sign(plot)
	signsByPlot[plot] = build_sign(adornee, userId, displayText)
end

local function unbind_plot(plot: Instance): ()
	local plotTrove = plotTroves[plot]
	if plotTrove then
		plotTroves[plot] = nil
		signTrove:Remove(plotTrove)
	end

	destroy_sign(plot)
end

local function bind_plot(plot: Instance): ()
	if plotTroves[plot] or tonumber(plot.Name) == nil then
		return
	end

	local plotTrove = signTrove:Extend()
	plotTroves[plot] = plotTrove

	plotTrove:Connect(plot:GetAttributeChangedSignal(BaseSignConfig.OwnerUserIdAttribute), function(): ()
		refresh_plot(plot)
	end)

	plotTrove:Connect(plot:GetAttributeChangedSignal(BaseSignConfig.OwnerNameAttribute), function(): ()
		refresh_plot(plot)
	end)

	plotTrove:Connect(plot.ChildAdded, function(child: Instance): ()
		if child.Name == BaseSignConfig.PlayerSpawnName then
			refresh_plot(plot)
		end
	end)

	refresh_plot(plot)
end

local function bind_stables(stablesFolder: Instance): ()
	for _, plot: Instance in stablesFolder:GetChildren() do
		bind_plot(plot)
	end

	signTrove:Connect(stablesFolder.ChildAdded, bind_plot)
	signTrove:Connect(stablesFolder.ChildRemoved, unbind_plot)
end

------------------//MAIN FUNCTIONS
local function start(): ()
	local stablesFolder = Workspace:WaitForChild(BaseSignConfig.StablesFolderName, 30)
	if not stablesFolder then
		warn("[BaseSigns] Missing Stables folder in Workspace")
		return
	end

	bind_stables(stablesFolder)
end

------------------//INIT
if BaseSignConfig.Enabled then
	start()
end

script:SetAttribute("RuntimeReady", true)
