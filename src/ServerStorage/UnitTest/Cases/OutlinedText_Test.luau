--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local OutlinedText: any = require(
	ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Client"):WaitForChild("Hud"):WaitForChild("OutlinedText")
)

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
	t.test("styles text idempotently and restores its original font", function(): ()
		local Root: Frame = Instance.new("Frame")
		local Label: TextLabel = Instance.new("TextLabel")
		Label.Font = Enum.Font.Arial
		Label.TextSize = 24
		Label.Parent = Root

		OutlinedText.bind_all(Root)
		OutlinedText.bind_all(Root)

		t.expect.equal(Label.Font, Enum.Font.GothamBlack)
		t.expect.equal(CountNamedChildren(Label, "TextOutline"), 1)
		local Outline: UIStroke? = Label:FindFirstChild("TextOutline") :: UIStroke?
		t.expect.truthy(Outline)
		t.expect.equal(Outline and Outline.Color, Color3.new(0, 0, 0))

		OutlinedText.unbind_all(Root)
		t.expect.equal(Label.Font, Enum.Font.Arial)
		t.expect.falsy(Label:FindFirstChild("TextOutline"))
		Root:Destroy()
	end)

	t.test("leaves opted-out icon text unchanged", function(): ()
		local Label: TextLabel = Instance.new("TextLabel")
		Label.Font = Enum.Font.Arial
		Label:SetAttribute(OutlinedText.IconAttribute, true)

		OutlinedText.bind(Label)

		t.expect.equal(Label.Font, Enum.Font.Arial)
		t.expect.falsy(Label:FindFirstChild("TextOutline"))
		Label:Destroy()
	end)
end
