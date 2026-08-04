--!strict

export type Rating = "Perfect" | "Good" | "Bad"

export type Metrics = {
	TimingAlpha: number,
	AlignmentAlpha: number,
	EdgeAlpha: number,
	RhythmAlpha: number,
}

local TIMING_WEIGHT: number = 0.35
local ALIGNMENT_WEIGHT: number = 0.3
local EDGE_WEIGHT: number = 0.15
local RHYTHM_WEIGHT: number = 0.2
local PERFECT_THRESHOLD: number = 0.82
local GOOD_THRESHOLD: number = 0.55

local Scoring = {}

local function IsFinite(Value: number): boolean
	return Value == Value and Value ~= math.huge and Value ~= -math.huge
end

local function NormalizeAlpha(Value: number): number
	if not IsFinite(Value) then
		return 0
	end

	return math.clamp(Value, 0, 1)
end

function Scoring.Calculate(MetricsValue: Metrics): (Rating, number)
	local NormalizedScore: number =
		(NormalizeAlpha(MetricsValue.TimingAlpha) * TIMING_WEIGHT)
		+ (NormalizeAlpha(MetricsValue.AlignmentAlpha) * ALIGNMENT_WEIGHT)
		+ (NormalizeAlpha(MetricsValue.EdgeAlpha) * EDGE_WEIGHT)
		+ (NormalizeAlpha(MetricsValue.RhythmAlpha) * RHYTHM_WEIGHT)
	local Score: number = math.floor((NormalizedScore * 100) + 0.5)

	if NormalizedScore >= PERFECT_THRESHOLD then
		return "Perfect", Score
	end
	if NormalizedScore >= GOOD_THRESHOLD then
		return "Good", Score
	end

	return "Bad", Score
end

return table.freeze(Scoring)
