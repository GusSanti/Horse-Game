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

local function clear_existing_tools(container)
	if not container then
		return
	end

	for _, child in ipairs(container:GetDescendants()) do
		if child:IsA("Tool") and ToolItemCatalog.ResolveDefinitionFromTool(child) then
			child:Destroy()
		end
	end
end

local function create_tool(itemDefinition)
	local tool = Instance.new("Tool")
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	ToolItemCatalog.ApplyToolMetadata(tool, itemDefinition)
	return tool
end

local function fill_container(container, templatesByItemId)
	if not container then
		return
	end

	clear_existing_tools(container)

	for _, itemDefinition in ipairs(ToolItemCatalog.GetAllItems()) do
		local template = templatesByItemId[itemDefinition.ItemId]
		if template then
			template:Clone().Parent = container
		end
	end
end

local itemsFolder, categoryFolders = ensure_item_folders()

clear_existing_tools(itemsFolder)
clear_existing_tools(StarterPack)

local templatesByItemId = {}
local createdCount = 0

for _, itemDefinition in ipairs(ToolItemCatalog.GetAllItems()) do
	local tool = create_tool(itemDefinition)
	local categoryFolder = categoryFolders[ToolItemCatalog.GetToolCategory(itemDefinition)]
	tool.Parent = categoryFolder or itemsFolder
	templatesByItemId[itemDefinition.ItemId] = tool
	createdCount += 1
end

fill_container(StarterPack, templatesByItemId)

for _, player in ipairs(Players:GetPlayers()) do
	fill_container(player:FindFirstChildOfClass("Backpack"), templatesByItemId)
	fill_container(player:FindFirstChild("StarterGear"), templatesByItemId)
	clear_existing_tools(player.Character)
end

print(("Created %d horse item tools in ReplicatedStorage.Assets.Items and cloned them to StarterPack."):format(createdCount))
