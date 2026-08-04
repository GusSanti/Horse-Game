--!strict

local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local HorseModules: Folder = ServerStorage.Modules.Horse
local MountDomain: any = require(HorseModules.Mount)
local Assembly: any = MountDomain.Assembly
local RigAdapter: any = MountDomain.RigAdapter
local TransactionRegistry: any = MountDomain.TransactionRegistry
local InputState: any = MountDomain.InputState

local function Contains(ValueList: { string }, Expected: string): boolean
	for _Index: number, Value: string in ValueList do
		if Value == Expected then
			return true
		end
	end

	return false
end

local function CreateRig(IncludeRiderAnchor: boolean, IncludeDisconnectedPart: boolean): Model
	local Visual: Model = Instance.new("Model")
	Visual.Name = "TestHorseRig"

	local RootPart: Part = Instance.new("Part")
	RootPart.Name = "RootPart"
	RootPart.Anchored = true
	RootPart.CFrame = CFrame.new(0, -10000, 0)
	RootPart.Parent = Visual
	Visual.PrimaryPart = RootPart

	local HorseMesh: Part = Instance.new("Part")
	HorseMesh.Name = "Horse"
	HorseMesh.Anchored = true
	HorseMesh.CFrame = RootPart.CFrame
	HorseMesh.Parent = Visual

	local VisualJoint: Motor6D = Instance.new("Motor6D")
	VisualJoint.Name = "HorseMotor6D"
	VisualJoint.Part0 = RootPart
	VisualJoint.Part1 = HorseMesh
	VisualJoint.Parent = RootPart

	if IncludeRiderAnchor then
		local RiderAnchor: Attachment = Instance.new("Attachment")
		RiderAnchor.Name = "RiderAnchor"
		RiderAnchor.Parent = RootPart
	end

	if IncludeDisconnectedPart then
		local Decoration: Part = Instance.new("Part")
		Decoration.Name = "LegacyDecoration"
		Decoration.Anchored = true
		Decoration.CFrame = RootPart.CFrame
		Decoration.Parent = Visual
	end

	return Visual
end

return function(t: any): ()
	t.test("resolves the authored rig contract", function(): ()
		local Visual: Model = CreateRig(true, false)
		local Rig: any, ResolveError: string? = RigAdapter.Resolve(Visual)

		t.expect.equal(ResolveError, nil)
		t.expect.truthy(Rig)
		t.expect.equal(Rig.RootPart, Visual.PrimaryPart)
		t.expect.equal(Rig.RiderAnchor.Name, "RiderAnchor")
		t.expect.equal(#Rig.Diagnostics, 0)
		Visual:Destroy()
	end)

	t.test("reports a missing animated rider anchor without rejecting legacy rigs", function(): ()
		local Visual: Model = CreateRig(false, false)
		local Rig: any, ResolveError: string? = RigAdapter.Resolve(Visual)

		t.expect.equal(ResolveError, nil)
		t.expect.truthy(Rig)
		t.expect.equal(Rig.RiderAnchor, nil)
		t.expect.truthy(Contains(Rig.Diagnostics, "MissingRiderAnchor"))
		Visual:Destroy()
	end)

	t.test("preserves authored joints and only welds disconnected legacy parts", function(): ()
		local Visual: Model = CreateRig(true, true)
		Visual.Parent = workspace
		local Rig: any = RigAdapter.Resolve(Visual)
		local OriginalPrimaryPart: BasePart = Visual.PrimaryPart :: BasePart
		local HorseMesh: BasePart = Visual.Horse :: BasePart

		local Success: boolean, ErrorValue: any = pcall(function(): ()
			local Result: any = Assembly.Create(Rig, CFrame.new(0, 2, 0), OriginalPrimaryPart.CFrame, {
				SeatSize = Vector3.new(2.4, 1, 2.4),
				LinearMaxForce = 1000000,
				AlignMaxTorque = 1000000,
				AlignMaxAngularVelocity = 18,
				AlignResponsiveness = 32,
			})

			t.expect.truthy(Result)
			t.expect.equal(Visual.PrimaryPart, OriginalPrimaryPart)
			t.expect.equal(#Result.FallbackWeldParts, 1)
			t.expect.equal(Result.FallbackWeldParts[1].Name, "LegacyDecoration")

			for _Index: number, Weld: WeldConstraint in Result.Welds do
				local DirectlyWeldsAnimatedMesh: boolean = Weld.Part0 == Result.Root and Weld.Part1 == HorseMesh
					or Weld.Part1 == Result.Root and Weld.Part0 == HorseMesh
				t.expect.falsy(DirectlyWeldsAnimatedMesh)
			end
		end)

		Visual:Destroy()
		if not Success then
			error(ErrorValue, 0)
		end
	end)

	t.test("locks every mount phase with a stale-safe token", function(): ()
		local Registry: any = TransactionRegistry.new()
		local PlayerKey: Folder = Instance.new("Folder")
		local FirstToken: any, BusyPhase: string? = Registry:TryBegin(PlayerKey, "Preparing")

		t.expect.truthy(FirstToken)
		t.expect.equal(BusyPhase, nil)
		local DuplicateToken: any, DuplicatePhase: string? = Registry:TryBegin(PlayerKey, "Preparing")
		t.expect.equal(DuplicateToken, nil)
		t.expect.equal(DuplicatePhase, "Preparing")
		t.expect.truthy(Registry:Transition(PlayerKey, FirstToken, "Preparing", "Mounting"))
		t.expect.truthy(Registry:Transition(PlayerKey, FirstToken, "Mounting", "Mounted"))
		t.expect.truthy(Registry:Transition(PlayerKey, FirstToken, "Mounted", "Dismounting"))
		t.expect.truthy(Registry:Finish(PlayerKey, FirstToken))

		local SecondToken: any = Registry:TryBegin(PlayerKey, "Preparing")
		t.expect.truthy(SecondToken)
		t.expect.falsy(Registry:Finish(PlayerKey, FirstToken))
		t.expect.equal(Registry:GetPhase(PlayerKey), "Preparing")
		PlayerKey:Destroy()
	end)

	-- Duplicate movement packets cannot overwrite the latest accepted input.
	t.test("accepts only monotonically sequenced mount inputs", function(): ()
		local State: any = {
			LastProcessedInputSequence = 0,
			InputX = 0,
			InputZ = 0,
		}
		local JumpRequests: number = 0
		local function BeginJump(): ()
			JumpRequests += 1
		end
		local function EndJump(): () end

		t.expect.truthy(InputState.Apply(State, {
			Sequence = 2,
			MoveX = 0.5,
			MoveZ = -1,
			GaitMode = "Trot",
			JumpRequested = true,
		}, BeginJump, EndJump))
		t.expect.equal(State.InputX, 0.5)
		t.expect.equal(State.InputZ, -1)
		t.expect.equal(State.ClientGaitMode, "Trot")
		t.expect.equal(JumpRequests, 1)

		t.expect.falsy(InputState.Apply(State, {
			Sequence = 2,
			MoveX = -1,
		}, BeginJump, EndJump))
		t.expect.equal(State.InputX, 0.5)
		t.expect.equal(JumpRequests, 1)
	end)
end
