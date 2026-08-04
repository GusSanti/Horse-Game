--!strict

local ServerStorage: ServerStorage = game:GetService("ServerStorage")

local function Format(Value: any): string
	return if type(Value) == "string" then string.format("%q", Value) else tostring(Value)
end

local Expect = {}

function Expect.equal(Actual: any, Expected: any): ()
	if Actual ~= Expected then
		error(`expected {Format(Expected)}, got {Format(Actual)}`, 2)
	end
end

function Expect.truthy(Value: any): ()
	if not Value then
		error(`expected truthy, got {Format(Value)}`, 2)
	end
end

function Expect.falsy(Value: any): ()
	if Value then
		error(`expected falsy, got {Format(Value)}`, 2)
	end
end

function Expect.throws(Callback: () -> ()): string
	local Success: boolean, ErrorValue: any = pcall(Callback)
	if Success then
		error("expected the callback to throw", 2)
	end
	return tostring(ErrorValue)
end

return function(Filter: string?): { Run: number, Passed: number, Failed: number }
	local Totals = {
		Run = 0,
		Passed = 0,
		Failed = 0,
	}

	local UnitTestFolder: Folder = ServerStorage:WaitForChild("UnitTest") :: Folder
	local Cases: Folder = UnitTestFolder:WaitForChild("Cases") :: Folder
	for _Index: number, CaseModule: Instance in Cases:GetChildren() do
		if not CaseModule:IsA("ModuleScript") or (Filter and not string.find(CaseModule.Name, Filter, 1, true)) then
			continue
		end

		local CaseBuilder: any = require(CaseModule)
		local Context: any = {
			expect = Expect,
		}

		function Context.test(Name: string, Callback: () -> ()): ()
			Totals.Run += 1
			local Success: boolean, ErrorValue: any = pcall(Callback)
			if Success then
				Totals.Passed += 1
				print(`[PASS] {CaseModule.Name} > {Name}`)
			else
				Totals.Failed += 1
				warn(`[FAIL] {CaseModule.Name} > {Name} | {tostring(ErrorValue)}`)
			end
		end

		CaseBuilder(Context)
	end

	print(`[SUMMARY] {Totals.Run} run, {Totals.Passed} passed, {Totals.Failed} failed`)
	return Totals
end
