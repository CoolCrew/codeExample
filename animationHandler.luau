local AnimationHandler = {}

local hitStartMarker = "hitStart"
local hitEndMarker = "hitEnd"

local sendPacket = game:GetService("ReplicatedStorage").sendPacket
local player = game.Players.LocalPlayer
local requestPacket = game:GetService("ReplicatedStorage").requestPacket
local currentClassInfo = nil
local runService = game:GetService("RunService")

local loadedAnimationTracks = {}
local delayTime = 10


function onCharAdded(char)
	currentClassInfo = nil
	while task.wait(1) do
		if delayTime == 0 then warn("TIMED OUT COULDNT GET CLASS") break end
		delayTime -= 1
		if char:GetAttribute("Class") then
			currentClassInfo = requestPacket:InvokeServer("getClassInfo")
		end
		if currentClassInfo then
			break
		end
		
	end
	

	loadedAnimationTracks = {}
end

function AnimationHandler.Init()
	player.CharacterAdded:Connect(function(char)
		onCharAdded(char)
		
	end)
	
	player.Character = player.Character or player.CharacterAdded:Wait()
	
	onCharAdded(player.Character)
	
	
	
	task.spawn(function()
		runService.Heartbeat:Connect(function()

			if not currentClassInfo then return end

			if not player.Character then return end

			if player.Character:GetAttribute("State") == "blocking" then
				local blockTrack = AnimationHandler.getTrack(currentClassInfo.blockAnimationId)::AnimationTrack
				if not blockTrack.IsPlaying then
					blockTrack:Play()
				end
			else
				local blockTrack = AnimationHandler.getTrack(currentClassInfo.blockAnimationId)::AnimationTrack
				if blockTrack.IsPlaying then
					blockTrack:Stop()
				end
			end
		end)
	end)
end




function AnimationHandler.getTrack(animationId)
	local char = player.Character 
	if not char then return end
	local hum = char:WaitForChild("Humanoid")
	local animator = hum:WaitForChild("Animator")
	
	if not loadedAnimationTracks[animationId] then
		local newAnimation = Instance.new("Animation")
		newAnimation.AnimationId = animationId
		local track = animator:LoadAnimation(newAnimation)
		loadedAnimationTracks[animationId] = track
		newAnimation:Destroy()
	end
	
	local animTrack = loadedAnimationTracks[animationId] :: AnimationTrack

	
	return animTrack
	
end

function AnimationHandler.stopAnims()
	for _, track in pairs(loadedAnimationTracks) do
		
		
		track:Stop()
	end
end


sendPacket.OnClientEvent:Connect(function(packet,animationId)
	if packet == "playAnimation" then
		
		local char = player.Character or player.CharacterAdded:Wait()
		local hum = char:WaitForChild("Humanoid")
		local animator = hum:WaitForChild("Animator")
		
		if not loadedAnimationTracks[animationId] then
			local newAnimation = Instance.new("Animation")
			newAnimation.AnimationId = animationId
			local track = animator:LoadAnimation(newAnimation)
			loadedAnimationTracks[animationId] = track
			newAnimation:Destroy()
			
		end
		
		
		local animTrack = loadedAnimationTracks[animationId] :: AnimationTrack
		AnimationHandler.stopAnims()
		animTrack:Play()
		
		local hitStartConnect = animTrack:GetMarkerReachedSignal("hitStart"):Connect(function(eventValue)
			sendPacket:FireServer("hitStart",{eventValue})
		end)
		
		local hitEndConnect = animTrack:GetMarkerReachedSignal("hitEnd"):Connect(function(eventValue)
			sendPacket:FireServer("hitEnd",{eventValue})
		end)
		
		animTrack.Stopped:Once(function()
			hitStartConnect:Disconnect()
			hitEndConnect:Disconnect()
			sendPacket:FireServer("animEnd")
		end)
		
		
	end
end)



return AnimationHandler
