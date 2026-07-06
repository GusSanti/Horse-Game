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

------------------//MAIN FUNCTIONS
StableDictionary.HorseSlotOrder = HORSE_SLOT_ORDER
StableDictionary.DefaultOwnedStalls = DEFAULT_OWNED_STALLS
StableDictionary.MaxOwnedStalls = MAX_OWNED_STALLS
StableDictionary.SlotPurchasePrices = SLOT_PURCHASE_PRICES

------------------//INIT
return StableDictionary
