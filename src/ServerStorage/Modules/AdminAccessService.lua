local Players = game:GetService("Players")

local AdminAccessService = {}

AdminAccessService.GROUP_ID = 1071228359
AdminAccessService.MINIMUM_ADMIN_RANK = 250

local function read_group_rank(player)
	local success, rankOrError = pcall(function()
		return player:GetRankInGroup(AdminAccessService.GROUP_ID)
	end)

	if success and type(rankOrError) == "number" then
		return rankOrError, nil
	end

	return 0, rankOrError
end

function AdminAccessService.ApplyAccessAttributes(player)
	local rank, rankError = read_group_rank(player)
	if rankError ~= nil then
		warn(("AdminAccess failed to read rank for %s: %s"):format(player.Name, tostring(rankError)))
	end

	player:SetAttribute("AdminGroupId", AdminAccessService.GROUP_ID)
	player:SetAttribute("AdminMinimumRank", AdminAccessService.MINIMUM_ADMIN_RANK)
	player:SetAttribute("AdminRank", rank)
	player:SetAttribute("CanOpenAdminPanel", rank >= AdminAccessService.MINIMUM_ADMIN_RANK)

	return rank >= AdminAccessService.MINIMUM_ADMIN_RANK, rank
end

function AdminAccessService.HasAccess(player)
	local canOpenPanel = player:GetAttribute("CanOpenAdminPanel")
	if canOpenPanel == true then
		return true, player:GetAttribute("AdminRank") or 0
	end

	return AdminAccessService.ApplyAccessAttributes(player)
end

function AdminAccessService.RefreshAllPlayers()
	for _, player in Players:GetPlayers() do
		task.spawn(AdminAccessService.ApplyAccessAttributes, player)
	end
end

return AdminAccessService
