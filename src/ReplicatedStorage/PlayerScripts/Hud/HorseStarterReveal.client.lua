local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local localPlayer = Players.LocalPlayer
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local RaceVisualFactory = require(Utility:WaitForChild("RaceVisualFactory"))
local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))

local SCREEN_GUI_NAME = "HorseStarterRevealGui"
local SPIN_DELAYS = {
	0.08, 0.08, 0.08, 0.08,
	0.09, 0.09,
	0.10, 0.10,
	0.11, 0.12,
	0.14, 0.16,
	0.19, 0.23,
	0.28, 0.34,
	0.42, 0.52,
	0.65, 0.82,
}

local RARITY_STYLES = {
	Common = {
		Accent = Color3.fromRGB(132, 195, 121),
		Surface = Color3.fromRGB(42, 70, 48),
		Text = Color3.fromRGB(232, 247, 227),
	},
	Uncommon = {
		Accent = Color3.fromRGB(89, 174, 212),
		Surface = Color3.fromRGB(34, 65, 83),
		Text = Color3.fromRGB(229, 243, 251),
	},
	Rare = {
		Accent = Color3.fromRGB(103, 124, 240),
		Surface = Color3.fromRGB(39, 48, 96),
		Text = Color3.fromRGB(234, 239, 255),
	},
	Epic = {
		Accent = Color3.fromRGB(188, 109, 255),
		Surface = Color3.fromRGB(78, 43, 112),
		Text = Color3.fromRGB(244, 232, 255),
	},
	Legendary = {
		Accent = Color3.fromRGB(242, 177, 73),
		Surface = Color3.fromRGB(111, 70, 24),
		Text = Color3.fromRGB(255, 245, 227),
	},
}

local horseOptions = HorseCatalog.GetRouletteHorseOptions()
local isShowingReveal = false
local currentRevealHorseId = nil
local selectedHorseIndex = 0
local orbitAngle = -1.3
local previewModel = nil
local previewFocus = Vector3.new(0, 3.5, 0)
local previewCameraDistance = 14
local previewCameraHeight = 4.5

local screenGui
local overlay
local viewportFrame
local worldModel
local previewCamera
local cardStroke
local nameLabel
local rarityBadge
local rarityStroke
local rarityLabel
local subtitleLabel
local revealLabel
local revealScale
local cardScale

local gameplayRemotes = ReplicatedStorage:WaitForChild(NetworkConfig.GameplayFolderName)
local horseRemotes = gameplayRemotes:WaitForChild(NetworkConfig.Horse.FolderName)
local acknowledgeRevealRemote = horseRemotes:WaitForChild(NetworkConfig.Horse.AcknowledgeReveal)

local function get_rarity_style(rarity)
	return RARITY_STYLES[rarity] or RARITY_STYLES.Common
end

local function create(className, properties)
	local instance = Instance.new(className)

	for propertyName, value in pairs(properties) do
		instance[propertyName] = value
	end

	return instance
end

local function build_ui()
	if screenGui then
		return
	end

	local playerGui = localPlayer:WaitForChild("PlayerGui")

	screenGui = create("ScreenGui", {
		Name = SCREEN_GUI_NAME,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 120,
		Enabled = false,
		Parent = playerGui,
	})

	overlay = create("Frame", {
		BackgroundColor3 = Color3.fromRGB(7, 11, 17),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Parent = screenGui,
	})

	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(25, 35, 48)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 13, 19)),
		}),
		Rotation = 90,
		Parent = overlay,
	})

	local card = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(19, 27, 37),
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(620, 470),
		Parent = overlay,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 22),
		Parent = card,
	})

	cardScale = create("UIScale", {
		Scale = 1,
		Parent = card,
	})

	cardStroke = create("UIStroke", {
		Color = Color3.fromRGB(132, 195, 121),
		Transparency = 0.08,
		Thickness = 2,
		Parent = card,
	})

	create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Seu cavalo chegou",
		TextColor3 = Color3.fromRGB(245, 248, 255),
		TextSize = 28,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.5, -250, 0, 20),
		Size = UDim2.fromOffset(500, 30),
		Parent = card,
	})

	subtitleLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = "A roleta vai desacelerar ate mostrar qual cavalo e seu.",
		TextColor3 = Color3.fromRGB(187, 199, 216),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.5, -250, 0, 56),
		Size = UDim2.fromOffset(500, 18),
		Parent = card,
	})

	local viewportCard = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(15, 21, 29),
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(530, 250),
		Parent = card,
	})

	create("UICorner", {
		CornerRadius = UDim.new(0, 20),
		Parent = viewportCard,
	})

	create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(32, 42, 58)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(12, 17, 24)),
		}),
		Rotation = 90,
		Parent = viewportCard,
	})

	viewportFrame = create("ViewportFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(14, 14),
		Size = UDim2.new(1, -28, 1, -28),
		Ambient = Color3.fromRGB(214, 222, 238),
		LightColor = Color3.fromRGB(255, 246, 235),
		LightDirection = Vector3.new(-0.8, -1, -0.45),
		Parent = viewportCard,
	})

	worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewportFrame

	previewCamera = Instance.new("Camera")
	previewCamera.Name = "PreviewCamera"
	previewCamera.Parent = viewportFrame
	viewportFrame.CurrentCamera = previewCamera

	nameLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "Nenhum cavalo",
		TextColor3 = Color3.fromRGB(242, 246, 255),
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.5, -250, 0, 358),
		Size = UDim2.fromOffset(500, 28),
		Parent = card,
	})

	rarityBadge = create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(42, 70, 48),
		BorderSizePixel = 0,
		Position = UDim2.new(0.5, 0, 0, 394),
		Size = UDim2.fromOffset(150, 32),
		Parent = card,
	})

	create("UICorner", {
		CornerRadius = UDim.new(1, 0),
		Parent = rarityBadge,
	})

	rarityStroke = create("UIStroke", {
		Color = Color3.fromRGB(132, 195, 121),
		Transparency = 0.14,
		Thickness = 1.2,
		Parent = rarityBadge,
	})

	rarityLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "COMMON",
		TextColor3 = Color3.fromRGB(232, 247, 227),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = rarityBadge,
	})

	revealLabel = create("TextLabel", {
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = "",
		TextColor3 = Color3.fromRGB(242, 177, 73),
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0.5, -250, 0, 432),
		Size = UDim2.fromOffset(500, 22),
		Visible = false,
		Parent = card,
	})

	revealScale = create("UIScale", {
		Scale = 1,
		Parent = revealLabel,
	})
end

local function clear_preview_model()
	if not worldModel then
		return
	end

	for _, child in ipairs(worldModel:GetChildren()) do
		child:Destroy()
	end

	previewModel = nil
end

local function find_horse_index(catalogId)
	for index, horseOption in ipairs(horseOptions) do
		if horseOption.CatalogId == catalogId then
			return index
		end
	end

	return nil
end

local function update_rarity(horseOption)
	local style = get_rarity_style(horseOption and horseOption.Rarity or nil)

	if cardStroke then
		cardStroke.Color = style.Accent
	end

	if rarityBadge then
		rarityBadge.BackgroundColor3 = style.Surface
	end

	if rarityStroke then
		rarityStroke.Color = style.Accent
	end

	if rarityLabel then
		rarityLabel.TextColor3 = style.Text
		rarityLabel.Text = horseOption and string.upper(horseOption.Rarity or "Common") or "COMMON"
	end
end

local function mount_preview_horse(horseOption)
	if not horseOption or not worldModel then
		return
	end

	clear_preview_model()

	local summary = {
		Id = horseOption.CatalogId,
		HorseId = horseOption.CatalogId,
		CatalogId = horseOption.CatalogId,
		PlaceholderModelKey = horseOption.ModelKey,
	}

	local model = RaceVisualFactory.CreateRaceModel(summary, nil, worldModel)
	previewModel = model

	local boxCFrame, boxSize = model:GetBoundingBox()
	local offset = model:GetPivot():ToObjectSpace(boxCFrame)
	local targetBoxCFrame = CFrame.new(0, math.max(2.2, boxSize.Y * 0.5), 0) * CFrame.Angles(0, math.rad(25), 0)
	model:PivotTo(targetBoxCFrame * offset:Inverse())

	local _, positionedSize = model:GetBoundingBox()
	previewFocus = Vector3.new(0, math.max(2.5, positionedSize.Y * 0.56), 0)
	previewCameraDistance = math.max(12, positionedSize.X * 1.45 + positionedSize.Z + 3.5)
	previewCameraHeight = math.max(3.8, positionedSize.Y * 0.33)

	if nameLabel then
		nameLabel.Text = horseOption.DisplayName or horseOption.CatalogId
	end

	update_rarity(horseOption)
end

local function select_horse_index(index)
	if #horseOptions == 0 then
		selectedHorseIndex = 0
		return
	end

	selectedHorseIndex = math.clamp(index, 1, #horseOptions)
	mount_preview_horse(horseOptions[selectedHorseIndex])
end

local function acknowledge_reveal(horseId)
	if type(horseId) ~= "string" or horseId == "" then
		return
	end

	acknowledgeRevealRemote:FireServer(horseId)
end

local function hide_reveal()
	isShowingReveal = false
	currentRevealHorseId = nil
	if screenGui then
		screenGui.Enabled = false
	end
end

local function play_reveal_animation(pendingReveal)
	if type(pendingReveal) ~= "table" then
		return
	end

	local finalIndex = find_horse_index(pendingReveal.CatalogId)
	if not finalIndex then
		acknowledge_reveal(pendingReveal.HorseId)
		return
	end

	if currentRevealHorseId == pendingReveal.HorseId and isShowingReveal then
		return
	end

	build_ui()

	isShowingReveal = true
	currentRevealHorseId = pendingReveal.HorseId
	screenGui.Enabled = true
	revealLabel.Visible = false
	subtitleLabel.Text = "A roleta vai desacelerar ate mostrar qual cavalo e seu."
	orbitAngle = -1.3

	if cardScale then
		cardScale.Scale = 1
	end

	local currentIndex = selectedHorseIndex > 0 and selectedHorseIndex or 1
	select_horse_index(currentIndex)

	task.spawn(function()
		for stepIndex, delaySeconds in ipairs(SPIN_DELAYS) do
			if not isShowingReveal or currentRevealHorseId ~= pendingReveal.HorseId then
				return
			end

			if stepIndex == #SPIN_DELAYS then
				currentIndex = finalIndex
			else
				local attempts = 0
				repeat
					currentIndex = (currentIndex % #horseOptions) + 1
					attempts += 1
				until currentIndex ~= finalIndex or stepIndex >= (#SPIN_DELAYS - 4) or attempts > #horseOptions
			end

			select_horse_index(currentIndex)
			task.wait(delaySeconds)
		end

		if not isShowingReveal or currentRevealHorseId ~= pendingReveal.HorseId then
			return
		end

		subtitleLabel.Text = "Esse foi o cavalo sorteado para voce."
		revealLabel.Text = "Primeiro cavalo desbloqueado"
		revealLabel.Visible = true
		revealScale.Scale = 0.82

		local popTween = TweenService:Create(
			revealScale,
			TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)
		local growTween = TweenService:Create(
			cardScale,
			TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1.03 }
		)
		local settleTween = TweenService:Create(
			cardScale,
			TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Scale = 1 }
		)

		popTween:Play()
		local settleConnection
		settleConnection = growTween.Completed:Connect(function()
			if settleConnection then
				settleConnection:Disconnect()
				settleConnection = nil
			end
			settleTween:Play()
		end)
		growTween:Play()

		task.wait(2)
		acknowledge_reveal(pendingReveal.HorseId)
		hide_reveal()
	end)
end

build_ui()

RunService.RenderStepped:Connect(function(deltaTime)
	if not screenGui or not screenGui.Enabled or not previewCamera or not previewModel then
		return
	end

	orbitAngle += deltaTime * (isShowingReveal and 1.05 or 0.34)

	local focus = previewFocus
	local position = focus + Vector3.new(
		math.cos(orbitAngle) * previewCameraDistance,
		previewCameraHeight,
		math.sin(orbitAngle) * previewCameraDistance
	)

	previewCamera.CFrame = CFrame.lookAt(position, focus + Vector3.new(0, 0.3, 0))
end)

DataUtility.client.bind("Progression.PendingHorseReveal", function(pendingReveal)
	if type(pendingReveal) == "table" then
		play_reveal_animation(pendingReveal)
	end
end)

local initialPendingReveal = DataUtility.client.get("Progression.PendingHorseReveal")
if type(initialPendingReveal) == "table" then
	play_reveal_animation(initialPendingReveal)
end
