-- Paste this entire file into Roblox Studio's Command Bar while NOT playing.
-- It permanently lowers the root Bones inside the horse templates so idle,
-- mounted movement, and race animations share the same corrected rig height.

local ChangeHistoryService = game:GetService("ChangeHistoryService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

assert(not RunService:IsRunning(), "Run this command from Studio edit mode, not during Play mode.")

local TARGET_RIG_HEIGHT_CORRECTION_Y = -0.75
local APPLIED_CORRECTION_ATTRIBUTE = "HorseRigHeightCorrectionY"

local sourceFolders = {}
local assets = ReplicatedStorage:FindFirstChild("Assets")
local assetHorses = assets and assets:FindFirstChild("Horses")
if assetHorses then
	sourceFolders[#sourceFolders + 1] = assetHorses
end

local replicatedHorseModels = ReplicatedStorage:FindFirstChild("HorseModels")
if replicatedHorseModels then
	sourceFolders[#sourceFolders + 1] = replicatedHorseModels
end

assert(#sourceFolders > 0, "No horse templates found in ReplicatedStorage.Assets.Horses or ReplicatedStorage.HorseModels.")

local correctedRootBones = 0
local unchangedRootBones = 0
local correctedTemplates = {}

ChangeHistoryService:SetWaypoint("Before correcting horse rig heights")

for _, sourceFolder: Instance in ipairs(sourceFolders) do
	for _, descendant: Instance in ipairs(sourceFolder:GetDescendants()) do
		if descendant:IsA("Bone") and not descendant.Parent:IsA("Bone") then
			local previousCorrection = tonumber(descendant:GetAttribute(APPLIED_CORRECTION_ATTRIBUTE)) or 0
			local correctionDelta = TARGET_RIG_HEIGHT_CORRECTION_Y - previousCorrection

			if math.abs(correctionDelta) > 0.0001 then
				-- Pre-multiplication applies the correction in the MeshPart's Y axis,
				-- independently of the Bone's local rotation.
				descendant.CFrame = CFrame.new(0, correctionDelta, 0) * descendant.CFrame
				descendant:SetAttribute(APPLIED_CORRECTION_ATTRIBUTE, TARGET_RIG_HEIGHT_CORRECTION_Y)
				correctedRootBones += 1
			else
				unchangedRootBones += 1
			end

			local template = descendant
			while template.Parent and template.Parent ~= sourceFolder do
				template = template.Parent
			end
			correctedTemplates[template] = true
		end
	end
end

assert(
	correctedRootBones > 0 or unchangedRootBones > 0,
	"No root Bones were found in the horse templates; no rig height was changed."
)

local templateCount = 0
for _ in pairs(correctedTemplates) do
	templateCount += 1
end

ChangeHistoryService:SetWaypoint("Corrected horse rig heights")
print(
	("[HorseRigHeightFix] Templates=%d RootBonesChanged=%d AlreadyCorrect=%d TargetY=%.2f"):format(
		templateCount,
		correctedRootBones,
		unchangedRootBones,
		TARGET_RIG_HEIGHT_CORRECTION_Y
	)
)
