local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local StarterPack = game:GetService("StarterPack")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameData = Modules:WaitForChild("GameData")
local ToolItemCatalog = require(GameData:WaitForChild("ToolItemCatalog"))

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

local function ensure_item_folders()
	local assetsFolder = ensure_folder(ReplicatedStorage, "Assets")
	local itemsFolder = ensure_folder(assetsFolder, "Items")
	local categoryFolders = {}

	for _, itemDefinition in ipairs(ToolItemCatalog.GetAllItems()) do
		local categoryName = ToolItemCatalog.GetToolCategory(itemDefinition)
		if not categoryFolders[categoryName] then
			categoryFolders[categoryName] = ensure_folder(itemsFolder, categoryName)
		end
	end

	return itemsFolder, categoryFolders
end

local function normalize_key(value)
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function resolve_item_definition_from_tool(tool)
	return ToolItemCatalog.ResolveDefinitionFromTool(tool)
end

local function clear_existing_tools(container)
	if not container then
		return
	end

	for _, child in ipairs(container:GetDescendants()) do
		if child:IsA("Tool") and resolve_item_definition_from_tool(child) then
			child:Destroy()
		end
	end
end

local function clone_templates_to_container(container, templates)
	if not container then
		return
	end

	clear_existing_tools(container)

	for _, template in ipairs(templates) do
		template:Clone().Parent = container
	end
end

local itemsFolder, categoryFolders = ensure_item_folders()
clear_existing_tools(itemsFolder)

local templates = {}

for _, child in ipairs(StarterPack:GetChildren()) do
	if child:IsA("Tool") then
		local itemDefinition = resolve_item_definition_from_tool(child)
		if itemDefinition then
			ToolItemCatalog.ApplyToolMetadata(child, itemDefinition)
			child.Parent = categoryFolders[ToolItemCatalog.GetToolCategory(itemDefinition)] or itemsFolder
			templates[#templates + 1] = child
		end
	end
end

for _, player in ipairs(Players:GetPlayers()) do
	clone_templates_to_container(player:FindFirstChildOfClass("Backpack"), templates)
	clone_templates_to_container(player:FindFirstChild("StarterGear"), templates)
	clear_existing_tools(player.Character)
end

clone_templates_to_container(StarterPack, templates)

print(("Organized %d existing horse item tools into ReplicatedStorage.Assets.Items folders."):format(#templates))
