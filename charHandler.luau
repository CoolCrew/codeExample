local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local dataManager = require(ServerScriptService.Server.Data.dataManager)
local coolHitbox = require(ReplicatedStorage.utils.coolHitbox)
local Template = require(ServerScriptService.Server.Data.Template)
local animHandler = require(script.AnimationHandler)
local stateHandler = require(script.StateHandler)

local classInfo

if not classInfo then
	classInfo = require(game:GetService("ServerScriptService").Main.CharHandler.classInfo)
end


local CharHandler = {}
CharHandler.activeChars = {}

export type activeSkill = {
	skillName: string?,
	activeHitboxes: { [any]: typeof(coolHitbox.New()) }
}

export type ServerCharData = {
	currentM1: number,
	m1ResetTime: number,
	ActiveSkill: activeSkill,
	Cooldowns: { [string]: number },
	stateThread: thread?,
}

export type CharInfo = {
	Class: string,
	GrabbedBy : Model?,
	State: string,
	StateExpiry: number,
	currentM1: number,
	m1ResetTime: number,
	ActiveSkill: activeSkill,
	Cooldowns: { [string]: number },
	stateThread: thread?,
	blockHealth : number,
}


local function createServerData(): ServerCharData
	return {
		currentM1 = 1,
		m1ResetTime = 0,
		ActiveSkill = {
			skillName = nil,
			activeHitboxes = {},
		},
		Cooldowns = {},
		stateThread = nil,
	}
end





function CharHandler.getInfo(char: Model): CharInfo?
	if not char or not char.Parent then return nil end

	local rawData = CharHandler.activeChars[char]
	if not rawData then return nil end

	local proxy = {}
	--proxy so i can edit the values i get however i want
	setmetatable(proxy, {
		__index = function(_, key)
			if key == "Class" then
				return char:GetAttribute("Class") or Template.Class
			elseif key == "GrabbedBy" then
				return char:GetAttribute("GrabbedBy")
			elseif key == "State" then
				local expiry = char:GetAttribute("StateExpiry") or 0
				if expiry > 0 and workspace:GetServerTimeNow() >= expiry then
					char:SetAttribute("State", "noState")
					char:SetAttribute("StateExpiry", 0)
					return "noState"
				end
				return char:GetAttribute("State") or "noState"
			elseif key == "StateExpiry" then
				return char:GetAttribute("StateExpiry") or 0
			elseif key == "blockHealth" then
				return char:GetAttribute("blockHealth") or 0
			elseif key == "currentM1" then
				local now = workspace:GetServerTimeNow()
				if now >= rawData.m1ResetTime and rawData.m1ResetTime >= 0 then
					local className = char:GetAttribute("Class") or Template.Class
					local charClassData = classInfo[className]
					local m1Data = charClassData and charClassData.m1
					if rawData.currentM1 > 1 then
					
						
						local fullCooldown = m1Data.coolDown

						
						rawData.Cooldowns["m1"] = rawData.m1ResetTime + fullCooldown
					end

					
					rawData.currentM1 = 1
					rawData.m1ResetTime = now + m1Data.ResetTime
				end
				return rawData.currentM1
			end

			return rawData[key]
		end,

		__newindex = function(_, key, value)
			if key == "Class" then
				char:SetAttribute("Class", value)
			elseif key == "GrabbedBy" then
				return char:SetAttribute("GrabbedBy",value)
			elseif key == "State" then
				char:SetAttribute("State", value)
			elseif key == "StateExpiry" then
				char:SetAttribute("StateExpiry", value)
			elseif key == "blockHealth" then
				char:SetAttribute("blockHealth", value)
			elseif key == "currentM1" then
				rawData.currentM1 = value --most likely will never run but better safe than sorry
			else
				rawData[key] = value
			end
		end,
		
		
	})
	return proxy :: any
end


function CharHandler.resetM1(char: Model)
	local charInfo = CharHandler.getInfo(char)
	if not charInfo then return end

	charInfo.currentM1 = 1
	charInfo.m1ResetTime = 0
end





function CharHandler.setSkill(char: Model, skillName: string, hitboxes: { any }?)
	local charInfo = CharHandler.getInfo(char)
	if not charInfo then return end

	CharHandler.clearSkill(char)

	char:SetAttribute("ActiveSkill", skillName)
	stateHandler.setState(char, "usingSkill")

	charInfo.ActiveSkill.skillName = skillName
	charInfo.ActiveSkill.activeHitboxes = hitboxes or {}
end

function CharHandler.clearSkill(char: Model)
	local charInfo = CharHandler.getInfo(char)
	if not charInfo then return end

	for _, hitbox in charInfo.ActiveSkill.activeHitboxes do
		if hitbox and hitbox.Destroy then
			hitbox:Destroy()
		end
	end
	table.clear(charInfo.ActiveSkill.activeHitboxes)

	charInfo.ActiveSkill.skillName = nil
	char:SetAttribute("ActiveSkill", nil)
	
	--didnt add the animation cancel here yet cus not planning on using this just yet
	
	if charInfo.State == "usingSkill" then
		stateHandler.setState(char, "noState", 0)
	end
end




function CharHandler.register(char: Model, customClass: string?): CharInfo?
	if CharHandler.activeChars[char] then
		return CharHandler.getInfo(char)
	end
	


	local player = Players:GetPlayerFromCharacter(char)
	local class = customClass

	if player then
		local playerData = dataManager.GetPlayerData(player)
		class = (playerData and playerData.Class) or Template.Class
	else
		class = class or char:GetAttribute("Class") or Template.Class
		local blockingTrack = animHandler.playAnimation(char,"rbxassetid://109282995787144")
		blockingTrack:Stop()
		char:GetAttributeChangedSignal("State"):Connect(function()
			if char:GetAttribute("State") == "blocking" then
				blockingTrack:Play()
			else
				blockingTrack:Stop()
			end
		end)
	end

	char:SetAttribute("Class", class)
	char:SetAttribute("State", "noState")
	char:SetAttribute("StateExpiry", 0)
	char:SetAttribute("blockHealth",100)
	
	
	local charClassInfo = classInfo[customClass or char:GetAttribute("Class")]

	CharHandler.activeChars[char] = createServerData()
	local charInfo = CharHandler.getInfo(char)

	char.Destroying:Connect(function()
		CharHandler.unregister(char)
	end)

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			CharHandler.clearSkill(char)
			CharHandler.resetM1(char)
		end)
	end

	task.spawn(function()
		local event = char:GetAttributeChangedSignal("blockHealth"):Connect(function()
			char:SetAttribute("blockHealth",math.clamp(char:GetAttribute("blockHealth"),0,100))
			if char:GetAttribute("blockHealth") <= 0 then

				animHandler.playAnimation(char,"rbxassetid://118386539203529")
				stateHandler.setState(char,"Stunned",2)		
				task.delay(2,function()
					charInfo.blockHealth = 100
				end)
			end
		end)
		
		local event2 = char:GetAttributeChangedSignal("State"):Connect(function()
			if char:GetAttribute("State") == "blocking" then
				char.Humanoid.WalkSpeed = charClassInfo.blockWalkSpeed
			elseif char:GetAttribute("State") == "Stunned" then
				char.Humanoid.WalkSpeed = 2
			elseif char:GetAttribute("State") == "usingSkill" then
				char.Humanoid.WalkSpeed = 10
			else
				char.Humanoid.WalkSpeed = charClassInfo.baseWalkSpeed
			end
		end)
		
		while task.wait(2) do
			

			if charInfo.State == "noState" then
				
				local blockHealth = char:GetAttribute("blockHealth")
				
				if blockHealth < 100 then
					char:SetAttribute("blockHealth",math.clamp(blockHealth + 10,0,100))
				end
				
				
				
				
			end
			if not char or not char.Parent or not charInfo then event:Disconnect() event2:Disconnect() break end
		end
	end)

	return charInfo
end

function CharHandler.unregister(char: Model)
	local charInfo = CharHandler.getInfo(char)
	if charInfo then
		if charInfo.stateThread then
			task.cancel(charInfo.stateThread)
			charInfo.stateThread = nil
		end

		for _, hitbox in charInfo.ActiveSkill.activeHitboxes do
			if hitbox and hitbox.Destroy then
				hitbox:Destroy()
			end
		end

		CharHandler.activeChars[char] = nil
	end
end

function CharHandler.Init()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(char)
			CharHandler.register(char)
		end)

		if player.Character then
			CharHandler.register(player.Character)
		end
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	CollectionService:GetInstanceAddedSignal("CombatEntity"):Connect(function(npcModel)
		if npcModel:IsA("Model") then
			CharHandler.register(npcModel)
		end
	end)

	for _, npc in CollectionService:GetTagged("CombatEntity") do
		if npc:IsA("Model") then
			CharHandler.register(npc)
		end
	end
end

return CharHandler
