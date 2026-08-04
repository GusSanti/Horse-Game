--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local Trove: any = require(Modules:WaitForChild("Libraries"):WaitForChild("Trove"))

local NPCS_FOLDER_NAME: string = "Npcs"
local DEFAULT_FADE_TIME: number = 0.15

local NPC_IDLE_ANIMATIONS: { [string]: string } = {
	chef = "rbxassetid://122382477972816",
	cowboy = "rbxassetid://92691472480288",
	doctor = "rbxassetid://99194435491936",
	farmer = "rbxassetid://122382477972816",
	noob = "rbxassetid://92691472480288",
}

local R6_PART_NAMES: { string } = {
	"Head",
	"Torso",
	"HumanoidRootPart",
	"Left Arm",
	"Right Arm",
	"Left Leg",
	"Right Leg",
}

local NpcIdleRuntime = {
	Name = "NpcIdleRuntime",
	Trove = nil :: any,
	NpcTroves = {} :: { [Instance]: any },
}

local function FindR6Humanoid(Npc: Model): Humanoid?
	local HumanoidValue: Humanoid? = Npc:FindFirstChildOfClass("Humanoid")
		or Npc:FindFirstChildWhichIsA("Humanoid", true)
	if not HumanoidValue or HumanoidValue.RigType ~= Enum.HumanoidRigType.R6 then
		return nil
	end

	for _Index: number, PartName: string in R6_PART_NAMES do
		local PartValue: Instance? = Npc:FindFirstChild(PartName)
		if not PartValue or not PartValue:IsA("BasePart") then
			return nil
		end
	end
	return HumanoidValue
end

function NpcIdleRuntime:_CleanupNpc(Npc: Instance): ()
	local NpcTrove: any = self.NpcTroves[Npc]
	if NpcTrove then
		NpcTrove:Destroy()
		self.NpcTroves[Npc] = nil
	end
end

function NpcIdleRuntime:_BindNpc(Npc: Instance): ()
	self:_CleanupNpc(Npc)
	if not Npc:IsA("Model") then
		return
	end

	local AnimationId: string? = NPC_IDLE_ANIMATIONS[string.lower(Npc.Name)]
	local Humanoid: Humanoid? = FindR6Humanoid(Npc)
	if not Humanoid or not AnimationId then
		if AnimationId and not Humanoid then
			warn(`[NpcIdleRuntime] NPC '{Npc.Name}' is not a valid R6 dummy`)
		end
		return
	end

	local Animator: Animator? = Humanoid:FindFirstChildOfClass("Animator")
	if not Animator then
		Animator = Instance.new("Animator")
		Animator.Parent = Humanoid
	end

	local AnimationValue: Animation = Instance.new("Animation")
	AnimationValue.AnimationId = AnimationId
	local Success: boolean, TrackOrError: any = pcall(Animator.LoadAnimation, Animator, AnimationValue)
	if not Success then
		AnimationValue:Destroy()
		warn(`[NpcIdleRuntime] Failed to load idle animation for {Npc:GetFullName()}: {tostring(TrackOrError)}`)
		return
	end

	local Track: AnimationTrack = TrackOrError
	local NpcTrove: any = Trove.new()
	self.NpcTroves[Npc] = NpcTrove
	NpcTrove:Add(AnimationValue)
	NpcTrove:Add(function(): ()
		pcall(function(): ()
			Track:Stop(DEFAULT_FADE_TIME)
			Track:Destroy()
		end)
	end)
	Track.Looped = true
	Track.Priority = Enum.AnimationPriority.Idle
	Track:Play(DEFAULT_FADE_TIME, 1, 1)
end

function NpcIdleRuntime:Init(): ()
	if self.Trove then
		return
	end
	self.Trove = Trove.new()
end

function NpcIdleRuntime:Start(): ()
	local Npcs: Folder = workspace:WaitForChild(NPCS_FOLDER_NAME) :: Folder
	for _Index: number, Npc: Instance in Npcs:GetChildren() do
		self:_BindNpc(Npc)
	end
	self.Trove:Connect(Npcs.ChildAdded, function(Npc: Instance): ()
		task.defer(function(): ()
			self:_BindNpc(Npc)
		end)
	end)
	self.Trove:Connect(Npcs.ChildRemoved, function(Npc: Instance): ()
		self:_CleanupNpc(Npc)
	end)
end

function NpcIdleRuntime:Destroy(): ()
	for Npc: Instance in table.clone(self.NpcTroves) do
		self:_CleanupNpc(Npc)
	end
	if self.Trove then
		self.Trove:Destroy()
		self.Trove = nil
	end
end

return NpcIdleRuntime
