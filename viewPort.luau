-- Connected Discord-GitHub
local rep = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local player = game:GetService("Players").LocalPlayer
local uis = game:GetService("UserInputService")

local animFolder = rep:WaitForChild("Anims")
local viewportFolder = rep:WaitForChild("viewPorts")
local crossHair = player.PlayerGui:WaitForChild("Cross")


local camera = workspace.CurrentCamera

-- Rod config
local ROPE_LENGTH = 5
local THROW_SPEED = 100            
local WINCH_FORCE = 10000
local CRANK_STEP = math.rad(3.55)
local REEL_STOP_MARGIN = 0.5       -- how close the bait must be to stop reeling

-- ads animation blending
local ADS_BLEND_TIME = 0.15


local isAiming = false --unused for now

local activePort = nil -- the active viewport model (there can only be one)
local activeThread = nil -- the thread that is connected to the port (there can also only be one cus its connected to the viewport)

local char
local hrp
local hum

local oldEvents = {} -- to avoid memory leaks
local loadedAnims = {} -- to again avoid memory leaks and re-loading

local function updateVariables()
	--so the variables stay updated
	char = player.Character or player.CharacterAdded:Wait()
	hrp = char:WaitForChild("HumanoidRootPart")
	hum = char:WaitForChild("Humanoid")
end

-- call first in case .characteradded doesnt catch it at startup
updateVariables()

local portFolder = Instance.new("Folder")
portFolder.Name = "portFolder"
portFolder.Parent = camera

player.CharacterAdded:Connect(function()
	-- call it on character loads so the variables update
	updateVariables()
end)

local function cleanPort()
	if activeThread then
		task.cancel(activeThread)
		activeThread = nil
		--killing the thread that the port is connected to so the rest of the code just stops running if not finished
	end

	if activePort and loadedAnims[activePort] then
		--stop and destroy the loaded animations
		for _, track in loadedAnims[activePort] do
			track:Stop()
			track:Destroy()
		end
		loadedAnims[activePort] = nil
	end

	for _, v in oldEvents do
		--clearing old events
		v:Disconnect()
	end
	table.clear(oldEvents)

	for _, v in portFolder:GetChildren() do
		--clearing old port models
		v:Destroy()
	end
	activePort = nil
end

local function loadTrack(animator: Animator, animInstance: Animation): AnimationTrack
	
	--basic check to see if its alr loaded or not
	if not loadedAnims[activePort] then
		loadedAnims[activePort] = {}
	end

	local cached = loadedAnims[activePort][animInstance.AnimationId]
	if cached then
		return cached
	end

	local track = animator:LoadAnimation(animInstance)
	loadedAnims[activePort][animInstance.AnimationId] = track
	return track
end


local function getPortAnimator(port: Model): Animator?
	local animController = port:WaitForChild("Animation", 3)
	return animController and animController:WaitForChild("Animator", 3)
end


local function prepareTrack(animator: Animator, anim: Animation, priority: Enum.AnimationPriority, looped: boolean?): AnimationTrack
	--loading the track and settings priority and looping if needed
	local track = loadTrack(animator, anim)
	track.Priority = priority
	track.Looped = looped or false
	return track
end


local function buildBait(rodCopy: Model): (Part, RopeConstraint)
	local Bait = Instance.new("Part")
	Bait.Name = "Bait"
	Bait.Size = Vector3.one
	Bait.CanCollide = true
	Bait.Anchored = false
	Bait.Transparency = 0.5
	Bait.Parent = rodCopy

	local baitAtt = Instance.new("Attachment")
	baitAtt.Parent = Bait

	local rodAtt = Instance.new("Attachment")
	rodAtt.Parent = rodCopy.Tip

	local rope = Instance.new("RopeConstraint")
	rope.Attachment0 = baitAtt
	rope.Attachment1 = rodAtt
	rope.Length = ROPE_LENGTH
	rope.WinchTarget = rope.Length
	rope.Parent = Bait
	rope.Visible = true
	rope.Restitution = 0.2
	rope.WinchEnabled = false
	rope.WinchResponsiveness = 45
	rope.WinchSpeed = 20

	local dragAttachment = Instance.new("Attachment")
	dragAttachment.Parent = Bait


	-- a drag force to not make it fly around
	local drag = Instance.new("LinearVelocity")
	drag.Attachment0 = dragAttachment
	drag.MaxForce = 15
	drag.VectorVelocity = Vector3.zero
	drag.RelativeTo = Enum.ActuatorRelativeTo.World
	drag.Parent = Bait
	
	

	return Bait, rope
end


local function rigRod(rodCopy: Model, port: Model): Motor6D
	local crankArm = rodCopy:WaitForChild("Reel"):WaitForChild("crankArm") :: Model
	local shaft = crankArm:WaitForChild("CrankShaft")

	local crankMotor = shaft:FindFirstChild("CrankMotor")
	if not crankMotor then
		--setting up the crankmotor6dweld if not present
		crankMotor = Instance.new("Motor6D")
		crankMotor.Name = "CrankMotor"
		crankMotor.Part0 = rodCopy.Handle
		crankMotor.Part1 = shaft
		crankMotor.C0 = rodCopy.Handle.CFrame:ToObjectSpace(shaft.CFrame)
		crankMotor.C1 = CFrame.identity
		crankMotor.Parent = shaft
	end

	local motorWeld = rodCopy:FindFirstChildOfClass("Motor6D")
	if not motorWeld then
		--positioning the rod
		motorWeld = Instance.new("Motor6D")
		motorWeld.C0 = CFrame.new(0, 1.5, 0) * CFrame.fromOrientation(math.rad(13), 0, 0)
		motorWeld.Parent = rodCopy
		motorWeld.Part0 = rodCopy.Handle
		motorWeld.Part1 = port:FindFirstChild("Right Arm")
	end

	return crankMotor
end

local function bindThrowInput(throwTrack: AnimationTrack, reelTrack: AnimationTrack, Bait: Part, rope: RopeConstraint, crankMotor: Motor6D)
	local throwEvent = uis.InputBegan:Connect(function(key, gameProcessed)
		if gameProcessed then return end

		if key.UserInputType == Enum.UserInputType.MouseButton1 and not throwTrack.IsPlaying then
			if activeThread then
				task.cancel(activeThread)
				-- cancels the active thread even if the rod is already equipped so it can restart
				activeThread = nil
			end

			activeThread = task.spawn(function()
				throwTrack:Play()
				throwTrack:GetMarkerReachedSignal("hold"):Wait()
				-- wait until it gets to the holding part of the anim and freeze it
				throwTrack:AdjustSpeed(0)

				repeat task.wait() until not uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) -- waiting till the mouse is released

				throwTrack:AdjustSpeed(1)
				throwTrack:GetMarkerReachedSignal("throw"):Wait()
				-- wait until the throw animation is done

				rope.WinchEnabled = true
				rope.WinchForce = 0
				--enabling the winch and setting the force to 0 so that the rope can get as far as it wants without any pull

				local forceWanted = camera.CFrame.LookVector.Unit * THROW_SPEED
				Bait.AssemblyLinearVelocity = forceWanted
				--throwing the bait

				while task.wait() do
					if uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then
						rope.WinchForce = WINCH_FORCE
						if not reelTrack.IsPlaying then
							reelTrack:Play()
						end

						crankMotor.C0 *= CFrame.fromOrientation(CRANK_STEP, 0, 0) -- crank animation

						if rope.Length >= rope.CurrentDistance - REEL_STOP_MARGIN then
							-- if the bait is close enough to the player then stop the winch
							rope.WinchEnabled = false
							reelTrack:Stop()
							break
						end
					else
						reelTrack:Stop()
						rope.WinchForce = 0
					end
				end

				activeThread = nil
				--since the thread ended set it back to nil
			end)
		end
	end)

	table.insert(oldEvents, throwEvent)
	--add the event for cleanup later
end

local function setupRod(port: Model)
	

	local animator = getPortAnimator(port)
	if not animator then return end

	local reelTrack = prepareTrack(animator, animFolder.Rod.Reel, Enum.AnimationPriority.Action, true)
	local throwTrack = prepareTrack(animator, animFolder.Rod.Throw, Enum.AnimationPriority.Action)
	prepareTrack(animator, animFolder.Rod.Idle, Enum.AnimationPriority.Idle, true):Play()

	local rodCopy = rep.Assets.Rods["River Reed Rod"]:Clone()
	local Bait, rope = buildBait(rodCopy)
	rodCopy.Parent = port

	local crankMotor = rigRod(rodCopy, port)
	bindThrowInput(throwTrack, reelTrack, Bait, rope, crankMotor)
end

local function setupGlock(port: Model)
	

	local animator = getPortAnimator(port)
	if not animator then return end

	local zoomTrack = prepareTrack(animator, animFolder.Guns.Glock.Zoom, Enum.AnimationPriority.Action, true) -- isnt an animation just a singular frame pose
	prepareTrack(animator, animFolder.Guns.Glock.Idle, Enum.AnimationPriority.Idle, true):Play()

	local zoomPressEvent = uis.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			zoomTrack:Play(ADS_BLEND_TIME)
			--ads blend time makes the transition smoother
		end
	end)

	local zoomReleaseEvent = uis.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton2 then
			if zoomTrack.IsPlaying then
				--ads blend time again makes the transition smoother
				zoomTrack:Stop(ADS_BLEND_TIME)
			end
		end
	end)

	table.insert(oldEvents, zoomPressEvent)
	table.insert(oldEvents, zoomReleaseEvent)
	--insert the events for cleanup later
end

--the setup functions of the items
local itemSetups = {
	Rod = setupRod,
	Glock = setupGlock,
}

local function setupActivePort(holdingName)
	cleanPort()
	--clean up the old port

	if not holdingName or holdingName == "" then
		--returns if the player is not holding anything
		return
	end

	local template = viewportFolder:FindFirstChild(holdingName, true)
	if not template then
		return
	end

	local model = template:Clone() :: Model

	for _, v in model:GetDescendants() do
		if v:IsA("BasePart") then
			v.CanCollide = false
			v.Anchored = false
		end
	end

	model.Parent = portFolder
	activePort = model

	local hrpPort = activePort:WaitForChild("HumanoidRootPart")
	hrpPort.Anchored = true

	local fakeCam = activePort:WaitForChild("FakeCamera", 3)
	if fakeCam then
		fakeCam.CFrame = camera.CFrame
	end

	local setup = itemSetups[holdingName] -- find the setup function
	
	if setup then
		setup(activePort)
	end
end

player:GetAttributeChangedSignal("Holding"):Connect(function()
	local newHolding = player:GetAttribute("Holding")
	setupActivePort(newHolding)
	--update once holding attribute changes (it is changed on the server)
end)

local initialHolding = player:GetAttribute("Holding")
if initialHolding and initialHolding ~= "" then
	setupActivePort(initialHolding)
	--in case if the event misses it at start
end

-- sway config
local swayCFrame = CFrame.new(0,0,0) -- the sway cframe that will be applied none at start
local lastCamCF = camera.CFrame

 
local SWAY_STRENGTH = 0.7 -- multiplier for the sway
local SWAY_SMOOTHNESS = 7 -- changes the lerp alpha value
local MAX_SWAY_ANGLE = math.rad(20) -- max angle the camera can sway




runService.RenderStepped:Connect(function(dt)
	local camCF = camera.CFrame
	local turnCF = lastCamCF:ToObjectSpace(camCF) -- get the relative cframe of the last cams frame to the curent cams cframe
	lastCamCF = camCF
	
	
	if not activePort then return end

	local fakeCamera = activePort:FindFirstChild("FakeCamera")
	if not fakeCamera then return end

	
	local pitch, yaw = turnCF:ToEulerAnglesYXZ() -- get the angles of it in radians
	local targetSwayPitch = math.clamp(-pitch * SWAY_STRENGTH, -MAX_SWAY_ANGLE, MAX_SWAY_ANGLE) -- clamp it so it doesnt get too extreme
	local targetSwayYaw = math.clamp(-yaw * SWAY_STRENGTH, -MAX_SWAY_ANGLE, MAX_SWAY_ANGLE) -- clamp it so it doesnt get too extreme
	

	local targetSwayCF = CFrame.Angles(targetSwayPitch, targetSwayYaw, targetSwayYaw * 0.7) -- apply everything to a cframe
	swayCFrame = swayCFrame:Lerp(targetSwayCF, math.clamp(dt * SWAY_SMOOTHNESS, 0, 1)) -- slowly go towards the target cframe so its smooth

	

	-- apply it
	fakeCamera.CFrame = camera.CFrame * swayCFrame
end)
