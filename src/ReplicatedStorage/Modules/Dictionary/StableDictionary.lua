------------------//SERVICES

------------------//CONSTANTS
local HORSE_SLOT_ORDER = {
	"Slot1",
	"Slot2",
	"Slot3",
}

local DEFAULT_HORSE_SLOTS = {
	Slot1 = "",
	Slot2 = "",
	Slot3 = "",
}

local DEFAULT_OWNED_STALLS = 1
local MAX_OWNED_STALLS = #HORSE_SLOT_ORDER
local DEFAULT_LEVEL = 1
local MAX_LEVEL = 4
local LEVEL_UPGRADES = {
	[2] = {
		Price = 1000,
		Description = "Expanda seu estábulo e prepare espaço para mais cavalos.",
	},
	[3] = {
		Price = 5000,
		Description = "Melhore para um estábulo maior e mais completo.",
	},
	[4] = {
		Price = 15000,
		Description = "Conclua a expansão definitiva do seu estábulo.",
	},
}
local SLOT_PURCHASE_PRICES = {
	Slot2 = 500,
	Slot3 = 1500,
}

------------------//VARIABLES
local StableDictionary = {}

------------------//FUNCTIONS
function StableDictionary.get_default_horse_slots(): {[string]: string}
	return {
		Slot1 = DEFAULT_HORSE_SLOTS.Slot1,
		Slot2 = DEFAULT_HORSE_SLOTS.Slot2,
		Slot3 = DEFAULT_HORSE_SLOTS.Slot3,
	}
end

function StableDictionary.get_slot_purchase_price(slotName: string): number?
	return SLOT_PURCHASE_PRICES[slotName]
end

function StableDictionary.get_normalized_level(level): number
	return math.clamp(
		math.floor(tonumber(level) or DEFAULT_LEVEL),
		DEFAULT_LEVEL,
		MAX_LEVEL
	)
end

function StableDictionary.get_level_template_name(level): string
	return ("Level%d"):format(StableDictionary.get_normalized_level(level))
end

function StableDictionary.get_level_upgrade(level: number): any?
	local numericLevel = tonumber(level)
	if not numericLevel or numericLevel % 1 ~= 0 then
		return nil
	end

	return LEVEL_UPGRADES[math.floor(numericLevel)]
end

function StableDictionary.get_level_upgrade_price(level: number): number?
	local upgrade = StableDictionary.get_level_upgrade(level)
	return if type(upgrade) == "table" and type(upgrade.Price) == "number" then upgrade.Price else nil
end

------------------//MAIN FUNCTIONS
StableDictionary.HorseSlotOrder = HORSE_SLOT_ORDER
StableDictionary.DefaultOwnedStalls = DEFAULT_OWNED_STALLS
StableDictionary.MaxOwnedStalls = MAX_OWNED_STALLS
StableDictionary.DefaultLevel = DEFAULT_LEVEL
StableDictionary.MaxLevel = MAX_LEVEL
StableDictionary.LevelUpgrades = LEVEL_UPGRADES
StableDictionary.SlotPurchasePrices = SLOT_PURCHASE_PRICES

------------------//INIT
return StableDictionary
