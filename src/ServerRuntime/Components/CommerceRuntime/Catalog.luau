--!strict

local MarketplaceService: MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local RobuxShopCatalog: any = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameData"):WaitForChild("RobuxShopCatalog")
)

local Catalog = {}

local function GetInfoType(ProductType: string): Enum.InfoType
	if ProductType == "GamePass" then
		return Enum.InfoType.GamePass
	end
	return Enum.InfoType.Product
end

local function BuildLiveProductPayload(Definition: any): any
	local Payload: any = RobuxShopCatalog.BuildStaticProductPayload(Definition)
	local Success: boolean, ProductInfo: any = pcall(
		MarketplaceService.GetProductInfo,
		MarketplaceService,
		Definition.ProductId,
		GetInfoType(Definition.ProductType)
	)

	Payload.IsForSale = false
	Payload.PriceInRobux = nil
	Payload.MarketplaceName = Definition.DisplayName
	if Success and type(ProductInfo) == "table" then
		Payload.IsForSale = ProductInfo.IsForSale ~= false
		Payload.PriceInRobux = tonumber(ProductInfo.PriceInRobux)
		Payload.MarketplaceName = ProductInfo.Name or Payload.MarketplaceName
		Payload.Image = RobuxShopCatalog.ResolveImageUri(Definition, ProductInfo.IconImageAssetId)
	end
	return Payload
end

function Catalog.BuildResponse(): any
	local Response: any = {
		Success = true,
		DeveloperProducts = {},
		GamePasses = {},
	}
	for _Index: number, Definition: any in RobuxShopCatalog.GetDeveloperProductDefinitions() do
		Response.DeveloperProducts[Definition.Key] = BuildLiveProductPayload(Definition)
	end
	for _Index: number, Definition: any in RobuxShopCatalog.GetGamePassDefinitions() do
		Response.GamePasses[Definition.Key] = BuildLiveProductPayload(Definition)
	end
	return Response
end

return Catalog
