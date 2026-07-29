local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local NatureCatalog = require(GameData:WaitForChild("NatureCatalog"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local HorseEquipmentUtility = {}

local MOVEMENT_BONUS_FIELDS = {
	WalkSpeed = "WalkSpeedAdd",
	TrotSpeed = "TrotSpeedAdd",
	CanterSpeed = "CanterSpeedAdd",
	SprintSpeed = "SprintSpeedAdd",
	Acceleration = "AccelerationAdd",
	TurnRate = "TurnRateAdd",
	Stamina = "StaminaAdd",
	Jump = "JumpAdd",
	RaceAffinity = "RaceAffinityAdd",
}

function HorseEquipmentUtility.GetSaddleVisualAsset(itemDefinitionOrId): Model?
	local itemId = type(itemDefinitionOrId) == "table" and itemDefinitionOrId.ItemId or itemDefinitionOrId
	if type(itemId) ~= "string" or itemId == "" then
		return nil
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local horseEquipment = assets and assets:FindFirstChild("HorseEquipment")
	local saddles = horseEquipment and horseEquipment:FindFirstChild("Saddles")
	local asset = saddles and saddles:FindFirstChild(itemId)
	return asset and asset:IsA("Model") and asset or nil
end

function HorseEquipmentUtility.GetEquippedSaddleDefinition(horse)
	local equipment = type(horse) == "table" and horse.Equipment or nil
	local saddleItemId = type(equipment) == "table" and equipment.SaddleItemId or nil
	if type(saddleItemId) ~= "string" or saddleItemId == "" then
		return nil
	end

	local definition = ToolItemCatalog.GetItemDefinition(saddleItemId)
	if not definition or definition.EquipmentType ~= "Saddle" then
		return nil
	end

	return definition
end

function HorseEquipmentUtility.ApplySaddleBonuses(horse, movement)
	local result = {}
	for key, value in pairs(type(movement) == "table" and movement or {}) do
		result[key] = value
	end

	local saddleDefinition = HorseEquipmentUtility.GetEquippedSaddleDefinition(horse)
	local bonuses = saddleDefinition and saddleDefinition.SaddleBonuses or {}

	for movementName, bonusName in pairs(MOVEMENT_BONUS_FIELDS) do
		local currentValue = tonumber(result[movementName])
		local bonusValue = tonumber(bonuses[bonusName])
		if currentValue and bonusValue then
			result[movementName] = currentValue + bonusValue
		end
	end

	return result, saddleDefinition
end

function HorseEquipmentUtility.GetEffectiveMovement(horse)
	local natureMovement, naturePerformance = NatureCatalog.GetEffectiveMovement(horse)
	local movement, saddleDefinition = HorseEquipmentUtility.ApplySaddleBonuses(horse, natureMovement)
	return movement, naturePerformance, saddleDefinition
end

return HorseEquipmentUtility
