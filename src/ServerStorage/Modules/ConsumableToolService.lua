local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local DataUtility = require(Utility:WaitForChild("DataUtility"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local Trove = require(Libraries:WaitForChild("Trove"))

local ConsumableToolService = {}

local initialized = false
local playerTroves = {}

local MANAGED_TOOL_ATTRIBUTE = "InventoryManaged"
local MANAGED_INVENTORY_PATHS = {
	["Inventory.Consumables.Food"] = true,
	["Inventory.Consumables.Water"] = true,
	["Inventory.Consumables.Grooming"] = true,
	["Inventory.Consumables.Misc"] = true,
	["Inventory.Consumables.Medical"] = true,
}

local TOOL_COLOR_BY_CATEGORY = {
	Food = Color3.fromRGB(231, 175, 87),
	Water = Color3.fromRGB(98, 175, 255),
	Grooming = Color3.fromRGB(225, 157, 188),
	Misc = Color3.fromRGB(201, 201, 201),
	Medicine = Color3.fromRGB(121, 205, 140),
}

local function normalize_key(value): string?
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function normalize_inventory_path(path: string?): string?
	if type(path) ~= "string" then
		return nil
	end

	local trimmedPath = string.gsub(path, "^%s*(.-)%s*$", "%1")
	if trimmedPath == "" then
		return nil
	end

	if string.sub(trimmedPath, 1, #"Inventory.") == "Inventory." then
		return trimmedPath
	end

	return ("Inventory.%s"):format(trimmedPath)
end

local function get_inventory_path(itemDefinition): string?
	if not itemDefinition then
		return nil
	end

	return normalize_inventory_path(itemDefinition.InventoryPath)
end

local function get_item_count(player: Player, itemDefinition): number
	local inventoryPath = get_inventory_path(itemDefinition)
	if not inventoryPath then
		return 0
	end

	local bucket = DataUtility.server.get(player, inventoryPath)
	if type(bucket) ~= "table" then
		return 0
	end

	return bucket[itemDefinition.ItemId] or 0
end

local function is_managed_item(itemDefinition): boolean
	local inventoryPath = get_inventory_path(itemDefinition)
	return inventoryPath ~= nil and MANAGED_INVENTORY_PATHS[inventoryPath] == true
end

local function build_managed_item_list()
	local items = {}

	for _, itemDefinition in ipairs(ToolItemCatalog.GetAllItems()) do
		if is_managed_item(itemDefinition) then
			items[#items + 1] = itemDefinition
		end
	end

	return items
end

local managedItemDefinitions = build_managed_item_list()

local function get_item_search_names(itemDefinition): { string }
	local names = {}
	local seen = {}

	local function push(value)
		if type(value) ~= "string" or value == "" or seen[value] then
			return
		end

		seen[value] = true
		names[#names + 1] = value
	end

	push(itemDefinition.ToolName)
	push(itemDefinition.DisplayName)
	push(itemDefinition.ItemId)

	return names
end

local function find_first_named_asset(root: Instance?, itemDefinition): Instance?
	if not root then
		return nil
	end

	for _, name in ipairs(get_item_search_names(itemDefinition)) do
		local found = root:FindFirstChild(name, true)
		if found then
			return found
		end
	end

	return nil
end

local function get_item_tool_template(itemDefinition): Instance?
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		return nil
	end

	local itemsFolder = assetsFolder:FindFirstChild("Items")
	if not itemsFolder then
		return nil
	end

	local categoryFolderName = ToolItemCatalog.GetCategoryFolderName(itemDefinition)
	local categoryFolder = itemsFolder:FindFirstChild(categoryFolderName)
	if categoryFolder and categoryFolder:IsA("Folder") then
		local categoryMatch = find_first_named_asset(categoryFolder, itemDefinition)
		if categoryMatch then
			return categoryMatch
		end
	end

	return find_first_named_asset(itemsFolder, itemDefinition)
end

local function create_placeholder_tool(itemDefinition): Tool
	local tool = Instance.new("Tool")
	tool.Name = itemDefinition.ToolName or itemDefinition.DisplayName or itemDefinition.ItemId
	tool.RequiresHandle = false
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Material = Enum.Material.SmoothPlastic
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Color = TOOL_COLOR_BY_CATEGORY[itemDefinition.ToolCategory] or Color3.fromRGB(214, 214, 214)
	handle.CanCollide = false
	handle.Parent = tool

	return tool
end

local function strip_tool_scripts(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") then
			descendant:Destroy()
		end
	end
end

local function sanitize_tool(tool: Tool, itemDefinition)
	ToolItemCatalog.ApplyToolMetadata(tool, itemDefinition)
	tool:SetAttribute(MANAGED_TOOL_ATTRIBUTE, true)

	local handle = tool:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		handle.Anchored = false
		handle.CanCollide = false
	end
end

local function clone_item_tool(itemDefinition): Tool
	local template = get_item_tool_template(itemDefinition)
	local tool = nil

	if template and template:IsA("Tool") then
		tool = template:Clone()
	elseif template then
		tool = Instance.new("Tool")
		template:Clone().Parent = tool
	else
		tool = create_placeholder_tool(itemDefinition)
	end

	strip_tool_scripts(tool)
	sanitize_tool(tool, itemDefinition)
	return tool
end

local function is_matching_managed_tool(tool: Tool, itemDefinition): boolean
	if tool:GetAttribute(MANAGED_TOOL_ATTRIBUTE) ~= true then
		return false
	end

	local itemId = normalize_key(tool:GetAttribute("ToolItemId"))
		or normalize_key(tool:GetAttribute("ItemId"))
		or normalize_key(tool.Name)

	return itemId == normalize_key(itemDefinition.ItemId)
end

local function collect_managed_tools(container: Instance?, itemDefinition): { Tool }
	local tools = {}

	if not container then
		return tools
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and is_matching_managed_tool(child, itemDefinition) then
			tools[#tools + 1] = child
		end
	end

	return tools
end

local function sync_item_tools(player: Player, itemDefinition)
	if not player.Parent then
		return
	end

	local desiredCount = get_item_count(player, itemDefinition)
	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	local character = player.Character
	local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 5)

	local backpackTools = collect_managed_tools(backpack, itemDefinition)
	local characterTools = collect_managed_tools(character, itemDefinition)
	local liveCount = #backpackTools + #characterTools

	if liveCount > desiredCount then
		local overflow = liveCount - desiredCount
		local destroyQueue = {}

		for _, tool in ipairs(backpackTools) do
			destroyQueue[#destroyQueue + 1] = tool
		end

		for _, tool in ipairs(characterTools) do
			destroyQueue[#destroyQueue + 1] = tool
		end

		for index = 1, overflow do
			local tool = destroyQueue[index]
			if tool and tool.Parent then
				tool:Destroy()
			end
		end
	elseif liveCount < desiredCount and backpack then
		for _ = 1, desiredCount - liveCount do
			clone_item_tool(itemDefinition).Parent = backpack
		end
	end

	if starterGear then
		local starterTools = collect_managed_tools(starterGear, itemDefinition)

		if #starterTools > desiredCount then
			for index = 1, #starterTools - desiredCount do
				local tool = starterTools[index]
				if tool and tool.Parent then
					tool:Destroy()
				end
			end
		elseif #starterTools < desiredCount then
			for _ = 1, desiredCount - #starterTools do
				clone_item_tool(itemDefinition).Parent = starterGear
			end
		end
	end
end

local function sync_player_tools(player: Player)
	for _, itemDefinition in ipairs(managedItemDefinitions) do
		sync_item_tools(player, itemDefinition)
	end
end

local function disconnect_player(player: Player)
	local trove = playerTroves[player]
	if not trove then
		return
	end

	trove:Destroy()
	playerTroves[player] = nil
end

local function track_player(player: Player)
	disconnect_player(player)

	local trove = Trove.new()
	playerTroves[player] = trove

	local inventoryPaths = {
		"Inventory",
		"Inventory.Consumables",
		"Inventory.Consumables.Food",
		"Inventory.Consumables.Water",
		"Inventory.Consumables.Grooming",
		"Inventory.Consumables.Misc",
		"Inventory.Consumables.Medical",
	}

	for _, inventoryPath in ipairs(inventoryPaths) do
		local connection = DataUtility.server.bind(player, inventoryPath, function()
			task.defer(sync_player_tools, player)
		end)

		if connection then
			trove:Add(connection)
		end
	end

	trove:Add(player.CharacterAdded:Connect(function()
		task.defer(sync_player_tools, player)
	end))

	task.defer(sync_player_tools, player)
end

function ConsumableToolService.SyncPlayerTools(player: Player)
	sync_player_tools(player)
end

function ConsumableToolService.Init()
	if initialized then
		return
	end

	for _, player in ipairs(Players:GetPlayers()) do
		track_player(player)
	end

	Players.PlayerAdded:Connect(track_player)
	Players.PlayerRemoving:Connect(disconnect_player)

	initialized = true
end

return ConsumableToolService
