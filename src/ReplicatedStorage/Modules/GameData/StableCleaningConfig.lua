local StableCleaningConfig = {
	TargetType = "StableDirt",
	RemoteFolderName = "StableCleaning",
	CleanRemoteName = "CleanStableDirt",

	DirtFolderName = "StableDirt",
	DirtAttribute = "IsStableDirt",
	DirtIdAttribute = "StableDirtId",
	DirtTypeAttribute = "StableDirtTypeId",
	RequiredToolAttribute = "RequiredCleaningToolId",

	MaxDirtPerHorse = 5,
	MaxDecayMultiplier = 2.5,
	MaxCleanDistance = 12,
	CleanlinessRestorePerDirt = 2,
	AllCleanHappinessBonus = 5,

	InitialSpawnDelaySeconds = 60,
	SpawnIntervalSeconds = 6 * 60,
	SpawnJitterSeconds = 75,
	ServiceTickSeconds = 5,

	-- Short values keep Studio tests practical without changing live balancing.
	StudioInitialSpawnDelaySeconds = 2,
	StudioSpawnIntervalSeconds = 18,
	StudioSpawnJitterSeconds = 3,
	StudioServiceTickSeconds = 1,

	DirtOrder = {
		"loose_hay",
		"mud_patch",
		"manure",
	},

	DirtTypes = {
		loose_hay = {
			Id = "loose_hay",
			DisplayName = "Loose Hay",
			TemplateName = "LooseHay",
			RequiredToolId = "stable_broom",
			ActionText = "Sweep",
			HoldDuration = 0.8,
			Weight = 4,
			DecayMultipliers = {
				Happiness = 1.15,
				Cleanliness = 1.10,
			},
		},
		mud_patch = {
			Id = "mud_patch",
			DisplayName = "Mud Patch",
			TemplateName = "MudPatch",
			RequiredToolId = "cleaning_bucket",
			ActionText = "Rinse",
			HoldDuration = 1.1,
			Weight = 3,
			DecayMultipliers = {
				Cleanliness = 1.30,
				Health = 1.08,
			},
		},
		manure = {
			Id = "manure",
			DisplayName = "Manure",
			TemplateName = "Manure",
			RequiredToolId = "muck_fork",
			ActionText = "Remove",
			HoldDuration = 1.3,
			Weight = 2,
			DecayMultipliers = {
				Cleanliness = 1.35,
				Health = 1.15,
			},
		},
	},
}

local function get_dirt_records(horse)
	local stableCare = type(horse) == "table" and horse.StableCare or nil
	if type(stableCare) ~= "table" or type(stableCare.Dirt) ~= "table" then
		return {}
	end

	return stableCare.Dirt
end

function StableCleaningConfig.GetDirtDefinition(dirtTypeId: string?)
	if type(dirtTypeId) ~= "string" then
		return nil
	end

	return StableCleaningConfig.DirtTypes[dirtTypeId]
end

function StableCleaningConfig.GetDecayMultiplier(horse, statusName: string): number
	local multiplier = 1

	for _, dirtRecord in ipairs(get_dirt_records(horse)) do
		local definition = StableCleaningConfig.GetDirtDefinition(dirtRecord.TypeId)
		local statusMultiplier = definition
			and definition.DecayMultipliers
			and definition.DecayMultipliers[statusName]

		if type(statusMultiplier) == "number" and statusMultiplier > 1 then
			multiplier += statusMultiplier - 1
		end
	end

	return math.clamp(multiplier, 1, StableCleaningConfig.MaxDecayMultiplier)
end

function StableCleaningConfig.GetPenaltySummary(dirtTypeId: string?): string
	local definition = StableCleaningConfig.GetDirtDefinition(dirtTypeId)
	if not definition then
		return ""
	end

	local parts = {}
	for _, statusName in ipairs({ "Happiness", "Cleanliness", "Health" }) do
		local multiplier = definition.DecayMultipliers[statusName]
		if type(multiplier) == "number" and multiplier > 1 then
			local multiplierText = ("%.2f"):format(multiplier)
			multiplierText = string.gsub(multiplierText, "0+$", "")
			multiplierText = string.gsub(multiplierText, "%.$", "")
			parts[#parts + 1] = ("%s x%s"):format(statusName, multiplierText)
		end
	end

	return table.concat(parts, "  |  ")
end

return StableCleaningConfig
