--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local ObstacleDomain: any = require(ReplicatedStorage.Modules.Game.Horse.Obstacle)
local Scoring: any = ObstacleDomain.Scoring

return function(t: any): ()
	t.test("rates a balanced obstacle jump as perfect", function(): ()
		local Rating: string, Score: number = Scoring.Calculate({
			TimingAlpha = 1,
			AlignmentAlpha = 1,
			EdgeAlpha = 1,
			RhythmAlpha = 1,
		})

		t.expect.equal(Rating, "Perfect")
		t.expect.equal(Score, 100)
	end)

	t.test("rates a recoverable obstacle jump as good", function(): ()
		local Rating: string, Score: number = Scoring.Calculate({
			TimingAlpha = 0.6,
			AlignmentAlpha = 0.7,
			EdgeAlpha = 0.8,
			RhythmAlpha = 0.65,
		})

		t.expect.equal(Rating, "Good")
		t.expect.equal(Score, 67)
	end)

	t.test("rates a mistimed and crooked obstacle jump as bad", function(): ()
		local Rating: string, Score: number = Scoring.Calculate({
			TimingAlpha = 0.1,
			AlignmentAlpha = 0.2,
			EdgeAlpha = 0.3,
			RhythmAlpha = 0.25,
		})

		t.expect.equal(Rating, "Bad")
		t.expect.equal(Score, 19)
	end)

	t.test("clamps invalid metric ranges", function(): ()
		local Rating: string, Score: number = Scoring.Calculate({
			TimingAlpha = math.huge,
			AlignmentAlpha = 2,
			EdgeAlpha = -1,
			RhythmAlpha = 2,
		})

		t.expect.equal(Rating, "Bad")
		t.expect.equal(Score, 50)
	end)
end
