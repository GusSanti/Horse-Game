--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService: ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

return function(): { Success: boolean, Failures: { string } }
	local Failures: { string } = {}
	local FrameworkModule: ModuleScript = ReplicatedStorage.Modules.Framework
	local Manifest: any = require(FrameworkModule.RuntimeManifest)

	local function Check(Condition: boolean, Message: string): ()
		if not Condition then
			table.insert(Failures, Message)
		end
	end

	Check(FrameworkModule:GetAttribute("ServerReady") == true, "server did not report ready")
	Check(FrameworkModule:GetAttribute("ServerFailed") ~= true, "server reported startup failure")
	Check(ServerScriptService:FindFirstChild("ServerBootup") ~= nil, "central server bootstrap is missing")
	Check(ServerScriptService:FindFirstChild("Runtime") == nil, "legacy runtime folder still exists")
	Check(ServerStorage:FindFirstChild("RuntimeEntrypoints") == nil, "legacy entrypoint templates still exist")
	Check(#Manifest.Server == 0, "legacy server manifest still contains entries")
	Check(ReplicatedStorage:FindFirstChild("Net") ~= nil, "code-owned network root is missing")
	Check(workspace:FindFirstChild("Characters") ~= nil, "managed character folder is missing")

	return {
		Success = #Failures == 0,
		Failures = Failures,
	}
end
