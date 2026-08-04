--!strict

local MOUNT_RUNTIME_PART_NAMES: { [string]: boolean } = table.freeze({
	HorseMountRoot = true,
	HorseMountSeat = true,
})

local ROOT_PART_NAMES: { string } = table.freeze({
	"HorseRoot",
	"RootPart",
})

local RIDER_ANCHOR_NAMES: { string } = table.freeze({
	"RiderAnchor",
	"RiderAttachment",
	"SaddleAttachment",
})

local ReportedDiagnostics: { [string]: boolean } = {}

export type RiderAnchor = Attachment | Bone

export type Rig = {
	Visual: Instance,
	RootPart: BasePart,
	BaseParts: { BasePart },
	RiderAnchor: RiderAnchor?,
	Diagnostics: { string },
}

local RigAdapter = {}

local function CollectBaseParts(Visual: Instance): { BasePart }
	local BaseParts: { BasePart } = {}
	if Visual:IsA("BasePart") and not MOUNT_RUNTIME_PART_NAMES[Visual.Name] then
		table.insert(BaseParts, Visual)
	end

	for _Index: number, Descendant: Instance in Visual:GetDescendants() do
		if Descendant:IsA("BasePart") and not MOUNT_RUNTIME_PART_NAMES[Descendant.Name] then
			table.insert(BaseParts, Descendant)
		end
	end

	table.sort(BaseParts, function(Left: BasePart, Right: BasePart): boolean
		return Left:GetFullName() < Right:GetFullName()
	end)
	return BaseParts
end

local function ResolveRootPart(Visual: Instance, BaseParts: { BasePart }, Diagnostics: { string }): BasePart?
	if Visual:IsA("BasePart") then
		return Visual
	end

	if Visual:IsA("Model") and Visual.PrimaryPart and Visual.PrimaryPart:IsDescendantOf(Visual) then
		return Visual.PrimaryPart
	end

	table.insert(Diagnostics, "MissingPrimaryPart")
	for _Index: number, RootName: string in ROOT_PART_NAMES do
		local NamedRoot: Instance? = Visual:FindFirstChild(RootName, true)
		if NamedRoot and NamedRoot:IsA("BasePart") then
			table.insert(Diagnostics, "ResolvedNamedRootFallback")
			return NamedRoot
		end
	end

	if BaseParts[1] then
		table.insert(Diagnostics, "ResolvedFirstBasePartFallback")
		return BaseParts[1]
	end

	return nil
end

local function ResolveRiderAnchor(Visual: Instance): RiderAnchor?
	for _Index: number, AnchorName: string in RIDER_ANCHOR_NAMES do
		local Candidate: Instance? = Visual:FindFirstChild(AnchorName, true)
		if Candidate and (Candidate:IsA("Attachment") or Candidate:IsA("Bone")) then
			return Candidate :: RiderAnchor
		end
	end

	return nil
end

function RigAdapter.Resolve(Visual: Instance): (Rig?, string?)
	local Diagnostics: { string } = {}
	local BaseParts: { BasePart } = CollectBaseParts(Visual)
	if #BaseParts == 0 then
		return nil, "HorseRigHasNoBaseParts"
	end

	local RootPart: BasePart? = ResolveRootPart(Visual, BaseParts, Diagnostics)
	if not RootPart then
		return nil, "HorseRigRootMissing"
	end

	local RiderAnchor: RiderAnchor? = ResolveRiderAnchor(Visual)
	if not RiderAnchor then
		table.insert(Diagnostics, "MissingRiderAnchor")
	end

	return {
		Visual = Visual,
		RootPart = RootPart,
		BaseParts = BaseParts,
		RiderAnchor = RiderAnchor,
		Diagnostics = Diagnostics,
	}, nil
end

function RigAdapter.ResolveAndReport(Visual: Instance): (Rig?, string?)
	local RigValue: Rig?, ResolveError: string? = RigAdapter.Resolve(Visual)
	if not RigValue or #RigValue.Diagnostics == 0 then
		return RigValue, ResolveError
	end

	local DiagnosticText: string = table.concat(RigValue.Diagnostics, ",")
	local DiagnosticKey: string = string.format("%s:%s", Visual.Name, DiagnosticText)
	if not ReportedDiagnostics[DiagnosticKey] then
		ReportedDiagnostics[DiagnosticKey] = true
		warn(string.format(
			"[HorseRigAdapter] Rig %s mounted with compatibility diagnostics: %s",
			Visual:GetFullName(),
			DiagnosticText
		))
	end

	return RigValue, nil
end

function RigAdapter.GetBaseParts(Visual: Instance): { BasePart }
	return CollectBaseParts(Visual)
end

function RigAdapter.GetDisconnectedParts(RigValue: Rig): { BasePart }
	local Connected: { [BasePart]: boolean } = {
		[RigValue.RootPart] = true,
	}

	for _Index: number, Part: BasePart in RigValue.RootPart:GetConnectedParts(true) do
		Connected[Part] = true
	end

	local Disconnected: { BasePart } = {}
	for _Index: number, Part: BasePart in RigValue.BaseParts do
		if not Connected[Part] then
			table.insert(Disconnected, Part)
		end
	end

	return Disconnected
end

function RigAdapter.ClearReportedDiagnostics(): ()
	table.clear(ReportedDiagnostics)
end

return table.freeze(RigAdapter)
