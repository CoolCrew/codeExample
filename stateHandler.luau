local StateHandler = {}

local activeThreads: { [Model]: thread } = {}

function StateHandler.getState(char: Model): string
	return char:GetAttribute("State") or "noState"
end

function StateHandler.setState(char: Model, state: string, duration: number?)
	if not char or not char.Parent then return end

	local now = workspace:GetServerTimeNow()
	local expiry = (duration and duration > 0 and duration ~= math.huge) and (now + duration) or 0


	if state == char:GetAttribute("State") and expiry <= char:GetAttribute("StateExpiry") then return end -- Prevents overriding a longer state
	
	if activeThreads[char] then
		task.cancel(activeThreads[char])
		activeThreads[char] = nil
	end

	
	char:SetAttribute("State", state)
	char:SetAttribute("StateExpiry", expiry)

	
	if not duration or duration <= 0 or duration == math.huge or state == "noState" then
		return
	end


	activeThreads[char] = task.delay(duration, function()
		activeThreads[char] = nil
		if not char.Parent then return end

		local currentExpiry = char:GetAttribute("StateExpiry") or 0
		local currentState = char:GetAttribute("State") or "noState"

		if workspace:GetServerTimeNow() >= currentExpiry and currentState == state then
			char:SetAttribute("State", "noState")
			char:SetAttribute("StateExpiry", 0)
		end
	end)
end


workspace.DescendantRemoving:Connect(function(descendant)
	if activeThreads[descendant] then
		task.cancel(activeThreads[descendant])
		activeThreads[descendant] = nil
	end
end)

return StateHandler
