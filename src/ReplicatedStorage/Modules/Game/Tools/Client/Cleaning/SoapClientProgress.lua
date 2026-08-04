local SoapClientProgress = {}

local function build_config(session, context)
	local progressGoal = math.max(context.getProgressGoal(session), 1)
	local progressAlpha = math.clamp(session.stageProgress / progressGoal, 0, 1)

	if session.completed then
		progressAlpha = 1
	end

	return {
		variant = context.taskVariant,
		text = session.instructionText or context.getInstructionText(session) or context.instructionText,
		timerText = session.statusText or context.getProgressTitle(session),
		progress = progressAlpha,
	}
end

function SoapClientProgress.show(session, context): boolean
	if type(session.showTask) ~= "function" then
		return false
	end

	return session.showTask(build_config(session, context)) ~= false
end

function SoapClientProgress.update(session, context): ()
	if type(session.updateTask) ~= "function" then
		return
	end

	session.updateTask(build_config(session, context))
end

function SoapClientProgress.hide(session, context): ()
	if type(session.hideTask) ~= "function" then
		return
	end

	session.hideTask({ variant = context.taskVariant })
end

return SoapClientProgress
