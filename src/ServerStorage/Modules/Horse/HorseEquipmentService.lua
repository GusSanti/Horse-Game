local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local ConsumableToolService = require(script.Parent.Parent:WaitForChild("Inventory"):WaitForChild("ConsumableToolService"))

local HorseEquipmentService = {}

local function get_owned_count(tackInventory, itemId: string): number
	return math.max(0, math.floor(tonumber(tackInventory[itemId]) or 0))
end

function HorseEquipmentService.EquipSaddle(
	player: Player,
	horseId: string,
	saddleItemId: string
): (boolean, string)
	local saddleDefinition = ToolItemCatalog.GetItemDefinition(saddleItemId)
	if not saddleDefinition
		or saddleDefinition.ToolCategory ~= "Tack"
		or saddleDefinition.EquipmentType ~= "Saddle"
	then
		return false, "InvalidSaddle"
	end

	local horses = DataUtility.server.get(player, "Horses")
	local horse = horses and horses.Owned and horses.Owned[horseId]
	if not horse then
		return false, "HorseNotOwned"
	end

	horse.Equipment = type(horse.Equipment) == "table" and horse.Equipment or {}
	local previousSaddleItemId = horse.Equipment.SaddleItemId
	local hadPreviousSaddle = type(previousSaddleItemId) == "string" and previousSaddleItemId ~= ""
	if previousSaddleItemId == saddleItemId then
		return false, "AlreadyEquipped"
	end

	local tackInventory = DataUtility.server.get(player, "Inventory.Tack")
	if type(tackInventory) ~= "table" or get_owned_count(tackInventory, saddleItemId) < 1 then
		return false, "ItemUnavailable"
	end

	local nextCount = get_owned_count(tackInventory, saddleItemId) - 1
	if nextCount > 0 then
		tackInventory[saddleItemId] = nextCount
	else
		tackInventory[saddleItemId] = nil
	end

	if hadPreviousSaddle then
		local previousDefinition = ToolItemCatalog.GetItemDefinition(previousSaddleItemId)
		if previousDefinition and previousDefinition.EquipmentType == "Saddle" then
			tackInventory[previousSaddleItemId] = get_owned_count(tackInventory, previousSaddleItemId) + 1
		end
	end

	local now = os.time()
	horse.Equipment.SaddleItemId = saddleItemId
	horse.Equipment.LastSaddleEquippedAt = now
	horse.State = type(horse.State) == "table" and horse.State or {}
	horse.State.IsSaddled = true
	horse.State.LastCareAt = now

	DataUtility.server.set(player, "Inventory.Tack", tackInventory)
	DataUtility.server.set(player, "Horses", horses)

	local stats = DataUtility.server.get(player, "Stats")
	if stats then
		stats.TotalSaddleEquipActions = (stats.TotalSaddleEquipActions or 0) + 1
		DataUtility.server.set(player, "Stats", stats)
	end

	ConsumableToolService.SyncPlayerTools(player)

	return true, if hadPreviousSaddle then "SaddleSwapped" else "SaddleEquipped"
end

return HorseEquipmentService
