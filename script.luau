--[[ 
   Connected Discord-GitHub
   
   Discord: @synitx. (974345285742526474)
   Roblox: Synitx (1863535003)

]]

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local petConfig = table.freeze({
	folderName = "Pets",
	templateName = "Pet",
	ownerAttribute = "ownerUserId",
	playerAttribute = "petName",
	followOffset = Vector3.new(3, 2.5, 4),
	spawnHeight = 5,
	bobHeight = 0.4,
	bobSpeed = 2.5,
	damping = 0.7, -- 0 bounces forever, 1 no bounce at all, above 1 gets lazy
	frequency = 2.5, -- spring stiffness in hz, higher = snappier
	leanAmount = 0.02,
	maxLean = math.rad(25),
	teleportDistance = 60,
	catchUpDistance = 14, -- pet further than this from its spot gets a stiffer spring so fast players dont lose it
	catchUpBoost = 1.6, -- how much stiffer it gets at the most
	maxFailures = 5, -- frames in a row a pet can error before it gets rebuilt
	warnCooldown = 10, -- seconds between warnings for the same player
})

local Pets = {}
Pets.installizedIn = 0
Pets.startedIn = 0
Pets.running = false

local function throwWarning(reason)
	warn(`---------------------------------`)
	warn(`[SERVER] | PETS | {reason}`)
	warn(`---------------------------------`)
end

function Pets:Init()
	self.assignedPets = {} -- [player] = the pet and its spring state
	self.characterConnections = {}
	self.lastWarning = {}
	self.petFolder = self:getPetFolder()
	self.petTemplate = ServerStorage:FindFirstChild(petConfig.templateName)
end

function Pets:Start()
	if not self.petTemplate or not self.petTemplate:IsA("BasePart") then
		throwWarning(`{petConfig.templateName} template missing from ServerStorage (or its not a part)`)
		return
	end

	if petConfig.damping < 0 or petConfig.frequency <= 0 then -- These would make the spring explode so we dont even start
		throwWarning("damping / frequency in petConfig are not valid")
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

	RunService.Heartbeat:Connect(function(dt) -- Constantly update the pet's position
		self:updatePets(dt)
	end)

	self.running = true
end

function Pets:getPetFolder() -- Checks for pet folder, if not then creates one
	local petFolder = Workspace:FindFirstChild(petConfig.folderName)
	if petFolder then
		return petFolder
	end

	petFolder = Instance.new("Folder")
	petFolder.Name = petConfig.folderName
	petFolder.Parent = Workspace
	return petFolder
end

function Pets:warnPlayer(player, reason) -- Same as throwWarning but only once every few seconds per player, a broken pet would flood the output at 60 times a second
	local now = os.clock()
	local last = self.lastWarning[player]
	if last and now - last < petConfig.warnCooldown then
		return
	end

	self.lastWarning[player] = now
	throwWarning(`{player.Name}: {reason}`)
end

function Pets:preparePet(pet) -- Removes unnecessary stuff from the pet
	pet.Anchored = false -- Has to be unanchored, anchored parts moved by the server look choppy for everyone else
	pet.CanCollide = false
	pet.CanTouch = false
	pet.CanQuery = false

	local attachment = Instance.new("Attachment")
	attachment.Parent = pet

	local lift = Instance.new("VectorForce") -- Pushes up with the same force gravity pulls down, so the pet doesnt sag between frames
	lift.Attachment0 = attachment
	lift.RelativeTo = Enum.ActuatorRelativeTo.World
	lift.ApplyAtCenterOfMass = true
	lift.Force = Vector3.new(0, pet:GetMass() * Workspace.Gravity, 0)
	lift.Parent = pet
end

function Pets:createPet(player) -- Creates the pet and set its position
	local pet = self.petTemplate:Clone() -- Clones the template provided in the pet config
	pet.Name = `{player.Name}Pet`
	pet:SetAttribute(petConfig.ownerAttribute, player.UserId) -- Sets the owner's id as the attribute
	self:preparePet(pet)
	pet.CFrame = CFrame.new(0, petConfig.spawnHeight, 0)
	return pet
end

function Pets:assignPet(player) -- Assigns the pet to the player
	local existing = self.assignedPets[player] -- Get the existing pet assigned to the player
	if existing then
		return existing.pet
	end

	local pet = self:createPet(player) -- If pet is not assigned, it will create a new one and assign it to the player
	self:givePet(player, pet)
	return pet
end

function Pets:givePet(player, pet) -- Gives the pet to the player
	self:removePet(player) -- Remove the existing pet if there is one

	self.assignedPets[player] = {
		pet = pet,
		phase = (player.UserId % 10) * 0.7, -- Random phase for smoother animation
		pos = pet.Position, -- Spring for the position, where the pet is and how fast its moving
		vel = Vector3.zero,
		ang = Vector3.zero, -- Spring for the rotation, same thing but holds pitch, yaw, roll
		angVel = Vector3.zero,
		failures = 0,
	}

	pet.Parent = self.petFolder

	local ok, reason = pcall(pet.SetNetworkOwner, pet, nil) -- Server keeps control of the pet, if roblox hands it to the nearest player their physics fights with our movement
	if not ok then
		self:warnPlayer(player, `couldnt take network ownership of {pet.Name}: {reason}`)
	end

	player:SetAttribute(petConfig.playerAttribute, pet.Name) -- Set the player's attribute to the assigned pet's name

	self.characterConnections[player] = player.CharacterAdded:Connect(function(character) -- When the player's character is added, it will seat the pet to the player
		self:seatPet(player, character)
	end)

	if player.Character then -- If the player's character is already loaded, it will seat the pet to the player
		task.spawn(self.seatPet, self, player, player.Character)
	end

	print(`[{script.Name}] gave {pet.Name} to {player.Name}`)
end

function Pets:seatPet(player, character) -- Seats the pet to the player
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	local state = self.assignedPets[player]
	if not rootPart or not state or not state.pet.Parent then
		return
	end

	self:followRoot(player, state, rootPart, 0, true) -- snap = true, puts the pet right on its spot without any spring
end

function Pets:removePet(player) -- Removes the pet from the player (clean up function)
	local connection = self.characterConnections[player] -- Get the player character connection
	-- Cleaning up the connection to prevent memory leaks --
	if connection then
		connection:Disconnect() -- Disconnect the connection
		self.characterConnections[player] = nil -- Remove the connection from the table
	end

	local state = self.assignedPets[player] -- Get the pet assigned to the player
	-- Cleaning up the pet to prevent memory leaks --
	if state then
		self.assignedPets[player] = nil
		state.pet:Destroy()
	end

	self.lastWarning[player] = nil
	player:SetAttribute(petConfig.playerAttribute, nil)
end

function Pets:getOwnerRoot(player) -- Gets the owner's root part
	local character = player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

function Pets:getFlatCFrame(rootPart, lastYaw) -- Gets the flat CFrame of the root part
	local position = rootPart.Position
	local lookVector = rootPart.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z) -- Sets Y to 0 which removes the vertical part of the direction.

	if flatLook.Magnitude < 0.01 then -- Safety check, if the part faces straight up or down there is no flat direction so it just keeps the last yaw
		return CFrame.new(position) * CFrame.Angles(0, lastYaw, 0)
	end

	return CFrame.lookAt(position, position + flatLook)
end

function Pets:getLean(rootPart, flatCFrame) -- Gets how much the pet tilts (pitch, roll) from the owner's speed
	local velocity = rootPart.AssemblyLinearVelocity
	local localVelocity = flatCFrame:VectorToObjectSpace(Vector3.new(velocity.X, 0, velocity.Z)) -- Throws away the up/down speed, so jumping or falling doesn't make the pet tilt, only ground movement counts
	local pitch = math.clamp(localVelocity.Z * petConfig.leanAmount, -petConfig.maxLean, petConfig.maxLean) -- The faster it moves the more it tilts, clamped with maxLean so it doesnt go past that
	local roll = math.clamp(-localVelocity.X * petConfig.leanAmount, -petConfig.maxLean, petConfig.maxLean) -- Same for the sideways tilt
	return pitch, roll
end

function Pets:followRoot(player, state, rootPart, dt, snap) -- Moves the pet one step towards where it should be, snap = true skips the spring
	local flatCFrame = self:getFlatCFrame(rootPart, state.ang.Y)
	local _, goalYaw = flatCFrame:ToEulerAnglesYXZ()
	local pitch, roll = self:getLean(rootPart, flatCFrame)
	local bob = math.sin(os.clock() * petConfig.bobSpeed + state.phase) * petConfig.bobHeight -- A sine wave which is used to give smooth up and down float effect

	-- goalYaw is always between -pi and pi, this moves it by whole laps to the one closest to the pet's yaw, else going 179 -> -179 spins the pet 358 degrees instead of 2
	goalYaw = state.ang.Y + (goalYaw - state.ang.Y + math.pi) % (math.pi * 2) - math.pi

	local goalPos = flatCFrame:PointToWorldSpace(petConfig.followOffset) + Vector3.new(0, bob, 0)
	local goalAng = Vector3.new(pitch, goalYaw, roll)
	local distance = (state.pos - goalPos).Magnitude

	if snap or distance > petConfig.teleportDistance then
		state.pos, state.vel = goalPos, Vector3.zero
		state.ang, state.angVel = goalAng, Vector3.zero
	else
		-- The spring is solved exactly instead of adding a force every frame, so it doesnt go crazy when the server lags
		-- offset = how far the pet is from where it should be
		-- newOffset = P * offset + Q * velocity  |  newVelocity = R * offset + S * velocity
		-- P Q R S only depend on dt, stiffness (w) and damping (z)
		local w = petConfig.frequency * math.pi * 2 * (1 + math.clamp((distance - petConfig.catchUpDistance) / petConfig.catchUpDistance, 0, 1) * (petConfig.catchUpBoost - 1))
		local z = petConfig.damping
		if math.abs(z - 1) < 0.001 then
			z = 1.001 -- exactly 1 divides by 0 in the no bounce part, this is close enough that you cant tell
		end

		local P, Q, R, S
		if z < 1 then -- Bouncy, wobbles around the goal while it settles
			local wd = w * math.sqrt(1 - z * z) -- wobble speed, damping slows it down a bit
			local fade = math.exp(-z * w * dt)
			local cs, sn = math.cos(wd * dt), math.sin(wd * dt)
			local k = z * w / wd
			P, Q, R, S = fade * (cs + k * sn), fade * sn / wd, -fade * w * w / wd * sn, fade * (cs - k * sn)
		else -- No bounce, just eases in
			local sq = w * math.sqrt(z * z - 1)
			local r1, r2 = -z * w + sq, -z * w - sq -- the two fade out speeds it is mixed from
			local e1, e2 = math.exp(r1 * dt), math.exp(r2 * dt)
			P, Q, R, S = (r1 * e2 - r2 * e1) / (2 * sq), (e1 - e2) / (2 * sq), w * w * (e2 - e1) / (2 * sq), (r1 * e1 - r2 * e2) / (2 * sq)
		end

		local offset = state.pos - goalPos
		state.pos = goalPos + offset * P + state.vel * Q
		state.vel = offset * R + state.vel * S

		local angOffset = state.ang - goalAng -- rotation uses the exact same numbers, it only holds pitch/yaw/roll instead of x/y/z
		state.ang = goalAng + angOffset * P + state.angVel * Q
		state.angVel = angOffset * R + state.angVel * S

		if state.pos ~= state.pos or state.ang ~= state.ang then -- NaN is the only thing that isnt equal to itself, if the math blew up put the pet back on its spot
			state.pos, state.vel = goalPos, Vector3.zero
			state.ang, state.angVel = goalAng, Vector3.zero
			self:warnPlayer(player, `spring of {state.pet.Name} went NaN, reset it`)
		end
	end

	-- YXZ = turn by yaw first, then tilt (pitch, roll) relative to where the pet is facing
	state.pet.CFrame = CFrame.new(state.pos) * CFrame.fromEulerAnglesYXZ(state.ang.X, state.ang.Y, state.ang.Z)
	state.pet.AssemblyLinearVelocity = state.vel -- Tells roblox how fast the pet moves so it can smooth it out for the clients
end

function Pets:updatePets(dt) -- Moves every pet towards its owner, also deals with pets that got removed or keep erroring
	local rebuild = {} -- Players who need a new pet, done after the loop because we cant add/remove keys of assignedPets while looping over it

	for player, state in self.assignedPets do
		local rootPart = self:getOwnerRoot(player)

		if not state.pet.Parent then -- Something else destroyed it (fell out of the world, another script)
			table.insert(rebuild, player)
		elseif rootPart then
			local ok, reason = pcall(self.followRoot, self, player, state, rootPart, dt, false) -- pcall so one broken pet doesnt stop everyone else's
			if ok then
				state.failures = 0
			else
				state.failures += 1
				self:warnPlayer(player, `{state.pet.Name} failed to update ({state.failures}/{petConfig.maxFailures}): {reason}`)
				if state.failures >= petConfig.maxFailures then
					table.insert(rebuild, player)
				end
			end
		else -- No character right now (dead / loading), hold the pet still or it keeps drifting away with its last speed
			state.vel, state.angVel = Vector3.zero, Vector3.zero
			state.pet.AssemblyLinearVelocity = Vector3.zero
		end
	end

	for _, player in rebuild do
		throwWarning(`{player.Name}'s pet was removed or kept failing, giving them a new one`)
		self:removePet(player)
		self:assignPet(player)
	end
end

local startTime = os.clock()
Pets:Init()
Pets.installizedIn = os.clock() - startTime

startTime = os.clock()
Pets:Start()
Pets.startedIn = os.clock() - startTime

if Pets.running then
	print(`[{script.Name}] ready | init {math.floor(Pets.installizedIn * 1000)}ms, start {math.floor(Pets.startedIn * 1000)}ms`)
end
