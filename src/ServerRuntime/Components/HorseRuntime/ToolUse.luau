--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Network: any = require(Modules:WaitForChild("Network"))
local ToolRegistry: any = require(Modules:WaitForChild("Game"):WaitForChild("Tools"):WaitForChild("Registry"))
local CareItemCatalog: any = require(Modules:WaitForChild("GameData"):WaitForChild("CareItemCatalog"))
local HorseService: any = require(
	ServerStorage:WaitForChild("Modules"):WaitForChild("Horse"):WaitForChild("HorseService")
)

local ActiveUseByPlayer: { [Player]: boolean } = {}
local ActiveBrushAnimationByPlayer: { [Player]: string } = {}
local ActiveFeedAnimationByPlayer: { [Player]: string } = {}
local ToolUse = {}
local StopFeedAnimation: (Player, any) -> ()

local function IsToolEquippedByPlayer(Player: Player, ToolValue: Tool): boolean
	local Character: Model? = Player.Character
	return Character ~= nil and ToolValue.Parent == Character
end

local function StopBrushAnimation(Player: Player, HorseId: any): ()
	local ActiveHorseId: string? = ActiveBrushAnimationByPlayer[Player]
	if not ActiveHorseId or HorseId ~= ActiveHorseId then
		return
	end

	ActiveBrushAnimationByPlayer[Player] = nil
	HorseService.StopBrushAnimation(Player, ActiveHorseId)
end

local function StartBrushAnimation(Player: Player, ToolValue: Instance?, HorseId: any): ()
	if not ToolValue or not ToolValue:IsA("Tool") or type(HorseId) ~= "string" or HorseId == "" then
		return
	end
	if not IsToolEquippedByPlayer(Player, ToolValue) then
		return
	end

	local Definition: any, ResolvedItemId: string? = ToolRegistry.resolve_definition_from_tool(ToolValue)
	if not Definition or ResolvedItemId ~= "horse_brush" then
		return
	end

	local Horse: any, ResolvedHorseId: string? = HorseService.GetPlayerHorse(Player, HorseId)
	if not Horse or not ResolvedHorseId then
		return
	end

	StopFeedAnimation(Player, ActiveFeedAnimationByPlayer[Player])
	StopBrushAnimation(Player, ActiveBrushAnimationByPlayer[Player])
	local Started: boolean = HorseService.PlayBrushAnimation(Player, ResolvedHorseId)
	if not Started then
		return
	end

	ActiveBrushAnimationByPlayer[Player] = ResolvedHorseId
	task.delay(3, function(): ()
		StopBrushAnimation(Player, ResolvedHorseId)
	end)
end

StopFeedAnimation = function(Player: Player, HorseId: any): ()
	local ActiveHorseId: string? = ActiveFeedAnimationByPlayer[Player]
	if not ActiveHorseId or HorseId ~= ActiveHorseId then
		return
	end

	ActiveFeedAnimationByPlayer[Player] = nil
	HorseService.StopFeedAnimation(Player, ActiveHorseId)
end

local function StartFeedAnimation(Player: Player, ToolValue: Instance?, HorseId: any, Duration: any): ()
	if not ToolValue or not ToolValue:IsA("Tool") or type(HorseId) ~= "string" or HorseId == "" then
		return
	end
	if not IsToolEquippedByPlayer(Player, ToolValue) then
		return
	end

	local Definition: any, ResolvedItemId: string? = ToolRegistry.resolve_definition_from_tool(ToolValue)
	local CareItemDefinition: any = ResolvedItemId and CareItemCatalog.GetItemDefinition(ResolvedItemId) or nil
	if not Definition or not CareItemDefinition or CareItemDefinition.CareType ~= "Food" then
		return
	end

	local Horse: any, ResolvedHorseId: string? = HorseService.GetPlayerHorse(Player, HorseId)
	if not Horse or not ResolvedHorseId then
		return
	end

	StopBrushAnimation(Player, ActiveBrushAnimationByPlayer[Player])
	StopFeedAnimation(Player, ActiveFeedAnimationByPlayer[Player])
	local Started: boolean = HorseService.PlayFeedAnimation(Player, ResolvedHorseId)
	if not Started then
		return
	end

	ActiveFeedAnimationByPlayer[Player] = ResolvedHorseId
	local AnimationDuration = if type(Duration) == "number" then math.clamp(Duration, 0.05, 30) else 3
	task.delay(AnimationDuration + 0.5, function(): ()
		StopFeedAnimation(Player, ResolvedHorseId)
	end)
end

local function UseHorseTool(
	Player: Player,
	ToolValue: Instance?,
	ItemId: string?,
	HorseId: string
): (boolean, string)
	if ActiveUseByPlayer[Player] then
		return false, "Busy"
	end
	if not ToolValue or not ToolValue:IsA("Tool") then
		return false, "InvalidTool"
	end
	if type(HorseId) ~= "string" or HorseId == "" then
		return false, "InvalidHorseId"
	end
	if not IsToolEquippedByPlayer(Player, ToolValue) then
		return false, "ToolNotEquipped"
	end

	local Definition: any, ResolvedItemId: string? = ToolRegistry.resolve_definition_from_tool(ToolValue)
	if not Definition or not ResolvedItemId then
		return false, "ToolNotRegistered"
	end

	local RequestedItemId: string? = ItemId
	if type(RequestedItemId) == "string" then
		RequestedItemId = string.lower(RequestedItemId)
	end
	if RequestedItemId ~= nil and RequestedItemId ~= ResolvedItemId then
		return false, "ItemMismatch"
	end

	local Horse: any, ResolvedHorseId: string? = HorseService.GetPlayerHorse(Player, HorseId)
	if not Horse or not ResolvedHorseId then
		return false, "HorseNotOwned"
	end

	local Context: any = {
		player = Player,
		tool = ToolValue,
		itemId = ResolvedItemId,
		horse = Horse,
		horseId = ResolvedHorseId,
	}
	if type(Definition.canUse) == "function" then
		local CanUse: boolean?, CanUseReason: string? = Definition.canUse(Context)
		if CanUse ~= true then
			return false, CanUseReason or "CannotUse"
		end
	end

	ActiveUseByPlayer[Player] = true
	local Success: boolean, Result: any, Reason: any = pcall(function(): (any, any)
		if type(Definition.onUse) == "function" then
			return Definition.onUse(Context)
		end
		return true, "Used"
	end)
	ActiveUseByPlayer[Player] = nil

	if not Success then
		warn(`[HorseRuntime] Failed to use {ResolvedItemId} for {Player.Name}: {tostring(Result)}`)
		return false, "UseFailed"
	end

	local WasUsed: boolean = Result == true
	local ResponseReason: string = Reason or (if WasUsed then "Used" else "Rejected")
	if WasUsed and Definition.consumeOnUse ~= false and ToolValue.Parent then
		ToolValue:Destroy()
	end
	return WasUsed, ResponseReason
end

function ToolUse.Bind(TroveValue: any): ()
	Network.Horse.UseTool:Respond(UseHorseTool, TroveValue)
	Network.Horse.BrushAnimation:Connect(function(Player: Player, ToolValue: Instance?, HorseId: any, IsStarting: any): ()
		if IsStarting == true then
			StartBrushAnimation(Player, ToolValue, HorseId)
		else
			StopBrushAnimation(Player, HorseId)
		end
	end, TroveValue)
	local FeedAnimationEvent: any = Network.Horse and Network.Horse.FeedAnimation
	if FeedAnimationEvent and type(FeedAnimationEvent.Connect) == "function" then
		FeedAnimationEvent:Connect(function(
			Player: Player,
			ToolValue: Instance?,
			HorseId: any,
			IsStarting: any,
			Duration: any
		): ()
			if IsStarting == true then
				StartFeedAnimation(Player, ToolValue, HorseId, Duration)
			else
				StopFeedAnimation(Player, HorseId)
			end
		end, TroveValue)
	end
	TroveValue:Connect(Framework.RuntimeEvents.PlayerRemoving, function(Player: Player): ()
		ActiveUseByPlayer[Player] = nil
		StopBrushAnimation(Player, ActiveBrushAnimationByPlayer[Player])
		StopFeedAnimation(Player, ActiveFeedAnimationByPlayer[Player])
	end)
	TroveValue:Add(function(): ()
		table.clear(ActiveUseByPlayer)
		for Player: Player, HorseId: string in ActiveBrushAnimationByPlayer do
			HorseService.StopBrushAnimation(Player, HorseId)
		end
		table.clear(ActiveBrushAnimationByPlayer)
		for Player: Player, HorseId: string in ActiveFeedAnimationByPlayer do
			HorseService.StopFeedAnimation(Player, HorseId)
		end
		table.clear(ActiveFeedAnimationByPlayer)
	end)
end

return ToolUse
