--!strict

local Signal = require(script.Parent.Signal)

local RuntimeEvents = {
	PlayerAdded = Signal.new(),
	PlayerRemoving = Signal.new(),
	CharacterAdded = Signal.new(),
	CharacterRemoving = Signal.new(),
	ServerStarted = Signal.new(),
	ServerStopping = Signal.new(),
	ClientStarted = Signal.new(),
	ClientStopping = Signal.new(),
	ScreenRegistered = Signal.new(),
	ScreenOpened = Signal.new(),
	ScreenClosed = Signal.new(),
}

return table.freeze(RuntimeEvents)
