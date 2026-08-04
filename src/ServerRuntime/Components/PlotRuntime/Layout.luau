--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")
local Workspace: Workspace = game:GetService("Workspace")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local StableDictionary: any = require(Modules:WaitForChild("Dictionary"):WaitForChild("StableDictionary"))

local STABLES_FOLDER_NAME: string = "Stables"
local STABLE_PLOT_NAME: string = "Stable"
local STABLE_PLOT_NAME_PREFIX: string = "Stable"
local PLAYER_SPAWN_NAME: string = "PlayerSpawn"
local PLOT_NUMBER_ATTRIBUTE: string = "PlotNumber"
local PLOT_NUMBER_LOWER_ATTRIBUTE: string = "plotnumber"
local HORSE_FOLDER_NAME: string = "HorseFolder"

export type PlotData = {
	instance: Instance,
	number: number,
}

local StablesFolder: Instance = Workspace:WaitForChild(STABLES_FOLDER_NAME)
local Layout = {}

function Layout.GetPlotNumber(Plot: Instance): number?
	local PlotNumber: number? = tonumber(Plot.Name)
	if PlotNumber then
		return PlotNumber
	end

	local MainAttribute: any = Plot:GetAttribute(PLOT_NUMBER_ATTRIBUTE)
	if typeof(MainAttribute) == "number" then
		return MainAttribute
	end
	local LowerAttribute: any = Plot:GetAttribute(PLOT_NUMBER_LOWER_ATTRIBUTE)
	return if typeof(LowerAttribute) == "number" then LowerAttribute else nil
end

function Layout.GetPlayerSpawn(Plot: Instance): BasePart?
	local PlayerSpawn: Instance? = Plot:FindFirstChild(PLAYER_SPAWN_NAME)
	return if PlayerSpawn and PlayerSpawn:IsA("BasePart") then PlayerSpawn else nil
end

function Layout.GetLevelFromTemplateName(TemplateName: string): number?
	local LevelText: string? = string.match(string.lower(TemplateName), "^%s*level%s*(%d+)%s*$")
	return if LevelText then tonumber(LevelText) else nil
end

function Layout.EnsureHorseFolder(Plot: Instance): Instance?
	local HorseFolder: Instance? = Plot:FindFirstChild(HORSE_FOLDER_NAME)
	local DirectSlots: { Instance } = {}
	for _Index: number, SlotName: string in StableDictionary.HorseSlotOrder do
		local DirectSlot: Instance? = Plot:FindFirstChild(SlotName)
		if DirectSlot then
			table.insert(DirectSlots, DirectSlot)
		end
	end

	if not HorseFolder and #DirectSlots > 0 then
		local NewHorseFolder: Folder = Instance.new("Folder")
		NewHorseFolder.Name = HORSE_FOLDER_NAME
		NewHorseFolder.Parent = Plot
		HorseFolder = NewHorseFolder
	end
	if HorseFolder then
		for _Index: number, DirectSlot: Instance in DirectSlots do
			DirectSlot.Parent = HorseFolder
		end
	end
	return HorseFolder
end

function Layout.GetOrderedPlots(): { PlotData }
	local Plots: { PlotData } = {}
	for _Index: number, Plot: Instance in StablesFolder:GetChildren() do
		local IsLevelTemplate: boolean = Layout.GetLevelFromTemplateName(Plot.Name) ~= nil
		local PlotNumber: number? = if IsLevelTemplate then nil else Layout.GetPlotNumber(Plot)
		if PlotNumber and Layout.GetPlayerSpawn(Plot) then
			table.insert(Plots, { instance = Plot, number = PlotNumber })
		end
	end

	if #Plots == 0 then
		local StableContainer: Instance? = Workspace:FindFirstChild(STABLE_PLOT_NAME)
		if StableContainer and not Layout.GetPlayerSpawn(StableContainer) then
			for _Index: number, Plot: Instance in StableContainer:GetChildren() do
				local PlotNumber: number? = Layout.GetPlotNumber(Plot)
				if PlotNumber and Layout.GetPlayerSpawn(Plot) then
					table.insert(Plots, { instance = Plot, number = PlotNumber })
				end
			end
		end
	end

	if #Plots == 0 then
		for _Index: number, Plot: Instance in Workspace:GetChildren() do
			local StableSuffix: string? = string.match(Plot.Name, `^{STABLE_PLOT_NAME_PREFIX}(%d*)$`)
			if StableSuffix ~= nil and Layout.GetPlayerSpawn(Plot) then
				local FallbackNumber: number? = if Plot.Name == STABLE_PLOT_NAME then 1 else tonumber(StableSuffix)
				local PlotNumber: number? = Layout.GetPlotNumber(Plot) or FallbackNumber
				if PlotNumber then
					table.insert(Plots, { instance = Plot, number = PlotNumber })
				end
			end
		end
	end

	table.sort(Plots, function(First: PlotData, Second: PlotData): boolean
		return First.number < Second.number
	end)
	return Plots
end

local function GetPlotTemplateFromLevel(LevelTemplate: Instance, PlotNumber: number): Instance?
	if Layout.GetPlayerSpawn(LevelTemplate) then
		return LevelTemplate
	end
	for _Index: number, Candidate: Instance in LevelTemplate:GetChildren() do
		if Layout.GetPlotNumber(Candidate) == PlotNumber and Layout.GetPlayerSpawn(Candidate) then
			return Candidate
		end
	end
	return nil
end

function Layout.GetLevelPlotTemplate(Level: number, PlotNumber: number): Instance?
	local Visited: { [Instance]: boolean } = {}
	local function Test(LevelTemplate: Instance): Instance?
		if Visited[LevelTemplate] or Layout.GetLevelFromTemplateName(LevelTemplate.Name) ~= Level then
			return nil
		end
		Visited[LevelTemplate] = true
		return GetPlotTemplateFromLevel(LevelTemplate, PlotNumber)
	end

	for _Index: number, Child: Instance in StablesFolder:GetChildren() do
		local Template: Instance? = Test(Child)
		if Template then
			return Template
		end
	end
	for _Index: number, Root: Instance in { Workspace, ServerStorage, ReplicatedStorage } do
		for _DescendantIndex: number, Descendant: Instance in Root:GetDescendants() do
			local Template: Instance? = Test(Descendant)
			if Template then
				return Template
			end
		end
	end
	return nil
end

local function AlignCloneToSpawn(LevelClone: Instance, TargetSpawn: BasePart): (boolean, string)
	local LevelSpawn: BasePart? = Layout.GetPlayerSpawn(LevelClone)
	if not LevelSpawn then
		return false, PLAYER_SPAWN_NAME .. "Missing"
	end

	local Offset: CFrame = TargetSpawn.CFrame * LevelSpawn.CFrame:Inverse()
	if LevelClone:IsA("Model") then
		LevelClone:PivotTo(Offset * LevelClone:GetPivot())
	else
		if LevelClone:IsA("BasePart") then
			LevelClone.CFrame = Offset * LevelClone.CFrame
		end
		for _Index: number, Descendant: Instance in LevelClone:GetDescendants() do
			if Descendant:IsA("BasePart") then
				Descendant.CFrame = Offset * Descendant.CFrame
			end
		end
	end
	return true, "Aligned"
end

function Layout.ReplacePlotContents(Plot: Instance, Template: Instance): (boolean, string)
	local TargetSpawn: BasePart? = Layout.GetPlayerSpawn(Plot)
	if not TargetSpawn then
		return false, "TargetPlayerSpawnMissing"
	end

	local CloneSucceeded: boolean, LevelClone: Instance? = pcall(function(): Instance
		return Template:Clone()
	end)
	if not CloneSucceeded or not LevelClone then
		return false, "TemplateCloneFailed"
	end

	local Aligned: boolean, AlignReason: string = AlignCloneToSpawn(LevelClone, TargetSpawn)
	if not Aligned then
		LevelClone:Destroy()
		return false, AlignReason
	end

	local ClonedSpawn: BasePart? = Layout.GetPlayerSpawn(LevelClone)
	for _Index: number, Child: Instance in Plot:GetChildren() do
		if Child ~= TargetSpawn then
			Child:Destroy()
		end
	end
	for _Index: number, Child: Instance in LevelClone:GetChildren() do
		if Child ~= ClonedSpawn then
			Child.Parent = Plot
		end
	end
	LevelClone:Destroy()
	return true, "Replaced"
end

return Layout
