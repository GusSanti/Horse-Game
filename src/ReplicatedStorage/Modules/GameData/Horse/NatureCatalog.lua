local NatureCatalog = {}

NatureCatalog.RoulettePrice = 250

NatureCatalog.RarityOrder = {
	Common = 1,
	Uncommon = 2,
	Rare = 3,
	Epic = 4,
	Legendary = 5,
}

local function define(id, displayName, rarity, description, effectText, effects)
	return {
		Id = id,
		DisplayName = displayName,
		Rarity = rarity,
		Description = description,
		EffectText = effectText,
		Effects = effects or {},
	}
end

NatureCatalog.Definitions = {
	calm = define(
		"calm",
		"Tranquilo",
		"Common",
		"Mantém a cabeça fria e responde de forma previsível.",
		"+5% controle e necessidades decaem 5% mais devagar.",
		{ Movement = { TurnRate = 1.05 }, NeedDecay = 0.95 }
	),
	timid = define(
		"timid",
		"Medroso",
		"Common",
		"Precisa de carinho e vínculo antes de confiar totalmente no cavaleiro.",
		"Com pouco vínculo pode cair a 82% do desempenho; chega a 100% com 70 de amizade. +30% vínculo.",
		{
			LowBondPerformance = 0.82,
			FullPerformanceFriendship = 70,
			FriendshipGain = 1.3,
			HappinessGain = 1.2,
		}
	),
	playful = define(
		"playful",
		"Brincalhão",
		"Common",
		"Adora atenção e transforma cuidados em motivação.",
		"+20% felicidade nos cuidados, +8% aceleração e -4% foco de corrida.",
		{
			Movement = { Acceleration = 1.08, RaceAffinity = 0.96 },
			HappinessGain = 1.2,
		}
	),
	stubborn = define(
		"stubborn",
		"Teimoso",
		"Common",
		"É forte, mas só entrega tudo quando passa a respeitar o cavaleiro.",
		"Com pouco vínculo pode cair a 90% do desempenho; chega a 100% com 45 de amizade. +6% stamina.",
		{
			Movement = { Stamina = 1.06 },
			LowBondPerformance = 0.9,
			FullPerformanceFriendship = 45,
		}
	),
	curious = define(
		"curious",
		"Curioso",
		"Common",
		"Aprende rápido, porém se distrai com facilidade.",
		"+12% vínculo e +5% salto, mas -3% controle.",
		{
			Movement = { Jump = 1.05, TurnRate = 0.97 },
			FriendshipGain = 1.12,
		}
	),
	gentle = define(
		"gentle",
		"Gentil",
		"Uncommon",
		"Aceita cuidados com facilidade e cria laços rapidamente.",
		"+20% vínculo, +15% felicidade e necessidades decaem 8% mais devagar.",
		{ FriendshipGain = 1.2, HappinessGain = 1.15, NeedDecay = 0.92 }
	),
	energetic = define(
		"energetic",
		"Energético",
		"Uncommon",
		"Arranca com força e gosta de manter um ritmo acelerado.",
		"+6% velocidade e +10% aceleração, mas -8% stamina.",
		{
			Movement = {
				WalkSpeed = 1.04,
				TrotSpeed = 1.05,
				CanterSpeed = 1.06,
				SprintSpeed = 1.06,
				Acceleration = 1.1,
				Stamina = 0.92,
			},
		}
	),
	loyal = define(
		"loyal",
		"Leal",
		"Uncommon",
		"Fica melhor quanto mais forte é o vínculo com seu cavaleiro.",
		"Até +8% de desempenho ao alcançar 80 de amizade e +15% vínculo.",
		{ HighBondPerformance = 1.08, HighBondFriendship = 80, FriendshipGain = 1.15 }
	),
	brave = define(
		"brave",
		"Valente",
		"Uncommon",
		"Corre sem hesitar mesmo sob pressão.",
		"+7% afinidade de corrida e +4% velocidade de sprint.",
		{ Movement = { RaceAffinity = 1.07, SprintSpeed = 1.04 } }
	),
	focused = define(
		"focused",
		"Focado",
		"Rare",
		"Segue os comandos com precisão e quase nunca perde o ritmo.",
		"+10% controle, +8% afinidade de corrida e +4% aceleração.",
		{ Movement = { TurnRate = 1.1, RaceAffinity = 1.08, Acceleration = 1.04 } }
	),
	athletic = define(
		"athletic",
		"Atlético",
		"Rare",
		"Tem físico completo para velocidade, resistência e salto.",
		"+6% velocidade, +7% stamina e +7% salto.",
		{
			Movement = {
				TrotSpeed = 1.04,
				CanterSpeed = 1.05,
				SprintSpeed = 1.06,
				Stamina = 1.07,
				Jump = 1.07,
			},
		}
	),
	resilient = define(
		"resilient",
		"Resistente",
		"Rare",
		"Conserva energia e precisa de menos manutenção ao longo do dia.",
		"+12% stamina e necessidades decaem 15% mais devagar.",
		{ Movement = { Stamina = 1.12 }, NeedDecay = 0.85 }
	),
	fearless = define(
		"fearless",
		"Destemido",
		"Epic",
		"Uma natureza rara que combina coragem com explosão.",
		"+9% sprint, +10% afinidade de corrida e +6% aceleração.",
		{ Movement = { SprintSpeed = 1.09, RaceAffinity = 1.1, Acceleration = 1.06 } }
	),
	prodigy = define(
		"prodigy",
		"Prodígio",
		"Epic",
		"Aprende depressa e parece melhorar a cada interação.",
		"+35% vínculo e até +10% desempenho com 70 de amizade.",
		{ FriendshipGain = 1.35, HighBondPerformance = 1.1, HighBondFriendship = 70 }
	),
	champion = define(
		"champion",
		"Campeão",
		"Legendary",
		"Nasceu para competir e se destaca em todos os fundamentos de corrida.",
		"+10% sprint, +8% stamina, +8% aceleração e +12% afinidade de corrida.",
		{
			Movement = {
				SprintSpeed = 1.1,
				Stamina = 1.08,
				Acceleration = 1.08,
				RaceAffinity = 1.12,
			},
		}
	),
	kindred_spirit = define(
		"kindred_spirit",
		"Alma Gêmea",
		"Legendary",
		"Cria um vínculo excepcional e floresce quando é bem cuidado.",
		"+50% vínculo, +25% felicidade, necessidades -12% e até +12% desempenho.",
		{
			FriendshipGain = 1.5,
			HappinessGain = 1.25,
			NeedDecay = 0.88,
			HighBondPerformance = 1.12,
			HighBondFriendship = 75,
		}
	),
}

NatureCatalog.RoulettePool = {
	{ NatureId = "calm", Weight = 170 },
	{ NatureId = "timid", Weight = 150 },
	{ NatureId = "playful", Weight = 140 },
	{ NatureId = "stubborn", Weight = 120 },
	{ NatureId = "curious", Weight = 110 },
	{ NatureId = "gentle", Weight = 70 },
	{ NatureId = "energetic", Weight = 60 },
	{ NatureId = "loyal", Weight = 55 },
	{ NatureId = "brave", Weight = 45 },
	{ NatureId = "focused", Weight = 25 },
	{ NatureId = "athletic", Weight = 20 },
	{ NatureId = "resilient", Weight = 15 },
	{ NatureId = "fearless", Weight = 8 },
	{ NatureId = "prodigy", Weight = 7 },
	{ NatureId = "champion", Weight = 3 },
	{ NatureId = "kindred_spirit", Weight = 2 },
}

local function copy_dictionary(source)
	local result = {}
	for key, value in pairs(source or {}) do
		result[key] = value
	end
	return result
end

local function get_nature_id(horse)
	if type(horse) ~= "table" then
		return nil
	end

	if type(horse.Nature) == "table" then
		return horse.Nature.Id
	end

	if type(horse.Nature) == "string" then
		return horse.Nature
	end

	return horse.NatureId
end

function NatureCatalog.GetDefinition(natureId)
	return NatureCatalog.Definitions[natureId]
end

function NatureCatalog.GetHorseNatureDefinition(horse)
	return NatureCatalog.GetDefinition(get_nature_id(horse))
end

function NatureCatalog.GetRouletteOptions()
	local options = {}

	for _, entry in ipairs(NatureCatalog.RoulettePool) do
		local definition = NatureCatalog.GetDefinition(entry.NatureId)
		if definition then
			options[#options + 1] = {
				NatureId = definition.Id,
				Id = definition.Id,
				DisplayName = definition.DisplayName,
				Rarity = definition.Rarity,
				Description = definition.Description,
				EffectText = definition.EffectText,
				Weight = entry.Weight,
			}
		end
	end

	return options
end

function NatureCatalog.RollNatureId()
	local totalWeight = 0
	for _, entry in ipairs(NatureCatalog.RoulettePool) do
		totalWeight += math.max(0, math.floor(tonumber(entry.Weight) or 0))
	end

	if totalWeight <= 0 then
		return "calm"
	end

	local roll = math.random(1, totalWeight)
	local runningTotal = 0
	for _, entry in ipairs(NatureCatalog.RoulettePool) do
		runningTotal += math.max(0, math.floor(tonumber(entry.Weight) or 0))
		if roll <= runningTotal then
			return entry.NatureId
		end
	end

	return "calm"
end

function NatureCatalog.BuildRecord(natureId, source, rolledAt)
	local definition = NatureCatalog.GetDefinition(natureId) or NatureCatalog.GetDefinition("calm")
	return {
		Id = definition.Id,
		DisplayName = definition.DisplayName,
		Rarity = definition.Rarity,
		Description = definition.Description,
		EffectText = definition.EffectText,
		Source = source or "Generated",
		RolledAt = rolledAt or os.time(),
	}
end

function NatureCatalog.SetHorseNature(horse, natureId, source, rolledAt)
	if type(horse) ~= "table" then
		return nil
	end

	local record = NatureCatalog.BuildRecord(natureId, source, rolledAt)
	horse.Nature = record
	horse.NatureId = nil
	return record
end

function NatureCatalog.NormalizeHorseNature(horse, rolledAt)
	if type(horse) ~= "table" then
		return false
	end

	local natureId = get_nature_id(horse)
	local definition = NatureCatalog.GetDefinition(natureId)
	local current = horse.Nature
	local needsRefresh = type(current) ~= "table"
		or not definition
		or current.DisplayName ~= definition.DisplayName
		or current.Rarity ~= definition.Rarity
		or current.Description ~= definition.Description
		or current.EffectText ~= definition.EffectText

	if not definition then
		natureId = NatureCatalog.RollNatureId()
		needsRefresh = true
	end

	if needsRefresh or horse.NatureId ~= nil then
		local source = type(current) == "table" and current.Source or "LegacyMigration"
		NatureCatalog.SetHorseNature(horse, natureId, source, rolledAt)
		return true
	end

	return false
end

function NatureCatalog.GetCareMultipliers(horse)
	local definition = NatureCatalog.GetHorseNatureDefinition(horse)
	local effects = definition and definition.Effects or {}
	return {
		FriendshipGain = tonumber(effects.FriendshipGain) or 1,
		HappinessGain = tonumber(effects.HappinessGain) or 1,
		NeedDecay = tonumber(effects.NeedDecay) or 1,
	}
end

function NatureCatalog.GetPerformanceMultiplier(horse)
	local definition = NatureCatalog.GetHorseNatureDefinition(horse)
	local effects = definition and definition.Effects or {}
	local bond = type(horse) == "table" and horse.Bond or {}
	local friendship = math.max(0, tonumber(bond and bond.Friendship) or 0)
	local multiplier = 1

	local fullPerformanceFriendship = tonumber(effects.FullPerformanceFriendship)
	if fullPerformanceFriendship and fullPerformanceFriendship > 0 then
		local lowBondPerformance = math.clamp(tonumber(effects.LowBondPerformance) or 1, 0.5, 1)
		local progress = math.clamp(friendship / fullPerformanceFriendship, 0, 1)
		multiplier *= lowBondPerformance + ((1 - lowBondPerformance) * progress)
	end

	local highBondPerformance = tonumber(effects.HighBondPerformance)
	local highBondFriendship = tonumber(effects.HighBondFriendship)
	if highBondPerformance and highBondPerformance > 1 and highBondFriendship and highBondFriendship > 0 then
		local progress = math.clamp(friendship / highBondFriendship, 0, 1)
		multiplier *= 1 + ((highBondPerformance - 1) * progress)
	end

	return multiplier
end

function NatureCatalog.GetEffectiveMovement(horse)
	local movement = type(horse) == "table" and horse.Movement or {}
	local definition = NatureCatalog.GetHorseNatureDefinition(horse)
	local effects = definition and definition.Effects or {}
	local natureMovement = effects.Movement or {}
	local performance = NatureCatalog.GetPerformanceMultiplier(horse)
	local result = copy_dictionary(movement)

	for _, statName in ipairs({
		"WalkSpeed",
		"TrotSpeed",
		"CanterSpeed",
		"SprintSpeed",
		"Acceleration",
		"TurnRate",
		"Stamina",
		"Jump",
		"RaceAffinity",
	}) do
		local baseValue = tonumber(movement[statName])
		if baseValue then
			local natureMultiplier = tonumber(natureMovement[statName]) or 1
			result[statName] = baseValue * natureMultiplier * performance
		end
	end

	return result, performance
end

return NatureCatalog
