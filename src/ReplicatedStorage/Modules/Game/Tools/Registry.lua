------------------//SERVICES

------------------//VARIABLES
local ToolRegistry = {}

local cachedDefinitions: {[string]: any}? = nil
local cachedToolNameMap: {[string]: string}? = nil

------------------//FUNCTIONS
local function normalize_key(value: string?): string?
	if type(value) ~= "string" then
		return nil
	end

	local normalizedValue = string.lower(string.gsub(value, "^%s*(.-)%s*$", "%1"))
	if normalizedValue == "" then
		return nil
	end

	return normalizedValue
end

local function build_cache(): ()
	cachedDefinitions = {}
	cachedToolNameMap = {}

	for _, child: Instance in script.Parent:GetChildren() do
		if child:IsA("ModuleScript") and child ~= script then
			local definition = require(child)
			local itemId = normalize_key(definition.id)

			if itemId then
				definition.id = itemId
				cachedDefinitions[itemId] = definition

				local toolNames = definition.toolNames or { itemId }
				for _, toolName: string in toolNames do
					local normalizedToolName = normalize_key(toolName)
					if normalizedToolName then
						cachedToolNameMap[normalizedToolName] = itemId
					end
				end
			end
		end
	end
end

local function ensure_cache(): ()
	if cachedDefinitions and cachedToolNameMap then
		return
	end

	build_cache()
end

------------------//MAIN FUNCTIONS
function ToolRegistry.get_definition(itemId: string): any
	ensure_cache()

	local normalizedItemId = normalize_key(itemId)
	if not normalizedItemId then
		return nil
	end

	return cachedDefinitions[normalizedItemId]
end

function ToolRegistry.get_all_definitions(): {[string]: any}
	ensure_cache()

	local definitions: {[string]: any} = {}
	for itemId: string, definition: any in cachedDefinitions do
		definitions[itemId] = definition
	end

	return definitions
end

function ToolRegistry.resolve_tool_item_id(tool: Tool?): string?
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

function ToolRegistry.resolve_definition_from_tool(tool: Tool?): (any?, string?)
	local itemId = ToolRegistry.resolve_tool_item_id(tool)
	if not itemId then
		return nil, nil
	end

	return ToolRegistry.get_definition(itemId), itemId
end

------------------//INIT
return ToolRegistry
