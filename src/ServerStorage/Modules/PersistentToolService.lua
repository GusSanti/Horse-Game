local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local Trove = require(Libraries:WaitForChild("Trove"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))

local PersistentToolService = {}

local initialized = false
local playerTroves = {}
local suppressRefresh = {}
local pendingRefresh = {}

local MANAGED_TOOL_ATTRIBUTE = "InventoryManaged"
local SAVED_ITEM_COUNTS_PATH = "SavedTools.ItemCounts"
local SAVED_GENERIC_COUNTS_PATH = "SavedTools.GenericCounts"

local TOOL_COLOR_BY_CATEGORY = {
	Food = Color3.fromRGB(231, 175, 87),
	Water = Color3.fromRGB(98, 175, 255),
	Grooming = Color3.fromRGB(225, 157, 188),
	Misc = Color3.fromRGB(201, 201, 201),
	Medicine = Color3.fromRGB(121, 205, 140),
	Seeds = Color3.fromRGB(126, 97, 64),
	Tack = Color3.fromRGB(150, 117, 86),
	Cosmetics = Color3.fromRGB(212, 136, 174),
	StableDecor = Color3.fromRGB(159, 134, 98),
}

local allItemDefinitions = ToolItemCatalog.GetAllItems()

local function normalize_key(value)
	return ToolItemCatalog.NormalizeKey(value)
end

local function normalize_generic_name(value)
	if type(value) ~= "string" then
		return nil
	end

	local trimmedValue = string.gsub(value, "^%s*(.-)%s*$", "%1")
	if trimmedValue == "" then
		return nil
	end

	return trimmedValue
end

local function sanitize_item_count_map(rawCounts)
	local sanitizedCounts = {}

	if type(rawCounts) ~= "table" then
		return sanitizedCounts
	end

	for itemId, count in pairs(rawCounts) do
		local itemDefinition = ToolItemCatalog.GetItemDefinition(itemId)
		local normalizedCount = math.max(0, math.floor(tonumber(count) or 0))

		if itemDefinition and normalizedCount > 0 then
			sanitizedCounts[itemDefinition.ItemId] = normalizedCount
		end
	end

	return sanitizedCounts
end

local function sanitize_generic_count_map(rawCounts)
	local sanitizedCounts = {}

	if type(rawCounts) ~= "table" then
		return sanitizedCounts
	end

	for toolName, count in pairs(rawCounts) do
		local normalizedToolName = normalize_generic_name(toolName)
		local normalizedCount = math.max(0, math.floor(tonumber(count) or 0))

		if normalizedToolName and normalizedCount > 0 then
			sanitizedCounts[normalizedToolName] = normalizedCount
		end
	end

	return sanitizedCounts
end

local function add_to_count_map(counts, key, amount)
	if type(key) ~= "string" or key == "" then
		return
	end

	local normalizedAmount = math.max(0, math.floor(tonumber(amount) or 0))
	if normalizedAmount <= 0 then
		return
	end

	counts[key] = (counts[key] or 0) + normalizedAmount
end

local function combine_count_maps(baseCounts, extraCounts)
	local combinedCounts = {}

	for key, count in pairs(baseCounts or {}) do
		add_to_count_map(combinedCounts, key, count)
	end

	for key, count in pairs(extraCounts or {}) do
		add_to_count_map(combinedCounts, key, count)
	end

	return combinedCounts
end

local function subtract_count_maps(totalCounts, baselineCounts)
	local reducedCounts = {}

	for key, totalCount in pairs(totalCounts or {}) do
		local normalizedTotal = math.max(0, math.floor(tonumber(totalCount) or 0))
		local normalizedBaseline = math.max(0, math.floor(tonumber((baselineCounts or {})[key]) or 0))
		local excessCount = math.max(0, normalizedTotal - normalizedBaseline)

		if excessCount > 0 then
			reducedCounts[key] = excessCount
		end
	end

	return reducedCounts
end

local function count_maps_equal(leftCounts, rightCounts)
	leftCounts = leftCounts or {}
	rightCounts = rightCounts or {}

	for key, leftCount in pairs(leftCounts) do
		if (rightCounts[key] or 0) ~= leftCount then
			return false
		end
	end

	for key, rightCount in pairs(rightCounts) do
		if (leftCounts[key] or 0) ~= rightCount then
			return false
		end
	end

	return true
end

local function count_map_has_decrease(nextCounts, currentCounts)
	nextCounts = nextCounts or {}
	currentCounts = currentCounts or {}

	for key, currentCount in pairs(currentCounts) do
		if (nextCounts[key] or 0) < currentCount then
			return true
		end
	end

	return false
end

local function is_character_transitioning(player)
	local character = player.Character
	if not character then
		return true
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid == nil or humanoid.Health <= 0
end

local function should_skip_live_tool(tool)
	if not tool or not tool:IsA("Tool") then
		return true
	end

	if tool:GetAttribute(MANAGED_TOOL_ATTRIBUTE) == true then
		return true
	end

	if tool:GetAttribute(FarmingUtility.FARMING_ITEM_ATTRIBUTE) ~= nil then
		return true
	end

	if tool:GetAttribute(FarmingUtility.FARMING_KIND_ATTRIBUTE) ~= nil then
		return true
	end

	return false
end

local function get_tool_search_names(itemDefinition)
	local names = {}
	local seenNames = {}

	local function push(value)
		if type(value) ~= "string" or value == "" or seenNames[value] then
			return
		end

		seenNames[value] = true
		names[#names + 1] = value
	end

	push(itemDefinition.ToolName)
	push(itemDefinition.DisplayName)
	push(itemDefinition.ItemId)

	return names
end

local function find_first_named_asset(root, itemDefinition)
	if not root then
		return nil
	end

	for _, name in ipairs(get_tool_search_names(itemDefinition)) do
		local found = root:FindFirstChild(name, true)
		if found then
			return found
		end
	end

	return nil
end

local function get_item_tool_template(itemDefinition)
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

local function create_placeholder_tool(itemDefinition)
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

local function clone_saved_item_tool(itemDefinition)
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

	ToolItemCatalog.ApplyToolMetadata(tool, itemDefinition)
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool:SetAttribute(MANAGED_TOOL_ATTRIBUTE, nil)
	tool:SetAttribute(FarmingUtility.FARMING_ITEM_ATTRIBUTE, nil)
	tool:SetAttribute(FarmingUtility.FARMING_CROP_ATTRIBUTE, nil)
	tool:SetAttribute(FarmingUtility.FARMING_KIND_ATTRIBUTE, nil)
	return tool
end

local function create_generic_tool(toolName)
	local tool = Instance.new("Tool")
	tool.Name = toolName
	tool.RequiresHandle = false
	tool.CanBeDropped = false

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(1, 1, 1)
	handle.Material = Enum.Material.SmoothPlastic
	handle.TopSurface = Enum.SurfaceType.Smooth
	handle.BottomSurface = Enum.SurfaceType.Smooth
	handle.Color = Color3.fromRGB(214, 214, 214)
	handle.CanCollide = false
	handle.Parent = tool

	return tool
end

local function is_matching_saved_item_tool(tool, itemDefinition)
	if should_skip_live_tool(tool) then
		return false
	end

	local resolvedItemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(tool)
	return resolvedItemDefinition ~= nil and normalize_key(resolvedItemDefinition.ItemId) == normalize_key(itemDefinition.ItemId)
end

local function is_matching_saved_generic_tool(tool, toolName)
	if should_skip_live_tool(tool) then
		return false
	end

	if ToolItemCatalog.ResolveDefinitionFromTool(tool) ~= nil then
		return false
	end

	return tool.Name == toolName
end

local function collect_matching_tools(container, predicate)
	local tools = {}

	if not container then
		return tools
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") and predicate(child) then
			tools[#tools + 1] = child
		end
	end

	return tools
end

local function collect_saved_tool_counts(player)
	local itemCounts = {}
	local genericCounts = {}
	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player.Character,
	}

	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and not should_skip_live_tool(child) then
					local itemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(child)

					if itemDefinition then
						itemCounts[itemDefinition.ItemId] = (itemCounts[itemDefinition.ItemId] or 0) + 1
					else
						local genericToolName = normalize_generic_name(child.Name)
						if genericToolName then
							genericCounts[genericToolName] = (genericCounts[genericToolName] or 0) + 1
						end
					end
				end
			end
		end
	end

	return itemCounts, genericCounts
end

local function collect_starter_pack_tool_counts()
	local itemCounts = {}
	local genericCounts = {}

	for _, descendant in ipairs(StarterPack:GetDescendants()) do
		if descendant:IsA("Tool") and not should_skip_live_tool(descendant) then
			local itemDefinition = ToolItemCatalog.ResolveDefinitionFromTool(descendant)

			if itemDefinition then
				itemCounts[itemDefinition.ItemId] = (itemCounts[itemDefinition.ItemId] or 0) + 1
			else
				local genericToolName = normalize_generic_name(descendant.Name)
				if genericToolName then
					genericCounts[genericToolName] = (genericCounts[genericToolName] or 0) + 1
				end
			end
		end
	end

	return itemCounts, genericCounts
end

local function collect_generic_tool_names(player)
	local toolNames = {}
	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player.Character,
		player:FindFirstChild("StarterGear"),
	}

	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and not should_skip_live_tool(child) and ToolItemCatalog.ResolveDefinitionFromTool(child) == nil then
					local genericToolName = normalize_generic_name(child.Name)
					if genericToolName then
						toolNames[genericToolName] = true
					end
				end
			end
		end
	end

	return toolNames
end

local function sync_saved_item_definition(player, itemDefinition, desiredCount)
	if not player.Parent then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	local character = player.Character
	local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 5)

	local backpackTools = collect_matching_tools(backpack, function(tool)
		return is_matching_saved_item_tool(tool, itemDefinition)
	end)
	local characterTools = collect_matching_tools(character, function(tool)
		return is_matching_saved_item_tool(tool, itemDefinition)
	end)
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
			clone_saved_item_tool(itemDefinition).Parent = backpack
		end
	end

	if starterGear then
		local starterTools = collect_matching_tools(starterGear, function(tool)
			return is_matching_saved_item_tool(tool, itemDefinition)
		end)

		if #starterTools > desiredCount then
			for index = 1, #starterTools - desiredCount do
				local tool = starterTools[index]
				if tool and tool.Parent then
					tool:Destroy()
				end
			end
		elseif #starterTools < desiredCount then
			for _ = 1, desiredCount - #starterTools do
				clone_saved_item_tool(itemDefinition).Parent = starterGear
			end
		end
	end
end

local function sync_saved_generic_tool(player, toolName, desiredCount)
	if not player.Parent then
		return
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	local character = player.Character
	local starterGear = player:FindFirstChild("StarterGear") or player:WaitForChild("StarterGear", 5)

	local backpackTools = collect_matching_tools(backpack, function(tool)
		return is_matching_saved_generic_tool(tool, toolName)
	end)
	local characterTools = collect_matching_tools(character, function(tool)
		return is_matching_saved_generic_tool(tool, toolName)
	end)
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
			create_generic_tool(toolName).Parent = backpack
		end
	end

	if starterGear then
		local starterTools = collect_matching_tools(starterGear, function(tool)
			return is_matching_saved_generic_tool(tool, toolName)
		end)

		if #starterTools > desiredCount then
			for index = 1, #starterTools - desiredCount do
				local tool = starterTools[index]
				if tool and tool.Parent then
					tool:Destroy()
				end
			end
		elseif #starterTools < desiredCount then
			for _ = 1, desiredCount - #starterTools do
				create_generic_tool(toolName).Parent = starterGear
			end
		end
	end
end

local function sync_player_tools(player)
	if not player.Parent then
		return
	end

	if not DataUtility.server.get(player) then
		return
	end

	suppressRefresh[player] = true

	local starterItemCounts, starterGenericCounts = collect_starter_pack_tool_counts()
	local savedItemCounts = sanitize_item_count_map(DataUtility.server.get(player, SAVED_ITEM_COUNTS_PATH))
	local savedGenericCounts = sanitize_generic_count_map(DataUtility.server.get(player, SAVED_GENERIC_COUNTS_PATH))
	local desiredItemCounts = combine_count_maps(starterItemCounts, savedItemCounts)
	local desiredGenericCounts = combine_count_maps(starterGenericCounts, savedGenericCounts)

	for _, itemDefinition in ipairs(allItemDefinitions) do
		sync_saved_item_definition(player, itemDefinition, desiredItemCounts[itemDefinition.ItemId] or 0)
	end

	local genericToolNames = collect_generic_tool_names(player)
	for toolName in pairs(desiredGenericCounts) do
		genericToolNames[toolName] = true
	end

	for toolName in pairs(genericToolNames) do
		sync_saved_generic_tool(player, toolName, desiredGenericCounts[toolName] or 0)
	end

	suppressRefresh[player] = nil
end

local function refresh_saved_tools(player)
	if not player.Parent or suppressRefresh[player] then
		return
	end

	if not DataUtility.server.get(player) then
		return
	end

	local starterItemCounts, starterGenericCounts = collect_starter_pack_tool_counts()
	local liveItemCounts, liveGenericCounts = collect_saved_tool_counts(player)
	local nextItemCounts = subtract_count_maps(liveItemCounts, starterItemCounts)
	local nextGenericCounts = subtract_count_maps(liveGenericCounts, starterGenericCounts)
	local currentItemCounts = sanitize_item_count_map(DataUtility.server.get(player, SAVED_ITEM_COUNTS_PATH))
	local currentGenericCounts = sanitize_generic_count_map(DataUtility.server.get(player, SAVED_GENERIC_COUNTS_PATH))

	if is_character_transitioning(player)
		and (
			count_map_has_decrease(nextItemCounts, currentItemCounts)
			or count_map_has_decrease(nextGenericCounts, currentGenericCounts)
		) then
		return
	end

	if not count_maps_equal(nextItemCounts, currentItemCounts) then
		DataUtility.server.set(player, SAVED_ITEM_COUNTS_PATH, nextItemCounts)
	end

	if not count_maps_equal(nextGenericCounts, currentGenericCounts) then
		DataUtility.server.set(player, SAVED_GENERIC_COUNTS_PATH, nextGenericCounts)
	end

	sync_player_tools(player)
end

local function persist_saved_tools(player)
	if not player.Parent or suppressRefresh[player] then
		return
	end

	if not DataUtility.server.get(player) then
		return
	end

	local starterItemCounts, starterGenericCounts = collect_starter_pack_tool_counts()
	local liveItemCounts, liveGenericCounts = collect_saved_tool_counts(player)
	local nextItemCounts = subtract_count_maps(liveItemCounts, starterItemCounts)
	local nextGenericCounts = subtract_count_maps(liveGenericCounts, starterGenericCounts)
	local currentItemCounts = sanitize_item_count_map(DataUtility.server.get(player, SAVED_ITEM_COUNTS_PATH))
	local currentGenericCounts = sanitize_generic_count_map(DataUtility.server.get(player, SAVED_GENERIC_COUNTS_PATH))

	if is_character_transitioning(player)
		and (
			count_map_has_decrease(nextItemCounts, currentItemCounts)
			or count_map_has_decrease(nextGenericCounts, currentGenericCounts)
		) then
		return
	end

	if not count_maps_equal(nextItemCounts, currentItemCounts) then
		DataUtility.server.set(player, SAVED_ITEM_COUNTS_PATH, nextItemCounts)
	end

	if not count_maps_equal(nextGenericCounts, currentGenericCounts) then
		DataUtility.server.set(player, SAVED_GENERIC_COUNTS_PATH, nextGenericCounts)
	end
end

local function request_refresh(player)
	if suppressRefresh[player] or pendingRefresh[player] then
		return
	end

	pendingRefresh[player] = true

	task.defer(function()
		pendingRefresh[player] = nil
		refresh_saved_tools(player)
	end)
end

local function watch_container(player, container, trove)
	if not container then
		return
	end

	trove:Add(container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			request_refresh(player)
		end
	end))

	trove:Add(container.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			request_refresh(player)
		end
	end))
end

local function disconnect_player(player)
	persist_saved_tools(player)

	local trove = playerTroves[player]
	if trove then
		trove:Destroy()
		playerTroves[player] = nil
	end

	suppressRefresh[player] = nil
	pendingRefresh[player] = nil
end

local function track_player(player)
	disconnect_player(player)

	local trove = Trove.new()
	playerTroves[player] = trove

	local backpackTrove = Trove.new()
	local characterTrove = Trove.new()
	trove:Add(backpackTrove)
	trove:Add(characterTrove)

	local function bind_backpack(backpack)
		backpackTrove:Clean()
		watch_container(player, backpack, backpackTrove)
	end

	local function bind_character(character)
		characterTrove:Clean()
		watch_container(player, character, characterTrove)
		task.defer(sync_player_tools, player)
	end

	local backpack = player:FindFirstChildOfClass("Backpack") or player:WaitForChild("Backpack", 5)
	if backpack then
		bind_backpack(backpack)
	end

	if player.Character then
		bind_character(player.Character)
	end

	trove:Add(player.ChildAdded:Connect(function(child)
		if child:IsA("Backpack") then
			bind_backpack(child)
			task.defer(sync_player_tools, player)
		end
	end))

	trove:Add(player.CharacterAdded:Connect(bind_character))

	task.defer(sync_player_tools, player)
end

function PersistentToolService.SyncPlayerTools(player)
	sync_player_tools(player)
end

function PersistentToolService.RefreshPlayerTools(player)
	refresh_saved_tools(player)
end

function PersistentToolService.Init()
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

return PersistentToolService
