--!strict

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, Callback: (...any) -> ()) -> Connection,
	Once: (self: Signal, Callback: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Destroy: (self: Signal) -> (),
}

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect(): ()
	if not self.Connected then
		return
	end

	self.Connected = false
	local Owner: any = (self :: any)._Owner
	if Owner then
		Owner._Listeners[(self :: any)._Id] = nil
	end
	(self :: any)._Owner = nil
	(self :: any)._Callback = nil
end

function Signal.new(): Signal
	return setmetatable({
		_Destroyed = false,
		_NextId = 0,
		_Listeners = {},
	}, Signal) :: any
end

function Signal:Connect(Callback: (...any) -> ()): Connection
	assert(not (self :: any)._Destroyed, "Cannot connect to a destroyed signal")
	assert(type(Callback) == "function", "Signal callback must be a function")

	local Self: any = self
	Self._NextId += 1
	local NewConnection: any = setmetatable({
		Connected = true,
		_Owner = self,
		_Id = Self._NextId,
		_Callback = Callback,
	}, Connection)
	Self._Listeners[NewConnection._Id] = NewConnection
	return NewConnection
end

function Signal:Once(Callback: (...any) -> ()): Connection
	local NewConnection: Connection? = nil
	NewConnection = self:Connect(function(...: any): ()
		if NewConnection then
			NewConnection:Disconnect()
		end
		Callback(...)
	end)
	return NewConnection
end

function Signal:Fire(...: any): ()
	if (self :: any)._Destroyed then
		return
	end

	local Snapshot: { any } = {}
	for _Id: number, Listener: any in (self :: any)._Listeners do
		table.insert(Snapshot, Listener)
	end

	for _Index: number, Listener: any in Snapshot do
		if Listener.Connected and Listener._Callback then
			Listener._Callback(...)
		end
	end
end

function Signal:Destroy(): ()
	local Self: any = self
	if Self._Destroyed then
		return
	end

	Self._Destroyed = true
	for _Id: number, Listener: any in Self._Listeners do
		Listener:Disconnect()
	end
	table.clear(Self._Listeners)
end

return table.freeze(Signal)
