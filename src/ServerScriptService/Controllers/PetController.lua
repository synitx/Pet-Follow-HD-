--[[ 
   Connected Discord-GitHub
   
   Discord: @synitx. (974345285742526474)
   Roblox: Synitx (1863535003)
   
   
   Resources used
   - spr (spring driven motion) | author: @Fractality | [https://devforum.roblox.com/t/spring-driven-motion-spr/714728]
   - Syn's modular framework | author: @Synitx | [https://devforum.roblox.com/t/simple-modular-framework/3379110]
]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Controller = require(ReplicatedStorage.Controller).new()
local petConfig = require(ReplicatedStorage.Modules.PetConfig)

function Controller:Init()
	self.printService = self:GetService("PrintService")
	self.assignedPets = {}
	self.characterConnections = {}
	self.petFolder = self:getPetFolder()
	self.petTemplate = ServerStorage:FindFirstChild(petConfig.templateName)
end

function Controller:Start()
	if not self.petTemplate then
        warn(`[{script.Name}] {petConfig.templateName} template missing from ServerStorage`)
		return
	end

	Players.PlayerAdded:Connect(function(player) -- Whenever player gets added, assign a pet to them
		self:assignPet(player)
	end)

	Players.PlayerRemoving:Connect(function(player) -- Clean up the player's pet when they leave
		self:removePet(player)
	end)

	for _, player in Players:GetPlayers() do -- For every player who are already in the server before this script installization
		self:assignPet(player)
	end
end

function Controller:getPetFolder() -- Checks for pet folder, if not then creates one
	local petFolder = Workspace:FindFirstChild(petConfig.folderName)
	if petFolder then
		return petFolder
	end

	petFolder = Instance.new("Folder")
	petFolder.Name = petConfig.folderName
	petFolder.Parent = Workspace
	return petFolder
end

function Controller:getPet(player) -- Gets the pet assigned to the player from the memory
	return self.assignedPets[player]
end

function Controller:preparePet(pet) -- Removes unnecessary stuff from the pet
	local instances = pet:GetDescendants()
	table.insert(instances, pet)

	for _, instance in instances do
		if instance:IsA("BasePart") then
			instance.Anchored = true
			instance.CanCollide = false
			instance.CanTouch = false
			instance.CanQuery = false
			instance.Massless = true
		end
	end
end

function Controller:createPet(player) -- Creates the pet and set its position
	local pet = self.petTemplate:Clone() -- Clones the template provided in the pet config
	pet.Name = `{player.Name}Pet`
	pet:SetAttribute(petConfig.ownerAttribute, player.UserId) -- Sets the owner's id as the attribute
	self:preparePet(pet)
	pet:PivotTo(CFrame.new(0, petConfig.spawnHeight, 0))
	return pet
end

function Controller:assignPet(player) -- Assigns the pet to the player
	local existingPet = self.assignedPets[player] -- Get the existing pet assigned to the player
	if existingPet then
		return existingPet
	end

	local pet = self:createPet(player) -- If pet is not assigned, it will create a new one and assign it to the player
	self:givePet(player, pet)
	return pet
end

function Controller:givePet(player, pet) -- Gives the pet to the player
	self:removePet(player) -- Remove the existing pet if there is one

	self.assignedPets[player] = pet
	pet.Parent = self.petFolder
	player:SetAttribute(petConfig.playerAttribute, pet.Name) -- Set the player's attribute to the assigned pet's name

	self.characterConnections[player] = player.CharacterAdded:Connect(function(character) -- When the player's character is added, it will seat the pet to the player
		self:seatPet(player, character) 
	end)

	if player.Character then -- If the player's character is already loaded, it will seat the pet to the player
		task.spawn(self.seatPet, self, player, player.Character)
	end

    self.printService:Print(`[{script.Name}] gave {pet.Name} to {player.Name}`)
end

function Controller:seatPet(player, character) -- Seats the pet to the player
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	local pet = self.assignedPets[player]
	if not rootPart or not pet or not pet.Parent then
		return
	end

	pet:PivotTo(rootPart.CFrame * CFrame.new(petConfig.followOffset)) -- Set the pet's position to the player's root part
end

function Controller:removePet(player) -- Removes the pet from the player (clean up function)
	local connection = self.characterConnections[player] -- Get the player character connection
	-- Cleaning up the connection to prevent memory leaks --
	if connection then
		connection:Disconnect() -- Disconnect the connection
		self.characterConnections[player] = nil -- Remove the connection from the table
	end

	local pet = self.assignedPets[player] -- Get the pet assigned to the player
	-- Cleaning up the pet to prevent memory leaks --
	if pet then
		self.assignedPets[player] = nil
		pet:Destroy()
	end

	player:SetAttribute(petConfig.playerAttribute, nil)
end

return Controller
