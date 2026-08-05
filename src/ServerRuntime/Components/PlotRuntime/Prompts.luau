--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local StableDictionary: any = require(Modules:WaitForChild("Dictionary"):WaitForChild("StableDictionary"))
local HorseMountConfig: any = require(
	Modules:WaitForChild("GameData"):WaitForChild("Horse"):WaitForChild("HorseMountConfig")
)
local DataUtility: any = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))
local HorseModules: Folder = ServerStorage:WaitForChild("Modules"):WaitForChild("Horse") :: Folder
local HorseRoamingService: any = require(HorseModules:WaitForChild("HorseRoamingService"))
local HorseService: any = require(HorseModules:WaitForChild("HorseService"))

local HORSE_FOLDER_NAME: string = "HorseFolder"
local SLOT_PROMPT_PART_NAME: string = "Proximity"
local SLOT_PROMPT_NAME: string = "BuyStableSlotPrompt"
local SLOT_PROMPT_HOLD_DURATION: number = 0
local SLOT_PROMPT_MAX_ACTIVATION_DISTANCE: number = tonumber(HorseMountConfig.StableMountPromptMaxActivationDistance) or 14
local STABLE_SLOT_PROMPT_ATTRIBUTE: string = "StableSlotPrompt"
local STABLE_SLOT_NAME_ATTRIBUTE: string = "StableSlotName"
local STABLE_HORSE_ID_ATTRIBUTE: string = "StableHorseId"
local STABLE_HORSE_FREE_ATTRIBUTE: string = "StableHorseFree"
local STABLE_CAN_BUY_ATTRIBUTE: string = "StableCanBuy"
local STABLE_PROMPT_AVAILABLE_ATTRIBUTE: string = "StablePromptAvailable"
local ACTION_COOLDOWN_SECONDS: number = 0.35
local DISTANCE_TOLERANCE: number = 4

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

function Prompts.new(
	AssignedPlotByPlayer: any,
	SyncPlotHorses: (Player) -> (),
	SyncPlotDoors: (Player, boolean?) -> ()
): any
	return setmetatable({
		_AssignedPlots = AssignedPlotByPlayer,
		_SyncHorses = SyncPlotHorses,
		_SyncDoors = SyncPlotDoors,
		_PlotTroves = {},
		_LastActionAt = {},
	}, Prompts)
end

function Prompts:Disable(Plot: Instance): ()
	for _Index: number, SlotName: string in StableDictionary.HorseSlotOrder do
		local SlotPrompt: ProximityPrompt? = GetSlotPrompt(Plot, SlotName)
		if SlotPrompt then
			SlotPrompt.Enabled = false
			SlotPrompt:SetAttribute(STABLE_PROMPT_AVAILABLE_ATTRIBUTE, false)
		end
	end
end

function Prompts:RefreshSlots(Player: Player): ()
	local PlotData: any = self._AssignedPlots[Player]
	if not PlotData then
		return
	end
	local Stable: any = DataUtility.server.get(Player, "Stable")
	if not Stable then
		self:Disable(PlotData.instance)
		return
	end

	local OwnedStalls: number = GetOwnedStalls(Stable)
	local HorseSlots: any = if type(Stable.HorseSlots) == "table" then Stable.HorseSlots else nil
	for SlotIndex: number, SlotName: string in StableDictionary.HorseSlotOrder do
		local Prompt: ProximityPrompt? = GetSlotPrompt(PlotData.instance, SlotName)
		if Prompt then
			local SlotPrice: number? = StableDictionary.get_slot_purchase_price(SlotName)
			local IsPurchasable: boolean = SlotIndex ~= 1
				and SlotIndex > OwnedStalls
				and SlotIndex == OwnedStalls + 1
				and type(SlotPrice) == "number"
				and SlotPrice > 0
			local HorseId: any = if HorseSlots then HorseSlots[SlotName] else nil
			local HasAssignedHorse: boolean = SlotIndex <= OwnedStalls
				and type(HorseId) == "string"
				and HorseId ~= ""
			local IsFree: boolean = HasAssignedHorse and HorseRoamingService.IsHorseFree(Player, HorseId)
			Prompt.Enabled = IsPurchasable or HasAssignedHorse
			Prompt:SetAttribute(STABLE_PROMPT_AVAILABLE_ATTRIBUTE, Prompt.Enabled)
			Prompt.HoldDuration = SLOT_PROMPT_HOLD_DURATION
			Prompt.ActionText = "Interact"
			Prompt.ObjectText = if HasAssignedHorse then "Your Horse" else `Stable Slot {SlotIndex}`
			Prompt.Style = Enum.ProximityPromptStyle.Custom
			Prompt.KeyboardKeyCode = Enum.KeyCode.E
			Prompt:SetAttribute(STABLE_SLOT_PROMPT_ATTRIBUTE, true)
			Prompt:SetAttribute(STABLE_SLOT_NAME_ATTRIBUTE, SlotName)
			Prompt:SetAttribute(STABLE_HORSE_ID_ATTRIBUTE, if HasAssignedHorse then HorseId else nil)
			Prompt:SetAttribute(STABLE_HORSE_FREE_ATTRIBUTE, IsFree)
			Prompt:SetAttribute(STABLE_CAN_BUY_ATTRIBUTE, IsPurchasable)
			Prompt:SetAttribute("StableSlotPrice", if IsPurchasable then SlotPrice else nil)
		end
	end
end

function Prompts:_Bind(Player: Player, _PlotTrove: any, Plot: Instance): ()
	self:RefreshSlots(Player)
end

local function GetRootPart(Player: Player): BasePart?
	local Character: Model? = Player.Character
	local RootPart: Instance? = if Character then Character:FindFirstChild("HumanoidRootPart") else nil
	return if RootPart and RootPart:IsA("BasePart") then RootPart else nil
end

local function GetPromptPosition(Prompt: ProximityPrompt): Vector3?
	local Parent: Instance? = Prompt.Parent
	if Parent and Parent:IsA("Attachment") then
		return Parent.WorldPosition
	end
	if Parent and Parent:IsA("BasePart") then
		return Parent.Position
	end
	return nil
end

function Prompts:Execute(Player: Player, Payload: any): any
	if type(Payload) ~= "table" then
		return { Success = false, Code = "InvalidPayload" }
	end

	local PlotData: any = self._AssignedPlots[Player]
	local SlotName: any = Payload.SlotName
	local Action: any = Payload.Action
	if not PlotData or type(SlotName) ~= "string" or type(Action) ~= "string" then
		return { Success = false, Code = "InvalidRequest" }
	end

	local Prompt: ProximityPrompt? = GetSlotPrompt(PlotData.instance, SlotName)
	local RootPart: BasePart? = GetRootPart(Player)
	local PromptPosition: Vector3? = if Prompt then GetPromptPosition(Prompt) else nil
	if not Prompt or not Prompt.Enabled or not RootPart or not PromptPosition then
		return { Success = false, Code = "Unavailable" }
	end
	if (RootPart.Position - PromptPosition).Magnitude > Prompt.MaxActivationDistance + DISTANCE_TOLERANCE then
		return { Success = false, Code = "TooFar" }
	end

	local Now: number = os.clock()
	local LastActionAt: number = tonumber(self._LastActionAt[Player]) or -math.huge
	if Now - LastActionAt < ACTION_COOLDOWN_SECONDS then
		return { Success = false, Code = "Cooldown" }
	end
	self._LastActionAt[Player] = Now

	if Action == "Buy" then
		local Success: boolean, Code: string, OwnedStalls: number? = HorseService.BuyStableSlot(Player, SlotName)
		self:RefreshSlots(Player)
		return {
			Success = Success,
			Code = Code,
			OwnedStalls = OwnedStalls,
		}
	end

	if Action == "ToggleFree" then
		local Stable: any = DataUtility.server.get(Player, "Stable")
		local HorseSlots: any = if type(Stable) == "table" then Stable.HorseSlots else nil
		local HorseId: any = if type(HorseSlots) == "table" then HorseSlots[SlotName] else nil
		if type(HorseId) ~= "string" or HorseId == "" then
			return { Success = false, Code = "HorseMissing" }
		end

		local Success: boolean = HorseRoamingService.ToggleHorseFree(Player, HorseId)
		if not Success then
			self._SyncHorses(Player)
		end
		self._SyncDoors(Player, true)
		self:RefreshSlots(Player)
		return {
			Success = Success,
			Code = if Success then "Updated" else "Unavailable",
			IsFree = HorseRoamingService.IsHorseFree(Player, HorseId),
		}
	end

	return { Success = false, Code = "UnknownAction" }
end

function Prompts:Rebind(Player: Player, Plot: Instance): ()
	self:CleanupPlayer(Player)
	local PlotTrove: any = Trove.new()
	self._PlotTroves[Player] = PlotTrove
	self:_Bind(Player, PlotTrove, Plot)
end

function Prompts:CleanupPlayer(Player: Player): ()
	local PlotTrove: any = self._PlotTroves[Player]
	if PlotTrove then
		PlotTrove:Destroy()
		self._PlotTroves[Player] = nil
	end
	self._LastActionAt[Player] = nil
end

function Prompts:Destroy(): ()
	for Player: Player in table.clone(self._PlotTroves) do
		self:CleanupPlayer(Player)
	end
	table.clear(self._LastActionAt)
end

return Prompts
