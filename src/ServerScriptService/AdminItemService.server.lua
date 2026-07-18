local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local Services = Modules:WaitForChild("Services")
local Utility = Modules:WaitForChild("Utility")

local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local HorseStatusService = require(Services:WaitForChild("HorseStatusService"))
local DataUtility = require(Utility:WaitForChild("DataUtility"))
local AdminAccessService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("AdminAccessService"))
local HorseRouletteService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("HorseRouletteService"))

local function ensure_folder(parent, folderName)
	local folder = parent:FindFirstChild(folderName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	if folder then
		folder:Destroy()
	end

	folder = Instance.new("Folder")
	folder.Name = folderName
	folder.Parent = parent
	return folder
end

local function ensure_remote_function(parent, remoteName)
	local remote = parent:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteFunction") then
		return remote
	end

	if remote then
		remote:Destroy()
	end

	remote = Instance.new("RemoteFunction")
	remote.Name = remoteName
	remote.Parent = parent
	return remote
end

local function get_items_root()
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
	if not assetsFolder then
		return nil
	end

	return assetsFolder:FindFirstChild("Items")
end

local function normalize_key(value)
	return ToolItemCatalog.NormalizeKey(value)
end

local function resolve_item_definition_from_tool(tool)
	return ToolItemCatalog.ResolveDefinitionFromTool(tool)
end

local function get_category_folder(categoryName)
	local itemsRoot = get_items_root()
	if not itemsRoot then
		return nil
	end

	local folder = itemsRoot:FindFirstChild(categoryName)
	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

local function build_catalog()
	local itemsRoot = get_items_root()
	local categories = {}

	if not itemsRoot then
		return categories
	end

	for _, categoryFolder in ipairs(itemsRoot:GetChildren()) do
		if categoryFolder:IsA("Folder") then
			local categoryItems = {}

			for _, child in ipairs(categoryFolder:GetChildren()) do
				if child:IsA("Tool") then
					local itemDefinition = resolve_item_definition_from_tool(child)
					if itemDefinition then
						ToolItemCatalog.ApplyToolMetadata(child, itemDefinition)
					end

					local resolvedItemId = normalize_key(child:GetAttribute("ToolItemId"))
						or normalize_key(child:GetAttribute("ItemId"))
						or normalize_key(child.Name)

					if itemDefinition then
						resolvedItemId = itemDefinition.ItemId
					end

					categoryItems[#categoryItems + 1] = {
						Name = itemDefinition and itemDefinition.DisplayName or child.Name,
						ItemId = resolvedItemId or child.Name,
						PriceLabel = child:GetAttribute("PlaceholderPriceLabel")
							or (itemDefinition and itemDefinition.PriceLabel)
							or "",
						ToolTip = child.ToolTip ~= "" and child.ToolTip
							or (itemDefinition and itemDefinition.ToolTip)
							or "",
					}
				end
			end

			table.sort(categoryItems, function(a, b)
				return string.lower(a.Name) < string.lower(b.Name)
			end)

			categories[#categories + 1] = {
				Name = categoryFolder.Name,
				ItemCount = #categoryItems,
				Items = categoryItems,
			}
		end
	end

	table.sort(categories, function(a, b)
		return string.lower(a.Name) < string.lower(b.Name)
	end)

	return categories
end

local function clone_tool_to_backpack(player, toolTemplate)
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return false, "BackpackMissing"
	end

	local itemDefinition = resolve_item_definition_from_tool(toolTemplate)
	if itemDefinition then
		ToolItemCatalog.ApplyToolMetadata(toolTemplate, itemDefinition)
	end

	toolTemplate:Clone().Parent = backpack
	return true, "Granted"
end

local gameplayRemotes = ensure_folder(ReplicatedStorage, NetworkConfig.GameplayFolderName)
local adminFolder = ensure_folder(gameplayRemotes, NetworkConfig.Admin.FolderName)

local getCatalogRemote = ensure_remote_function(adminFolder, NetworkConfig.Admin.GetItemCatalog)
local requestItemRemote = ensure_remote_function(adminFolder, NetworkConfig.Admin.RequestItemTool)
local getHorseRouletteStateRemote = ensure_remote_function(adminFolder, NetworkConfig.Admin.GetHorseRouletteState)
local rollHorseRouletteRemote = ensure_remote_function(adminFolder, NetworkConfig.Admin.RollHorseRoulette)
local restoreEquippedHorseNeedsRemote = ensure_remote_function(adminFolder, NetworkConfig.Admin.RestoreEquippedHorseNeeds)

getCatalogRemote.OnServerInvoke = function(player)
	local hasAccess = AdminAccessService.HasAccess(player)
	if not hasAccess then
		return {
			Success = false,
			Code = "AccessDenied",
		}
	end

	return {
		Success = true,
		Categories = build_catalog(),
	}
end

requestItemRemote.OnServerInvoke = function(player, request)
	local hasAccess = AdminAccessService.HasAccess(player)
	if not hasAccess then
		return {
			Success = false,
			Code = "AccessDenied",
		}
	end

	if type(request) ~= "table" then
		return {
			Success = false,
			Code = "InvalidRequest",
		}
	end

	local mode = request.Mode
	local categoryName = request.CategoryName
	if type(categoryName) ~= "string" or categoryName == "" then
		return {
			Success = false,
			Code = "CategoryMissing",
		}
	end

	local categoryFolder = get_category_folder(categoryName)
	if not categoryFolder then
		return {
			Success = false,
			Code = "CategoryNotFound",
		}
	end

	if mode == "Category" then
		local grantedCount = 0
		for _, child in ipairs(categoryFolder:GetChildren()) do
			if child:IsA("Tool") then
				local success = clone_tool_to_backpack(player, child)
				if success then
					grantedCount += 1
				end
			end
		end

		return {
			Success = grantedCount > 0,
			Code = grantedCount > 0 and "CategoryGranted" or "NoToolsFound",
			GrantedCount = grantedCount,
		}
	end

	if mode == "Single" then
		local itemId = request.ItemId
		if type(itemId) ~= "string" or itemId == "" then
			return {
				Success = false,
				Code = "ItemMissing",
			}
		end

		for _, child in ipairs(categoryFolder:GetChildren()) do
			if child:IsA("Tool") then
				local toolItemId = normalize_key(child:GetAttribute("ToolItemId"))
					or normalize_key(child:GetAttribute("ItemId"))
					or normalize_key(child.Name)
				if toolItemId == normalize_key(itemId) then
					local success, code = clone_tool_to_backpack(player, child)
					return {
						Success = success,
						Code = code,
						ItemName = child.Name,
					}
				end
			end
		end

		return {
			Success = false,
			Code = "ItemNotFound",
		}
	end

	return {
		Success = false,
		Code = "UnsupportedMode",
	}
end

getHorseRouletteStateRemote.OnServerInvoke = function(player)
	local hasAccess = AdminAccessService.HasAccess(player)
	if not hasAccess then
		return {
			Success = false,
			Code = "AccessDenied",
		}
	end

	return HorseRouletteService.GetState(player)
end

rollHorseRouletteRemote.OnServerInvoke = function(player)
	local hasAccess = AdminAccessService.HasAccess(player)
	if not hasAccess then
		return {
			Success = false,
			Code = "AccessDenied",
		}
	end

	return HorseRouletteService.Roll(player)
end

restoreEquippedHorseNeedsRemote.OnServerInvoke = function(player)
	local hasAccess = AdminAccessService.HasAccess(player)
	if not hasAccess then
		return {
			Success = false,
			Code = "AccessDenied",
		}
	end

	local horses = DataUtility.server.get(player, "Horses")
	local equippedHorseId = horses and horses.EquippedHorseId or nil
	local horse = equippedHorseId and horses and horses.Owned and horses.Owned[equippedHorseId] or nil
	if not horse then
		return {
			Success = false,
			Code = "EquippedHorseNotFound",
		}
	end

	local now = os.time()
	HorseStatusService.NormalizeHorse(horse, now)
	local needs = horse.Needs
	needs.Modifiers = {}
	needs.ActiveEffects = {}

	for _, statusName in ipairs(HorseStatusService.StatusOrder) do
		needs.Values[statusName] = math.max(1, tonumber(needs.Max[statusName]) or 100)
	end

	needs.LastUpdatedAt = now
	DataUtility.server.set(player, "Horses", horses)

	return {
		Success = true,
		HorseId = equippedHorseId,
		HorseName = (type(horse.Nickname) == "string" and horse.Nickname ~= "" and horse.Nickname)
			or horse.DisplayName
			or horse.CatalogId
			or equippedHorseId,
	}
end
