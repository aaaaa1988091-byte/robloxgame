local Catalog = {}

Catalog.Items = {
	{ id = "sell_sand", name = "出售沙子", description = "把背包裡的沙子全部換成金幣，每顆 +5。", action = "Sell", item = "", price = 0, model = { kind = "block", size = Vector3.new(2.5, 2.5, 2.5), color = Color3.fromRGB(235, 205, 130), material = Enum.Material.Sand } },
	{ id = "fists", name = "空手", description = "不拿鎬子，切回空手狀態。已購買的工具會保留，可隨時再裝備。", action = "BuyTool", item = "拳頭", price = 0, model = { kind = "block", size = Vector3.new(1.5, 1.5, 1.5), color = Color3.fromRGB(245, 210, 170), material = Enum.Material.SmoothPlastic } },
	{ id = "wood_pickaxe", name = "木鎬", description = "工具強度 20 / 秒，適合開始挖深一點。", action = "BuyTool", item = "木鎬", price = 150, model = { kind = "pickaxe", color = Color3.fromRGB(126, 78, 36), material = Enum.Material.Wood } },
	{ id = "iron_pickaxe", name = "鐵鎬", description = "工具強度 50 / 秒，更快打穿中層沙子。", action = "BuyTool", item = "鐵鎬", price = 500, model = { kind = "pickaxe", color = Color3.fromRGB(180, 185, 190), material = Enum.Material.Metal } },
	{ id = "diamond_pickaxe", name = "鑽石鎬", description = "工具強度 100 / 秒，深層挖礦核心裝備。", action = "BuyTool", item = "鑽石鎬", price = 1500, model = { kind = "pickaxe", color = Color3.fromRGB(45, 210, 235), material = Enum.Material.Neon } },
	{ id = "iron_drill", name = "鐵鑽頭", description = "自動工具：按住即可連續挖掘，工具強度 35 / 秒。", action = "BuyTool", item = "鐵鑽頭", price = 3000, model = { kind = "pickaxe", color = Color3.fromRGB(140, 150, 160), material = Enum.Material.Metal } },
	{ id = "diamond_drill", name = "鑽石鑽頭", description = "高級自動工具：按住即可連續挖掘，工具強度 80 / 秒。", action = "BuyTool", item = "鑽石鑽頭", price = 9000, model = { kind = "pickaxe", color = Color3.fromRGB(65, 240, 255), material = Enum.Material.Neon } },
	{ id = "bomb", name = "炸彈", description = "可無限重複購買。投擲後以拋物線飛出並爆炸。", action = "BuyBomb", item = "", price = 50, model = { kind = "bomb", color = Color3.fromRGB(25, 25, 25), material = Enum.Material.Slate } },
	{ id = "cluster_bomb", name = "集束炸彈", description = "高級炸彈：價格為普通炸彈 3 倍，可堆疊，爆炸範圍更大。", action = "BuyBomb", item = "ClusterBombCount", price = 150, model = { kind = "bomb", color = Color3.fromRGB(120, 30, 30), material = Enum.Material.Metal } },
	{ id = "sand_pet", name = "沙漠小蜥蜴", description = "會跟著你，並且每隔一段時間慢慢吃掉附近一顆沙子。", action = "BuyPet", item = "SandPet", price = 2500, model = { kind = "bomb", color = Color3.fromRGB(210, 170, 75), material = Enum.Material.SmoothPlastic } },
}

Catalog.Backpacks = {
	{ id = "small_backpack", name = "小背包", capacity = 40, price = 250, color = Color3.fromRGB(95, 140, 205) },
	{ id = "trail_backpack", name = "旅行背包", capacity = 70, price = 650, color = Color3.fromRGB(75, 170, 120) },
	{ id = "miner_backpack", name = "礦工背包", capacity = 110, price = 1300, color = Color3.fromRGB(180, 130, 65) },
	{ id = "wide_backpack", name = "寬口背包", capacity = 160, price = 2300, color = Color3.fromRGB(200, 90, 75) },
	{ id = "steel_backpack", name = "鋼架背包", capacity = 230, price = 3800, color = Color3.fromRGB(130, 145, 160) },
	{ id = "desert_backpack", name = "沙漠背包", capacity = 320, price = 5600, color = Color3.fromRGB(220, 180, 95) },
	{ id = "crystal_backpack", name = "水晶背包", capacity = 450, price = 8200, color = Color3.fromRGB(90, 220, 240) },
	{ id = "royal_backpack", name = "皇家背包", capacity = 620, price = 12000, color = Color3.fromRGB(175, 95, 230) },
	{ id = "void_backpack", name = "虛空背包", capacity = 850, price = 17500, color = Color3.fromRGB(45, 45, 75) },
	{ id = "endless_backpack", name = "無盡背包", capacity = 1200, price = 26000, color = Color3.fromRGB(255, 220, 90) },
}

function Catalog.getShopCatalog()
	local catalog = table.clone(Catalog.Items)
	for _, backpack in ipairs(Catalog.Backpacks) do
		table.insert(catalog, {
			id = backpack.id,
			name = backpack.name,
			description = "購買後背包容量變為 " .. backpack.capacity .. "。背包和鎬子一樣是直接購買不同大小。",
			action = "BuyBackpack",
			item = tostring(backpack.capacity),
			price = backpack.price,
			model = { kind = "backpack", color = backpack.color, material = Enum.Material.Fabric },
		})
	end
	return catalog
end

return Catalog
