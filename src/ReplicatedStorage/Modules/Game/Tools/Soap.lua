------------------//SERVICES

------------------//VARIABLES
local soap = {
	id = "soap",
	toolNames = {
		"soap",
	},
	prompt = {
		actionText = "Ensaboar",
		objectText = "Seu cavalo",
		holdDuration = 0.2,
		maxActivationDistance = 10,
		requiresLineOfSight = false,
	},
	consumeOnUse = true,
	onUse = function(_context)
		return true, "Consumed"
	end,
}

------------------//FUNCTIONS

------------------//MAIN FUNCTIONS

------------------//INIT
return soap
