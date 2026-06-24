local TableUtility = {}

function TableUtility.DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}

	for key, child in pairs(value) do
		copy[TableUtility.DeepCopy(key)] = TableUtility.DeepCopy(child)
	end

	return copy
end

function TableUtility.InsertUnique(array, value)
	for _, existing in ipairs(array) do
		if existing == value then
			return false
		end
	end

	array[#array + 1] = value
	return true
end

function TableUtility.GetByPath(root, path)
	if not path or path == "" then
		return root
	end

	local current = root

	for segment in string.gmatch(path, "[^%.]+") do
		if type(current) ~= "table" then
			return nil
		end

		current = current[segment]

		if current == nil then
			return nil
		end
	end

	return current
end

function TableUtility.EnsurePath(root, path)
	if not path or path == "" then
		return root
	end

	local current = root

	for segment in string.gmatch(path, "[^%.]+") do
		if type(current[segment]) ~= "table" then
			current[segment] = {}
		end

		current = current[segment]
	end

	return current
end

function TableUtility.CountKeys(map)
	local total = 0

	for _ in pairs(map) do
		total += 1
	end

	return total
end

return TableUtility
