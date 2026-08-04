--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local InventoryLoadout: any = require(
	ReplicatedStorage.Modules.Utility.InventoryLoadout
)

return function(T: any): ()
	T.test("preserves a mixed preferred hotbar order", function(): ()
		local Entries: { any } = InventoryLoadout.GetOrderedEntries(
			{ "soap", "horse_brush" },
			{ "Regadera" },
			{
				{ Kind = "item", Value = "horse_brush" },
				{ Kind = "generic", Value = "Regadera" },
				{ Kind = "item", Value = "soap" },
			}
		)

		T.expect.equal(Entries[1].Value, "horse_brush")
		T.expect.equal(Entries[2].Kind, "generic")
		T.expect.equal(Entries[3].Value, "soap")
	end)

	T.test("drops stale entries and appends missing equipped entries", function(): ()
		local Entries: { any } = InventoryLoadout.GetOrderedEntries(
			{ "soap", "horse_brush" },
			{},
			{
				{ Kind = "item", Value = "missing" },
				{ Kind = "item", Value = "soap" },
				{ Kind = "item", Value = "soap" },
			}
		)

		T.expect.equal(#Entries, 2)
		T.expect.equal(Entries[1].Value, "soap")
		T.expect.equal(Entries[2].Value, "horse_brush")
	end)

	T.test("splits ordered entries without changing relative kind order", function(): ()
		local ItemIds: { any }, ToolNames: { any } = InventoryLoadout.SplitEntries({
			{ Kind = "generic", Value = "Regadera" },
			{ Kind = "item", Value = "soap" },
			{ Kind = "item", Value = "horse_brush" },
		})

		T.expect.equal(ItemIds[1], "soap")
		T.expect.equal(ItemIds[2], "horse_brush")
		T.expect.equal(ToolNames[1], "Regadera")
	end)
end
