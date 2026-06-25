local ToolRegistry = {}

local cachedDefinitions = nil
local cachedToolNameMap = nil

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

local function build_cache()
	cachedDefinitions = {}
	cachedToolNameMap = {}

	for _, child in script.Parent:GetChildren() do
		if child:IsA("ModuleScript") and child ~= script then
			local definition = require(child)
			local itemId = normalize_key(definition.Id)

			if itemId then
				definition.Id = itemId
				cachedDefinitions[itemId] = definition

				local toolNames = definition.ToolNames or { itemId }
				for _, toolName in ipairs(toolNames) do
					local normalizedToolName = normalize_key(toolName)
					if normalizedToolName then
						cachedToolNameMap[normalizedToolName] = itemId
					end
				end
			end
		end
	end
end

local function ensure_cache()
	if cachedDefinitions and cachedToolNameMap then
		return
	end

	build_cache()
end

function ToolRegistry.GetDefinition(itemId)
	ensure_cache()

	local normalizedItemId = normalize_key(itemId)
	if not normalizedItemId then
		return nil
	end

	return cachedDefinitions[normalizedItemId]
end

function ToolRegistry.GetAllDefinitions()
	ensure_cache()

	local definitions = {}
	for itemId, definition in pairs(cachedDefinitions) do
		definitions[itemId] = definition
	end

	return definitions
end

function ToolRegistry.ResolveToolItemId(tool)
	if not tool or not tool:IsA("Tool") then
		return nil
	end

	ensure_cache()

	local explicitItemId = normalize_key(tool:GetAttribute("ToolItemId"))
	if explicitItemId and cachedDefinitions[explicitItemId] then
		return explicitItemId
	end

	local legacyItemId = normalize_key(tool:GetAttribute("ItemId"))
	if legacyItemId and cachedDefinitions[legacyItemId] then
		return legacyItemId
	end

	local normalizedToolName = normalize_key(tool.Name)
	if not normalizedToolName then
		return nil
	end

	return cachedToolNameMap[normalizedToolName]
end

function ToolRegistry.ResolveDefinitionFromTool(tool)
	local itemId = ToolRegistry.ResolveToolItemId(tool)
	if not itemId then
		return nil, nil
	end

	return ToolRegistry.GetDefinition(itemId), itemId
end

return ToolRegistry
