--!strict

export type Options = {
	Now: () -> number,
	Delay: ((number, () -> ()) -> any)?,
	Cancel: ((any) -> ())?,
	GetDeadline: () -> number?,
	Advance: (number) -> (),
}

local GrowthSchedule = {}
GrowthSchedule.__index = GrowthSchedule

local function DefaultCancel(Thread: thread): ()
	if coroutine.status(Thread) ~= "dead" then
		task.cancel(Thread)
	end
end

function GrowthSchedule.new(OptionsValue: Options): any
	return setmetatable({
		_Now = OptionsValue.Now,
		_Delay = OptionsValue.Delay or task.delay,
		_Cancel = OptionsValue.Cancel or DefaultCancel,
		_GetDeadline = OptionsValue.GetDeadline,
		_Advance = OptionsValue.Advance,
		_Thread = nil,
		_Token = 0,
		_Destroyed = false,
	}, GrowthSchedule)
end

function GrowthSchedule:_CancelThread(): ()
	local Thread: any = self._Thread
	self._Thread = nil
	if Thread ~= nil then
		self._Cancel(Thread)
	end
end

function GrowthSchedule:Refresh(): ()
	if self._Destroyed then
		return
	end

	self._Token += 1
	local Token: number = self._Token
	self:_CancelThread()

	local Deadline: number? = self._GetDeadline()
	if Deadline == nil then
		return
	end

	local DelaySeconds: number = math.max(Deadline - self._Now(), 0.05)
	self._Thread = self._Delay(DelaySeconds, function(): ()
		if self._Destroyed or self._Token ~= Token then
			return
		end

		self._Thread = nil
		self._Advance(self._Now())
		self:Refresh()
	end)
end

function GrowthSchedule:Destroy(): ()
	if self._Destroyed then
		return
	end

	self._Destroyed = true
	self._Token += 1
	self:_CancelThread()
end

return GrowthSchedule
