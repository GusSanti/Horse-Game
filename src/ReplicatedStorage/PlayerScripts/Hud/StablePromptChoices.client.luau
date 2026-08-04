--!strict

local Players: Players = game:GetService("Players")
local ProximityPromptService: ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local HudModules: Folder = Modules:WaitForChild("Client"):WaitForChild("Hud") :: Folder
local Libraries: Folder = Modules:WaitForChild("Libraries") :: Folder
local Network: any = require(Modules:WaitForChild("Network"))
local PromptChoices: any = require(HudModules:WaitForChild("PromptChoices"))
local Trove: any = require(Libraries:WaitForChild("Trove"))

local STABLE_SLOT_PROMPT_ATTRIBUTE: string = "StableSlotPrompt"
local STABLE_SLOT_NAME_ATTRIBUTE: string = "StableSlotName"
local STABLE_HORSE_ID_ATTRIBUTE: string = "StableHorseId"
local STABLE_HORSE_FREE_ATTRIBUTE: string = "StableHorseFree"
local STABLE_CAN_BUY_ATTRIBUTE: string = "StableCanBuy"

local LocalPlayer: Player = Players.LocalPlayer
local PlayerGui: PlayerGui = LocalPlayer:WaitForChild("PlayerGui") :: PlayerGui
local Scope: any = Trove.new()
local Choices: any = PromptChoices.new(PlayerGui)
local RequestBusy: boolean = false

local function CallStableAction(Action: string, SlotName: string): ()
	if RequestBusy then
		return
	end
	RequestBusy = true
	pcall(function(): ()
		Network.Horse.StableSlotAction:Call({
			Action = Action,
			SlotName = SlotName,
		})
	end)
	RequestBusy = false
end

local function CallMount(HorseId: string): ()
	if RequestBusy then
		return
	end
	RequestBusy = true
	pcall(function(): ()
		Network.Functions.HorseMountAction:Call({
			Action = "Mount",
			HorseId = HorseId,
			MountAtHorse = true,
		})
	end)
	RequestBusy = false
end

local function BuildChoices(Prompt: ProximityPrompt): { any }
	local SlotName: any = Prompt:GetAttribute(STABLE_SLOT_NAME_ATTRIBUTE)
	if type(SlotName) ~= "string" or SlotName == "" then
		return {}
	end

	local Result: { any } = {}
	local HorseId: any = Prompt:GetAttribute(STABLE_HORSE_ID_ATTRIBUTE)
	local IsFree: boolean = Prompt:GetAttribute(STABLE_HORSE_FREE_ATTRIBUTE) == true
	if type(HorseId) == "string" and HorseId ~= "" then
		if not IsFree then
			Result[#Result + 1] = {
				Id = "Mount",
				Text = "MOUNT",
				Activate = function(): ()
					CallMount(HorseId)
				end,
			}
		end
		Result[#Result + 1] = {
			Id = "ToggleFree",
			Text = if IsFree then "RETURN HORSE" else "RELEASE HORSE",
			Activate = function(): ()
				CallStableAction("ToggleFree", SlotName)
			end,
		}
	end

	if Prompt:GetAttribute(STABLE_CAN_BUY_ATTRIBUTE) == true then
		local Price: number = math.max(math.floor(tonumber(Prompt:GetAttribute("StableSlotPrice")) or 0), 0)
		Result[#Result + 1] = {
			Id = "Buy",
			Text = if Price > 0 then `BUY  {Price}` else "BUY",
			Activate = function(): ()
				CallStableAction("Buy", SlotName)
			end,
		}
	end

	return Result
end

Scope:Connect(ProximityPromptService.PromptTriggered, function(Prompt: ProximityPrompt): ()
	if Prompt:GetAttribute(STABLE_SLOT_PROMPT_ATTRIBUTE) ~= true then
		return
	end
	Choices:Open(Prompt, BuildChoices(Prompt))
end)

Scope:Add(function(): ()
	Choices:Destroy()
end)

script.Destroying:Connect(function(): ()
	Scope:Destroy()
end)

script:SetAttribute("RuntimeReady", true)
