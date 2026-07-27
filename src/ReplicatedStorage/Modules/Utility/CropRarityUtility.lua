local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CropRarityUtility = {}

local RARITY_VFX_ATTRIBUTE = "CropRarityVFX"
local VIEWPORT_OVERLAY_NAME = "CropRarityVFXOverlay"

local STATIC_PARTICLE_LAYOUT = {
	{ X = 0.32, Y = 0.58, Size = 1.0, Rotation = -24, Transparency = 0.06 },
	{ X = 0.48, Y = 0.38, Size = 0.72, Rotation = 16, Transparency = 0.16 },
	{ X = 0.62, Y = 0.54, Size = 0.92, Rotation = 32, Transparency = 0.08 },
	{ X = 0.40, Y = 0.72, Size = 0.64, Rotation = 68, Transparency = 0.2 },
	{ X = 0.70, Y = 0.31, Size = 0.58, Rotation = -42, Transparency = 0.24 },
	{ X = 0.24, Y = 0.42, Size = 0.5, Rotation = 48, Transparency = 0.28 },
	{ X = 0.76, Y = 0.66, Size = 0.68, Rotation = -6, Transparency = 0.18 },
	{ X = 0.55, Y = 0.77, Size = 0.46, Rotation = 86, Transparency = 0.3 },
	{ X = 0.29, Y = 0.28, Size = 0.44, Rotation = 9, Transparency = 0.34 },
	{ X = 0.84, Y = 0.48, Size = 0.52, Rotation = -74, Transparency = 0.26 },
}

local function get_effect_attachment(itemDefinition): Attachment?
	local vfxName = itemDefinition and itemDefinition.RarityVFXName
	if type(vfxName) ~= "string" or vfxName == "" then
		return nil
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local vfx = assets and assets:FindFirstChild("VFX")
	local stars = vfx and vfx:FindFirstChild("Stars")
	local effect = stars and stars:FindFirstChild(vfxName)
	local attachment = effect and effect:FindFirstChild("Main", true)

	if attachment and attachment:IsA("Attachment") then
		return attachment
	end

	return nil
end

local function get_effect_target(root: Instance): BasePart?
	if root:IsA("BasePart") then
		return root
	end

	local handle = root:FindFirstChild("Handle", true)
	if handle and handle:IsA("BasePart") then
		return handle
	end

	return root:FindFirstChildWhichIsA("BasePart", true)
end

local function remove_existing_effect(root: Instance)
	if root:IsA("Attachment") and root:GetAttribute(RARITY_VFX_ATTRIBUTE) == true then
		root:Destroy()
		return
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant:GetAttribute(RARITY_VFX_ATTRIBUTE) == true then
			descendant:Destroy()
		end
	end
end

local function enable_effects(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
			or descendant:IsA("Light")
		then
			descendant.Enabled = true
		end
	end
end

local function get_sequence_max_value(sequence: NumberSequence): number
	local maxValue = 0

	for _, keypoint in ipairs(sequence.Keypoints) do
		maxValue = math.max(maxValue, keypoint.Value)
	end

	return maxValue
end

local function get_sequence_min_value(sequence: NumberSequence): number
	if #sequence.Keypoints == 0 then
		return 0
	end

	local minValue = 1

	for _, keypoint in ipairs(sequence.Keypoints) do
		minValue = math.min(minValue, keypoint.Value)
	end

	return minValue
end

local function get_emitter_color(emitter: ParticleEmitter, index: number): Color3
	local keypoints = emitter.Color.Keypoints
	if #keypoints == 0 then
		return Color3.new(1, 1, 1)
	end

	return keypoints[((index - 1) % #keypoints) + 1].Value
end

local function create_viewport_particle(overlay: Frame, emitter: ParticleEmitter, index: number, totalCount: number)
	local layout = STATIC_PARTICLE_LAYOUT[((index - 1) % #STATIC_PARTICLE_LAYOUT) + 1]
	local ringOffset = math.floor((index - 1) / #STATIC_PARTICLE_LAYOUT)
	local particle = Instance.new("ImageLabel")
	particle.Name = "RarityParticle"
	particle.AnchorPoint = Vector2.new(0.5, 0.5)
	particle.BackgroundTransparency = 1
	particle.BorderSizePixel = 0
	particle.Image = emitter.Texture
	particle.ImageColor3 = get_emitter_color(emitter, index)
	particle.ImageTransparency = math.clamp(
		math.max(get_sequence_min_value(emitter.Transparency), layout.Transparency),
		0,
		0.75
	)
	particle.ScaleType = Enum.ScaleType.Fit
	particle.ZIndex = overlay.ZIndex + index

	local maxParticleSize = math.max(0.4, get_sequence_max_value(emitter.Size))
	local baseSize = math.clamp(math.floor(maxParticleSize * 18), 12, 46)
	local countScale = math.clamp(10 / math.max(totalCount, 1), 0.72, 1)
	local pixelSize = math.clamp(math.floor(baseSize * layout.Size * countScale), 10, 48)
	particle.Size = UDim2.fromOffset(pixelSize, pixelSize)
	particle.Position = UDim2.fromScale(
		math.clamp(layout.X + ringOffset * 0.025, 0.08, 0.92),
		math.clamp(layout.Y - ringOffset * 0.025, 0.08, 0.88)
	)
	particle.Rotation = layout.Rotation
	particle.Parent = overlay
end

function CropRarityUtility.ApplyToInstance(root: Instance?, itemDefinition): boolean
	if not root then
		return false
	end

	remove_existing_effect(root)

	if not itemDefinition or not itemDefinition.Rarity then
		return false
	end

	local attachmentTemplate = get_effect_attachment(itemDefinition)
	local target = get_effect_target(root)
	if not attachmentTemplate or not target then
		return false
	end

	local attachment = attachmentTemplate:Clone()
	attachment:SetAttribute(RARITY_VFX_ATTRIBUTE, true)
	attachment:SetAttribute("CropRarity", itemDefinition.Rarity)
	enable_effects(attachment)
	attachment.Parent = target

	return true
end

function CropRarityUtility.ApplyToViewport(viewportFrame: ViewportFrame?, itemDefinition): boolean
	if not viewportFrame then
		return false
	end

	local existingOverlay = viewportFrame:FindFirstChild(VIEWPORT_OVERLAY_NAME)
	if existingOverlay then
		existingOverlay:Destroy()
	end

	if not itemDefinition or not itemDefinition.Rarity then
		return false
	end

	local attachmentTemplate = get_effect_attachment(itemDefinition)
	if not attachmentTemplate then
		return false
	end

	local emitters = {}
	for _, descendant in ipairs(attachmentTemplate:GetDescendants()) do
		if descendant:IsA("ParticleEmitter") and descendant.Texture ~= "" then
			emitters[#emitters + 1] = descendant
		end
	end

	if #emitters == 0 then
		return false
	end

	local overlay = Instance.new("Frame")
	overlay.Name = VIEWPORT_OVERLAY_NAME
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ClipsDescendants = true
	overlay.Position = UDim2.fromScale(0, 0)
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = viewportFrame.ZIndex + 2
	overlay.Parent = viewportFrame

	for _, emitter in ipairs(emitters) do
		local particleCount = math.clamp(math.floor(emitter.Rate * 0.12), 4, 10)
		for index = 1, particleCount do
			create_viewport_particle(overlay, emitter, index, particleCount)
		end
	end

	return true
end

return CropRarityUtility
