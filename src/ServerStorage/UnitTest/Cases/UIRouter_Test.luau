--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIRouter: any = require(ReplicatedStorage.Modules.Client.Hud.UIRouter)

return function(t: any): ()
	t.test("opens one exclusive modal at a time", function(): ()
		UIRouter.Destroy()
		UIRouter.Init()
		local Changes: { string } = {}

		UIRouter.Register("Inventory", {
			SetOpen = function(IsOpen: boolean, Animate: boolean): ()
				table.insert(Changes, `Inventory:{tostring(IsOpen)}:{tostring(Animate)}`)
			end,
		}, false)
		UIRouter.Register("Shop", {
			SetOpen = function(IsOpen: boolean, Animate: boolean): ()
				table.insert(Changes, `Shop:{tostring(IsOpen)}:{tostring(Animate)}`)
			end,
		}, false)

		UIRouter.Open("Inventory", true)
		UIRouter.Open("Shop", true)

		t.expect.equal(table.concat(Changes, ","), "Inventory:true:true,Inventory:false:false,Shop:true:true")
		t.expect.falsy(UIRouter.IsOpen("Inventory"))
		t.expect.truthy(UIRouter.IsOpen("Shop"))
		UIRouter.Destroy()
	end)

	t.test("allows non-exclusive views to coexist", function(): ()
		UIRouter.Destroy()
		UIRouter.Init()
		local function IgnoreChange(_IsOpen: boolean, _Animate: boolean): () end

		UIRouter.Register("FirstToast", {
			Layer = "Notification",
			Exclusive = false,
			SetOpen = IgnoreChange,
		}, false)
		UIRouter.Register("SecondToast", {
			Layer = "Notification",
			Exclusive = false,
			SetOpen = IgnoreChange,
		}, false)

		UIRouter.Open("FirstToast", false)
		UIRouter.Open("SecondToast", false)
		t.expect.truthy(UIRouter.IsOpen("FirstToast"))
		t.expect.truthy(UIRouter.IsOpen("SecondToast"))
		UIRouter.Destroy()
	end)

	t.test("synchronizes visibility changed by legacy code", function(): ()
		UIRouter.Destroy()
		UIRouter.Init()
		local InventoryClosed: boolean = false

		UIRouter.Register("Inventory", {
			SetOpen = function(IsOpen: boolean, Animate: boolean): ()
				if not IsOpen and not Animate then
					InventoryClosed = true
				end
			end,
		}, false)
		UIRouter.Register("Shop", {
			SetOpen = function(_IsOpen: boolean, _Animate: boolean): () end,
		}, false)

		UIRouter.Open("Inventory", false)
		UIRouter.Sync("Shop", true)
		t.expect.truthy(InventoryClosed)
		t.expect.falsy(UIRouter.IsOpen("Inventory"))
		t.expect.truthy(UIRouter.IsOpen("Shop"))
		UIRouter.Destroy()
	end)

	t.test("does not let stale cleanup unregister a replacement", function(): ()
		UIRouter.Destroy()
		UIRouter.Init()
		local FirstCleanup: () -> () = UIRouter.Register("Stable", {
			SetOpen = function(_IsOpen: boolean, _Animate: boolean): () end,
		}, false)
		local SecondCleanup: () -> () = UIRouter.Register("Stable", {
			SetOpen = function(_IsOpen: boolean, _Animate: boolean): () end,
		}, false)

		FirstCleanup()
		t.expect.truthy(UIRouter.IsRegistered("Stable"))
		SecondCleanup()
		t.expect.falsy(UIRouter.IsRegistered("Stable"))
		UIRouter.Destroy()
	end)
end
