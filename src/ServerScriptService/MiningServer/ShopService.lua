local ShopService = {}

local context = {}

function ShopService.configure(newContext)
	context = newContext or {}
end

function ShopService.getBaseCatalog()
	local catalog = context.catalog
	if catalog and catalog.getShopCatalog then
		return catalog.getShopCatalog()
	end
	return {}
end

function ShopService.getItemById(itemId, runtimeCatalog)
	for _, item in ipairs(runtimeCatalog or ShopService.getBaseCatalog()) do
		if item.id == itemId then
			return item
		end
	end
	return nil
end

function ShopService.getToolPrices(runtimeCatalog)
	local prices = {}
	for _, item in ipairs(runtimeCatalog or ShopService.getBaseCatalog()) do
		if item.action == "BuyTool" then
			prices[item.item] = item.price
		end
	end
	return prices
end

return ShopService
