--[[ 
   Connected Discord-GitHub
   
   Discord: @synitx. (974345285742526474)
   Roblox: Synitx (1863535003)
   
   
   Resources used
   - spr (spring driven motion) | author: @Fractality | [https://devforum.roblox.com/t/spring-driven-motion-spr/714728]
   - Syn's modular framework | author: @Synitx | [https://devforum.roblox.com/t/simple-modular-framework/3379110]
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Controller = require(ReplicatedStorage.Controller).new()
local petConfig = require(ReplicatedStorage.Modules.PetConfig)
local spr = require(ReplicatedStorage.Shared.Packages.spr)

function Controller:Init()
	self.trackedPets = {} -- Table of pets to track
end

function Controller:Start()
	local petFolder = Workspace:WaitForChild(petConfig.folderName) -- Wait for the pet folder

	for _, pet in petFolder:GetChildren() do -- Track existing pets
		self:trackPet(pet)
	end

	petFolder.ChildAdded:Connect(function(pet) -- Track new pets (whenever they gets added to the pet folder)
		self:trackPet(pet)
	end)

	petFolder.ChildRemoved:Connect(function(pet) -- Once pets get removed, untrack the pet and clean up
		self:untrackPet(pet)
	end)

	RunService.Heartbeat:Connect(function() -- Constantly update the pet's position
		self:updatePets()
	end)
end

function Controller:trackPet(pet) -- Track the pet
	local ownerId = pet:GetAttribute(petConfig.ownerAttribute) or 0
	self.trackedPets[pet] = {
		phase = (ownerId % 10) * 0.7, -- Random phase for smoother animation
	}
end

function Controller:untrackPet(pet) -- Untrack the pet
	self.trackedPets[pet] = nil
	spr.stop(pet)
end

function Controller:getOwnerRoot(pet) -- Gets the owner's root part
	local ownerId = pet:GetAttribute(petConfig.ownerAttribute) -- getting the owner id from the pet
	local owner = ownerId and Players:GetPlayerByUserId(ownerId)
	local character = owner and owner.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function Controller:getFlatCFrame(rootPart) -- Gets the flat CFrame of the root part
	local position = rootPart.Position
	local lookVector = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z) -- Sets Y to 0 which removes the vertical part of the direction.

	if flatLook.Magnitude < 0.01 then -- Just a safety check for the part if it faces up or down just a little bit then returns the fallback value
		return CFrame.new(position)
	end

	return CFrame.lookAt(position, position + flatLook) -- Retuns the CFrame
end

function Controller:getLean(rootPart, flatCFrame)
	local velocity = rootPart.AssemblyLinearVelocity
	local localVelocity = flatCFrame:VectorToObjectSpace(Vector3.new(velocity.X, 0, velocity.Z)) -- Throws away the up/down speed, so jumping or falling doesn't make the pet tilt, only ground movement counts
	local pitch = math.clamp(localVelocity.Z * petConfig.leanAmount, -petConfig.maxLean, petConfig.maxLean) -- Handles the tilting, the faster it moves the more it tilts its clamped with the maxlean so it doesnt go past that value.
	local roll = math.clamp(-localVelocity.X * petConfig.leanAmount, -petConfig.maxLean, petConfig.maxLean) -- This handles sideways tilt
	return CFrame.Angles(pitch, 0, roll) -- Returns the final cframe with the proper tilt
end

function Controller:getTargetCFrame(rootPart, state)
	local flatCFrame = self:getFlatCFrame(rootPart)
	local bob = math.sin(os.clock() * petConfig.bobSpeed + state.phase) * petConfig.bobHeight -- A sine wave which is used to give smooth up and down float effect
	local anchorCFrame = flatCFrame * CFrame.new(petConfig.followOffset)
	local liftedCFrame = anchorCFrame + Vector3.new(0, bob, 0)
	return liftedCFrame * self:getLean(rootPart, flatCFrame)
end

function Controller:followRoot(pet, state, rootPart)
	-- Follows and constantly updates the pet's position towards the player's root part --
	local targetCFrame = self:getTargetCFrame(rootPart, state)
	local distance = (pet:GetPivot().Position - targetCFrame.Position).Magnitude

	if distance > petConfig.teleportDistance then
		spr.stop(pet)
		pet:PivotTo(targetCFrame)
		return
	end

	spr.target(pet, petConfig.damping, petConfig.frequency, {
		Pivot = targetCFrame,
	})
end

function Controller:updatePets()
	for pet, state in self.trackedPets do
		local rootPart = self:getOwnerRoot(pet)
		if rootPart then
			self:followRoot(pet, state, rootPart)
		end
	end
end

return Controller
