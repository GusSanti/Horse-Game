--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local Signal: any = require(ReplicatedStorage.Modules.Framework.Signal)

return function(t: any): ()
	-- Connected listeners receive the values supplied by the owner.
	t.test("delivers fired values", function(): ()
		local Event: any = Signal.new()
		local Received: string? = nil
		Event:Connect(function(Value: string): ()
			Received = Value
		end)

		Event:Fire("ready")
		t.expect.equal(Received, "ready")
		Event:Destroy()
	end)

	-- A disconnected listener releases ownership and receives no later events.
	t.test("disconnects listeners", function(): ()
		local Event: any = Signal.new()
		local Count: number = 0
		local Connection: any = Event:Connect(function(): ()
			Count += 1
		end)

		Event:Fire()
		Connection:Disconnect()
		Event:Fire()
		t.expect.equal(Count, 1)
		Event:Destroy()
	end)

	-- Once listeners remove themselves before invoking user code.
	t.test("fires once listeners once", function(): ()
		local Event: any = Signal.new()
		local Count: number = 0
		Event:Once(function(): ()
			Count += 1
		end)

		Event:Fire()
		Event:Fire()
		t.expect.equal(Count, 1)
		Event:Destroy()
	end)

	-- Destroy is idempotent and rejects new resource ownership.
	t.test("rejects connections after destroy", function(): ()
		local Event: any = Signal.new()
		Event:Destroy()
		Event:Destroy()
		t.expect.throws(function(): ()
			Event:Connect(function(): () end)
		end)
	end)
end
