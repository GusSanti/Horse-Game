--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Framework: any = require(Modules:WaitForChild("Framework"))
local Network: any = require(Modules:WaitForChild("Network"))
local ToolRegistry: any = require(Modules:WaitForChild("Game"):WaitForChild("Tools"):WaitForChild("Registry"))
local HorseService: any = require(
	ServerStorage:WaitForChild("Modules"):WaitForChild("Horse"):WaitForChild("HorseService")
)

local ActiveUseByPlayer: { [Player]: boolean } = {}
local ActiveBrushAnimationByPlayer: { [Player]: string } = {}
local ToolUse = {}

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
	TroveValue:Connect(Framework.RuntimeEvents.PlayerRemoving, function(Player: Player): ()
		ActiveUseByPlayer[Player] = nil
		StopBrushAnimation(Player, ActiveBrushAnimationByPlayer[Player])
	end)
	TroveValue:Add(function(): ()
		table.clear(ActiveUseByPlayer)
		for Player: Player, HorseId: string in ActiveBrushAnimationByPlayer do
			HorseService.StopBrushAnimation(Player, HorseId)
		end
		table.clear(ActiveBrushAnimationByPlayer)
	end)
end

return ToolUse
