--!strict

local Crossing = {}

function Crossing.CrossedCenter(PreviousSignedCoordinate: number, SignedCoordinate: number): boolean
	return PreviousSignedCoordinate > 0 and SignedCoordinate <= 0
end

function Crossing.CanCapture(
	IsJumping: boolean,
	WasJumping: boolean,
	LandedAt: number?,
	Now: number,
	GraceSeconds: number
): boolean
	if IsJumping or WasJumping then
		return true
	end
	if not LandedAt or Now < LandedAt then
		return false
	end

	return Now - LandedAt <= GraceSeconds
end

return table.freeze(Crossing)
