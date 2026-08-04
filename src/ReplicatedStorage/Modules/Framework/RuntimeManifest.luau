--!strict

export type Entrypoint = {
	Name: string,
	Path: { string },
}

local function Entry(Name: string, ...: string): Entrypoint
	return table.freeze({
		Name = Name,
		Path = table.freeze({ ... }),
	})
end

local RuntimeManifest = {
	Server = table.freeze({}),
	Client = table.freeze({
		Entry("DisableReset", "Hud", "DisableReset"),
		Entry("Hotbar", "Hud", "Hotbar"),
		Entry("ZoneFrames", "Hud", "ZoneFrames"),
		Entry("Settings", "Hud", "Settings"),
		Entry("ZoneTeleport", "Hud", "ZoneTeleport"),
		Entry("Inventory", "Hud", "Inventory"),
		Entry("Quests", "Hud", "Quests"),
		Entry("Stable", "Hud", "Stable"),
		Entry("Index", "Hud", "Index"),
		Entry("Cooking", "Hud", "Cooking"),
		Entry("FarmingShop", "Hud", "FarmingShop"),
		Entry("NpcSeller", "Hud", "NpcSeller"),
		Entry("Upgrade", "Hud", "Upgrade"),
		Entry("Shop", "Hud", "Shop"),
		Entry("HorseStarterReveal", "Hud", "HorseStarterReveal"),
		Entry("HorseRoulette", "Hud", "HorseRoulette"),
		Entry("HorseRace", "Hud", "HorseRace"),
		Entry("HorseMount", "Hud", "HorseMount"),
		Entry("ObstacleFeedback", "Hud", "ObstacleFeedback"),
		Entry("AdminPanel", "Hud", "AdminPanel"),
		Entry("FruitViewportCapture", "Hud", "FruitViewportCapture"),
		Entry("BaseSigns", "Visual", "BaseSigns"),
		Entry("Farming", "Visual", "Farming"),
		Entry("HorseIdle", "Visual", "HorseIdle"),
		Entry("HorseBondBillboards", "Visual", "HorseBondBillboards"),
		Entry("HorseStatusBillboards", "Visual", "HorseStatusBillboards"),
		Entry("Music", "Visual", "Music"),
		Entry("ProximityConfig", "Visual", "ProximityConfig"),
		Entry("HayBaleCarryAnimations", "Tools", "HayBaleCarryAnimations"),
		Entry("HayBalePrompts", "Tools", "HayBalePrompts"),
		Entry("HorseToolPrompts", "Tools", "HorseToolPrompts"),
		Entry("StableCleaningPrompts", "Tools", "StableCleaningPrompts"),
		Entry("WaterTankPrompts", "Tools", "WaterTankPrompts"),
		Entry("WellCrank", "Tools", "WellCrank"),
	}),
}

return table.freeze(RuntimeManifest)
