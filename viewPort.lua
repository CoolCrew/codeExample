-- Connected Discord-GitHub
-- everything is grouped in this order: services, constants, references, tool tables, state,
-- then the glock section, the fishing rod section, the viewport section, each section starts with its own animations

--// Services
local rep = game:GetService("ReplicatedStorage") -- Getting replicated storage from gameservice so that even if the name changes there would be no problem
local runService = game:GetService("RunService") -- getting runservice
local player = game:GetService("Players").LocalPlayer -- getting local player for use
local uis = game:GetService("UserInputService") -- getting userinputservice for input checkings

--// Constants
-- Rod config
local ROPE_LENGTH = 5 -- base hanging lenth of the rope that hangs from the rod
local THROW_SPEED = 100  -- sets the speed which the bait will be thrown
local WINCH_FORCE = 10000 -- a high force as a baseline so there wont be any problem on winching
local CRANK_STEP = math.rad(3.55) -- for the visual crank of the rod the amount of degrees itll turn each step
local REEL_STOP_MARGIN = 0.5 -- how close the bait must be to stop reeling

-- ads animation blending
local ADS_BLEND_TIME = 0.15 -- Will be put in :Play() to make the fade into the ads animation smoother

-- sway config
local SWAY_STRENGTH = 0.7 -- multiplier for the sway
local SWAY_SMOOTHNESS = 7 -- changes the lerp alpha value
local MAX_SWAY_ANGLE = math.rad(20) -- max angle the camera can sway

--// References
local animFolder = rep:WaitForChild("Anims") -- the place where the animations reside, waitforchild for delayed loads
local viewportFolder = rep:WaitForChild("viewPorts") -- the place where the viewport models reside, waitforchild for delayed loads

local camera = workspace.CurrentCamera -- getting the players camera to use its cframes and manipulate it

--// Tool tables
local Glock = {}
local FishingRod = {}

local itemSetups = { -- the name of the held item and the table that sets it up
	Rod = FishingRod,
	Glock = Glock,
}

--// State
local activePort = nil -- the active viewport model (there can only be one)
local activeThread = nil -- the thread that is connected to the port (there can also only be one cus its connected to the viewport)

local char -- representing the players character is updated when needed (functions for it below)
local hrp -- representing the players HumanoidRootPart is updated when needed (functions for it below)
local hum -- representing the players Humanoid is updated when needed (functions for it below)

local oldEvents = {} -- Events that are connected to an active port is stored here and cleared when the port changes
local activeTracks = {} -- the loaded animation tracks of the active port, [name] = track, cleared when activeport changes

local portFolder: Folder -- the folder where the activeport models will reside, created in startup

local swayCFrame = CFrame.new(0,0,0) -- the sway cframe that will be applied none at start
local lastCamCF = camera.CFrame -- the old cam cf that will be updated on every runservice renderstepped event


-- Glock.luau
-- the animations of the glock and their priority and looped are written here once at the start so nothing has to be set again when a port is made
-- the tracks themselves still have to be loaded per port since the port gets destroyed when the held item changes
Glock.animations = {
	Zoom = { Animation = animFolder:WaitForChild("Guns"):WaitForChild("Glock"):WaitForChild("Zoom"), Priority = Enum.AnimationPriority.Action, Looped = true }, -- its a pose animation with 1 frame so its looped and action
	Idle = { Animation = animFolder:WaitForChild("Guns"):WaitForChild("Glock"):WaitForChild("Idle"), Priority = Enum.AnimationPriority.Idle, Looped = true }, -- idle so the action animations can override it
}

function Glock.setup(port: Model)
	local zoomTrack = activeTracks.Zoom -- get the ads zoom track, it is already loaded with its priority and looped set
	activeTracks.Idle:Play() -- the idle track will always need to play so play it instantly

	local zoomPressEvent = uis.InputBegan:Connect(function(input, gameProcessed) -- create the event for ads'ing
		if gameProcessed then return end  -- meaning if they pressed while their chat was on etc. not count it

		if input.UserInputType == Enum.UserInputType.MouseButton2 then --if they pressed mb2
			zoomTrack:Play(ADS_BLEND_TIME) -- play the anim ads blend time makes the transition smoother

		end
	end)

	local zoomReleaseEvent = uis.InputEnded:Connect(function(input) -- another event for stopping ads'ing
		if input.UserInputType == Enum.UserInputType.MouseButton2 then -- if they let go of mb2
			if zoomTrack.IsPlaying then -- if the animation is already playing

				zoomTrack:Stop(ADS_BLEND_TIME) --Pause the anim ads blend time again makes the transition smoother
			end
		end
	end)

	table.insert(oldEvents, zoomPressEvent)
	table.insert(oldEvents, zoomReleaseEvent)
	--insert the events for cleanup later
end


-- FishingRod.luau
-- the animations of the rod and their priority and looped are written here once at the start so nothing has to be set again when a port is made
-- the tracks themselves still have to be loaded per port since the port gets destroyed when the held item changes
FishingRod.animations = {
	Reel = { Animation = animFolder:WaitForChild("Rod"):WaitForChild("Reel"), Priority = Enum.AnimationPriority.Action, Looped = true }, -- action so it overrides the idle
	Throw = { Animation = animFolder:WaitForChild("Rod"):WaitForChild("Throw"), Priority = Enum.AnimationPriority.Action, Looped = false }, -- action so it overrides the idle
	Idle = { Animation = animFolder:WaitForChild("Rod"):WaitForChild("Idle"), Priority = Enum.AnimationPriority.Idle, Looped = true }, -- idle so action animations like reeling can override it
}

local function buildBait(rodCopy: Model): (Part, RopeConstraint) -- making the bait that gets connected to the rope on the rod
	local Bait = Instance.new("Part") -- making the bait part
	Bait.Name = "Bait" -- naming it Bait so it can be found
	Bait.Size = Vector3.one -- using vector.one to size it to vector.new(1,1,1)
	Bait.CanCollide = true -- setting its cancollide to true since ill be using its physics
	Bait.Anchored = false -- to use its physics i need to set its anchored to false
	Bait.Transparency = 0.5 -- transparency is set 0.5 so that it is see thru
	Bait.Parent = rodCopy -- parented to rodcopy so when it needs to be cleared i can just clear rodcopy

	local baitAtt = Instance.new("Attachment") -- the endPoint attachment for the rope to connect
	baitAtt.Parent = Bait -- parenting to bait so its apparent

	local rodAtt = Instance.new("Attachment") -- the startPoint attachment for the rope to connect
	rodAtt.Parent = rodCopy.Tip -- parenting to rods tip so its apparent

	local rope = Instance.new("RopeConstraint") -- now construction the rope
	rope.Attachment0 = baitAtt -- setting the attachment0 of the rope to baitAtt so it has somewhere to connect to
	rope.Attachment1 = rodAtt -- setting the attachemtn1 of the rope to rodAatt so it has somewhere to connect to
	rope.Length = ROPE_LENGTH -- setting the base length of the rope to the length we've configured at the start of the code
	rope.WinchTarget = rope.Length -- making it so that if the winch is active at any time it will try to go back to its original length
	rope.Parent = Bait -- parenting it to bait which is parented to rod so if i destroy rod it will also be destroyed
	rope.Visible = true -- making it visible
	rope.Restitution = 0.2 -- it changes the rope bounce making it 0.2 gives it a good realistic feeling
	rope.WinchEnabled = false -- at start disabling the winch so the rope length doesnt change at all
	rope.WinchSpeed = 20 -- setting the winch speed to 20

	local dragAttachment = Instance.new("Attachment") -- making an attachment for the dragVector to connect to
	dragAttachment.Parent = Bait -- parenting it to bait for it to get destroyed along the rod


	-- a drag force to not make it fly around
	local drag = Instance.new("LinearVelocity") -- making a linearvelocity so that it will counteract the baits movement giving it drag
	drag.Attachment0 = dragAttachment -- connecting its attachment
	drag.MaxForce = 15 -- set the maxforce to 15 so that it doesnt stop instantly
	drag.VectorVelocity = Vector3.zero -- the target velocity which the velocity is trying to achieve
	drag.RelativeTo = Enum.ActuatorRelativeTo.World -- isnt really needed since vectorVelocity is zero but i like to keep it
	drag.Parent = Bait -- parenting it to bait for it to get destroyed along the rod

	return Bait, rope -- returning the bait and the rope for use
end

local function rigRod(rodCopy: Model, port: Model): Motor6D --adding the necceseary motor6ds that are needed
	local crankArm = rodCopy:WaitForChild("Reel"):WaitForChild("crankArm") :: Model -- shafts parent
	local shaft = crankArm:WaitForChild("CrankShaft") -- the part on the rod that will be rotated

	local crankMotor = shaft:FindFirstChild("CrankMotor") -- try to look for a motor6d
	if not crankMotor then -- if not found
		--setting up the crankmotor6dweld if not present
		crankMotor = Instance.new("Motor6D") --create it
		crankMotor.Name = "CrankMotor" -- name it the same
		crankMotor.Part0 = rodCopy.Handle -- setting the part0 to the handle of the rod
		crankMotor.Part1 = shaft -- setting the part1 to the shaft
		crankMotor.C0 = rodCopy.Handle.CFrame:ToObjectSpace(shaft.CFrame) -- taking the relative cframe and setting it as c0 so that the position and the rotation wont be distorted and it will stay in place
		crankMotor.C1 = CFrame.new(0,0,0) -- no need to change
		crankMotor.Parent = shaft -- parent it to the right part
	end

	local motorWeld = rodCopy:FindFirstChildOfClass("Motor6D") -- try to look for a motor6d
	if not motorWeld then -- if not found
		--positioning the rod
		motorWeld = Instance.new("Motor6D") -- create it
		motorWeld.C0 = CFrame.new(0, 1.5, 0) * CFrame.fromOrientation(math.rad(13), 0, 0) -- give its c0 cframes that have been set beforehand
		motorWeld.Parent = rodCopy -- parent it to the right part
		motorWeld.Part0 = rodCopy.Handle -- set the part0 to handle
		motorWeld.Part1 = port:FindFirstChild("Right Arm") -- set the part1 to the arm of the player
	end

	return crankMotor -- return the motor6d
end

local function bindThrowInput(throwTrack: AnimationTrack, reelTrack: AnimationTrack, Bait: Part, rope: RopeConstraint, crankMotor: Motor6D)
	local throwEvent = uis.InputBegan:Connect(function(key, gameProcessed)
		if gameProcessed then return end -- meaning if they pressed while their chat was on etc. not count it

		if key.UserInputType == Enum.UserInputType.MouseButton1 and not throwTrack.IsPlaying then --if they pressed the mouse and the throwtrack is not already playing
			if activeThread then -- check if there is an active thread
				task.cancel(activeThread)-- cancel if there is
				-- cancels the active thread even if the rod is already equipped so it can restart
				activeThread = nil -- set the thread to nil
			end

			activeThread = task.spawn(function() -- create a new thread for it
				throwTrack:Play() -- play the animation
				throwTrack:GetMarkerReachedSignal("hold"):Wait() -- wait until the animation event called hold

				throwTrack:AdjustSpeed(0) -- freeze the animation

				repeat task.wait() until not uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) -- waiting till the mouse is released

				throwTrack:AdjustSpeed(1) -- let the animation flow again
				throwTrack:GetMarkerReachedSignal("throw"):Wait() -- wait until the animation event called throw


				rope.WinchEnabled = true -- enable the winc
				rope.WinchForce = 0 -- set the force of it to 0
				--enabling the winch and setting the force to 0 so that the rope can get as far as it wants without any pull

				local forceWanted = camera.CFrame.LookVector.Unit * THROW_SPEED -- calculate the necceseary force using the config value and the cameras look vector
				Bait.AssemblyLinearVelocity = forceWanted -- change the balls linearvelocity to the calculated force
				--throwing the bait

				while task.wait() do -- open a new loop to check for reels
					if uis:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then -- if the user is pressing m2
						rope.WinchForce = WINCH_FORCE -- set the winch force to config'd winch force so it starts pulling
						if not reelTrack.IsPlaying then -- if the reeling anim is not playing
							reelTrack:Play() -- start the animation
						end

						crankMotor.C0 *= CFrame.fromOrientation(CRANK_STEP, 0, 0) -- rotating the shaft from its crankmotor weld6d .c0 value to not distort it and only rotate the offset rotation since its welded and in a model

						if rope.Length >= rope.CurrentDistance - REEL_STOP_MARGIN then -- if the bait has come close enough with in the stop margin
							-- if the bait is close enough to the player then stop the winch
							rope.WinchEnabled = false -- stop the winch so the rope length becomes a set value again
							reelTrack:Stop() -- stop the animation
							break -- break the loop
						end
					else --if not
						reelTrack:Stop() -- stop the reeling animation
						rope.WinchForce = 0 -- and stop the reeling by setting the winchforce to 0
					end
				end

				activeThread = nil --since the thread ended set it back to nil
			end)
		end
	end)

	table.insert(oldEvents, throwEvent) --add the event for cleanup later

end

function FishingRod.setup(port: Model)
	local reelTrack = activeTracks.Reel -- get the reel track, it is already loaded with its priority and looped set
	local throwTrack = activeTracks.Throw -- get the throw track, same
	activeTracks.Idle:Play() -- the idle track will always need to play so play it instantly

	local rodCopy = rep.Assets.Rods["River Reed Rod"]:Clone() -- make a copy of the rod
	local Bait, rope = buildBait(rodCopy) -- get the rope and the bait
	rodCopy.Parent = port -- parent the rod to the viewport

	local crankMotor = rigRod(rodCopy, port) -- get the motor6d by using the rigrod functipon and also rigging the rod
	bindThrowInput(throwTrack, reelTrack, Bait, rope, crankMotor) -- now throw it all together and fully set it up
end


-- Viewport.luau
local function updateVariables()
	char = player.Character or player.CharacterAdded:Wait() -- get the players character, or player.characteradded:wait() acts if this runs before the players character loads and waits for it to load
	hrp = char:WaitForChild("HumanoidRootPart") -- gets the players humanoidrootpart with waitforchild in case it loads slow
	hum = char:WaitForChild("Humanoid") -- gets the players Humanoid with waitforchild in case it loads slow
end

local function cleanPort()
	--below runs when a port changes and it needs cleaning
	if activeThread then -- checks if there is an activethread
		task.cancel(activeThread) -- if there is cancels it
		activeThread = nil -- and sets it to nil
		--killing the thread that the port is connected to so the rest of the code just stops running if not finished
	end

	for _, track in activeTracks do -- loop thru the loaded tracks
		--stop and destroy the loaded animations
		track:Stop() -- stop the track
		track:Destroy() -- destroy the track
	end
	table.clear(activeTracks) -- completely empty it

	for _, v in oldEvents do -- loop in existing events
		--clearing old events
		v:Disconnect() -- disconnect each one
	end
	table.clear(oldEvents)

	for _, v in portFolder:GetChildren() do -- loop in the folder where the port models exist
		--clearing old port models
		v:Destroy() -- destroy each one
	end
	activePort = nil -- after cleaning it all set activeport to nil
end

local function getPortAnimator(port: Model): Animator?
	local animController = port:WaitForChild("Animation", 3) -- look for the animationController named Animation under port model with a timeout time of 3 seconds
	return animController -- return the found thing the animationcontroller if found nil if not
end

local function setupActivePort(holdingName)
	cleanPort() --clean up the old port


	if not holdingName or holdingName == "" then
		--returns if the player is not holding anything
		return
	end

	local template = viewportFolder:FindFirstChild(holdingName, true) -- look for the templatemodel of the port
	if not template then
		return --if not found return
	end

	local model = template:Clone() :: Model -- clone the template

	for _, v in model:GetDescendants() do
		if v:IsA("BasePart") then
			v.CanCollide = false
			v.Anchored = false
			--set everything inside the model to cancollide = false and anchored = false just in case
		end
	end

	model.Parent = portFolder -- parent the model to the port folder
	activePort = model -- set the activeport to the model we are using

	local hrpPort = activePort:WaitForChild("HumanoidRootPart") -- find the hrpPort for the model since every port needs to have one didnt make a check for it since i need it to error that must've mean i forgot something
	hrpPort.Anchored = true -- anchor the hrp so it doesnt fall

	local fakeCam = activePort:WaitForChild("FakeCamera", 3) -- find the fakecamera
	if fakeCam then
		fakeCam.CFrame = camera.CFrame -- if found set it to the players camera
	end

	local animator = getPortAnimator(activePort) -- get the animator of the port by using the function written above
	if not animator then return end -- if not found return

	local toolTable = itemSetups[holdingName] -- find the table of the tool
	if not toolTable then return end -- if not found return

	for trackName, trackSettings in toolTable.animations do -- loop thru the animations of the held tool and the settings written in its section
		local track = animator:LoadAnimation(trackSettings.Animation) -- load the track
		track.Priority = trackSettings.Priority -- the priority is already decided in the settings
		track.Looped = trackSettings.Looped -- same for looped
		activeTracks[trackName] = track -- keep it where the setup function can find it
	end

	toolTable.setup(activePort) -- set up the port
end

local function updateSway(dt: number)
	local camCF = camera.CFrame -- get the current camera cframe
	local turnCF = lastCamCF:ToObjectSpace(camCF) -- get the relative cframe of the current cams frame to the last cams cframe
	lastCamCF = camCF -- update the old cframe to the current cframe
	-- put all this above the return since i dont want it to jerk or snap

	if not activePort then return end -- if there is no active port return

	local fakeCamera = activePort:FindFirstChild("FakeCamera") -- find the fakecamera
	if not fakeCamera then return end -- if not found return


	local pitch, yaw = turnCF:ToEulerAnglesYXZ() -- get the angles of it in radians ( i didnt need to use the z which is roll since the camera will never rotate that way i used used the yaw for it)
	local targetSwayPitch = math.clamp(-pitch * SWAY_STRENGTH, -MAX_SWAY_ANGLE, MAX_SWAY_ANGLE) -- clamp it so it doesnt get too extreme
	local targetSwayYaw = math.clamp(-yaw * SWAY_STRENGTH, -MAX_SWAY_ANGLE, MAX_SWAY_ANGLE) -- clamp it so it doesnt get too extreme


	local targetSwayCF = CFrame.Angles(targetSwayPitch, targetSwayYaw, targetSwayYaw * 0.7) -- apply everything to a cframe ( to add a roll to the viewport just used the yaw)
	swayCFrame = swayCFrame:Lerp(targetSwayCF, math.clamp(dt * SWAY_SMOOTHNESS, 0, 1)) -- slowly go towards the target cframe so its smooth



	-- apply it
	fakeCamera.CFrame = camera.CFrame * swayCFrame
end


-- Startup (procedural code only)
updateVariables()-- call first in case .characteradded doesnt catch it at startup

portFolder = Instance.new("Folder") -- the folder where the activeport models will reside
portFolder.Name = "portFolder" -- name it so it shows itself
portFolder.Parent = camera -- put it in camera to find it easier and it shows itself better

player.CharacterAdded:Connect(function()
	updateVariables() -- called when .characterAdded fires so that the old char hrp and hum values update
end)

player:GetAttributeChangedSignal("Holding"):Connect(function()
	local newHolding = player:GetAttribute("Holding")
	setupActivePort(newHolding)
	--update once holding attribute changes (it is changed on the server)
end)

runService.RenderStepped:Connect(updateSway)

local initialHolding = player:GetAttribute("Holding") -- find what the player is holding
if initialHolding and initialHolding ~= "" then
	setupActivePort(initialHolding)
	--in case if the event misses it at start
end
