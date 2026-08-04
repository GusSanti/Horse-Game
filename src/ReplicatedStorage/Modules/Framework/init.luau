--!strict

local Framework = {
	Lifecycle = require(script.Lifecycle),
	RuntimeManifest = require(script.RuntimeManifest),
	RuntimeEvents = require(script.RuntimeEvents),
	Signal = require(script.Signal),
}

return table.freeze(Framework)
