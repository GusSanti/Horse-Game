--!strict

local Workspace: Workspace = game:GetService("Workspace")

local RigAdapter = require(script.Parent.RigAdapter)

local NAMES = table.freeze({
	Root = "HorseMountRoot",
	Seat = "HorseMountSeat",
	DriverAttachment = "HorseMountDriverAttachment",
	LinearVelocity = "HorseMountLinearVelocity",
	AlignOrientation = "HorseMountAlignOrientation",
	AntiGravityAttachment = "HorseMountAntiGravityAttachment",
	AntiGravityForce = "HorseMountAntiGravityForce",
})

export type Config = {
	SeatSize: Vector3,
	LinearMaxForce: number,
	AlignMaxTorque: number,
	AlignMaxAngularVelocity: number,
	AlignResponsiveness: number,
}

export type Result = {
	Root: BasePart,
	Seat: Seat,
	Welds: { WeldConstraint },
	FallbackWeldParts: { BasePart },
	DriverAttachment: Attachment,
	LinearVelocity: LinearVelocity,
	AlignOrientation: AlignOrientation,
	AntiGravityForce: VectorForce,
}

local Assembly = {
	Names = NAMES,
}

local function CreateWeld(Part0: BasePart, Part1: BasePart, Parent: Instance): WeldConstraint
	local Weld: WeldConstraint = Instance.new("WeldConstraint")
	Weld.Part0 = Part0
	Weld.Part1 = Part1
	Weld.Parent = Parent
	return Weld
end

local function ConfigureRuntimePart(Part: BasePart): ()
	Part.Anchored = false
	Part.CanCollide = false
	Part.CanQuery = false
	Part.CanTouch = false
end

local function CreateAntiGravityForce(MountRoot: BasePart): VectorForce
	local AttachmentValue: Attachment = Instance.new("Attachment")
	AttachmentValue.Name = NAMES.AntiGravityAttachment
	AttachmentValue.Parent = MountRoot

	local Force: VectorForce = Instance.new("VectorForce")
	Force.Name = NAMES.AntiGravityForce
	Force.ApplyAtCenterOfMass = true
	Force.RelativeTo = Enum.ActuatorRelativeTo.World
	Force.Attachment0 = AttachmentValue
	Force.Parent = MountRoot
	return Force
end

local function CreateDriverConstraints(
	MountRoot: BasePart,
	InitialRootCFrame: CFrame,
	ConfigValue: Config
): (Attachment, LinearVelocity, AlignOrientation)
	local DriverAttachment: Attachment = Instance.new("Attachment")
	DriverAttachment.Name = NAMES.DriverAttachment
	DriverAttachment.Parent = MountRoot

	local Velocity: LinearVelocity = Instance.new("LinearVelocity")
	Velocity.Name = NAMES.LinearVelocity
	Velocity.Attachment0 = DriverAttachment
	Velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	Velocity.VectorVelocity = Vector3.zero
	Velocity.MaxForce = ConfigValue.LinearMaxForce
	Velocity.Parent = MountRoot

	local Orientation: AlignOrientation = Instance.new("AlignOrientation")
	Orientation.Name = NAMES.AlignOrientation
	Orientation.Attachment0 = DriverAttachment
	Orientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	Orientation.CFrame = InitialRootCFrame.Rotation
	Orientation.MaxTorque = ConfigValue.AlignMaxTorque
	Orientation.MaxAngularVelocity = ConfigValue.AlignMaxAngularVelocity
	Orientation.Responsiveness = ConfigValue.AlignResponsiveness
	Orientation.RigidityEnabled = false
	Orientation.Parent = MountRoot

	return DriverAttachment, Velocity, Orientation
end

function Assembly.Create(
	Rig: RigAdapter.Rig,
	SeatLocalCFrame: CFrame,
	InitialRootCFrame: CFrame,
	ConfigValue: Config
): Result?
	local MountParent: Instance? = if Rig.Visual:IsA("Model") then Rig.Visual else Rig.Visual.Parent
	if not MountParent then
		return nil
	end

	local MountRoot: Part = Instance.new("Part")
	MountRoot.Name = NAMES.Root
	MountRoot.Transparency = 1
	MountRoot.Size = Vector3.new(2.4, 2.4, 2.4)
	ConfigureRuntimePart(MountRoot)
	MountRoot.CFrame = InitialRootCFrame
	MountRoot.Parent = MountParent

	local MountSeat: Seat = Instance.new("Seat")
	MountSeat.Name = NAMES.Seat
	MountSeat.Size = ConfigValue.SeatSize
	MountSeat.Transparency = 1
	ConfigureRuntimePart(MountSeat)
	MountSeat.CFrame = InitialRootCFrame * SeatLocalCFrame
	MountSeat.Parent = MountParent

	for _Index: number, Part: BasePart in Rig.BaseParts do
		Part.Massless = true
		ConfigureRuntimePart(Part)
	end

	local Welds: { WeldConstraint } = {
		CreateWeld(MountRoot, MountSeat, MountRoot),
		CreateWeld(MountRoot, Rig.RootPart, MountRoot),
	}

	-- Existing Motor6Ds and authored constraints remain the source of truth for
	-- the visual rig. Only genuinely disconnected legacy pieces receive a
	-- compatibility weld, avoiding closed rigid loops through animated parts.
	local FallbackWeldParts: { BasePart } = RigAdapter.GetDisconnectedParts(Rig)
	for _Index: number, Part: BasePart in FallbackWeldParts do
		table.insert(Welds, CreateWeld(Rig.RootPart, Part, Rig.RootPart))
	end

	local AntiGravityForce: VectorForce = CreateAntiGravityForce(MountRoot)
	local DriverAttachment: Attachment, Velocity: LinearVelocity, Orientation: AlignOrientation =
		CreateDriverConstraints(MountRoot, InitialRootCFrame, ConfigValue)
	AntiGravityForce.Force = Vector3.new(0, MountRoot.AssemblyMass * Workspace.Gravity, 0)

	return {
		Root = MountRoot,
		Seat = MountSeat,
		Welds = Welds,
		FallbackWeldParts = FallbackWeldParts,
		DriverAttachment = DriverAttachment,
		LinearVelocity = Velocity,
		AlignOrientation = Orientation,
		AntiGravityForce = AntiGravityForce,
	}
end

return table.freeze(Assembly)
