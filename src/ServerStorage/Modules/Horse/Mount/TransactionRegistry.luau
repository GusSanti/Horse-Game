--!strict

export type Phase = "Preparing" | "Mounting" | "Mounted" | "Dismounting"

export type Token = {
	Id: number,
}

type Entry = {
	Phase: Phase,
	Token: Token,
}

export type Registry = {
	Entries: { [Instance]: Entry },
	NextId: number,
	TryBegin: (self: Registry, Key: Instance, Phase: Phase) -> (Token?, Phase?),
	Transition: (self: Registry, Key: Instance, Token: Token, Expected: Phase, Next: Phase) -> boolean,
	GetPhase: (self: Registry, Key: Instance) -> Phase?,
	IsCurrent: (self: Registry, Key: Instance, Token: Token, Phase: Phase?) -> boolean,
	Finish: (self: Registry, Key: Instance, Token: Token) -> boolean,
	Cancel: (self: Registry, Key: Instance) -> boolean,
	Clear: (self: Registry) -> (),
}

local TransactionRegistry = {}
TransactionRegistry.__index = TransactionRegistry

function TransactionRegistry.new(): Registry
	return setmetatable({
		Entries = {},
		NextId = 0,
	}, TransactionRegistry) :: any
end

function TransactionRegistry.TryBegin(self: Registry, Key: Instance, Phase: Phase): (Token?, Phase?)
	local Existing: Entry? = self.Entries[Key]
	if Existing then
		return nil, Existing.Phase
	end

	self.NextId += 1
	local Token: Token = table.freeze({
		Id = self.NextId,
	})
	self.Entries[Key] = {
		Phase = Phase,
		Token = Token,
	}
	return Token, nil
end

function TransactionRegistry.Transition(
	self: Registry,
	Key: Instance,
	Token: Token,
	Expected: Phase,
	Next: Phase
): boolean
	local EntryValue: Entry? = self.Entries[Key]
	if not EntryValue or EntryValue.Token ~= Token or EntryValue.Phase ~= Expected then
		return false
	end

	EntryValue.Phase = Next
	return true
end

function TransactionRegistry.GetPhase(self: Registry, Key: Instance): Phase?
	local EntryValue: Entry? = self.Entries[Key]
	return if EntryValue then EntryValue.Phase else nil
end

function TransactionRegistry.IsCurrent(self: Registry, Key: Instance, Token: Token, Phase: Phase?): boolean
	local EntryValue: Entry? = self.Entries[Key]
	return EntryValue ~= nil
		and EntryValue.Token == Token
		and (Phase == nil or EntryValue.Phase == Phase)
end

function TransactionRegistry.Finish(self: Registry, Key: Instance, Token: Token): boolean
	local EntryValue: Entry? = self.Entries[Key]
	if not EntryValue or EntryValue.Token ~= Token then
		return false
	end

	self.Entries[Key] = nil
	return true
end


function TransactionRegistry.Cancel(self: Registry, Key: Instance): boolean
	if not self.Entries[Key] then
		return false
	end

	self.Entries[Key] = nil
	return true
end


function TransactionRegistry.Clear(self: Registry): ()
	table.clear(self.Entries)
end

return table.freeze(TransactionRegistry)
