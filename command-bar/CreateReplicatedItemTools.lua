local ReplicatedStorage = game:GetService("ReplicatedStorage")

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

local function clear_existing_item_tools(container)
	if not container then
		return
	end

	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			child:Destroy()
		end
	end
end

local function create_tool(itemDefinition)
	local tool = Instance.new("Tool")
	return ToolItemCatalog.ApplyToolMetadata(tool, itemDefinition)
end

local assetsFolder = ensure_folder(ReplicatedStorage, "Assets")
local itemsFolder = ensure_folder(assetsFolder, "Items")
local createdCount = 0

for _, categoryDefinition in ipairs(ToolItemCatalog.GetCategories()) do
	local categoryFolder = ensure_folder(itemsFolder, categoryDefinition.FolderName)
	local items = ToolItemCatalog.GetItemsByToolCategory(categoryDefinition.CategoryId)

	clear_existing_item_tools(categoryFolder)

	for _, itemDefinition in ipairs(items) do
		local tool = create_tool(itemDefinition)
		tool.Parent = categoryFolder
		createdCount += 1
	end
end

print(("Created %d item tools in ReplicatedStorage.Assets.Items."):format(createdCount))
