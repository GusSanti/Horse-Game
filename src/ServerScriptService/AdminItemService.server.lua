local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")

local NetworkConfig = require(GameData:WaitForChild("NetworkConfig"))
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))
local AdminAccessService = require(ServerStorage:WaitForChild("Modules"):WaitForChild("AdminAccessService"))

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

local function clear_existing_admin_item_tools(player)
	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player.Character,
	}

	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") and resolve_item_definition_from_tool(child) then
					child:Destroy()
				end
			end
		end
	end
end

local function remove_matching_tool_instances(player, itemId)
	local containers = {
		player:FindFirstChildOfClass("Backpack"),
		player.Character,
	}

	for _, container in ipairs(containers) do
		if container then
			for _, child in ipairs(container:GetChildren()) do
				if child:IsA("Tool") then
					local toolItemId = normalize_key(child:GetAttribute("ToolItemId"))
						or normalize_key(child:GetAttribute("ItemId"))
						or normalize_key(child.Name)
					if toolItemId == normalize_key(itemId) then
						child:Destroy()
					end
				end
			end
		end
	end
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

	local itemId = normalize_key(toolTemplate:GetAttribute("ToolItemId"))
		or normalize_key(toolTemplate:GetAttribute("ItemId"))
		or normalize_key(toolTemplate.Name)
	remove_matching_tool_instances(player, itemId)
	toolTemplate:Clone().Parent = backpack
	return true, "Granted"
end

local gameplayRemotes = ensure_folder(ReplicatedStorage, NetworkConfig.GameplayFolderName)
local adminFolder = ensure_folder(gameplayRemotes, NetworkConfig.Admin.FolderName)

local getCatalogRemote = ensure_remote_function(adminFolder, NetworkConfig.Admin.GetItemCatalog)
local requestItemRemote = ensure_remote_function(adminFolder, NetworkConfig.Admin.RequestItemTool)

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
		clear_existing_admin_item_tools(player)

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
