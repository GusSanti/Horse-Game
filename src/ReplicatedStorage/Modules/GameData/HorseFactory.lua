local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Utility = Modules:WaitForChild("Utility")

local HorseCatalog = require(GameData:WaitForChild("HorseCatalog"))
local TableUtility = require(Utility:WaitForChild("TableUtility"))

local HorseFactory = {}

function HorseFactory.Create(catalogId, instanceId, options)
	options = options or {}

	local definition = HorseCatalog.GetDefinition(catalogId)
	if not definition then
		error(("HorseFactory.Create could not find catalog id '%s'"):format(tostring(catalogId)))
	end

	local now = options.ObtainedAt or os.time()
	local horseId = options.HorseId or ("horse_%d"):format(instanceId)

	return {
		Id = horseId,
		InstanceId = instanceId,
		CatalogId = definition.CatalogId,
		DisplayName = definition.DisplayName,
		Nickname = options.Nickname or definition.ShortName or definition.DisplayName,
		Tier = definition.Tier,
		Rarity = definition.Rarity,
		LaunchGroup = definition.LaunchGroup,
		PlaceholderModelKey = definition.PlaceholderModelKey,
		Description = definition.Description,
		OwnerUserId = options.OwnerUserId or 0,
		Acquisition = {
			Source = options.Source or "Unknown",
			ObtainedAt = now,
			IsStarterGrant = options.IsStarterGrant == true,
		},
		Bond = {
			Level = 1,
			XP = 0,
			MaxLevel = definition.Bonding.MaxBondLevel,
			Friendship = definition.Bonding.StartingFriendship,
			MaxFriendship = definition.Bonding.MaxFriendship,
			CareBonus = TableUtility.DeepCopy(definition.Bonding.CareBonus),
		},
		Needs = {
			Values = TableUtility.DeepCopy(definition.Needs.Starting),
			Max = TableUtility.DeepCopy(definition.Needs.Max),
			DecayPerHour = TableUtility.DeepCopy(definition.Needs.DecayPerHour),
			LastUpdatedAt = now,
		},
		Movement = TableUtility.DeepCopy(definition.Movement),
		Temperament = TableUtility.DeepCopy(definition.Temperament),
		Dependencies = TableUtility.DeepCopy(definition.Dependencies),
		State = {
			Mood = "Curious",
			Energy = 100,
			IsDirty = false,
			IsSaddled = false,
			LastCareAt = 0,
			LastFedAt = 0,
			LastWateredAt = 0,
			LastGroomedAt = 0,
			LastCleanedAt = 0,
		},
		Equipment = {
			SaddleItemId = "",
			BridleItemId = "",
			SaddlePadItemId = "",
			AccessoryItemIds = {},
		},
		Stats = {
			CareActions = 0,
			RacesEntered = 0,
			RacesWon = 0,
			BestRaceTimeMs = 0,
		},
	}
end

return HorseFactory
