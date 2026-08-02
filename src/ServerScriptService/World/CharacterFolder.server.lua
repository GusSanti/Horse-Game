------------------//SERVICES
local Players: Players = game:GetService("Players")
local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")

------------------//CONSTANTS
local CHARACTERS_FOLDER_NAME = "Characters"

------------------//VARIABLES
local Modules = ReplicatedStorage:WaitForChild("Modules")
local Libraries = Modules:WaitForChild("Libraries")
local Trove = require(Libraries:WaitForChild("Trove"))

local charactersFolder: Folder? = nil
local playerTroves: {[Player]: any} = {}

------------------//FUNCTIONS
local function ensure_characters_folder(): Folder
	if charactersFolder and charactersFolder.Parent == workspace then
		return charactersFolder
	end

	local currentFolder = workspace:FindFirstChild(CHARACTERS_FOLDER_NAME)
	if currentFolder and currentFolder:IsA("Folder") then
		charactersFolder = currentFolder
		return currentFolder
	end

	local newFolder = Instance.new("Folder")
	newFolder.Name = CHARACTERS_FOLDER_NAME
	newFolder.Parent = workspace
	charactersFolder = newFolder

	return newFolder
end

local function cleanup_player(player: Player): ()
	local playerTrove = playerTroves[player]
	if not playerTrove then
		return
	end

	playerTrove:Destroy()
	playerTroves[player] = nil
end

------------------//MAIN FUNCTIONS
local function on_character_added(player: Player, character: Model): ()
	if not character or not character.Parent then
		warn("Invalid character for " .. player.Name)
		return
	end

	character.Parent = ensure_characters_folder()
end

local function on_player_added(player: Player): ()
	cleanup_player(player)

	local playerTrove = Trove.new()
	playerTroves[player] = playerTrove

	playerTrove:Connect(player.CharacterAdded, function(character: Model)
		on_character_added(player, character)
	end)

	local currentCharacter = player.Character
	if currentCharacter then
		on_character_added(player, currentCharacter)
	end
end

local function on_player_removing(player: Player): ()
	cleanup_player(player)
end

------------------//INIT
ensure_characters_folder()

for _, player: Player in Players:GetPlayers() do
	on_player_added(player)
end

Players.PlayerAdded:Connect(on_player_added)
Players.PlayerRemoving:Connect(on_player_removing)
