local SoapClientProgress = {}

function SoapClientProgress.updateProgressUi(session, context, shouldTween)
	local progressAlpha = math.clamp(session.stageProgress / context.getProgressGoal(session), 0, 1)
	local displayedPercent = math.floor((progressAlpha * 100 * 2) + 0.5) / 2

	session.titleLabel.Text = context.getProgressTitle(session)

	if session.progressTween then
		session.progressTween:Cancel()
		session.progressTween = nil
	end

	if shouldTween then
		session.progressTween = context.TweenService:Create(
			session.fillFrame,
			TweenInfo.new(context.progressTweenTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(progressAlpha, 1) }
		)
		session.progressTween:Play()
	else
		session.fillFrame.Size = UDim2.fromScale(progressAlpha, 1)
	end

	session.progressLabel.Text = ("%.1f%%"):format(displayedPercent)
end

function SoapClientProgress.createProgressGui(session, context)
	local playerGui = context.getPlayerGui()
	if not playerGui then
		return false
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = context.actionName .. "Progress"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "ProgressBillboard"
	billboardGui.Adornee = session.focusPart
	billboardGui.AlwaysOnTop = true
	billboardGui.Size = UDim2.fromOffset(280, 80)
	billboardGui.StudsOffset = Vector3.new(0, (session.extents.Y * 0.5) + context.progressStudsOffset, 0)
	billboardGui.Parent = screenGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	mainFrame.BackgroundTransparency = 0.16
	mainFrame.BorderSizePixel = 0
	mainFrame.Position = UDim2.fromScale(0.5, 0.5)
	mainFrame.Size = UDim2.fromOffset(260, 68)
	mainFrame.Parent = billboardGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 18)
	mainCorner.Parent = mainFrame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 16
	titleLabel.Position = UDim2.fromOffset(16, 10)
	titleLabel.Size = UDim2.new(1, -32, 0, 20)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = mainFrame

	local barFrame = Instance.new("Frame")
	barFrame.Name = "BarFrame"
	barFrame.BackgroundColor3 = Color3.fromRGB(44, 52, 66)
	barFrame.BorderSizePixel = 0
	barFrame.Position = UDim2.fromOffset(16, 38)
	barFrame.Size = UDim2.fromOffset(context.progressBarWidth, context.progressBarHeight)
	barFrame.Parent = mainFrame

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = barFrame

	local fillFrame = Instance.new("Frame")
	fillFrame.Name = "FillFrame"
	fillFrame.BackgroundColor3 = Color3.fromRGB(255, 244, 196)
	fillFrame.BorderSizePixel = 0
	fillFrame.Size = UDim2.fromScale(0, 1)
	fillFrame.Parent = barFrame

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fillFrame

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.BackgroundTransparency = 1
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.TextColor3 = Color3.fromRGB(206, 214, 227)
	progressLabel.TextSize = 14
	progressLabel.Position = UDim2.new(1, -56, 0, 34)
	progressLabel.Size = UDim2.fromOffset(40, 20)
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.Parent = mainFrame

	local instructionGui = Instance.new("ScreenGui")
	instructionGui.Name = context.actionName .. "Instruction"
	instructionGui.ResetOnSpawn = false
	instructionGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	instructionGui.Parent = playerGui

	local instructionFrame = Instance.new("Frame")
	instructionFrame.Name = "InstructionFrame"
	instructionFrame.AnchorPoint = Vector2.new(0.5, 1)
	instructionFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
	instructionFrame.BackgroundTransparency = 0.18
	instructionFrame.BorderSizePixel = 0
	instructionFrame.Position = UDim2.new(0.5, 0, 1, -44)
	instructionFrame.Size = UDim2.fromOffset(340, 44)
	instructionFrame.Parent = instructionGui

	local instructionCorner = Instance.new("UICorner")
	instructionCorner.CornerRadius = UDim.new(0, 16)
	instructionCorner.Parent = instructionFrame

	local instructionLabel = Instance.new("TextLabel")
	instructionLabel.Name = "InstructionLabel"
	instructionLabel.BackgroundTransparency = 1
	instructionLabel.Font = Enum.Font.GothamMedium
	instructionLabel.Text = context.instructionText
	instructionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	instructionLabel.TextSize = 15
	instructionLabel.Size = UDim2.new(1, -24, 1, 0)
	instructionLabel.Position = UDim2.fromOffset(12, 0)
	instructionLabel.Parent = instructionFrame

	session.screenGui = screenGui
	session.instructionGui = instructionGui
	session.titleLabel = titleLabel
	session.fillFrame = fillFrame
	session.progressLabel = progressLabel
	session.instructionLabel = instructionLabel

	session.instances[#session.instances + 1] = screenGui
	session.instances[#session.instances + 1] = instructionGui

	SoapClientProgress.updateProgressUi(session, context)

	return true
end

return SoapClientProgress
