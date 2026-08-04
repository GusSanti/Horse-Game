--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RuntimeManifest: any = require(ReplicatedStorage.Modules.Framework.RuntimeManifest)

return function(t: any): ()
	local function ValidateEntries(Entries: { any }): ()
		local Names: { [string]: boolean } = {}
		for _Index: number, Definition: any in Entries do
			t.expect.truthy(type(Definition.Name) == "string" and Definition.Name ~= "")
			t.expect.truthy(type(Definition.Path) == "table" and #Definition.Path > 0)
			t.expect.falsy(Names[Definition.Name])
			Names[Definition.Name] = true
		end
	end

	-- Every runtime entry has a stable unique name and a resolvable path contract.
	t.test("defines valid server entrypoints", function(): ()
		ValidateEntries(RuntimeManifest.Server)
	end)

	-- Client startup uses the same explicit manifest contract as server startup.
	t.test("defines valid client entrypoints", function(): ()
		ValidateEntries(RuntimeManifest.Client)
	end)

	-- The server no longer depends on cloned scripts; components own its lifecycle.
	t.test("has no legacy server entrypoints", function(): ()
		t.expect.equal(#RuntimeManifest.Server, 0)
	end)
end
