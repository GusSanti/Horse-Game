--!strict

local ServerStorage: ServerStorage = game:GetService("ServerStorage")
local GrowthSchedule: any = require(ServerStorage.Modules.Farming.GrowthSchedule)

return function(T: any): ()
	T.test("advances once at the scheduled deadline", function(): ()
		local Now: number = 4
		local Deadline: number? = 10
		local Callback: (() -> ())? = nil
		local AdvancedAt: number? = nil
		local Schedule: any = GrowthSchedule.new({
			Now = function(): number
				return Now
			end,
			Delay = function(_Seconds: number, Next: () -> ()): any
				Callback = Next
				return {}
			end,
			Cancel = function(_Thread: any): () end,
			GetDeadline = function(): number?
				return Deadline
			end,
			Advance = function(CurrentTime: number): ()
				AdvancedAt = CurrentTime
				Deadline = nil
			end,
		})

		Schedule:Refresh()
		T.expect.truthy(Callback)
		Now = 10
		local Run: (() -> ())? = Callback
		if not Run then
			error("growth callback was not scheduled")
		end
		Run()
		T.expect.equal(AdvancedAt, 10)
		Schedule:Destroy()
	end)

	T.test("cancels replaced and destroyed deadlines", function(): ()
		local Cancelled: number = 0
		local Schedule: any = GrowthSchedule.new({
			Now = function(): number
				return 0
			end,
			Delay = function(_Seconds: number, _Next: () -> ()): any
				return {}
			end,
			Cancel = function(_Thread: any): ()
				Cancelled += 1
			end,
			GetDeadline = function(): number?
				return 10
			end,
			Advance = function(_CurrentTime: number): () end,
		})

		Schedule:Refresh()
		Schedule:Refresh()
		Schedule:Destroy()
		T.expect.equal(Cancelled, 2)
	end)
end
