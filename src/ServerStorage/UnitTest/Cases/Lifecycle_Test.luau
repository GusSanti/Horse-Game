--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lifecycle: any = require(ReplicatedStorage.Modules.Framework.Lifecycle)

return function(t: any): ()
	-- Init completes for every component before Start begins.
	t.test("runs lifecycle phases in deterministic order", function(): ()
		local Order: { string } = {}
		local Runtime: any = Lifecycle.new("Test", {
			{
				Name = "First",
				Init = function(): ()
					table.insert(Order, "First.Init")
				end,
				Start = function(): ()
					table.insert(Order, "First.Start")
				end,
			},
			{
				Name = "Second",
				Init = function(): ()
					table.insert(Order, "Second.Init")
				end,
				Start = function(): ()
					table.insert(Order, "Second.Start")
				end,
			},
		})

		Runtime:Start()
		t.expect.equal(table.concat(Order, ","), "First.Init,Second.Init,First.Start,Second.Start")
	end)

	-- Cleanup reverses dependency order so consumers stop before providers.
	t.test("destroys components in reverse order", function(): ()
		local Order: { string } = {}
		local Runtime: any = Lifecycle.new("Test", {
			{
				Name = "Provider",
				Destroy = function(): ()
					table.insert(Order, "Provider")
				end,
			},
			{
				Name = "Consumer",
				Destroy = function(): ()
					table.insert(Order, "Consumer")
				end,
			},
		})

		Runtime:Start()
		Runtime:Destroy()
		t.expect.equal(table.concat(Order, ","), "Consumer,Provider")
	end)

	-- Repeated calls are safe and never bind resources twice.
	t.test("is idempotent", function(): ()
		local Starts: number = 0
		local Destroys: number = 0
		local Runtime: any = Lifecycle.new("Test", {
			{
				Start = function(): ()
					Starts += 1
				end,
				Destroy = function(): ()
					Destroys += 1
				end,
			},
		})

		Runtime:Start()
		Runtime:Start()
		Runtime:Destroy()
		Runtime:Destroy()
		t.expect.equal(Starts, 1)
		t.expect.equal(Destroys, 1)
	end)

	-- A component failure prevents the runtime from reporting a successful start.
	t.test("propagates component startup failures", function(): ()
		local Runtime: any = Lifecycle.new("Test", {
			{
				Name = "Broken",
				Start = function(): ()
					error("expected failure")
				end,
			},
		})

		local Message: string = t.expect.throws(function(): ()
			Runtime:Start()
		end)
		t.expect.truthy(string.find(Message, "Broken.Start failed", 1, true))
	end)
end
