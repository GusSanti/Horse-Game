--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local StableDictionary: any = require(Modules:WaitForChild("Dictionary"):WaitForChild("StableDictionary"))
local HorseRoamingConfig: any = require(
	Modules:WaitForChild("GameData"):WaitForChild("Horse"):WaitForChild("HorseRoamingConfig")
)
local HorseMountConfig: any = require(
	Modules:WaitForChild("GameData"):WaitForChild("Horse"):WaitForChild("HorseMountConfig")
)
local DataUtility: any = require(Modules:WaitForChild("Utility"):WaitForChild("DataUtility"))
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))
local HorseModules: Folder = ServerStorage:WaitForChild("Modules"):WaitForChild("Horse") :: Folder
local HorseMountService: any = require(HorseModules:WaitForChild("HorseMountService"))
local HorseRoamingService: any = require(HorseModules:WaitForChild("HorseRoamingService"))
local HorseService: any = require(HorseModules:WaitForChild("HorseService"))

local HORSE_FOLDER_NAME: string = "HorseFolder"
local SLOT_PROMPT_PART_NAME: string = "Proximity"
local SLOT_PROMPT_NAME: string = "BuyStableSlotPrompt"
local HORSE_MOUNT_PROMPT_NAME: string = "StableHorseMountPrompt"
local VISUAL_HORSE_ATTRIBUTE: string = "IsStableVisualHorse"
local HORSE_ID_ATTRIBUTE: string = "HorseId"
local SLOT_PROMPT_ACTION_TEXT: string = "Buy"
local SLOT_PROMPT_HOLD_DURATION: number = 0
local SLOT_PROMPT_MAX_ACTIVATION_DISTANCE: number = tonumber(HorseMountConfig.StableMountPromptMaxActivationDistance) or 14
local STABLE_PROMPT_KIND_ATTRIBUTE: string = "StablePromptKind"
local STABLE_PROMPT_DEBUG_ATTRIBUTE: string = "StablePromptDebug"

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

local function GetSlotVisualHorse(Plot: Instance, SlotName: string): Instance?
	local SlotFolder: Instance? = GetSlotFolder(Plot, SlotName)
	if not SlotFolder then
		return nil
	end
	for _Index: number, Child: Instance in SlotFolder:GetChildren() do
		if Child:GetAttribute(VISUAL_HORSE_ATTRIBUTE) == true then
			return Child
		end
	end
	return nil
end

local function GetHorsePromptParent(VisualHorse: Instance): BasePart?
	if VisualHorse:IsA("BasePart") then
		return VisualHorse
	end
	if VisualHorse:IsA("Model") and VisualHorse.PrimaryPart and VisualHorse.PrimaryPart:IsDescendantOf(VisualHorse) then
		return VisualHorse.PrimaryPart
	end
	for _Index: number, PartName: string in { "HorseRoot", "RootPart" } do
		local NamedPart: Instance? = VisualHorse:FindFirstChild(PartName, true)
		if NamedPart and NamedPart:IsA("BasePart") then
			return NamedPart
		end
	end
	return VisualHorse:FindFirstChildWhichIsA("BasePart", true)
end

local function GetHorseMountPrompt(Plot: Instance, SlotName: string): ProximityPrompt?
	local VisualHorse: Instance? = GetSlotVisualHorse(Plot, SlotName)
	local PromptParent: BasePart? = if VisualHorse then GetHorsePromptParent(VisualHorse) else nil
	local Prompt: Instance? = if PromptParent then PromptParent:FindFirstChild(HORSE_MOUNT_PROMPT_NAME) else nil
	return if Prompt and Prompt:IsA("ProximityPrompt") then Prompt else nil
end

local function EnsureHorseMountPrompt(Plot: Instance, SlotName: string): ProximityPrompt?
	local VisualHorse: Instance? = GetSlotVisualHorse(Plot, SlotName)
	local PromptParent: BasePart? = if VisualHorse then GetHorsePromptParent(VisualHorse) else nil
	if not PromptParent then
		return nil
	end

	local Existing: Instance? = PromptParent:FindFirstChild(HORSE_MOUNT_PROMPT_NAME)
	if Existing and not Existing:IsA("ProximityPrompt") then
		warn(`{HORSE_MOUNT_PROMPT_NAME} must be a ProximityPrompt in {PromptParent:GetFullName()}`)
		return nil
	end

	local Prompt: ProximityPrompt
	if Existing then
		Prompt = Existing :: ProximityPrompt
	else
		Prompt = Instance.new("ProximityPrompt")
		Prompt.Name = HORSE_MOUNT_PROMPT_NAME
		Prompt.Parent = PromptParent
	end

	Prompt.HoldDuration = HorseMountConfig.StableMountPromptHoldDuration or 0
	Prompt.MaxActivationDistance = HorseMountConfig.StableMountPromptMaxActivationDistance or 14
	Prompt.KeyboardKeyCode = Enum.KeyCode.E
	Prompt.RequiresLineOfSight = false
	return Prompt
end

local function SetPromptDebug(Prompt: ProximityPrompt, Kind: string, Details: string): ()
	Prompt:SetAttribute(STABLE_PROMPT_KIND_ATTRIBUTE, Kind)
	Prompt:SetAttribute(STABLE_PROMPT_DEBUG_ATTRIBUTE, Details)
end

local function DebugAction(Player: Player, Action: string, SlotName: string, Code: string): ()
	print(`[StablePromptDebug] player={Player.Name} action={Action} slot={SlotName} code={Code}`)
end

function Prompts.new(AssignedPlotByPlayer: any, SyncPlotHorses: (Player) -> ()): any
	return setmetatable({
		_AssignedPlots = AssignedPlotByPlayer,
		_SyncHorses = SyncPlotHorses,
		_PlotTroves = {},
		_HorseMountPromptBindings = {},
	}, Prompts)
end

function Prompts:Disable(Plot: Instance): ()
	for _Index: number, SlotName: string in StableDictionary.HorseSlotOrder do
		for _PromptIndex: number, Prompt: ProximityPrompt? in {
			GetSlotPrompt(Plot, SlotName),
			GetFreeHorsePrompt(Plot, SlotName),
			GetHorseMountPrompt(Plot, SlotName),
		} do
			if Prompt then
				Prompt.Enabled = false
			end
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
			Prompt.Style = Enum.ProximityPromptStyle.Default
			Prompt.KeyboardKeyCode = Enum.KeyCode.E
			SetPromptDebug(
				Prompt,
				"Purchase",
				`slot={SlotName}; enabled={tostring(IsPurchasable)}; ownedStalls={OwnedStalls}; price={tostring(SlotPrice)}`
			)
		end
	end
end

function Prompts:_BindHorseMountPrompt(Player: Player, Prompt: ProximityPrompt): ()
	local BoundPrompts: { [ProximityPrompt]: boolean } = self._HorseMountPromptBindings[Player]
	if not BoundPrompts then
		BoundPrompts = {}
		self._HorseMountPromptBindings[Player] = BoundPrompts
	end
	if BoundPrompts[Prompt] then
		return
	end

	local PlotTrove: any = self._PlotTroves[Player]
	if not PlotTrove then
		return
	end
	BoundPrompts[Prompt] = true
	PlotTrove:Connect(Prompt.Triggered, function(TriggeringPlayer: Player): ()
		if TriggeringPlayer ~= Player or Prompt.Enabled ~= true then
			return
		end

		local HorseId: any = Prompt:GetAttribute(HORSE_ID_ATTRIBUTE)
		if type(HorseId) ~= "string" or HorseId == "" then
			DebugAction(Player, "Mount", "Unknown", "HorseMissing")
			return
		end

		Prompt.Enabled = false
		local Response: any = HorseMountService.Mount(Player, {
			HorseId = HorseId,
			MountAtHorse = true,
		})
		DebugAction(Player, "Mount", tostring(Prompt:GetAttribute("StableSlotName")), tostring(Response and Response.Code))
		self:RefreshHorseInteractions(Player)
	end)
end

function Prompts:RefreshHorseInteractions(Player: Player): ()
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
		local HorseId: any = if HorseSlots then HorseSlots[SlotName] else nil
		local HasAssignedHorse: boolean = SlotIndex <= OwnedStalls
			and type(HorseId) == "string"
			and HorseId ~= ""
		local IsFree: boolean = HasAssignedHorse and HorseRoamingService.IsHorseFree(Player, HorseId)

		local FreePrompt: ProximityPrompt? = EnsureFreeHorsePrompt(PlotData.instance, SlotName)
		if FreePrompt then
			FreePrompt.Enabled = HasAssignedHorse
			FreePrompt.HoldDuration = HorseRoamingConfig.FreePromptHoldDuration
			FreePrompt.ActionText = if IsFree
				then HorseRoamingConfig.ReturnPromptActionText
				else HorseRoamingConfig.FreePromptActionText
			FreePrompt.ObjectText = HorseRoamingConfig.FreePromptObjectText
			FreePrompt.Style = Enum.ProximityPromptStyle.Default
			SetPromptDebug(
				FreePrompt,
				"FreeHorse",
				`slot={SlotName}; enabled={tostring(HasAssignedHorse)}; horseId={tostring(HorseId)}; free={tostring(IsFree)}`
			)
		end

		local MountPrompt: ProximityPrompt? = EnsureHorseMountPrompt(PlotData.instance, SlotName)
		if MountPrompt then
			MountPrompt.Enabled = HasAssignedHorse and not IsFree
			MountPrompt.ActionText = HorseMountConfig.StableMountPromptActionText or "Mount"
			MountPrompt.ObjectText = HorseMountConfig.StableMountPromptObjectText or "Your Horse"
			MountPrompt.Style = Enum.ProximityPromptStyle.Default
			MountPrompt:SetAttribute(HORSE_ID_ATTRIBUTE, if HasAssignedHorse then HorseId else nil)
			MountPrompt:SetAttribute("StableSlotName", SlotName)
			SetPromptDebug(
				MountPrompt,
				"HorseMount",
				`slot={SlotName}; enabled={tostring(MountPrompt.Enabled)}; horseId={tostring(HorseId)}; free={tostring(IsFree)}`
			)
			self:_BindHorseMountPrompt(Player, MountPrompt)
		end
	end
end

function Prompts:_Bind(Player: Player, PlotTrove: any, Plot: Instance): ()
	for _Index: number, SlotName: string in StableDictionary.HorseSlotOrder do
		local SlotPrompt: ProximityPrompt? = GetSlotPrompt(Plot, SlotName)
		if SlotPrompt then
			PlotTrove:Connect(SlotPrompt.Triggered, function(TriggeringPlayer: Player): ()
				if TriggeringPlayer ~= Player or SlotPrompt.Enabled ~= true then
					return
				end

				local _Success: boolean, Code: string = HorseService.BuyStableSlot(Player, SlotName)
				DebugAction(Player, "Buy", SlotName, Code)
				self:RefreshSlots(Player)
				self._SyncHorses(Player)
				self:RefreshHorseInteractions(Player)
			end)
		end

		local FreePrompt: ProximityPrompt? = EnsureFreeHorsePrompt(Plot, SlotName)
		if FreePrompt then
			PlotTrove:Connect(FreePrompt.Triggered, function(TriggeringPlayer: Player): ()
				if TriggeringPlayer ~= Player or FreePrompt.Enabled ~= true then
					return
				end

				local Stable: any = DataUtility.server.get(Player, "Stable")
				local HorseSlots: any = if type(Stable) == "table" then Stable.HorseSlots else nil
				local HorseId: any = if type(HorseSlots) == "table" then HorseSlots[SlotName] else nil
				if type(HorseId) ~= "string" or HorseId == "" then
					DebugAction(Player, "ToggleFree", SlotName, "HorseMissing")
					self:RefreshHorseInteractions(Player)
					return
				end

				local _Success: boolean, Code: string = HorseRoamingService.ToggleHorseFree(Player, HorseId)
				if Code == "Returned" then
					self._SyncHorses(Player)
				end
				DebugAction(Player, "ToggleFree", SlotName, Code)
				self:RefreshHorseInteractions(Player)
			end)
		end
	end

	self:RefreshSlots(Player)
	self:RefreshHorseInteractions(Player)
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
	self._HorseMountPromptBindings[Player] = nil
end

function Prompts:Destroy(): ()
	for Player: Player in table.clone(self._PlotTroves) do
		self:CleanupPlayer(Player)
	end
	table.clear(self._HorseMountPromptBindings)
end

return Prompts
