--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

local Framework: any = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Framework"))

export type EntryConfig = {
	Layer: string?,
	Exclusive: boolean?,
	SetOpen: (IsOpen: boolean, Animate: boolean) -> (),
}

type Entry = {
	Id: string,
	Layer: string,
	Exclusive: boolean,
	Open: boolean,
	Version: number,
	SetOpen: (IsOpen: boolean, Animate: boolean) -> (),
}

local DEFAULT_LAYER: string = "Modal"
local Entries: { [string]: Entry } = {}
local Initialized: boolean = false

local UIRouter = {}

local function UpdateDiagnostics(): ()
	local RegisteredCount: number = 0
	local OpenScreen: string? = nil
	for _Id: string, EntryValue: Entry in Entries do
		RegisteredCount += 1
		if EntryValue.Open then
			OpenScreen = EntryValue.Id
		end
	end
	script:SetAttribute("RegisteredCount", RegisteredCount)
	script:SetAttribute("OpenScreen", OpenScreen)
end

local function Apply(EntryValue: Entry, IsOpen: boolean, Animate: boolean): boolean
	if EntryValue.Open == IsOpen then
		return false
	end

	EntryValue.Open = IsOpen
	EntryValue.SetOpen(IsOpen, Animate)

	if IsOpen then
		Framework.RuntimeEvents.ScreenOpened:Fire(EntryValue.Id, EntryValue.Layer)
	else
		Framework.RuntimeEvents.ScreenClosed:Fire(EntryValue.Id, EntryValue.Layer)
	end
	UpdateDiagnostics()
	return true
end

local function CloseExclusiveSiblings(Target: Entry): ()
	if not Target.Exclusive then
		return
	end

	for Id: string, EntryValue: Entry in Entries do
		if Id ~= Target.Id and EntryValue.Open and EntryValue.Layer == Target.Layer then
			Apply(EntryValue, false, false)
		end
	end
end

function UIRouter.Init(): ()
	Initialized = true
	script:SetAttribute("Initialized", true)
	UpdateDiagnostics()
end

function UIRouter.Register(Id: string, Config: EntryConfig, InitiallyOpen: boolean?): (() -> ())
	assert(type(Id) == "string" and Id ~= "", "UIRouter.Register requires a non-empty id")
	assert(type(Config) == "table" and type(Config.SetOpen) == "function", "UIRouter.Register requires SetOpen")

	local Existing: Entry? = Entries[Id]
	if Existing then
		Existing.Layer = Config.Layer or Existing.Layer
		Existing.Exclusive = Config.Exclusive ~= false
		Existing.Open = if InitiallyOpen == nil then Existing.Open else InitiallyOpen
		Existing.Version += 1
		Existing.SetOpen = Config.SetOpen
		UpdateDiagnostics()
		local Version: number = Existing.Version
		return function(): ()
			local Current: Entry? = Entries[Id]
			if Current == Existing and Current.Version == Version then
				UIRouter.Unregister(Id)
			end
		end
	end

	local EntryValue: Entry = {
		Id = Id,
		Layer = Config.Layer or DEFAULT_LAYER,
		Exclusive = Config.Exclusive ~= false,
		Open = InitiallyOpen == true,
		Version = 1,
		SetOpen = Config.SetOpen,
	}
	Entries[Id] = EntryValue
	Framework.RuntimeEvents.ScreenRegistered:Fire(Id, EntryValue.Layer)
	UpdateDiagnostics()
	local Version: number = EntryValue.Version

	return function(): ()
		local Current: Entry? = Entries[Id]
		if Current == EntryValue and Current.Version == Version then
			UIRouter.Unregister(Id)
		end
	end
end

function UIRouter.Unregister(Id: string): ()
	local EntryValue: Entry? = Entries[Id]
	if not EntryValue then
		return
	end

	Entries[Id] = nil
	if EntryValue.Open then
		Framework.RuntimeEvents.ScreenClosed:Fire(EntryValue.Id, EntryValue.Layer)
	end
	UpdateDiagnostics()
end

function UIRouter.Open(Id: string, Animate: boolean?): boolean
	local EntryValue: Entry? = Entries[Id]
	if not EntryValue then
		return false
	end

	CloseExclusiveSiblings(EntryValue)
	Apply(EntryValue, true, Animate ~= false)
	return true
end

function UIRouter.Close(Id: string, Animate: boolean?): boolean
	local EntryValue: Entry? = Entries[Id]
	if not EntryValue then
		return false
	end

	Apply(EntryValue, false, Animate ~= false)
	return true
end

function UIRouter.Toggle(Id: string, Animate: boolean?): boolean
	if UIRouter.IsOpen(Id) then
		return UIRouter.Close(Id, Animate)
	end
	return UIRouter.Open(Id, Animate)
end

function UIRouter.Sync(Id: string, IsOpen: boolean): boolean
	local EntryValue: Entry? = Entries[Id]
	if not EntryValue then
		return false
	end

	if IsOpen then
		CloseExclusiveSiblings(EntryValue)
	end
	if EntryValue.Open == IsOpen then
		return true
	end

	EntryValue.Open = IsOpen
	if IsOpen then
		Framework.RuntimeEvents.ScreenOpened:Fire(EntryValue.Id, EntryValue.Layer)
	else
		Framework.RuntimeEvents.ScreenClosed:Fire(EntryValue.Id, EntryValue.Layer)
	end
	UpdateDiagnostics()
	return true
end

function UIRouter.IsRegistered(Id: string): boolean
	return Entries[Id] ~= nil
end

function UIRouter.IsOpen(Id: string): boolean
	local EntryValue: Entry? = Entries[Id]
	return EntryValue ~= nil and EntryValue.Open
end

function UIRouter.GetOpen(Layer: string?): string?
	for Id: string, EntryValue: Entry in Entries do
		if EntryValue.Open and (Layer == nil or EntryValue.Layer == Layer) then
			return Id
		end
	end
	return nil
end

function UIRouter.CloseLayer(Layer: string, Animate: boolean?): ()
	for _Id: string, EntryValue: Entry in Entries do
		if EntryValue.Open and EntryValue.Layer == Layer then
			Apply(EntryValue, false, Animate ~= false)
		end
	end
end

function UIRouter.Destroy(): ()
	if not Initialized and next(Entries) == nil then
		return
	end

	for Id: string in table.clone(Entries) do
		UIRouter.Unregister(Id)
	end
	Initialized = false
	script:SetAttribute("Initialized", false)
	UpdateDiagnostics()
end

return UIRouter
