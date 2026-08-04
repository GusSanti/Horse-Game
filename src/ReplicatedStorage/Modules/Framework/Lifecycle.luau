--!strict

export type Component = {
	Name: string?,
	Init: ((self: Component) -> ())?,
	Start: ((self: Component) -> ())?,
	Destroy: ((self: Component) -> ())?,
}

export type Lifecycle = {
	Name: string,
	Components: { Component },
	Initialized: boolean,
	Started: boolean,
	Destroyed: boolean,
	Init: (self: Lifecycle) -> (),
	Start: (self: Lifecycle) -> (),
	Destroy: (self: Lifecycle) -> (),
}

local Lifecycle = {}
Lifecycle.__index = Lifecycle

local function ComponentName(ComponentValue: Component, Index: number): string
	return ComponentValue.Name or `Component{Index}`
end

local function CallPhase(RuntimeName: string, ComponentValue: Component, Index: number, Phase: string): ()
	local Method: any = (ComponentValue :: any)[Phase]
	if type(Method) ~= "function" then
		return
	end

	local Success: boolean, ErrorValue: any = pcall(Method, ComponentValue)
	if not Success then
		error(`[{RuntimeName}] {ComponentName(ComponentValue, Index)}.{Phase} failed: {tostring(ErrorValue)}`, 0)
	end
end

function Lifecycle.new(Name: string, Components: { Component }): Lifecycle
	assert(Name ~= "", "Lifecycle requires a runtime name")

	local Self: Lifecycle = setmetatable({
		Name = Name,
		Components = table.clone(Components),
		Initialized = false,
		Started = false,
		Destroyed = false,
	}, Lifecycle) :: any

	return Self
end

function Lifecycle:Init(): ()
	if self.Initialized then
		return
	end
	assert(not self.Destroyed, `[{self.Name}] cannot initialize a destroyed lifecycle`)

	for Index: number, ComponentValue: Component in self.Components do
		CallPhase(self.Name, ComponentValue, Index, "Init")
	end

	self.Initialized = true
end

function Lifecycle:Start(): ()
	if self.Started then
		return
	end
	assert(not self.Destroyed, `[{self.Name}] cannot start a destroyed lifecycle`)

	self:Init()

	for Index: number, ComponentValue: Component in self.Components do
		CallPhase(self.Name, ComponentValue, Index, "Start")
	end

	self.Started = true
end

function Lifecycle:Destroy(): ()
	if self.Destroyed then
		return
	end

	self.Destroyed = true
	self.Started = false

	for Index: number = #self.Components, 1, -1 do
		local ComponentValue: Component = self.Components[Index]
		local Method: any = ComponentValue.Destroy
		if type(Method) == "function" then
			local Success: boolean, ErrorValue: any = pcall(Method, ComponentValue)
			if not Success then
				warn(`[{self.Name}] {ComponentName(ComponentValue, Index)}.Destroy failed: {tostring(ErrorValue)}`)
			end
		end
	end

	table.clear(self.Components)
end

return Lifecycle
