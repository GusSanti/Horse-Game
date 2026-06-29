local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Utility = Modules:WaitForChild("Utility")

local FarmingUtility = require(Utility:WaitForChild("FarmingUtility"))
local Net = require(Libraries:WaitForChild("Net"))
local Trove = require(Libraries:WaitForChild("Trove"))

local localPlayer = Players.LocalPlayer

local rootTrove = Trove.new()
local toolTroves: { [Tool]: any } = {}

local activeTool: Tool? = nil
local activeToolTrove = nil
local previewPart: Part? = nil
local currentPlacement = nil
local requestInFlight = false

local function ensure_preview_part(): Part
	if previewPart then
		return previewPart
	end

	local part = Instance.new("Part")
	part.Name = "SeedPreview"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.Neon
	part.Size = Vector3.new(2.4, 0.2, 2.4)
	part.Transparency = 1
	part.Parent = Workspace

	previewPart = part
	return part
end

local function hide_preview()
	currentPlacement = nil

	if previewPart then
		previewPart.Transparency = 1
	end
end

local function clear_active_tool()
	activeTool = nil

	if activeToolTrove then
		activeToolTrove:Destroy()
		activeToolTrove = nil
	end

	hide_preview()
end

local function get_mouse_raycast(ignoreFarmPlants: boolean): RaycastResult?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

	local filter = {}

	if localPlayer.Character then
		table.insert(filter, localPlayer.Character)
	end

	if previewPart then
		table.insert(filter, previewPart)
	end

	if ignoreFarmPlants then
		local farmFolder = Workspace:FindFirstChild(FarmingUtility.FARM_FOLDER_NAME)
		if farmFolder then
			table.insert(filter, farmFolder)
		end
	end

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filter

	return Workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
end

local function update_seed_preview()
	local part = ensure_preview_part()
	local raycastResult = get_mouse_raycast(true)

	if not raycastResult then
		hide_preview()
		return
	end

	local placement = FarmingUtility.GetSoilPlacementData(raycastResult.Position)
	local isValid = placement ~= nil

	if placement then
		currentPlacement = placement
		part.CFrame = placement.Soil.CFrame
			* CFrame.new(
				placement.LocalPoint.X,
				placement.Soil.Size.Y * 0.5 + part.Size.Y * 0.5 + 0.03,
				placement.LocalPoint.Z
			)
	else
		currentPlacement = nil
		part.CFrame = CFrame.new(raycastResult.Position + Vector3.new(0, part.Size.Y * 0.5 + 0.03, 0))
	end

	part.Color = isValid and Color3.fromRGB(92, 214, 102) or Color3.fromRGB(235, 88, 88)
	part.Transparency = 0.4
end

local function try_place_seed()
	if requestInFlight or not currentPlacement then
		return
	end

	requestInFlight = true

	local success, response = pcall(function()
		return Net.Function.PlantSeed:Call(FarmingUtility.GetWorldTopPosition(currentPlacement.Soil, currentPlacement.LocalPoint))
	end)

	requestInFlight = false

	if success and response and response.Success then
		hide_preview()
	end
end

local function try_water_plant()
	if requestInFlight then
		return
	end

	local raycastResult = get_mouse_raycast(false)
	if not raycastResult or not raycastResult.Instance then
		return
	end

	requestInFlight = true
	pcall(function()
		return Net.Function.WaterPlant:Call(raycastResult.Instance)
	end)
	requestInFlight = false
end

local function activate_seed_tool(tool: Tool)
	clear_active_tool()

	activeTool = tool
	activeToolTrove = Trove.new()

	activeToolTrove:Add(RunService.RenderStepped:Connect(update_seed_preview))
	activeToolTrove:Add(tool.Activated:Connect(try_place_seed))
	activeToolTrove:Add(function()
		if activeTool == tool then
			activeTool = nil
		end
	end)

	update_seed_preview()
end

local function activate_watering_tool(tool: Tool)
	clear_active_tool()

	activeTool = tool
	activeToolTrove = Trove.new()

	activeToolTrove:Add(tool.Activated:Connect(try_water_plant))
	activeToolTrove:Add(function()
		if activeTool == tool then
			activeTool = nil
		end
	end)
end

local function handle_tool_equipped(tool: Tool)
	if tool.Name == FarmingUtility.SEED_TOOL_NAME then
		activate_seed_tool(tool)
		return
	end

	if tool.Name == FarmingUtility.WATERING_TOOL_NAME then
		activate_watering_tool(tool)
	end
end

local function watch_tool(tool: Tool)
	if toolTroves[tool] then
		return
	end

	local trove = Trove.new()
	toolTroves[tool] = trove

	trove:Add(tool.Equipped:Connect(function()
		handle_tool_equipped(tool)
	end))

	trove:Add(tool.Unequipped:Connect(function()
		if activeTool == tool then
			clear_active_tool()
		end
	end))

	trove:Add(tool.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		if activeTool == tool then
			clear_active_tool()
		end

		trove:Destroy()
		toolTroves[tool] = nil
	end))
end

local function watch_tool_container(container: Instance, trove)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("Tool") then
			watch_tool(child)
		end
	end

	trove:Add(container.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			watch_tool(child)
		end
	end))
end

local function bind_character(character: Model)
	local characterTrove = Trove.new()

	watch_tool_container(character, characterTrove)

	local backpack = localPlayer:WaitForChild("Backpack")
	watch_tool_container(backpack, characterTrove)

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then
			handle_tool_equipped(child)
		end
	end

	characterTrove:Add(character.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end

		clear_active_tool()
		characterTrove:Destroy()
	end))
end

rootTrove:Add(localPlayer.CharacterAdded:Connect(bind_character))

if localPlayer.Character then
	bind_character(localPlayer.Character)
end
