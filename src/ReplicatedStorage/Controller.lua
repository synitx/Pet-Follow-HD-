local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Controller = {}
Controller.__index = Controller

local Services = ReplicatedStorage:FindFirstChild("Services")

function Controller.new()
	local self = setmetatable({}, Controller)
	self.isFrameworkLoader = true
	self.installizedIn = 0
	self.startedIn = 0
	return self
end

function Controller:GetService(serviceName : string)
	if not Services then return end
	local module = Services:FindFirstChild(serviceName)
	if module then
		return require(module)
	else
		local status, service = pcall(function()
			return game:GetService(serviceName)
		end)
		return service
	end
end

return Controller