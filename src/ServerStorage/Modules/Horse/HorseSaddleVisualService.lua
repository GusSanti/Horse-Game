local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SADDLE_VISUAL_NAME = "EquippedSaddleVisual"
local SADDLE_ITEM_ID_ATTRIBUTE = "SaddleItemId"
local MOUNTED_USER_ID_ATTRIBUTE = "MountedUserId"
local SADDLE_ATTACHMENT_NAME = "SaddleAttachment"
local REFERENCE_SADDLE_WIDTH = 2.45

local HorseSaddleVisualService = {}
local missingAssetWarnings = {}

local function get_saddle_item_id(horse): string?
	local equipment = type(horse) == "table" and horse.Equipment or nil
	local saddleItemId = type(equipment) == "table" and equipment.SaddleItemId or nil
	if type(saddleItemId) ~= "string" or saddleItemId == "" then
		return nil
	end

	return saddleItemId
end

local function get_saddle_assets_folder(): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local horseEquipment = assets and assets:FindFirstChild("HorseEquipment")
	return horseEquipment and horseEquipment:FindFirstChild("Saddles") or nil
end

local function find_saddle_asset(itemId: string): Model?
	local folder = get_saddle_assets_folder()
	local asset = folder and folder:FindFirstChild(itemId)
	return asset and asset:IsA("Model") and asset or nil
end

local function find_saddle_attachment(horseVisual: Instance): Attachment?
	for _, descendant in ipairs(horseVisual:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant.Name == SADDLE_ATTACHMENT_NAME then
			return descendant
		end
	end

	return nil
end

local function find_nearest_host_part(horseVisual: Instance, position: Vector3): BasePart?
	if horseVisual:IsA("BasePart") then
		return horseVisual
	end

	if horseVisual:IsA("Model") and horseVisual.PrimaryPart then
		return horseVisual.PrimaryPart
	end

	local nearestPart = nil
	local nearestDistance = math.huge
	for _, descendant in ipairs(horseVisual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local distance = (descendant.Position - position).Magnitude
			if distance < nearestDistance then
				nearestDistance = distance
				nearestPart = descendant
			end
		end
	end

	return nearestPart
end

local function get_saddle_target(horseVisual: Instance): (CFrame, number)
	local attachment = find_saddle_attachment(horseVisual)
	if attachment then
		return attachment.WorldCFrame, 1
	end

	local boxCFrame, boxSize
	if horseVisual:IsA("BasePart") then
		boxCFrame, boxSize = horseVisual.CFrame, horseVisual.Size
	else
		boxCFrame, boxSize = horseVisual:GetBoundingBox()
	end

	local targetCFrame = boxCFrame * CFrame.new(0, boxSize.Y * 0.2, boxSize.Z * 0.08)
	local scale = math.clamp((boxSize.X * 0.58) / REFERENCE_SADDLE_WIDTH, 0.72, 1.35)
	return targetCFrame, scale
end

local function prepare_saddle_parts(saddleVisual: Model, hostPart: BasePart)
	for _, descendant in ipairs(saddleVisual:GetDescendants()) do
		if descendant:IsA("WeldConstraint") then
			descendant:Destroy()
		end
	end

	for _, descendant in ipairs(saddleVisual:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
			descendant.Massless = true

			local weld = Instance.new("WeldConstraint")
			weld.Name = "SaddleHorseWeld"
			weld.Part0 = hostPart
			weld.Part1 = descendant
			weld.Parent = descendant
		end
	end
end

function HorseSaddleVisualService.Sync(horseVisual: Instance, horse): boolean
	if not horseVisual or not horseVisual.Parent then
		return false
	end

	local mountedUserId = tonumber(horseVisual:GetAttribute(MOUNTED_USER_ID_ATTRIBUTE)) or 0
	if mountedUserId > 0 then
		return false
	end

	local itemId = get_saddle_item_id(horse)
	local existingVisual = horseVisual:FindFirstChild(SADDLE_VISUAL_NAME)
	if existingVisual
		and existingVisual:IsA("Model")
		and existingVisual:GetAttribute(SADDLE_ITEM_ID_ATTRIBUTE) == itemId
	then
		return true
	end

	if existingVisual then
		existingVisual:Destroy()
	end

	if not itemId then
		return true
	end

	local source = find_saddle_asset(itemId)
	if not source then
		if not missingAssetWarnings[itemId] then
			missingAssetWarnings[itemId] = true
			warn(
				("[HorseSaddleVisual] Missing 3D asset for '%s'. Run scripts/GenerateSaddleAssets.commandbar.lua in Studio."):format(
					itemId
				)
			)
		end
		return false
	end

	local targetCFrame, scale = get_saddle_target(horseVisual)
	local hostPart = find_nearest_host_part(horseVisual, targetCFrame.Position)
	if not hostPart then
		return false
	end

	local saddleVisual = source:Clone()
	saddleVisual.Name = SADDLE_VISUAL_NAME
	saddleVisual:SetAttribute(SADDLE_ITEM_ID_ATTRIBUTE, itemId)
	saddleVisual.Parent = horseVisual

	pcall(function()
		saddleVisual:ScaleTo(scale)
	end)
	saddleVisual:PivotTo(targetCFrame)
	prepare_saddle_parts(saddleVisual, hostPart)
	return true
end

return HorseSaddleVisualService
