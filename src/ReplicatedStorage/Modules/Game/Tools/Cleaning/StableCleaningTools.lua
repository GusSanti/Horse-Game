local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local StableCleaningConfig = require(GameData:WaitForChild("Horse"):WaitForChild("StableCleaningConfig"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local definitions = {}

for _, itemId in ipairs({
	"stable_broom",
	"muck_fork",
	"cleaning_bucket",
}) do
	local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)

	definitions[#definitions + 1] = {
		id = itemId,
		toolNames = {
			itemId,
			itemDefinition and itemDefinition.DisplayName or itemId,
		},
		target = StableCleaningConfig.TargetType,
		consumeOnUse = false,
		canUse = function()
			return false, "UseOnStableDirt"
		end,
	}
end

return definitions
