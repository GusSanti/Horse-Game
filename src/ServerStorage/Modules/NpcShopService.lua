local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local ConsumableToolService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("ConsumableToolService"))

local NpcShopService = {}
local initialized = false

local NPC_SHOPS = {
	Cowboy = { ShopId = "Cowboy", ActionText = "Shop", ObjectText = "Cowboy" },
	Doctor = { ShopId = "Doctor", ActionText = "Shop", ObjectText = "Doctor" },
}

local function get_inventory_path(item)
	if type(item.InventoryPath) ~= "string" or item.InventoryPath == "" then
		return nil
	end
	if string.sub(item.InventoryPath, 1, 10) == "Inventory." then
		return item.InventoryPath
	end
	return "Inventory." .. item.InventoryPath
end

local function purchase(player, shopId, itemId)
	local item = ToolItemCatalog.GetItemDefinition(itemId)
	if not item or item.ShopId ~= shopId then
		return { Success = false, Code = "UnknownItem" }
	end

	local inventoryPath = get_inventory_path(item)
	if not inventoryPath then
		return { Success = false, Code = "InvalidItem" }
	end

	local horseshoes = math.max(0, math.floor(tonumber(DataUtility.server.get(player, "Currencies.Horseshoes")) or 0))
	local price = math.max(0, math.floor(tonumber(item.Price) or 0))
	if horseshoes < price then
		return { Success = false, Code = "NotEnoughHorseshoes", ItemId = item.ItemId }
	end

	local bucket = DataUtility.server.get(player, inventoryPath) or {}
	local count = math.max(0, math.floor(tonumber(bucket[item.ItemId]) or 0))
	if count >= (item.MaxStack or 99) then
		return { Success = false, Code = "InventoryFull", ItemId = item.ItemId }
	end

	bucket[item.ItemId] = count + 1
	DataUtility.server.set(player, inventoryPath, bucket)
	DataUtility.server.set(player, "Currencies.Horseshoes", horseshoes - price)
	ConsumableToolService.SyncPlayerTools(player)

	return { Success = true, Code = "Purchased", ItemId = item.ItemId, ItemCount = count + 1, Horseshoes = horseshoes - price }
end

local function find_prompt_parent(npc)
	if npc:IsA("BasePart") then
		return npc
	end
	return npc:FindFirstChild("HumanoidRootPart", true) or npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart", true)
end

local function configure_npc(npc, definition)
	local parent = find_prompt_parent(npc)
	if not parent or not parent:IsA("BasePart") then
		return
	end
	local prompt = parent:FindFirstChild("NpcShopPrompt") or Instance.new("ProximityPrompt")
	prompt.Name = "NpcShopPrompt"
	prompt.ActionText = definition.ActionText
	prompt.ObjectText = definition.ObjectText
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("NpcShopId", definition.ShopId)
	prompt.Parent = parent
end

local function configure_npcs()
	local npcs = Workspace:FindFirstChild("Npcs")
	if not npcs then return end
	for npcName, definition in pairs(NPC_SHOPS) do
		local npc = npcs:FindFirstChild(npcName)
		if npc then configure_npc(npc, definition) end
	end
end

function NpcShopService.Init()
	if initialized then return end
	Net.Function.BuyNpcShopItem:Respond(purchase)
	configure_npcs()
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == "Npcs" then configure_npcs() end
	end)
	initialized = true
end

return NpcShopService
