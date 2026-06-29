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

local DEFAULT_OWNED_STALLS = #HORSE_SLOT_ORDER

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

------------------//MAIN FUNCTIONS
StableDictionary.HorseSlotOrder = HORSE_SLOT_ORDER
StableDictionary.DefaultOwnedStalls = DEFAULT_OWNED_STALLS

------------------//INIT
return StableDictionary
