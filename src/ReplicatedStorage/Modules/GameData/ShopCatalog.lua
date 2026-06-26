local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

local ShopCatalog = {
	Items = ToolItemCatalog.Items,
	Shops = ToolItemCatalog.Shops,
}

function ShopCatalog.GetItemDefinition(itemId)
	return ToolItemCatalog.GetItemDefinition(itemId)
end

function ShopCatalog.GetShopDefinition(shopId)
	return ToolItemCatalog.GetShopDefinition(shopId)
end

function ShopCatalog.GetItemsForShop(shopId)
	return ToolItemCatalog.GetItemsForShop(shopId)
end

return ShopCatalog
