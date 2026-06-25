return {
	Id = "soap",
	ToolNames = {
		"soap",
	},
	Prompt = {
		ActionText = "Ensaboar",
		ObjectText = "Seu cavalo",
		HoldDuration = 0.2,
		MaxActivationDistance = 10,
		RequiresLineOfSight = false,
	},
	ConsumeOnUse = true,
	OnUse = function(_context)
		return true, "Consumed"
	end,
}
