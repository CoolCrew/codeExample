local coolHitbox = {}
coolHitbox.__index = coolHitbox
local runService = game:GetService("RunService")
local signal = require(game:GetService("ReplicatedStorage").utils.Signal)


local allHitbox = {}

--export type config = {
--	CFrame : CFrame,
--	Size : Vector3,
--	Offset : Vector3,
--	Owner : Player,
--	attachPart : BasePart,
--	hitAmount : number?,
--	coolDown : number?,
--	OverlapParams : OverlapParams?,	
--}



type hitList = {
	[Player] : {hitAmount : number, lastHitTime : number, blockedHits : number}
}


function coolHitbox:Reset()
	self.hitList = {}
end




export type coolHitboxConfig = {
	hitboxCFrame : CFrame?,
	Size : Vector3?,
	Offset : Vector3?,
	Owner : Player?,
	attachPart : BasePart?,
	hitAmount : number?,
	coolDown : number?,
	OverlapParams : OverlapParams?,	
	maxHitChars : number?,
}


function coolHitbox.newHitboxConfig(configChange : coolHitboxConfig) : coolHitboxConfig
	configChange = configChange or {}
	local config = {
		hitboxCFrame = configChange.hitboxCFrame or CFrame.new(0,0,0),
		Size = configChange.Size or Vector3.new(3,3,3),
		Offset = configChange.Offset or Vector3.new(0,0,0),
		Owner = configChange.Owner or nil,
		attachPart = configChange.attachPart or nil,
		hitAmount = configChange.hitAmount or 1,
		coolDown = configChange.coolDown or 0,
		OverlapParams = configChange.OverlapParams or nil,
		maxHitChars = configChange.maxHitChars or math.huge,
	}
	
	return config
end




function coolHitbox.New(hitboxConfig : coolHitboxConfig)
	local self = setmetatable({}, coolHitbox)

	local hitAmount = hitboxConfig.hitAmount
	local Size = hitboxConfig.Size
	local hitboxCframe = hitboxConfig.hitboxCFrame
	local Offset = hitboxConfig.Offset
	local attachPart = hitboxConfig.attachPart
	local Owner = hitboxConfig.Owner
	local coolDown = hitboxConfig.coolDown


	local hitBoxPart = Instance.new("Part")
	hitBoxPart.Parent = workspace.Hitbox
	hitBoxPart.Anchored = false
	hitBoxPart.CanCollide = false
	hitBoxPart.CanTouch = false
	hitBoxPart.CanQuery = true
	hitBoxPart.Massless = true
	hitBoxPart.Transparency = 0.4
	hitBoxPart.BrickColor = BrickColor.new("Really red")
	hitBoxPart.Size = Size
	hitBoxPart.CFrame = hitboxCframe * CFrame.new(Offset)

	
	if attachPart  then
		local weldConstraint = Instance.new("WeldConstraint")
		weldConstraint.Parent = hitBoxPart
		weldConstraint.Part0 = hitBoxPart
		weldConstraint.Part1 = attachPart
	else
		hitBoxPart.Anchored = true
	end
	



	table.insert(allHitbox,self)

	self.Instance = hitBoxPart
	self.Owner = Owner
	self.hitList = {} :: hitList
	self.waitTime = workspace:GetServerTimeNow()
	self.Touched = signal.new()





	self.Connection = runService.Heartbeat:Connect(function()		
		local processing = {}
		local hitParts = workspace:GetPartsInPart(hitBoxPart,hitboxConfig.OverlapParams)

		for i, v in hitParts do
			if v:IsA("BasePart") then
				

				local target = v:FindFirstAncestorWhichIsA("Model")
				if not target then continue end
				if not target:FindFirstChild("Humanoid") then continue end

				if Owner and target == self.Owner.Character then continue end


				if table.find(processing,target) then
					continue
				end

				table.insert(processing,target)


				local hum = target:FindFirstChild("Humanoid")
				if not hum then continue end

				if not self.hitList[target] then
					self.hitList[target] = {hitAmount = 0, lastHitTime = 0, blockedHits = 0}
				end

				if self.hitList[target].hitAmount < hitAmount then	
					
					if coolDown then
						if workspace:GetServerTimeNow() - self.hitList[target].lastHitTime < coolDown then
							continue
						end			
					end
					
					local amount = 0
					for o, p in self.hitList do
						if p.hitAmount > 0 then
							amount += 1
						end
					end

					if amount >= hitboxConfig.maxHitChars then return end
					
					self.hitList[target].hitAmount += 1
					if target:GetAttribute("State") == "blocking" then
						self.hitList[target].blockedHits += 1
					end
					self.Touched:Fire(self.Owner :: Player ,target :: Model)
					self.hitList[target].lastHitTime = workspace:GetServerTimeNow()

				end	


			end
		end

	end)

	return self
end


function coolHitbox.DestroyAll()

	for i, v in table.clone(allHitbox) do
		v:Destroy()
	end
end

function coolHitbox:Destroy()


	assert(self.Owner,"Owner Not Found!")
	assert(self.Instance,"Instance Not Found!")
	assert(self.Connection,"Connection Not Found!")
	assert(table.find(allHitbox,self),"Not Found In Table!")

	table.remove(allHitbox,table.find(allHitbox,self))
	self.Instance:Destroy()
	self.Connection:Disconnect()	
	self.Touched:DisconnectAll()
	self.hitList = nil
	self.Owner = nil
	setmetatable(self, nil)
	self = nil

end

return coolHitbox
