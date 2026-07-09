local RunService = game:GetService("RunService")

local HorseMountCharacter = {}

function HorseMountCharacter.captureCharacterState(character, humanoid, disabledStates)
	local collisionStates = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			collisionStates[descendant] = descendant.CanCollide
		end
	end

	local stateEnabled = {}
	for _, stateType in ipairs(disabledStates or {}) do
		stateEnabled[stateType] = humanoid:GetStateEnabled(stateType)
	end

	return {
		AutoRotate = humanoid.AutoRotate,
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		UseJumpPower = humanoid.UseJumpPower,
		PlatformStand = humanoid.PlatformStand,
		CollisionStates = collisionStates,
		StateEnabled = stateEnabled,
	}
end

function HorseMountCharacter.applyCharacterMountState(character, humanoid, disabledStates)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
		end
	end

	humanoid.AutoRotate = false
	humanoid.PlatformStand = false
	humanoid.WalkSpeed = 0

	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	for _, stateType in ipairs(disabledStates or {}) do
		humanoid:SetStateEnabled(stateType, false)
	end
end

function HorseMountCharacter.restoreCharacterState(_character, humanoid, savedState)
	if not savedState then
		return
	end

	for part, canCollide in pairs(savedState.CollisionStates or {}) do
		if part and part.Parent then
			part.CanCollide = canCollide
		end
	end

	if humanoid and humanoid.Parent then
		humanoid.Sit = false
		humanoid.AutoRotate = savedState.AutoRotate
		humanoid.UseJumpPower = savedState.UseJumpPower
		humanoid.PlatformStand = savedState.PlatformStand
		humanoid.WalkSpeed = savedState.WalkSpeed

		if savedState.UseJumpPower then
			humanoid.JumpPower = savedState.JumpPower
		else
			humanoid.JumpHeight = savedState.JumpHeight
		end

		for stateType, enabled in pairs(savedState.StateEnabled or {}) do
			humanoid:SetStateEnabled(stateType, enabled)
		end
	end
end

function HorseMountCharacter.captureTransitionState(humanoid)
	return {
		AutoRotate = humanoid.AutoRotate,
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		JumpHeight = humanoid.JumpHeight,
		UseJumpPower = humanoid.UseJumpPower,
		PlatformStand = humanoid.PlatformStand,
	}
end

function HorseMountCharacter.applyCharacterTransitionState(humanoid, rootPart)
	if not humanoid or not humanoid.Parent then
		return
	end

	humanoid.AutoRotate = false
	humanoid.PlatformStand = false
	humanoid.WalkSpeed = 0

	if humanoid.UseJumpPower then
		humanoid.JumpPower = 0
	else
		humanoid.JumpHeight = 0
	end

	pcall(function()
		humanoid:Move(Vector3.zero)
	end)

	if rootPart and rootPart.Parent then
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
	end
end

function HorseMountCharacter.restoreTransitionState(humanoid, savedState)
	if not humanoid or not humanoid.Parent or not savedState then
		return
	end

	humanoid.AutoRotate = savedState.AutoRotate
	humanoid.UseJumpPower = savedState.UseJumpPower
	humanoid.PlatformStand = savedState.PlatformStand
	humanoid.WalkSpeed = savedState.WalkSpeed

	if savedState.UseJumpPower then
		humanoid.JumpPower = savedState.JumpPower
	else
		humanoid.JumpHeight = savedState.JumpHeight
	end
end

function HorseMountCharacter.buildCharacterPivotFromRoot(character, rootPart, desiredRootCFrame)
	if not character or not rootPart then
		return desiredRootCFrame
	end

	local relativePivotOffset = rootPart.CFrame:ToObjectSpace(character:GetPivot())
	return desiredRootCFrame * relativePivotOffset
end

function HorseMountCharacter.smoothCharacterToRootCFrame(character, rootPart, targetRootCFrame, duration)
	if not character or not rootPart or not rootPart.Parent or not targetRootCFrame then
		return
	end

	local startRootCFrame = rootPart.CFrame
	local blendDuration = math.max(duration or 0, 0)
	if blendDuration <= 0.01 then
		character:PivotTo(HorseMountCharacter.buildCharacterPivotFromRoot(character, rootPart, targetRootCFrame))
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero
		return
	end

	local startedAt = os.clock()
	while true do
		if not character.Parent or not rootPart.Parent then
			break
		end

		local alpha = math.clamp((os.clock() - startedAt) / blendDuration, 0, 1)
		local easedAlpha = alpha * alpha * (3 - (2 * alpha))
		local nextRootCFrame = startRootCFrame:Lerp(targetRootCFrame, easedAlpha)
		character:PivotTo(HorseMountCharacter.buildCharacterPivotFromRoot(character, rootPart, nextRootCFrame))
		rootPart.AssemblyLinearVelocity = Vector3.zero
		rootPart.AssemblyAngularVelocity = Vector3.zero

		if alpha >= 1 then
			break
		end

		RunService.Heartbeat:Wait()
	end
end

function HorseMountCharacter.applyMountedHumanoidPose(mountState)
	local humanoid = mountState and mountState.Humanoid
	if not humanoid or not humanoid.Parent then
		return
	end

	humanoid.Sit = true
	humanoid.PlatformStand = false

	if humanoid:GetState() ~= Enum.HumanoidStateType.Seated then
		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Seated)
		end)
	end
end

return HorseMountCharacter
