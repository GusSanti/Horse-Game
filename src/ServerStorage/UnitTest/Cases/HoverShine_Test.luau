--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules: Folder = ReplicatedStorage:WaitForChild("Modules") :: Folder
local HudAnim: any = require(Modules:WaitForChild("Libraries"):WaitForChild("HudAnim"))
local HoverShine: any = require(Modules:WaitForChild("Libraries"):WaitForChild("HudAnim"):WaitForChild("HoverShine"))

local function CountNamedChildren(Parent: Instance, Name: string): number
	local Count: number = 0
	for _Index: number, Child: Instance in Parent:GetChildren() do
		if Child.Name == Name then
			Count += 1
		end
	end
	return Count
end

return function(t: any): ()
	t.test("binds one reusable shine through HudAnim", function(): ()
		local Root: Frame = Instance.new("Frame")
		local Button: TextButton = Instance.new("TextButton")
		Button:SetAttribute("UIAnim", true)
		Button.Parent = Root

		HudAnim.bind(Button)
		HoverShine.bind(Button)

		t.expect.equal(CountNamedChildren(Button, "HoverShine"), 1)
		HudAnim.play_shine(Button)
		HudAnim.play_shine(Button)
		t.expect.equal(CountNamedChildren(Button, "HoverShine"), 1)

		HudAnim.unbind(Button)
		t.expect.falsy(Button:FindFirstChild("HoverShine"))
		Root:Destroy()
	end)

	t.test("leaves opted-out buttons unchanged", function(): ()
		local Button: TextButton = Instance.new("TextButton")
		Button:SetAttribute(HoverShine.IgnoreAttribute, true)

		HoverShine.bind(Button)

		t.expect.falsy(Button:FindFirstChild("HoverShine"))
		Button:Destroy()
	end)
end
