--[[ 
   Connected Discord-GitHub
   
   Discord: @synitx. (974345285742526474)
   Roblox: Synitx (1863535003)
   
   
   Resources used
   - spr (spring driven motion) | author: @Fractality | [https://devforum.roblox.com/t/spring-driven-motion-spr/714728]
   - Syn's modular framework | author: @Synitx | [https://devforum.roblox.com/t/simple-modular-framework/3379110]
]]

local controllers = script.Parent.Controllers:GetChildren()

function throwWarning(module : ModuleScript, reason)
	warn(`---------------------------------`)
	warn(`[CLIENT] | FRAMEWORK | Unable to load {module.Name}`)
	warn(`Reason: {reason}`)
	warn(`---------------------------------`)
end

for _, module in controllers do
	if typeof(module) == "Instance" and module:IsA("ModuleScript") then
		local status, requiredModule = pcall(function()
			return require(module)
		end)
		if not status then
			throwWarning(module, requiredModule)
			continue
		end
		if requiredModule.isFrameworkLoader then
			task.spawn(function()
				if requiredModule.Init then
					local startTime = tick()
					requiredModule:Init()
					requiredModule.installizedIn = tick() - startTime
				end

				if requiredModule.Start then
					local startTime = tick()
					requiredModule:Start()
					requiredModule.startedIn = tick() - startTime
				end
			end)
		else
			throwWarning(module, `{module.Name} is not a valid framework controller.`)
			continue
		end
	end
end