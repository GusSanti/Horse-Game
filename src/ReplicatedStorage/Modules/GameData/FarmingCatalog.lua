local FarmingCatalog = {}

FarmingCatalog.Seed = {
	ItemId = "carrot_seed",
	DisplayName = "Seed",
	InventoryPath = "Inventory.Seeds",
	Price = 1,
	ToolName = "Seed",
	TemplateSearchNames = {
		"Seed",
		"carrot_seed",
	},
}

FarmingCatalog.Fruit = {
	ItemId = "carrot_bunch",
	DisplayName = "Fruit",
	InventoryPath = "Inventory.Consumables.Food",
	SellPrice = 5,
	HarvestYield = 1,
	ToolName = "Fruit",
	TemplateSearchNames = {
		"Fruit",
		"carrot_bunch",
		"CarrotBunch",
	},
}

FarmingCatalog.ManagedItems = {
	FarmingCatalog.Seed,
	FarmingCatalog.Fruit,
}

function FarmingCatalog.GetItemCount(bucket, itemId)
	if type(bucket) ~= "table" then
		return 0
	end

	return bucket[itemId] or 0
end

function FarmingCatalog.GetManagedItems()
	return FarmingCatalog.ManagedItems
end

return FarmingCatalog
