--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local StableDictionary: any = require(Modules:WaitForChild("Dictionary"):WaitForChild("StableDictionary"))
local HorseRoamingConfig: any = require(
	Modules:WaitForChild("GameData"):WaitForChild("Horse"):WaitForChild("HorseRoamingConfig")
)
local DataUtility: any = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))
local HorseModules: Folder = ServerStorage:WaitForChild("Modules"):WaitForChild("Horse") :: Folder
local HorseRoamingService: any = require(HorseModules:WaitForChild("HorseRoamingService"))
local HorseService: any = require(HorseModules:WaitForChild("HorseService"))

local HORSE_FOLDER_NAME: string = "HorseFolder"
local SLOT_PROMPT_PART_NAME: string = "Proximity"
local SLOT_PROMPT_NAME: string = "BuyStableSlotPrompt"
local SLOT_PROMPT_ACTION_TEXT: string = "Buy"
local SLOT_PROMPT_HOLD_DURATION: number = 0
local SLOT_PROMPT_MAX_ACTIVATION_DISTANCE: number = 10

local Prompts = {}
Prompts.__index = Prompts

local function GetOwnedStalls(Stable: any): number
	local OwnedStalls: number = tonumber(Stable and Stable.OwnedStalls) or StableDictionary.DefaultOwnedStalls
	return math.clamp(math.floor(OwnedStalls), 0, StableDictionary.MaxOwnedStalls or #StableDictionary.HorseSlotOrder)
end

local function GetSlotFolder(Plot: Instance, SlotName: string): Instance?
	local HorseFolder: Instance? = Plot:FindFirstChild(HORSE_FOLDER_NAME)
	return if HorseFolder then HorseFolder:FindFirstChild(SlotName) else nil
end

local function GetSlotPrompt(Plot: Instance, SlotName: string): ProximityPrompt?
	local SlotFolder: Instance? = GetSlotFolder(Plot, SlotName)
	local ProximityPart: Instance? = if SlotFolder then SlotFolder:FindFirstChild(SLOT_PROMPT_PART_NAME) else nil
	if not ProximityPart then
		return nil
	end
	if ProximityPart:IsA("ProximityPrompt") then
		return ProximityPart
	end
	for _Index: number, Child: Instance in ProximityPart:GetChildren() do
		if Child:IsA("ProximityPrompt") then
			return Child
		end
	end
	if not ProximityPart:IsA("BasePart") and not ProximityPart:IsA("Attachment") then
		return nil
	end

	local Prompt: ProximityPrompt = Instance.new("ProximityPrompt")
	Prompt.Name = SLOT_PROMPT_NAME
	Prompt.HoldDuration = SLOT_PROMPT_HOLD_DURATION
	Prompt.MaxActivationDistance = SLOT_PROMPT_MAX_ACTIVATION_DISTANCE
	Prompt.RequiresLineOfSight = false
	Prompt.Parent = ProximityPart
	return Prompt
end

local function EnsureFreeHorsePart(SlotFolder: Instance): BasePart?
	local Existing: Instance? = SlotFolder:FindFirstChild(HorseRoamingConfig.FreeHorsePartName)
	if Existing then
		if Existing:IsA("BasePart") then
			return Existing
		end
		warn(`{HorseRoamingConfig.FreeHorsePartName} must be a BasePart in {SlotFolder:GetFullName()}`)
		return nil
	end

	local ReferencePart: Instance? = SlotFolder:FindFirstChild(SLOT_PROMPT_PART_NAME)
	if not ReferencePart or not ReferencePart:IsA("BasePart") then
		ReferencePart = SlotFolder:FindFirstChild("HorsePosition")
	end
	if not ReferencePart or not ReferencePart:IsA("BasePart") then
		return nil
	end

	local FreeHorsePart: Part = Instance.new("Part")
	FreeHorsePart.Name = HorseRoamingConfig.FreeHorsePartName
	FreeHorsePart.Size = ReferencePart.Size
	FreeHorsePart.CFrame = ReferencePart.CFrame
	FreeHorsePart.Transparency = 1
	FreeHorsePart.Anchored = true
	FreeHorsePart.CanCollide = false
	FreeHorsePart.CanQuery = false
	FreeHorsePart.CanTouch = false
	FreeHorsePart.CastShadow = false
	FreeHorsePart.Parent = SlotFolder
	return FreeHorsePart
end

local function GetFreeHorsePrompt(Plot: Instance, SlotName: string): ProximityPrompt?
	local SlotFolder: Instance? = GetSlotFolder(Plot, SlotName)
	local FreeHorsePart: Instance? = if SlotFolder
		then SlotFolder:FindFirstChild(HorseRoamingConfig.FreeHorsePartName)
		else nil
	local Prompt: Instance? = if FreeHorsePart
		then FreeHorsePart:FindFirstChild(HorseRoamingConfig.FreePromptName)
		else nil
	return if Prompt and Prompt:IsA("ProximityPrompt") then Prompt else nil
end

local function EnsureFreeHorsePrompt(Plot: Instance, SlotName: string): ProximityPrompt?
	local SlotFolder: Instance? = GetSlotFolder(Plot, SlotName)
	if not SlotFolder then
		return nil
	end
	local FreeHorsePart: BasePart? = EnsureFreeHorsePart(SlotFolder)
	if not FreeHorsePart then
		return nil
	end

	local Existing: Instance? = FreeHorsePart:FindFirstChild(HorseRoamingConfig.FreePromptName)
	if Existing and not Existing:IsA("ProximityPrompt") then
		warn(`{HorseRoamingConfig.FreePromptName} must be a ProximityPrompt in {FreeHorsePart:GetFullName()}`)
		return nil
	end
	local Prompt: ProximityPrompt
	if Existing then
		Prompt = Existing :: ProximityPrompt
	else
		Prompt = Instance.new("ProximityPrompt")
		Prompt.Name = HorseRoamingConfig.FreePromptName
		Prompt.Parent = FreeHorsePart
	end
	Prompt.HoldDuration = HorseRoamingConfig.FreePromptHoldDuration
	Prompt.MaxActivationDistance = HorseRoamingConfig.FreePromptMaxActivationDistance
	Prompt.KeyboardKeyCode = HorseRoamingConfig.FreePromptKeyboardKeyCode
	Prompt.RequiresLineOfSight = false
	return Prompt
end

function Prompts.new(AssignedPlotByPlayer: any, SyncPlotHorses: (Player) -> ()): any
	return setmetatable({
		AssignedPlotByPlayer = AssignedPlotByPlayer,
		SyncPlotHorses = SyncPlotHorses,
		PlotTroves = {},
	}, Prompts)
end

function Prompts:Disable(Plot: Instance): ()
	for _Index: number, SlotName: string in StableDictionary.HorseSlotOrder do
		local SlotPrompt: ProximityPrompt? = GetSlotPrompt(Plot, SlotName)
		if SlotPrompt then
			SlotPrompt.Enabled = false
		end
		local FreePrompt: ProximityPrompt? = GetFreeHorsePrompt(Plot, SlotName)
		if FreePrompt then
			FreePrompt.Enabled = false
		end
	end
end

function Prompts:RefreshSlots(Player: Player): ()
	local PlotData: any = self.AssignedPlotByPlayer[Player]
	if not PlotData then
		return
	end
	local Stable: any = DataUtility.server.get(Player, "Stable")
	if not Stable then
		self:Disable(PlotData.instance)
		return
	end

	local OwnedStalls: number = GetOwnedStalls(Stable)
	for SlotIndex: number, SlotName: string in StableDictionary.HorseSlotOrder do
		local Prompt: ProximityPrompt? = GetSlotPrompt(PlotData.instance, SlotName)
		if Prompt then
			local SlotPrice: number? = StableDictionary.get_slot_purchase_price(SlotName)
			local IsPurchasable: boolean = SlotIndex ~= 1
				and SlotIndex > OwnedStalls
				and SlotIndex == OwnedStalls + 1
				and type(SlotPrice) == "number"
				and SlotPrice > 0
			Prompt.Enabled = IsPurchasable
			Prompt.HoldDuration = SLOT_PROMPT_HOLD_DURATION
			Prompt.ActionText = SLOT_PROMPT_ACTION_TEXT
			Prompt.ObjectText = if type(SlotPrice) == "number"
				then `Slot {SlotIndex} - {SlotPrice} Horseshoes`
				else `Slot {SlotIndex}`
		end
	end
end

function Prompts:RefreshFree(Player: Player): ()
	local PlotData: any = self.AssignedPlotByPlayer[Player]
	if not PlotData then
		return
	end
	local Stable: any = DataUtility.server.get(Player, "Stable")
	local HorseSlots: any = if type(Stable) == "table" then Stable.HorseSlots else nil
	local OwnedStalls: number = GetOwnedStalls(Stable)
	for SlotIndex: number, SlotName: string in StableDictionary.HorseSlotOrder do
		local Prompt: ProximityPrompt? = GetFreeHorsePrompt(PlotData.instance, SlotName)
		if Prompt then
			local HorseId: any = if type(HorseSlots) == "table" then HorseSlots[SlotName] else nil
			local HasAssignedHorse: boolean = SlotIndex <= OwnedStalls and type(HorseId) == "string" and HorseId ~= ""
			local IsFree: boolean = HasAssignedHorse and HorseRoamingService.IsHorseFree(Player, HorseId)
			Prompt.Enabled = HasAssignedHorse
			Prompt.ActionText = if IsFree
				then HorseRoamingConfig.ReturnPromptActionText
				else HorseRoamingConfig.FreePromptActionText
			Prompt.ObjectText = HorseRoamingConfig.FreePromptObjectText
		end
	end
end

function Prompts:_Bind(Player: Player, PlotTrove: any, Plot: Instance): ()
	for _Index: number, SlotName: string in StableDictionary.HorseSlotOrder do
		local SlotPrompt: ProximityPrompt? = GetSlotPrompt(Plot, SlotName)
		if SlotPrompt then
			PlotTrove:Connect(SlotPrompt.Triggered, function(TriggeringPlayer: Player): ()
				if TriggeringPlayer == Player then
					HorseService.BuyStableSlot(Player, SlotName)
					self:RefreshSlots(Player)
					self:RefreshFree(Player)
				end
			end)
		end

		local FreePrompt: ProximityPrompt? = EnsureFreeHorsePrompt(Plot, SlotName)
		if FreePrompt then
			PlotTrove:Connect(FreePrompt.Triggered, function(TriggeringPlayer: Player): ()
				if TriggeringPlayer ~= Player then
					return
				end
				local Stable: any = DataUtility.server.get(Player, "Stable")
				local HorseSlots: any = if type(Stable) == "table" then Stable.HorseSlots else nil
				local HorseId: any = if type(HorseSlots) == "table" then HorseSlots[SlotName] else nil
				if type(HorseId) ~= "string" or HorseId == "" then
					self:RefreshFree(Player)
					return
				end
				if not HorseRoamingService.ToggleHorseFree(Player, HorseId) then
					self.SyncPlotHorses(Player)
				end
				self:RefreshFree(Player)
			end)
		end
	end
	self:RefreshSlots(Player)
	self:RefreshFree(Player)
end

function Prompts:Rebind(Player: Player, Plot: Instance): ()
	self:CleanupPlayer(Player)
	local PlotTrove: any = Trove.new()
	self.PlotTroves[Player] = PlotTrove
	self:_Bind(Player, PlotTrove, Plot)
end

function Prompts:CleanupPlayer(Player: Player): ()
	local PlotTrove: any = self.PlotTroves[Player]
	if PlotTrove then
		PlotTrove:Destroy()
		self.PlotTroves[Player] = nil
	end
end

function Prompts:Destroy(): ()
	for Player: Player in table.clone(self.PlotTroves) do
		self:CleanupPlayer(Player)
	end
end

return Prompts
