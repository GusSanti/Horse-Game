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

local function clear_existing_medicine_tools(container)
	if not container then
		return
	end

	for _, child in ipairs(container:GetDescendants()) do
		if child:IsA("Tool") and child:GetAttribute("ToolCategory") == "Medicine" then
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
local medicineFolder = ensure_folder(itemsFolder, "Medicine")

local createdCount = 0
local medicineDefinitions = ToolItemCatalog.GetItemsByToolCategory("Medicine")

clear_existing_medicine_tools(medicineFolder)

for _, itemDefinition in ipairs(medicineDefinitions) do
	local tool = create_tool(itemDefinition)
	tool.Parent = medicineFolder
	createdCount += 1
end

print(("Created %d medicine tools in ReplicatedStorage.Assets.Items.Medicine."):format(createdCount))
